# SMoRG's QoL

A small collection of **opt-in** quality-of-life tweaks for World of Warcraft (Retail).

Everything is toggleable:
- via the in-game Settings UI, or
- via `/sqol` chat commands.

## Features

- **Auto-track newly accepted quests**
  - Automatically tracks new quests in the Objective Tracker (with sanity checks to avoid unsupported edge cases).
- **Colorized progress messages**
  - Colorizes common progress patterns like `3/10` and quest objective progress (red → yellow → green).
- **Login splash**
  - Optional status splash on login showing which features are ON/OFF.
- **Hide completed achievements**
  - Makes the Achievement UI default to showing incomplete achievements only.
- **Auto-watch reputation gains**
  - Switches your watched faction to the one that changed when you gain reputation.
- **Nameplate objective counts**
  - Shows quest objective progress (e.g., 0/10) above relevant nameplates, with fallbacks for bonus/world quests.
- **PlayerFrame iLvl + Speed**
  - Adds an extra line to the PlayerFrame: `iLvl: xx.x  Spd: yy%`
- **Custom damage text font**
  - Replaces floating combat text damage numbers with a custom font.

## Configuration

### Settings UI

Open:
- **Esc → Options → AddOns → SMoRG's QoL**

### Slash commands

Type `/sqol` to see current status, or use:

- `/sqol help`
- `/sqol autotrack` (or `/sqol at`)
- `/sqol color` (or `/sqol col`)
- `/sqol splash`
- `/sqol hideach` (or `/sqol ha`)
- `/sqol rep` (or `/sqol rw`)
- `/sqol nameplate` (or `/sqol np`)
- `/sqol stats` (or `/sqol ilvl`)
- `/sqol damagefont` (or `/sqol df`)

## Saved Variables

Settings are stored per account in:
- `SQOL_DB`
