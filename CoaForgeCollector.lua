local ADDON_NAME = ...
local function GetSpellIcon(index, bookType)
	if GetSpellBookItemTexture then
		return GetSpellBookItemTexture(index, bookType)
	elseif GetSpellTexture then
		return GetSpellTexture(index, bookType)
	end
	return nil
end

local function GetSpellPassive(index, bookType)
    if IsPassiveSpell then
        return IsPassiveSpell(index, bookType) and true or false
    end
    return nil
end

local function GetCurrentSpecName()
	if CoATalentFrame and CoATalentFrame.activeSpecID then
		return tostring(CoATalentFrame.activeSpecID)
	end
	return nil
end

local function GetCurrentRace()
    if not UnitRace then
        return nil
    end

	local raceName = UnitRace("player")
	return raceName
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33cc99CoaForge Collector:|r " .. msg)
end

-- Best-effort cost lookup. GetSpellPowerCost takes a spell id (not a
-- spellbook index) and, where it exists on this client, returns the
-- cleanest answer. Not confirmed available on this 3.3.5-era client, so
-- this falls back to a heuristic scan of the tooltip lines already being
-- captured (a cost line reads like "30 Rage" or "18% of base mana").
-- Not yet verified in game, needs a real playtest before trusting it.
local function GetSpellCost(spellId, tooltipLines)
	if GetSpellPowerCost then
		local ok, costs = pcall(GetSpellPowerCost, spellId)
		if ok and type(costs) == "table" and costs[1] and costs[1].cost and costs[1].cost > 0 then
			local c = costs[1]
			if c.costPercent and c.costPercent > 0 then
				return c.costPercent .. "% of base " .. (c.name or "mana")
			end
			return tostring(c.cost) .. " " .. (c.name or "")
		end
	end

	if tooltipLines then
		for _, line in ipairs(tooltipLines) do
			if string.match(line, "^%d+%s+%a+$") or string.match(line, "base mana") or string.match(line, "^%d+%.?%d*%%") then
				return line
			end
		end
	end
	return nil
end

local function InitDB()
	CoaForgeCollectorDB = CoaForgeCollectorDB or {}
	CoaForgeCollectorDB.spells = CoaForgeCollectorDB.spells or {}
	CoaForgeCollectorDB.meta = CoaForgeCollectorDB.meta or {}
	CoaForgeCollectorDB.settings = CoaForgeCollectorDB.settings or {}
	if CoaForgeCollectorDB.settings.relayEnabled == nil then
		-- Opt-in, off by default. Never sends anything to another player
		-- unless this has been explicitly turned on with /cfc relay on.
		CoaForgeCollectorDB.settings.relayEnabled = false
	end
	CoaForgeCollectorDB.relayedSentIds = CoaForgeCollectorDB.relayedSentIds or {}
	CoaForgeCollectorDB.received = CoaForgeCollectorDB.received or {}
	CoaForgeCollectorDB.meta.addonVersion = GetAddOnMetadata(ADDON_NAME, "Version")
end

