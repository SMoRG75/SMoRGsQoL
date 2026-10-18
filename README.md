# SMoRG's QoL

**Hear your quest progress:** *"Work, work."* when you finish an objective, *"Work complete."* when the quest is done. Plus toggleable QoL tweaks for Retail and WoW Forever.

🔊 The worker voice lines are where it all started. Prefer the Alliance? Switch to the Human worker (*"More work?"* / *"Job's done!"*). Every other feature is a small, **individually toggleable** tweak.

Everything is toggleable:
- 🪟 via the options window (LibDataBroker displays such as Bazooka, the addon compartment menu, the optional minimap button or `/sqol config`),
- ⚙️ via the in-game Settings UI, or
- 💬 via `/sqol` chat commands.

## What's new in 1.2.1

- 🛠️ **Updated for WoW 12.1.5.**
- 📜 **New addon icon** — a simple quest scroll with a green check that is easy to recognize at the small sizes it is shown in: the AddOns list, the minimap button, the options window and LibDataBroker displays.
- 🔤 **Damage text font note** — the tooltip for **Custom damage text font** and the options window now say that the font only changes after a game client restart.

After updating, **restart the game** (a `/reload` is not enough), because the icon and the damage text font moved to the `Media` folder. See the [changelog](CHANGELOG.md) for the full release history.

### 1.2.0

- 🌍 **Translations** — the addon now follows your game language: German, French, Spanish (Spain and Latin America), Brazilian Portuguese, Italian, Russian, Korean, and Simplified and Traditional Chinese. That covers the options window, Blizzard's Settings page, tooltips, chat messages, `/sqol help` and on-screen text such as the item level/speed line and the range in meters (码/碼 in Chinese). The quest voice lines stay in English. ⚠️ The translations have not been checked by native speakers yet; see [Translations](#translations) to suggest corrections.
- 🤝 **Floating reputation gains and auto-watch reputation work on every client language** — they now read Blizzard's own localized reputation messages instead of English text.
- 💬 **Clearer chat output** — `/sqol`, `/sqol help` and the login splash use the same names as the options window and show each command's aliases.
- 📦 **More places to download** — besides CurseForge, the addon is now on Wago Addons, WoWInterface and GitHub Releases (WowUp installs from all of them).

### 1.1.0

- 🪟 **Options window** — all settings in one movable window, grouped into Quests, Character, Reputation & XP, Group, Interface and Advanced. Open it from Bazooka/Titan Panel and other LibDataBroker displays, the addon compartment menu, the optional minimap button (`/sqol minimap`) or `/sqol config`. Right-click the launcher for Blizzard's Settings page, which now uses the same sections.
- 🎨 **Colored objective counts in the quest tracker** — with **Color quest progress** on, the current count (the `1` in `1/5 Boar Pelt`) is colored red → yellow → green for quests, campaign quests, world quests and bonus objectives, and finished objectives keep a green count.
- 🎯 **Target in unit tooltips** — a `Target:` line showing who the unit is targeting, class- or reaction-colored, with a red `You` when it is you. `/sqol tooltiptarget` (`tt`).
- 🏹 **Range icon and distance** — on your target's nameplate, where Blizzard's soft target sword icon sits, the distance to your target in yards (e.g. `8-30 yd`), and a pulsing icon when none of the offensive abilities on your bars can reach it. `/sqol range` (`rng`).
- 🧾 **Better placement** — the item level/speed line sits above your name on Retail (clear of long names, druid mana and class resources), and nameplate objective counts sit above the unit name instead of overlapping it.
- 🌍 **WoW Forever support** — the addon loads in WoW Forever, with the item level/speed line placed for its player frame.

### 1.0.24

- **Floating reputation gains** — simple green `+25 Rep — Valarjar` text near the screen center, floating upward and fading out. Enable with `/sqol reptext` (`rt`). Preview with `/sqol reptexttest`.
- 🎨 **XP/reputation number colors** — the current number changes from red through yellow to green, with outlined text. Enable it with `/sqol barcolor` (`bc`).
- 🧾 **Separate item level and speed settings** — show either value alone or both on your PlayerFrame (`/sqol ilvl`, `/sqol speed`). The old combined preference carries over.
- 🛠️ **Modular code structure** — feature code is now organized into dedicated files for easier maintenance.

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

