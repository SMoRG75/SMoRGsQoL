# SMoRG's QoL

A small collection of **individually toggleable** quality-of-life tweaks for World of Warcraft (Retail).

Everything is toggleable:
- ⚙️ via the in-game Settings UI, or
- 💬 via `/sqol` chat commands.

## What's new in 1.0.24

- 🎨 **XP/reputation number colors** — the current number changes from red through yellow to green, with outlined text. Labels and maximum values stay white, and the bars keep their existing colors. Enable it with `/sqol barcolor` (`bc`); it is disabled by default and independent of quest colors.
- 🧾 **Separate item level and speed settings** — show either value alone or both on your PlayerFrame. Use `/sqol ilvl` for item level and `/sqol speed` for movement speed. `/sqol stats` now toggles only item level.
- ⚙️ **Your previous display is preserved** — the old combined item level/speed preference carries over to both new settings, which you can then change independently.
- 🛠️ **Modular code structure** — feature code is now organized into dedicated files for easier maintenance.

See the [changelog](CHANGELOG.md) for the full release history.

### 1.0.23

- 🐛 **Fixed nameplate taint error** — the party-level feature could spam an "Attempt to access forbidden object" error whenever nameplates appeared, because its hook also fired for (forbidden) nameplate frames. It now ignores those frames entirely.

### 1.0.22

- 👥 **Party member levels** — shows each party member's level on both the default party frames and raid-style party frames. Enabled by default; toggle with `/sqol partylevel` (`pl`).

### 1.0.21

- ⏳ **LFG queue pop countdown** — a live timer showing how long you have left to accept when the group finder pops (40 seconds), turning red for the last 5. Toggle with `/sqol lfgtimer` (`lfg`).
- Fixed the ready check countdown being invisible when *you* started the ready check — Blizzard never shows the popup to the initiator, so the timer now moves to the top of the screen instead.

### 1.0.20

- ⏱️ **Ready check countdown** — a live timer showing how many seconds are left before the ready check expires, turning red for the last 5 seconds. Toggle with `/sqol readycheck` (`rc`).

### 1.0.19

