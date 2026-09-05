# DMLUI v2.0.124

Modular UI addon for World of Warcraft 3.3.5a. Install DMLUI_Core plus any optional modules you want.

## 2.0.123
- Unit Frames: Blizzard-style party/group leader crown at the portrait top-left.
- Unit Frames: PvP faction/FFA badge at the portrait bottom-right for PvP-flagged player units.
- Core Profiles: shared named profiles for Unit Frames, Cast Bars, Buffs, and Quest Tracker.
- Action Bars intentionally keep their existing independent profile system.
- Shared profiles are module-safe: loading ignores missing modules, and saving an existing profile preserves data belonging to missing modules. Reinstalling a module later leaves its saved profile section intact.
- Quest Tracker profile snapshots intentionally exclude per-quest +/- collapse state.