- **Smart Quest Radar (development preview)**
  - Marks relevant visible nameplates with a quest icon and up to three unfinished objective counts on one line, for example `2/8 · 1/5`. More objectives are summarized as `+N`.
  - Enable **Smart Quest Radar** under **Quests**, or toggle it with `/sqol radar` (`qr`). It is off by default and works independently of **Show objective counts on nameplates**. While enabled, radar replaces the old counts in the same text region; turning it off restores the previous setting.
  - Uses readable quest sections from `C_TooltipInfo.GetUnit` and matches their titles to your active quest log. Typed tooltip objectives are preferred. Clients without line types require an exact match to your own unfinished objective text. Ambiguous titles, completed objectives, party progress sections and unavailable data are skipped. Non-numeric objectives are marked as **Quest objective** only when explicitly unfinished.
  - Shares existing quest caches and throttled nameplate updates. Relevant tooltip-data updates and entering/leaving combat refresh the display; no continuous scanning of nearby units is performed. **Color quest progress** also colors radar counters.
  - Requires visible nameplates and readable tooltip data. It cannot identify objects without nameplates or guarantee every quest target, especially when the client restricts data. In-game layout, combat, grouped questing, reload/login and addon compatibility still need verification in Retail and WoW Forever.
- 📖 **Adventure Recap (development preview)**
  - An optional, movable window with completed quests, world quests (included in the quest total), reputation gained, recorded playtime and the most active faction when all reputation messages were readable.
  - Enable **Adventure Recap** under **Quests**, then open it from the options window or with `/sqol recap`. There are no automatic popups; collection is off by default.
  - `/sqol recap last` shows the previous session, `/sqol recap reset` clears only the current session, and `/sqol recap test` previews sample data without changing real statistics.
  - Sessions are stored per character. `/reload` continues the session; logging in again starts a new one and keeps the previous session. Offline time and time with recording disabled are excluded. Disabling recording pauses it without deleting the totals.
  - Only `QUEST_TURNED_IN` counts a quest. Being ready to turn in or abandoning a quest does not count. Reputation counts positive gains, not gains minus losses; unreadable or unrecognized messages mark the total as incomplete and hide the top-faction highlight. If world quest classification is unavailable, its displayed count is marked as a minimum.
  - Event-driven tracking; the visible recap refreshes its clock once per second. This preview still needs in-game verification on Retail and WoW Forever before release.
- 🔊 **Quest sounds: objective and quest completion**
  - Plays a worker voice line when an individual objective is completed before the full quest is done (Peon: *"Work, work."*).
  - Plays another voice line and prints a chat message when the whole quest is ready to turn in, or done for bonus/world quests (Peon: *"Work complete."*).
  - Choose the Horde (Peon) or Alliance (Human worker: *"More work?"* / *"Job's done!"*) sound profile, and toggle each sound on its own (`/sqol objectivesound`, `/sqol questsound`, `/sqol soundprofile`).
- 🧭 **Auto-track newly accepted quests**
  - Automatically tracks new quests in the Objective Tracker (with sanity checks to avoid unsupported edge cases).
- 🎨 **Colorized progress messages**
  - Colorizes common progress patterns like `3/10` or `45%` and quest objective progress (red → yellow → green).
  - Also covers progress-bar quest objectives and scenario weighted-progress bars, which the default UI reports silently.
- 🎨 **XP/reputation number colors**
  - Reputation text also shows the percentage remaining in the current bar and your current standing after the total, e.g. `4995 / 6000 · 16.8% left · Friendly`.
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
  - Not available in WoW Forever, which replaces achievements with the Legacy system.
- 🤝 **Auto-watch reputation gains**
  - Switches your watched faction to the one that changed when you gain reputation.
- 🧠 **Reputation Memory (development preview)**
  - Keep one preferred faction per character. Choose a faction to watch in Blizzard's Reputation panel, then run `/sqol repfocus` to remember that faction.
  - Enable **Auto-watch reputation gains** and **Return to preferred reputation** under **Reputation & XP**. Both are optional and off by default. Auto-watch shows a new gain temporarily, then returns to your preferred faction after 10 seconds without new gains.
  - Changing or clearing the watched faction cancels the pending return, including changes made by another addon. A return that expires while the Reputation or Collections panel is open is cancelled to avoid rearranging the UI.
  - `/sqol repfocus status` shows the saved faction; `/sqol repfocus clear` forgets it. Disabling either option or resetting addon settings cancels pending work and keeps the saved preference.
  - Panel checks use effective visibility, including hidden parents. Delayed watched-faction updates are acknowledged for up to two seconds before being discarded; a confirmed temporary faction starts the return timer.
  - The preference and a pending return survive `/reload` and login. A saved return is resumed only if the watched faction still matches the temporary faction; it does not override a changed selection. Uses one return timer, with no frame polling. In-game Retail and WoW Forever validation is required before release.
- 🏷️ **Nameplate objective counts**
  - Shows quest objective progress (e.g., 0/10 or 45%) above relevant nameplates, with fallbacks for bonus/world quests.