- Colorized progress messages now cover scenario weighted-progress bars (e.g. Void Incursion's "Defending Stillwhisper"), which live outside the quest system and were previously never reported.

### 1.0.18

- RepWatch no longer rescans while the Reputation panel is open, so collapsing or expanding an expansion header no longer makes the list jump.

### 1.0.17

- Colorized progress messages now cover progress-bar quest objectives (e.g. "Umbral Attuning Shard charged"), using the objective's own label and without a duplicated percentage.

## Features

- 🧭 **Auto-track newly accepted quests**
  - Automatically tracks new quests in the Objective Tracker (with sanity checks to avoid unsupported edge cases).
- 🔔 **Quest completion alert**
  - Plays a sound (toggleable) and prints a chat message when a quest is ready to turn in (or done for bonus/world quests).
  - Optionally plays a separate worker voice line when an individual objective is completed before the full quest is done.
  - Supports selectable Horde (Peon) and Alliance (Human worker) sound profiles.
- 🎨 **Colorized progress messages**
  - Colorizes common progress patterns like `3/10` or `45%` and quest objective progress (red → yellow → green).
  - Also covers progress-bar quest objectives and scenario weighted-progress bars, which the default UI reports silently.
- 🎨 **XP/reputation number colors**
  - Independently colors the current XP/reputation number on Blizzard's standard bars (red → yellow → green), with outlined text. Labels and maximum values stay white; bar colors are unchanged.
  - Toggle with `/sqol barcolor` (`bc`) or **Color XP/reputation numbers** in Settings. Disabled by default; independent of quest progress colors.
- ⏱️ **Ready check countdown**
  - Shows a live countdown of the seconds left on a ready check, turning red for the last 5 seconds.
  - Appears below the ready check popup, or near the top of the screen when you started the ready check yourself (Blizzard never shows the popup to the initiator).
- ⏳ **LFG queue pop countdown**
  - Shows how many of your 40 seconds are left to accept a group finder pop, turning red for the last 5.
  - Sits below the queue pop's ready status frame, so it stays useful while you wait for the rest of the group to accept.
- 👥 **Party member levels**
  - Shows each party member's level on both default and raid-style party frames while leaving raid and arena frames unchanged.
- 🚪 **Login splash**
  - Optional status splash on login showing which features are ON/OFF.
- ✅ **Hide completed achievements**
  - Makes the Achievement UI default to showing incomplete achievements only.
- 🤝 **Auto-watch reputation gains**
  - Switches your watched faction to the one that changed when you gain reputation.
- 🏷️ **Nameplate objective counts**
  - Shows quest objective progress (e.g., 0/10 or 45%) above relevant nameplates, with fallbacks for bonus/world quests.
- 🧾 **PlayerFrame iLvl + Speed**
  - Independently toggle item level and movement speed. Shows either value alone, or both on the same line: `iLvl: xx.x  Spd: yy%`.
- 🖋️ **Custom damage text font**
  - Replaces floating combat text damage numbers with a custom font.
- 🖱️ **Cursor shake highlight**
  - Highlights the cursor when you shake the mouse.
- 🧪 **Debug tracking (optional)**
  - Enables verbose tracking output for troubleshooting.

## Configuration

### Settings UI

Open:
- ⚙️ **Esc → Options → AddOns → SMoRG's QoL**

### Slash commands

Type `/sqol` to see current status, or use:

- `/sqol help`
- `/sqol autotrack` (or `/sqol at`)
- `/sqol color` (or `/sqol col`) — toggle quest progress colors
- `/sqol barcolor` (or `/sqol bc`) — independently toggle XP/reputation number colors
- `/sqol questsound` (or `/sqol qs`)
- `/sqol objectivesound` (or `/sqol os`)
- `/sqol soundprofile` (or `/sqol soundset`)
- `/sqol splash`
- `/sqol hideach` (or `/sqol ha`)
- `/sqol rep` (or `/sqol rw`)
- `/sqol nameplate` (or `/sqol np`)
- `/sqol ilvl` (or `/sqol stats`) — toggle item level only
- `/sqol speed` (or `/sqol spd`) — independently toggle movement speed
- `/sqol damagefont` (or `/sqol df`)
- `/sqol cursor` (or `/sqol cs`)
- `/sqol cursorflash` (or `/sqol cf`)
- `/sqol readycheck` (or `/sqol rc`)
- `/sqol rctest` — preview the countdown solo; `/sqol rctest popup` also shows the ready check popup
- `/sqol lfgtimer` (or `/sqol lfg`)
- `/sqol lfgtest` — preview the queue pop countdown without a queue
- `/sqol partylevel` (or `/sqol pl`)
- `/sqol debugtrack` (or `/sqol dbg`)
- `/sqol reset`

## Saved Variables

Settings are stored per account in:
- 💾 `SQOL_DB`

## Updating to 1.0.24

Install the complete addon folder, including all Lua files listed in
`SMoRGsQoL.toc`. This release introduces additional modules, so replacing only
`SMoRGsQoL.lua` is not sufficient. Keep your saved variables; existing settings
are preserved and the old combined item level/speed setting migrates automatically.

## Code structure

The `.toc` loads shared utilities and feature modules before the main controller.
Modules share the addon's private `SQOL` namespace; implementation helpers stay local.

| File | Responsibility |
| --- | --- |
| `Core.lua` | Defaults, sound profiles, shared utilities and namespace setup |
| `VisualTweaks.lua` | Damage font, cursor highlight and achievement filter |
| `QuestProgress.lua` | Quest data cache, progress colors/messages, scenario progress and nameplate objectives |
| `PlayerStats.lua` | Independent item level and movement speed displays |
| `PartyLevels.lua` | Levels on default and raid-style party frames |
| `Reputation.lua` | Reputation watching, faction lookup and header preservation |
| `Countdowns.lua` | Shared countdown implementation, ready checks and queue pops |
| `SMoRGsQoL.lua` | Saved settings/migration, option side effects, commands, events, auto-tracking and quest completion notifications |
| `Options.lua` | In-game Settings controls |
| `StatusBarProgress.lua` | Independent XP/reputation number colors |

Quest progress and nameplate logic remain together because they share quest parsing
and cached data. New feature modules should keep private state/helpers local and
expose only the entry points needed by the controller through `SQOL`.

Run `lua tests/smoke.lua` from the repository root for a mocked load/event/command
smoke test. It reads the real TOC order. In-game testing is still needed for frame
layout, protected UI behavior and real quest/reputation data.
