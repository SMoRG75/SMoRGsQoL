# SMoRG's QoL

**Hear your quest progress:** *"Work, work."* when you finish an objective, *"Work complete."* when the quest is done. Plus toggleable QoL tweaks for Retail, WoW Forever, Classic Era, Anniversary and Mists of Pandaria Classic.

🔊 The worker voice lines are where it all started. Prefer the Alliance? Switch to the Human worker (*"More work?"* / *"Job's done!"*). Every other feature is a small, **individually toggleable** tweak.

Everything is toggleable:
- 🪟 via the options window (LibDataBroker displays such as Bazooka, the addon compartment menu, the optional minimap button or `/sqol config`),
- ⚙️ via the in-game Settings UI, or
- 💬 via `/sqol` chat commands.

## What's new in 1.4.0

- 🏰 **Classic Era, Anniversary and Mists of Pandaria Classic** — the addon now runs in the three Classic clients, quest sounds included. Features a client can't support are left out of its options instead of showing up and doing nothing; see [Classic clients](#classic-clients).
- 🏹 **Hunter range in WoW Forever** — the distance no longer reads `< 5 yd` at any range. It shows `8-35 yd` at shooting range, and out of combat `> 35 yd` with the icon when the target is too far.

See the [changelog](CHANGELOG.md) for the full release history.

### 1.3.0

- 📡 **Smart Quest Radar** — a quest icon and up to three unfinished objective counts above the nameplates of units you still need for your quests, e.g. `2/8 · 1/5`. `/sqol radar` (`qr`).
- 📖 **Adventure Recap** — a session window with the quests and world quests you completed, reputation gained, playtime and your most active faction, kept per character. `/sqol recap`.
- 🧠 **Reputation Memory** — save a preferred faction with `/sqol repfocus`; after auto-watch has shown a new gain, the reputation bar goes back to it after 10 seconds.
- 🌍 **WoW Forever** — the item level/speed line now sits above your name like on Retail and follows the player frame's size, and the colored XP/reputation text stays visible instead of only on mouseover.

All three new features are off by default; turn them on in the options window. 1.3.0 added new files, so updating from an older version needs a game restart.

### 1.2.1

- 🛠️ **Updated for WoW 12.1.5.**
- 📜 **New addon icon** — a simple quest scroll with a green check that is easy to recognize at the small sizes it is shown in: the AddOns list, the minimap button, the options window and LibDataBroker displays.
- 🔤 **Damage text font note** — the tooltip for **Custom damage text font** and the options window now say that the font only changes after a game client restart.

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

- 🔊 **Quest sounds: objective and quest completion**
  - Plays a worker voice line when an individual objective is completed before the full quest is done (Peon: *"Work, work."*).
  - Plays another voice line and prints a chat message when the whole quest is ready to turn in, or done for bonus/world quests (Peon: *"Work complete."*).
  - Choose the Horde (Peon) or Alliance (Human worker: *"More work?"* / *"Job's done!"*) sound profile, and toggle each sound on its own (`/sqol objectivesound`, `/sqol questsound`, `/sqol soundprofile`).
- 📡 **Smart Quest Radar**
  - Marks relevant visible nameplates with a quest icon and up to three unfinished objective counts on one line, for example `2/8 · 1/5`. More objectives are summarized as `+N`.
  - Enable **Smart Quest Radar** under **Quests**, or toggle it with `/sqol radar` (`qr`). Off by default. While enabled, it replaces the plain nameplate objective counts; turning it off brings them back. **Color quest progress** also colors the radar counts.
  - Reads the quest lines in the unit's tooltip and matches them to your own active quests. Finished objectives, your party's progress and anything the client keeps hidden are skipped, so a unit only gets marked when the addon is sure.
  - Only units with a visible nameplate can be marked; quest objects without a nameplate are not.
  - Retail and WoW Forever only.
- 📖 **Adventure Recap**
  - A movable window with this session's completed quests, world quests, reputation gained, playtime and your most active faction.
  - Enable **Adventure Recap** under **Quests**, then open it from the options window or with `/sqol recap`. Recording is off by default, and the window never pops up by itself.
  - `/sqol recap last` shows the previous session, `/sqol recap reset` starts the current session over, and `/sqol recap test` shows sample data without touching your real numbers.
  - Sessions are kept per character. `/reload` continues the session; logging in again starts a new one and keeps the previous one. Offline time and time with recording turned off are not counted.
  - A quest counts when you turn it in. If some reputation messages could not be read, the total is marked as incomplete and no top faction is shown.