- 🧾 **PlayerFrame iLvl + Speed**
  - Independently toggle item level and movement speed. Shows either value alone, or both on the same line: `iLvl: xx.x  Spd: yy%`.
- 🎯 **Target in unit tooltips**
  - Adds a `Target:` line to unit tooltips showing who the unit is targeting: class-colored for players, reaction-colored for NPCs, and a red `You` when it is you. Updates live while you hover.
  - Toggle with `/sqol tooltiptarget` (`tt`). Disabled by default. Skipped when the client hides the unit's data (secret values in 12.x).
- 🏹 **Range icon and distance**
  - Shows the distance to an attackable target on its nameplate (where Blizzard's soft target sword icon sits, just above the quest objective count when one is shown), or next to the target frame portrait when the target has no nameplate, as a range in yards (`< 5 yd`, `8-30 yd`, `> 40 yd`). The client has no exact distance for enemies, so the range comes from the abilities on your action bars that do and don't reach.
  - Adds a pulsing icon when none of your offensive abilities can reach the target. Uses the same range check that tints action buttons red, so it follows druid forms and bonus bars, and needs no class-specific spell lists.
  - While enabled, Blizzard's soft target sword icon over enemy nameplates (`SoftTargetIconEnemy`) is turned off so the two aren't confused; it is turned back on when you disable the feature.
  - Toggle with `/sqol range` (`rng`). Disabled by default.
- 🖋️ **Custom damage text font**
  - Replaces floating combat text damage numbers with a custom font.
- 🖱️ **Cursor shake highlight**
  - Highlights the cursor when you shake the mouse.
- 🧪 **Debug tracking (optional)**
  - Enables verbose tracking output for troubleshooting.

## Configuration

### Options window

A standalone, movable window with all settings grouped into sections (Quests, Character, Reputation & XP, Group, Interface, Advanced). Open it from:
- 🧩 **LibDataBroker displays** such as Bazooka, Titan Panel or ChocolateBar — left-click the SMoRG's QoL icon (right-click opens Blizzard's Settings page).
- 📋 **The addon compartment** menu by the minimap (Retail and WoW Forever).
- 🗺️ **The minimap button** — off by default; enable it with `/sqol minimap` (`mm`) or **Show minimap button**.
- 💬 `/sqol config` (or `/sqol options`).

### Settings UI

Open:
- ⚙️ **Esc → Options → AddOns → SMoRG's QoL**

Both show the same settings and stay in sync with each other and the slash commands.

### Slash commands

Type `/sqol` to see current status, or use:

- `/sqol help`
- `/sqol config` (or `/sqol options`) — open the options window
- `/sqol recap` — open Adventure Recap (enable recording in **Quests**)
- `/sqol recap last` — show the previous session
- `/sqol recap reset` — clear the current session; keep the previous session
- `/sqol recap test` — show sample data without changing saved statistics
- `/sqol minimap` (or `/sqol mm`) — toggle the minimap button
- `/sqol autotrack` (or `/sqol at`)
- `/sqol color` (or `/sqol col`) — toggle quest progress colors
- `/sqol barcolor` (or `/sqol bc`) — independently toggle XP/reputation number colors
- `/sqol questsound` (or `/sqol qs`)
- `/sqol objectivesound` (or `/sqol os`)
- `/sqol soundprofile` (or `/sqol soundset`)
- `/sqol splash`
- `/sqol hideach` (or `/sqol ha`)
- `/sqol rep` (or `/sqol rw`)
- `/sqol repmemory` (or `/sqol rm`) — toggle returning to your preferred reputation
- `/sqol repfocus` — save the currently watched faction for this character
- `/sqol repfocus status` — show the preferred faction
- `/sqol repfocus clear` — forget the preferred faction and cancel a pending return
- `/sqol nameplate` (or `/sqol np`)
- `/sqol radar` (or `/sqol qr`) — toggle Smart Quest Radar on visible nameplates
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
- `/sqol tooltiptarget` (or `/sqol tt`)
- `/sqol range` (or `/sqol rng`)
- `/sqol debugtrack` (or `/sqol dbg`)
- `/sqol reset`

## Saved Variables

Settings are stored per account in:
- 💾 `SQOL_DB`

Adventure Recap stores the current session, the previous session and its window
position per character in `SQOL_RecapDB`. Resetting addon settings pauses recording
and preserves recap data. As with other SavedVariables, changes reach disk when
the client saves the UI (normally on logout or `/reload`); a crash may lose changes
since that save. Clients without a reload flag conservatively start a new session
on UI load.

Reputation Memory stores its preferred faction and any pending return per character
in `SQOL_CharacterDB`, separately from Adventure Recap. Account-wide option switches
remain in `SQOL_DB`. Resetting addon settings disables memory without deleting the
character's preferred faction.

