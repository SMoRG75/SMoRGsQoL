# Changelog

## [1.0.18] - 2026-07-05

### Fixed
- RepWatch no longer rescans on UPDATE_FACTION while the Reputation panel is open, so clicking an expansion header to collapse/expand it no longer makes the list jump.

## [1.0.17] - 2026-07-04

### Fixed
- Show colorized progress messages for progress-bar quest objectives (e.g. "Umbral Attuning Shard charged"), using the objective's own label and avoiding a duplicated percentage.

## [1.0.16] - 2026-06-14

### Added
- Added a separate sound when an individual quest objective is completed.
- Added selectable Horde (Peon) and Alliance (Human worker) quest sound profiles.

### Fixed
- Reset quest completion tracking when a quest is accepted even if auto-track is disabled.

## [1.0.15] - 2026-05-05

### Fixed
- Kept quest completion sound and chat alerts limited to when a quest becomes ready to turn in.

## [1.0.14] - 2026-04-24

### Fixed
- Fixed PlayerFrame speed display errors caused by WoW 12.0 secret movement speed values.

## [1.0.13] - 2026-04-02

### Fixed
- Fixed 'msg' a secret string value tainted

## [1.0.11] - 2026-01-29

### Fixed
- Better nameplate objective handling

## [1.0.10] - 2026-01-08

### Fixed
- RepWatch preserves collapsed reputation headers instead of forcing the list open.
- RepWatch verifies the watched faction actually changed and falls back to legacy index switching when needed.

## [1.0.9] - 2026-01-07

### Fixed
- RepWatch now refreshes faction counts after expanding headers, so watched reputation switches reliably on gains.

## [1.0.8] - 2026-01-04

### Changed
- Progress for 100-based objectives now displays as a percent (e.g., 45% instead of 45/100).

## [1.0.7] - 2026-01-02

### Added
- Optional cursor shake highlight to help locate the mouse cursor during combat.
- Debug command to flash the cursor ring on demand (`/sqol cursorflash`).

## [1.0.6] - 2026-01-02

### Added
- Optional nameplate objective counts (e.g., 0/10) with tooltip/progress-bar fallbacks.

### Fixed
- Tooltip-based progress ignores threat lines to prevent false 100/100 displays.

## [1.0.5] - 2026-01-01

### Changed
- Updated `.toc` metadata (clean Notes, proper fields, removed unrelated CurseForge links).
- Added `README.md` and `CHANGELOG.md` for CurseForge / repository presentation.

## [1.0.0] - 2025-12-30

### Added
- Quest completion alert with sound + chat message when a quest is ready to turn in (or done for bonus/world quests).
- Debug tracking toggle and reset command (`/sqol debugtrack`, `/sqol reset`).