- 🤖 **Quest automation**
  - Accepts quests and turns in completed quests at quest givers, from the quest window, the quest list of NPCs without gossip and the quest lines in gossip — a replacement for Leatrix Plus' *Automate quests*. With several quests on one NPC it handles one at a time, completed quests first, until nothing is left that it may take.
  - Choose separately whether to accept regular, daily and weekly quests, and whether to turn in completed quests (`/sqol questaccept`, `/sqol questdaily`, `/sqol questweekly`, `/sqol questturnin`). All off by default.
  - **Override key** (SHIFT, ALT, CONTROL or CMD on a Mac, `/sqol questkey`): normally, holding it pauses automation, so you can read a quest or pick it yourself. With **Require override key for quest automation** on (`/sqol questrequirekey`), it works the other way round: quests are only automated while you hold the key. Same as Leatrix Plus.
  - Leaves the choice to you when a quest has several rewards, and never turns in a quest that takes money, currency or items that are not quest items (cloth donations, trade goods). Skips quests shared by other players (escorts, group quests in dungeons), quests that flag you for PvP, ignored quests and low-level quests (unless the minimap shows them; in the Classic clients low-level quests are always skipped).
  - Does nothing in combat inside instances, and in gossip only clicks quest lines, never gossip options, so dungeon NPCs that start an event are left alone. A quest it leaves for you is not picked again for 30 seconds, so **Back** in the quest window returns to the NPC's list.
- 🧭 **Auto-track newly accepted quests**
  - Automatically tracks new quests in the Objective Tracker (with sanity checks to avoid unsupported edge cases).
  - Retail and WoW Forever only.
- 🎨 **Colorized progress messages**
  - Colorizes common progress patterns like `3/10` or `45%` and quest objective progress (red → yellow → green).
  - Also covers progress-bar quest objectives and scenario weighted-progress bars, which the default UI reports silently.
  - The counts in the quest tracker are colored in Retail and WoW Forever; the Classic clients color the progress messages only.
- 🎨 **XP/reputation number colors**
  - Reputation text also shows the percentage remaining in the current bar and your current standing after the total, e.g. `4995 / 6000 · 16.8% left · Friendly`.
  - Independently colors the current XP/reputation number on Blizzard's standard bars (red → yellow → green), with outlined text. Labels and maximum values stay white; bar colors are unchanged.
  - Toggle with `/sqol barcolor` (`bc`) or **Color XP/reputation numbers** in Settings. Disabled by default; independent of quest progress colors.
  - In WoW Forever the text stays visible all the time while this is on; there it would otherwise only show on mouseover or with the Character window open.
  - In the Classic clients it is offered only where the client has the same XP/reputation bars as Retail.
- ⏱️ **Ready check countdown**
  - Shows a live countdown of the seconds left on a ready check, turning red for the last 5 seconds.
  - Appears below the ready check popup, or near the top of the screen when you started the ready check yourself (Blizzard never shows the popup to the initiator).
- ⏳ **LFG queue pop countdown**
  - Shows how many of your 40 seconds are left to accept a group finder pop, turning red for the last 5.
  - Sits below the queue pop's ready status frame, so it stays useful while you wait for the rest of the group to accept.
  - Not in Classic Era or Anniversary, which have no group finder queue.
- 👥 **Party member levels**
  - Shows each party member's level on both default and raid-style party frames while leaving raid and arena frames unchanged.
- 🚪 **Login splash**
  - Optional status splash on login showing which features are ON/OFF.
- ✅ **Hide completed achievements**
  - Makes the Achievement UI default to showing incomplete achievements only.
  - Not available in WoW Forever, which replaces achievements with the Legacy system, or in Classic Era and Anniversary, which have no achievements.
- 🤝 **Auto-watch reputation gains**
  - Switches your watched faction to the one that changed when you gain reputation.
