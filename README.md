# CoaForge Collector

A World of Warcraft addon for Ascension's Conquest of Azeroth (patch 3.3.5) that scans your spellbook and records what it finds - id, name, icon, passive flag, tooltip text, class, spec, race - so it can be imported into [CoaForge](https://coaforge.com), a visual macro builder for the CoA ruleset.

**It never sends anything anywhere on its own.** WoW's addon sandbox has no network access to begin with - the data just sits in your account's `SavedVariables` file until *you* choose to open it on the CoaForge website. Nothing is uploaded automatically, and nothing is shared with other players.

## Installation

1. Download the latest release from the [Releases page](https://github.com/beebsis/CoAForgeCollector/releases) and unzip it.
2. Drop the `CoaForgeCollector` folder into your WoW installation's `Interface/AddOns/` directory, so you end up with:
   ```
   <WoW install>/Interface/AddOns/CoaForgeCollector/CoaForgeCollector.toc
   <WoW install>/Interface/AddOns/CoaForgeCollector/CoaForgeCollector.lua
   ```
3. (Re)start WoW, or reload your UI (`/reload`) if it's already running. Make sure the addon is enabled on your character selection screen's AddOns list.

## Using it in-game

Nothing to configure - once it's enabled, it scans automatically:

- On login
- On level up
- On learning a new spell
- On a talent/spec change (including Ascension's own CoA talent panel)

Auto-scans are debounced (a couple of seconds after the triggering event), so a burst of changes - like a full talent reset - collapses into a single scan instead of several.

Two manual slash commands, if you want them:

| Command | What it does |
|---|---|
| `/cfc` | Scans your spellbook right now and prints how many spells were found (and how many are new). |
| `/cfc status` | Prints how many spells are currently recorded in total, and when the last scan happened. |

Everything accumulates in one account-wide `SavedVariables` table - playing multiple characters/classes on the same account keeps adding to the same shared data instead of each character overwriting the last.

## Submitting what it collected

The addon only *records* data locally. To actually contribute it to CoaForge's shared spell database:

1. Play at least one character for a bit (or just log in and level up a little) so the addon has something to scan. Log out normally, or just `/reload` - WoW writes `SavedVariables` to disk on logout/reload, not continuously.
2. Go to **[coaforge.com](https://coaforge.com)** in a browser (Chrome or Edge recommended - see note below) and click the import icon in the top toolbar (the tray/download icon).
3. Click **"Select CoaForgeCollector.lua…"** and pick your `SavedVariables` file. It lives at:
   ```
   <WoW install>/WTF/Account/<YOUR ACCOUNT NAME>/SavedVariables/CoaForgeCollector.lua
   ```
   (Same file regardless of which character or realm you played on - `SavedVariables` in this addon is account-wide.)
4. The site reads and parses the file **entirely on your own computer** - nothing is sent yet at this point, it's just a preview of what was found.
5. Review the preview, then click **"Submit these findings"**. This is the one step that actually sends data to CoaForge's servers.

On Chrome or Edge, the site can remember the file across visits (via the File System Access API) so you don't have to re-pick it every time - just hit "Check for updates" next time you want to submit fresh data. Firefox-based browsers don't support that API, so you'll need to re-select the file each time there instead.

### What happens to submitted data

CoaForge doesn't blindly trust a single submission. A spell nobody has data on yet gets added right away, but if your data *disagrees* with what's already recorded for a spell (e.g. a different class tag), it's recorded as a proposed correction rather than overwriting anything immediately - it only takes effect once a second, independent player has submitted the same correction. One bad or tampered file can't silently corrupt the shared data on its own.

## Why some fields might be missing

- **Spec** can come back empty right after logging in, until you've opened Ascension's Character Advancement panel at least once that session - that's where the addon reads your active spec from, and the game doesn't populate it before then.
- **Icon** may show a generic "unknown" placeholder for some spells - that's normal, and gets filled in automatically once someone's addon submission reports the real one.

## Privacy

This addon reads your own spellbook and character info (class/spec/race) - nothing about your account, guild, chat, or other players. As above, nothing leaves your computer unless you explicitly click "Submit these findings" on the CoaForge website.