local function ScanTooltipLines(index, bookType)
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	GameTooltip:ClearLines()
	if GameTooltip.SetSpellBookItem then
		GameTooltip:SetSpellBookItem(index, bookType)
	elseif GameTooltip.SetSpell then
		GameTooltip:SetSpell(index, bookType)
	else
		return {}
	end

	GameTooltip:Show()

	local lines = {}
	for i = 2, GameTooltip:NumLines() do
		local fs = _G["GameTooltipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text and text ~= "" then
			table.insert(lines, text)
		end
	end
	GameTooltip:Hide()
	return lines
end

local function ScanSpellbook()
	InitDB()

	local _, classFile = UnitClass("player")
	local specName = GetCurrentSpecName()
	local raceFile = GetCurrentRace()
	local scanned, newCount = 0, 0

	local numTabs = GetNumSpellTabs()
	for tabIndex = 1, numTabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
		for i = offset + 1, offset + numSpells do
			local spellType, spellId = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
			if spellType and spellId and string.lower(spellType) == "spell" then
				scanned = scanned + 1
				local isNew = CoaForgeCollectorDB.spells[spellId] == nil
				local ok, entry = pcall(function()
					-- GetSpellBookItemName's 2nd return value is the rank
					-- text (e.g. "Rank 3") on this client, already being
					-- fetched before and discarded.
					local name, rank = GetSpellBookItemName(i, BOOKTYPE_SPELL)
					local tooltipLines = ScanTooltipLines(i, BOOKTYPE_SPELL)
					return {
						name = name,
						rank = rank,
						icon = GetSpellIcon(i, BOOKTYPE_SPELL),
						isPassive = GetSpellPassive(i, BOOKTYPE_SPELL),
						cost = GetSpellCost(spellId, tooltipLines),
						tooltipLines = tooltipLines,
						class = classFile,
						spec = specName,
						race = raceFile,
						scannedAt = time(),
					}
				end)

				if ok then
					CoaForgeCollectorDB.spells[spellId] = entry
					if isNew then
						newCount = newCount + 1
					end
				else
					Print("|cffff5555skipped spell " .. spellId .. " (index " .. i .. "): " .. tostring(entry) .. "|r")
				end
			end
		end
	end

	CoaForgeCollectorDB.meta.lastScan = time()
	return scanned, newCount
end

local function CountStored()
	InitDB()
	local count = 0
	for _ in pairs(CoaForgeCollectorDB.spells) do
		count = count + 1
	end
	return count
end

-- ===========================================================================
-- Relay: opt-in only. Sends a player's own scanned spells directly to one of
-- a fixed, small set of known collector character names, whichever one
-- happens to be online at the time (WoW doesn't queue addon messages for
-- offline characters, so trying all of them covers "which alt is logged in
-- right now" without needing a shared channel or guild). Never sends
-- anything unless CoaForgeCollectorDB.settings.relayEnabled is true, which
-- defaults to false and is only ever set by running /cfc relay on yourself.
--
-- Whisper-style addon messages don't cross realm boundaries on this
-- 3.3.5-era client (that's a much later Battle.net-era feature), so this
-- only reaches a listed name if the sender is on the same realm as that
-- character. Vol'jin covers the CoA names below; Area 52 covers the
-- Wildcard one.
--
-- None of this has been tested in game yet -- write carefully, but treat
-- every assumption here (message size limits, character encoding safety,
-- whether GetSpellPowerCost exists on this client) as needing a real
-- playtest before trusting it.
-- ===========================================================================

local RELAY_PREFIX = "CFCRelay"
-- Beebsis/Clunky/CoaForge: CoA-ruleset collectors on Vol'jin (all three are
-- the same account, so at most one is ever actually online at once). mam:
-- the Wildcard-ruleset collector on Area 52 -- not on this account, run by
-- someone else, kept in the same list since a relay send just tries every
-- name regardless of who's behind it.
local COLLECTOR_NAMES = { "Beebsis", "Clunky", "CoaForge", "mam" }
local CHUNK_BODY_MAX = 200 -- leaves headroom under the addon message size cap for the id/index/total header
local SEND_TICK_SECONDS = 0.3 -- paces outgoing chunks well under the addon-message throttle instead of bursting
-- ASCII Unit Separator as the field delimiter. Deliberately not "|" -- WoW
-- uses "|" constantly for color codes and hyperlinks, so real tooltip text
-- can contain it. "\031" essentially never appears in real game text.
local FIELD_SEP = "\031"

local function SerializeSpellEntry(spellId, entry)
	local tooltip = table.concat(entry.tooltipLines or {}, " ")
	local fields = {
		tostring(spellId),
		entry.name or "",
		entry.icon or "",
		entry.rank or "",
		entry.cost or "",
		entry.isPassive and "1" or "0",
		tooltip,
	}
	return table.concat(fields, FIELD_SEP)
end

local function DeserializeSpellEntry(payload)
	local parts = {}
	for part in string.gmatch(payload .. FIELD_SEP, "(.-)" .. FIELD_SEP) do
		table.insert(parts, part)
	end
	local spellId = tonumber(parts[1])
	if not spellId then
		return nil
	end
	return spellId, {
		name = parts[2],
		icon = parts[3],
		rank = parts[4],
		cost = parts[5],
		isPassive = parts[6] == "1",
		tooltip = parts[7],
	}
end

local function ChunkPayload(payload)
	local chunks = {}
	local len = string.len(payload)
	local total = math.ceil(len / CHUNK_BODY_MAX)
	if total == 0 then
		total = 1
	end
	for i = 1, total do
		local startPos = (i - 1) * CHUNK_BODY_MAX + 1
		local endPos = math.min(i * CHUNK_BODY_MAX, len)
		table.insert(chunks, string.sub(payload, startPos, endPos))
	end
	return chunks, total
end

local sendQueue = {}
local sendFrame = nil

local function SendAddonMsg(message, target)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(RELAY_PREFIX, message, "WHISPER", target)
	elseif SendAddonMessage then
		SendAddonMessage(RELAY_PREFIX, message, "WHISPER", target)
	end
end

local function StartSendQueue()
	if sendFrame then
		return
	end
	local f = CreateFrame("Frame")
	f.elapsed = 0
	sendFrame = f
	f:SetScript("OnUpdate", function(self, dt)
		self.elapsed = self.elapsed + dt
		if self.elapsed < SEND_TICK_SECONDS then
			return
		end
		self.elapsed = 0

		if #sendQueue == 0 then
			self:SetScript("OnUpdate", nil)
			sendFrame = nil
			return
		end

		local item = table.remove(sendQueue, 1)
		for _, target in ipairs(COLLECTOR_NAMES) do
			-- Only one of these names is likely to actually be online at
			-- once; the rest are expected to silently fail. pcall so a
			-- rejected/invalid whisper target never breaks the queue.
			pcall(SendAddonMsg, item.message, target)
		end
	end)
end

local function QueueSpellForRelay(spellId, entry)
	local payload = SerializeSpellEntry(spellId, entry)
	local chunks, total = ChunkPayload(payload)
	for idx, chunkData in ipairs(chunks) do
		table.insert(sendQueue, {
			message = spellId .. "|" .. idx .. "|" .. total .. "|" .. chunkData,
		})
	end
end

-- Called after every scan when relay is enabled. Only queues spells not
-- already relayed before, tracked in relayedSentIds, so a normal scan
-- doesn't re-send the whole spellbook every time, only what's new since
-- the last relay. "Sent" here means "queued for send", not "confirmed
-- delivered" -- there's no acknowledgement/retry protocol yet, a dropped
-- packet on a bad connection is currently just lost.
local function RelayNewSpells()
	InitDB()
	if not CoaForgeCollectorDB.settings.relayEnabled then
		return 0
	end

	local queuedCount = 0
	for spellId, entry in pairs(CoaForgeCollectorDB.spells) do
		if not CoaForgeCollectorDB.relayedSentIds[spellId] then
			QueueSpellForRelay(spellId, entry)
			CoaForgeCollectorDB.relayedSentIds[spellId] = true
			queuedCount = queuedCount + 1
		end
	end

	if queuedCount > 0 then
		StartSendQueue()
	end
	return queuedCount
end

local incomingBuffers = {} -- [senderName][spellId] = { total = N, parts = {} }

local function HandleIncomingRelayMessage(message, sender)
	local spellIdStr, idxStr, totalStr, chunkData = string.match(message, "^(%d+)|(%d+)|(%d+)|(.*)$")
	if not spellIdStr then
		return
	end
	local spellId, idx, total = tonumber(spellIdStr), tonumber(idxStr), tonumber(totalStr)
	if not (spellId and idx and total) then
		return
	end

	incomingBuffers[sender] = incomingBuffers[sender] or {}
	incomingBuffers[sender][spellId] = incomingBuffers[sender][spellId] or { total = total, parts = {} }
	local buf = incomingBuffers[sender][spellId]
	buf.parts[idx] = chunkData

	for i = 1, buf.total do
		if not buf.parts[i] then
			return -- still waiting on more chunks
		end
	end

	local payload = table.concat(buf.parts, "", 1, buf.total)
	incomingBuffers[sender][spellId] = nil

	local parsedId, entry = DeserializeSpellEntry(payload)
	if parsedId then
		InitDB()
		CoaForgeCollectorDB.received[sender] = CoaForgeCollectorDB.received[sender] or {}
		CoaForgeCollectorDB.received[sender][parsedId] = entry
	end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(RELAY_PREFIX)
elseif RegisterAddonMessagePrefix then
	RegisterAddonMessagePrefix(RELAY_PREFIX)
end

SLASH_COAFORGECOLLECTOR1 = "/cfc"
SlashCmdList["COAFORGECOLLECTOR"] = function(input)
	local cmd, rest = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
	cmd = string.lower(cmd or "")

	if cmd == "status" then
		Print(CountStored() .. " spell(s) recorded so far. Last scan: " ..
			(CoaForgeCollectorDB.meta.lastScan and date("%Y-%m-%d %H:%M:%S", CoaForgeCollectorDB.meta.lastScan) or "never"))
	elseif cmd == "relay" then
		InitDB()
		local sub = string.lower(rest or "")
		if sub == "on" then
			CoaForgeCollectorDB.settings.relayEnabled = true
			Print("Relay enabled. Your scans will be sent directly to the collector characters from now on.")
		elseif sub == "off" then
			CoaForgeCollectorDB.settings.relayEnabled = false
			Print("Relay disabled.")
		else
			Print("Relay is currently " .. (CoaForgeCollectorDB.settings.relayEnabled and "ON" or "OFF") ..
				". Use /cfc relay on or /cfc relay off to change it.")
		end
	else
		local scanned, newCount = ScanSpellbook()
		local relayMsg = ""
		if CoaForgeCollectorDB.settings.relayEnabled then
			local queued = RelayNewSpells()
			relayMsg = " " .. queued .. " queued for relay."
		end
		Print("Scanned " .. scanned .. " spellbook entrie(s), " .. newCount .. " new. " ..
			CountStored() .. " total recorded." .. relayMsg)
	end
end

local SCAN_DELAY_SECONDS = 2
local pendingScanFrame = nil
local pendingScanLabel = nil

local function ScheduleScan(label)
	pendingScanLabel = label
	if pendingScanFrame then
		pendingScanFrame.elapsed = 0
		return
	end
	local f = CreateFrame("Frame")
	f.elapsed = 0
	pendingScanFrame = f
	f:SetScript("OnUpdate", function(self, dt)
		self.elapsed = self.elapsed + dt
		if self.elapsed >= SCAN_DELAY_SECONDS then
			self:SetScript("OnUpdate", nil)
			pendingScanFrame = nil
			local scanned, newCount = ScanSpellbook()
			local relayMsg = ""
			if CoaForgeCollectorDB.settings.relayEnabled then
				local queued = RelayNewSpells()
				relayMsg = " " .. queued .. " queued for relay."
			end
			Print(pendingScanLabel .. ": " .. scanned .. " spellbook entrie(s), " .. newCount .. " new." .. relayMsg)
		end
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("LEARNED_SPELL_IN_TAB")
loader:RegisterEvent("SPELLS_CHANGED")
loader:RegisterEvent("CHARACTER_POINTS_CHANGED")
loader:RegisterEvent("PLAYER_LEVEL_UP")
loader:RegisterEvent("ASCENSION_CA_SPECIALIZATION_ACTIVE_ID_CHANGED")
loader:RegisterEvent("CHAT_MSG_ADDON")
loader:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
	if event == "CHAT_MSG_ADDON" then
		if prefix == RELAY_PREFIX then
			HandleIncomingRelayMessage(message, sender)
		end
		return
	end

	InitDB()
	if event == "PLAYER_LOGIN" then
		ScheduleScan("Login scan")
	else
		ScheduleScan("Auto scan")
	end
end)