- 🧠 **Reputation Memory**
  - Keep one preferred faction per character. Choose a faction to watch in Blizzard's Reputation panel, then run `/sqol repfocus` to remember it.
  - Enable **Auto-watch reputation gains** and **Return to preferred reputation** under **Reputation & XP**. Both are off by default. Auto-watch shows a new gain for a moment, then goes back to your preferred faction after 10 seconds without new gains.
  - Picking another faction yourself (or with another addon) cancels the return. A return that comes due while the Reputation or Collections panel is open is skipped, so the list does not jump under your mouse.
  - `/sqol repfocus status` shows the saved faction; `/sqol repfocus clear` forgets it. The preference and a pending return survive `/reload` and login.
- 🏷️ **Nameplate objective counts**
  - Shows quest objective progress (e.g., 0/10 or 45%) above relevant nameplates, with fallbacks for bonus/world quests.
  - Retail and WoW Forever only.
- 🧾 **PlayerFrame iLvl + Speed**
  - Independently toggle item level and movement speed. Shows either value alone, or both on the same line: `iLvl: xx.x  Spd: yy%`.
- 🎯 **Target in unit tooltips**
  - Adds a `Target:` line to unit tooltips showing who the unit is targeting: class-colored for players, reaction-colored for NPCs, and a red `You` when it is you. Updates live while you hover.
  - Toggle with `/sqol tooltiptarget` (`tt`). Disabled by default. Skipped when the client hides the unit's data (secret values in 12.x).
  - In the Classic clients it is offered only where the client has Retail's tooltip system (Mists of Pandaria Classic does).
- 🎨 **Colorful unit tooltips**
  - Players' names, specs, the tooltip border and the health bar in their class color (reaction colors for NPCs, gray for tapped mobs), the guild in green as `<Guild>`, the level in Blizzard's difficulty color (red `??` for bosses), and `Horde` in red or `Alliance` in blue.
  - Shows the health on the tooltip's health bar, e.g. `18.8K / 23.8K (79%)`.
  - Toggle with `/sqol tooltipcolor` (`tc`). Disabled by default. Skipped when the client hides the unit's data (secret values in 12.x); offered where the tooltip target line is.
- 🔗 **Wowhead links** — a replacement for Leatrix Plus' *Show Wowhead links* and its *Show web link* key binding.
  - **Show Wowhead links** (under **Interface**, `/sqol wowhead` or `wh`, off by default) puts a Wowhead link for the quest in the quest log at the top of the world map (Retail and WoW Forever: the quest you have open, otherwise the one you track) or in place of the quest log title (Classic), and one for the achievement you open at the bottom of the achievement window. Hover the link and press CTRL+C to copy it.
  - **Show web link** is a key binding under **Key Bindings > SMoRG's QoL**, without a default key (Leatrix Plus users had SHIFT-W). It works without the option: press it over a tooltip and a copyable link pops up for the item, spell, aura, quest, achievement or currency, the NPC under the mouse, a battle pet, or a player's armory page (Retail). Anything else gets a Wowhead search for the tooltip's title. Press CTRL+C to copy and close it, or Escape or right-click to close it.
  - Links go to each client's own Wowhead: `de.wowhead.com` style in Retail, `wowhead.com/classic`, `/tbc`, `/mop-classic` and `/forever` (with `/de` and so on) elsewhere, in your client's language.
