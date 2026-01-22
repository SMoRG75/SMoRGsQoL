# SMoRG's QoL

A small collection of **opt-in** quality-of-life tweaks for World of Warcraft (Retail).

Everything is toggleable:
- ⚙️ via the in-game Settings UI, or
- 💬 via `/sqol` chat commands.

## Features

- 🧭 **Auto-track newly accepted quests**
  - Automatically tracks new quests in the Objective Tracker (with sanity checks to avoid unsupported edge cases).
- 🔔 **Quest completion alert**
  - Plays a sound (toggleable) and prints a chat message when a quest is ready to turn in (or done for bonus/world quests).
- 🎨 **Colorized progress messages**
  - Colorizes common progress patterns like `3/10` or `45%` and quest objective progress (red → yellow → green).
- 🚪 **Login splash**
  - Optional status splash on login showing which features are ON/OFF.
- ✅ **Hide completed achievements**
  - Makes the Achievement UI default to showing incomplete achievements only.
- 🤝 **Auto-watch reputation gains**
  - Switches your watched faction to the one that changed when you gain reputation.
- 🏷️ **Nameplate objective counts**
  - Shows quest objective progress (e.g., 0/10 or 45%) above relevant nameplates, with fallbacks for bonus/world quests.
- 🧾 **PlayerFrame iLvl + Speed**
  - Adds an extra line to the PlayerFrame: `iLvl: xx.x  Spd: yy%`
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
- `/sqol color` (or `/sqol col`)
- `/sqol questsound` (or `/sqol qs`)
- `/sqol splash`
- `/sqol hideach` (or `/sqol ha`)
- `/sqol rep` (or `/sqol rw`)
- `/sqol nameplate` (or `/sqol np`)
- `/sqol stats` (or `/sqol ilvl`)
- `/sqol damagefont` (or `/sqol df`)
- `/sqol cursor` (or `/sqol cs`)
- `/sqol cursorflash` (or `/sqol cf`)
- `/sqol debugtrack` (or `/sqol dbg`)
- `/sqol reset`

## Saved Variables

Settings are stored per account in:
- 💾 `SQOL_DB`