## Translations

SMoRG's QoL follows your game language: English, German, French, Spanish (Spain and Latin America), Brazilian Portuguese, Italian, Russian, Korean, and Simplified and Traditional Chinese. The quest voice lines are always in English, and the slash commands are the same in every language.

⚠️ **The translations have not been checked by native speakers.** They use Blizzard's own terms where possible, but some wording may be clumsy or wrong. If something reads oddly in your language, please suggest a better text on [CurseForge](https://www.curseforge.com/wow/addons/smorgsqol) or [GitHub](https://github.com/SMoRG75/SMoRGsQoL/issues). Corrections are very welcome.

## Support

SMoRG's QoL is free and always will be. If it makes your questing a little more fun and you'd like to say thanks, you can sponsor its development on [GitHub Sponsors](https://github.com/sponsors/SMoRG75). Bug reports and ideas are just as welcome on [CurseForge](https://www.curseforge.com/wow/addons/smorgsqol) or [GitHub](https://github.com/SMoRG75/SMoRGsQoL/issues).

## Updating to 1.2.1

Install the complete addon folder, including the `Media` folder (which now holds
the icon and the damage text font) and all files listed in `SMoRGsQoL.toc`, then
restart the game (a `/reload` does not load new files). Keep your saved variables; existing settings are preserved. The addon
picks the language of your game client automatically.

## Code structure

The `.toc` loads shared utilities and feature modules before the main controller.
Modules share the addon's private `SQOL` namespace; implementation helpers stay local.

| File | Responsibility |
| --- | --- |
| `Locales/Locales.lua` | The `SQOL.L` translation table (English text is the key and the fallback) |
| `Locales/<locale>.lua` | Translations for one client language (`esES.lua` also serves esMX) |
| `Core.lua` | Defaults, sound profiles, shared utilities and namespace setup |
| `VisualTweaks.lua` | Damage font, cursor highlight, achievement filter and tooltip target line |
| `QuestRadar.lua` | Optional quest radar, safe tooltip parsing and active-quest relevance |
| `QuestProgress.lua` | Quest data cache, progress colors/messages, scenario progress and nameplate objectives |
| `PlayerStats.lua` | Independent item level and movement speed displays |
| `PartyLevels.lua` | Levels on default and raid-style party frames |
| `RangeIndicator.lua` | Range icon and distance for the target |
| `Reputation.lua` | Reputation watching, preferred faction memory, safe faction lookup and header preservation |
| `SessionRecap.lua` | Per-character Adventure Recap tracking, persistence and movable window |
| `Countdowns.lua` | Shared countdown implementation, ready checks and queue pops |
| `SMoRGsQoL.lua` | Saved settings/migration, option side effects, commands, events, auto-tracking and quest completion notifications |
| `Options.lua` | Shared option list (sections, labels, tooltips) and Blizzard's Settings page |
| `OptionsPopup.lua` | Standalone options window built from the shared option list |
| `Launcher.lua` | LibDataBroker launcher, LibDBIcon minimap button and addon compartment entry |
| `StatusBarProgress.lua` | Independent XP/reputation number colors |

`Libs/` embeds LibStub (public domain), CallbackHandler-1.0 (Ace3), LibDataBroker-1.1
(public domain) and LibDBIcon-1.0, each under its own license.

Quest progress and nameplate logic remain together because they share quest parsing
and cached data. New feature modules should keep private state/helpers local and
expose only the entry points needed by the controller through `SQOL`.

Run `lua tests/smoke.lua` from the repository root for a mocked load/event/command
smoke test. It reads the real TOC order. In-game testing is still needed for frame
layout, protected UI behavior and real quest/reputation data.

Run `lua tests/recap.lua` for focused tests of turn-ins, repeatable quests,
duplicate events, localized reputation, secret values, fallback APIs, session
boundaries, character isolation, paused recording, reset and preview data.

Run `lua tests/reputation.lua` for reputation-memory deadlines, burst gains,
external bar changes, cancellation, effective panel visibility, delayed faction
acknowledgements, reload, per-character state, secret values,
and modern/legacy reputation and timer APIs. These tests mock the client APIs;
verify the actual watched bar and events in both clients before release.

Run `lua tests/radar.lua` for quest relevance, multiple and completed objectives,
party sections, text-only clients, restricted data, API failures, tooltip refreshes
and nameplate reuse. The smoke test also checks TOC loading and radar commands.
These mocked tests do not replace testing inside both clients.

All visible text goes through `L["English text"]`. Run `lua tests/locales.lua` after
changing any of it: it fails when a translation's English key is no longer used in
the code or its `%s`/`%d` or color codes don't match, and lists missing translations
(those fall back to English).