- 🏹 **Range icon and distance**
  - Shows the distance to an attackable target on its nameplate (where Blizzard's soft target sword icon sits, just above the quest objective count when one is shown), or next to the target frame portrait when the target has no nameplate, as a range in yards (`< 5 yd`, `8-30 yd`, `> 40 yd`). The client has no exact distance for enemies, so the range comes from the abilities on your action bars that do and don't reach.
  - Adds a pulsing icon when none of your offensive abilities can reach the target. Uses the same range check that tints action buttons red, so it follows druid forms and bonus bars, and needs no class-specific spell lists.
  - While enabled, Blizzard's soft target sword icon over enemy nameplates (`SoftTargetIconEnemy`) is turned off so the two aren't confused; it is turned back on when you disable the feature.
  - Toggle with `/sqol range` (`rng`). Disabled by default.
  - Retail and WoW Forever only. In WoW Forever, a hunter's distance to a far-away target can read `< 5 yd` in combat, because the client reports Raptor Strike in range at any distance and blocks the distance check that rules it out.
- 🖋️ **Custom damage text font**
  - Replaces floating combat text damage numbers with a custom font.
- 🖱️ **Cursor shake highlight**
  - Highlights the cursor when you shake the mouse.
- 🧪 **Debug tracking (optional)**
  - Enables verbose tracking output for troubleshooting.

## Classic clients

SMoRG's QoL runs in Classic Era, Anniversary and Mists of Pandaria Classic as well as Retail and WoW Forever, with the quest sounds working in all of them. Features a Classic client can't support are left out of the options window, the Settings page and `/sqol`, and are switched off if they were on:

| Feature | Classic Era | Anniversary | Mists of Pandaria Classic |
| --- | --- | --- | --- |
| Auto-track, Smart Quest Radar, nameplate objective counts | – | – | – |
| Range icon and distance | – | – | – |
| Colored counts in the quest tracker | – | – | – |
| Hide completed achievements | – | – | ✓ |
| LFG queue pop countdown | – | – | ✓ |
| Target in unit tooltips, colorful unit tooltips, XP/reputation number colors | where the client supports it | where the client supports it | where the client supports it |

Everything else, from the quest sounds, quest automation and Wowhead links to the item level/speed line, reputation features, countdowns and party levels, works in every client.

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
- `/sqol questaccept` (or `/sqol qa`) — accept regular quests automatically
- `/sqol questdaily` (or `/sqol qd`) — accept daily quests automatically
- `/sqol questweekly` (or `/sqol qw`) — accept weekly quests automatically
- `/sqol questturnin` (or `/sqol qt`) — turn in completed quests automatically
- `/sqol questrequirekey` (or `/sqol qrk`) — only automate quests while the override key is held
- `/sqol questkey` (or `/sqol qk`) — next override key; `/sqol questkey shift|alt|control|cmd` picks one
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
- `/sqol tooltipcolor` (or `/sqol tc`)
- `/sqol range` (or `/sqol rng`)
- `/sqol wowhead` (or `/sqol wh`) — toggle the Wowhead links in the quest log and achievement window
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

## Updating to 1.4.0

Install the complete addon folder, including the `Media` and `Sounds` folders and all
files listed in `SMoRGsQoL.toc`. 1.4.0 adds no new files, so coming from 1.3.0 a
`/reload` is enough; from an older version, restart the game (a `/reload` does not
load new files). In a Classic client, install it into that client's own
`Interface\AddOns` folder, e.g. `_classic_era_`, `_anniversary_` or `_classic_`. Keep
your saved variables; existing settings are preserved. The addon picks the language
of your game client automatically.

## Code structure

The `.toc` loads shared utilities and feature modules before the main controller.
Modules share the addon's private `SQOL` namespace; implementation helpers stay local.

| File | Responsibility |
| --- | --- |
| `Locales/Locales.lua` | The `SQOL.L` translation table (English text is the key and the fallback) |
| `Locales/<locale>.lua` | Translations for one client language (`esES.lua` also serves esMX) |
| `Core.lua` | Client detection (Retail, WoW Forever, Classic), defaults, sound profiles, shared utilities and namespace setup |
| `VisualTweaks.lua` | Damage font, cursor highlight, achievement filter, tooltip target line and tooltip colors |
| `QuestRadar.lua` | Optional quest radar, safe tooltip parsing and active-quest relevance |
| `QuestAutomation.lua` | Accepting and turning in quests at quest givers, with the override key |
| `WowheadLinks.lua` | Wowhead links in the quest log and achievement window, and the "Show web link" popup |
| `Bindings.xml` | The "Show web link" key binding (loaded by the client without a TOC entry) |
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

Run `lua tests/classic.lua` for a mocked Classic Era client: Retail-only events
that would fail to register, options hidden where Classic lacks the API, and quest
sounds from the `GetQuestLogTitle` quest log fallback. It does not replace testing
inside the Classic Era client.

All visible text goes through `L["English text"]`. Run `lua tests/locales.lua` after
changing any of it: it fails when a translation's English key is no longer used in
the code or its `%s`/`%d` or color codes don't match, and lists missing translations
(those fall back to English).
