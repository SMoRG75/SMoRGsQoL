# Changelog

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
