# DMLUI 2.0.104

DMLUI is a modular WoW 3.3.5a UI project. Install only the folders for the modules you want.

## Included modules

- `DMLUI_Core/` - shared minimap launcher and module framework (2.0.100).
- `DMLCooldownBar/` - Action Bars module (unchanged from 2.0.91).
- `DMLCooldownBar_J3Spells/` - optional J3Spells integration for Action Bars (unchanged from 2.0.91).
- `DMLUnitFrames/` - Unit Frames module (2.0.104).
- `DMLCastBar/` - optional movable/customizable player cast bar (2.0.101).


## 2.0.104 highlights

### Unit Frames
- Corrected 3D portraits for WoW 3.3.5a by selecting Model camera 0, the client's native facial portrait camera, after binding the unit model.
- Reapplies the facial camera when a portrait model is shown again so the client cannot leave it in the full-body view after UI/model visibility changes.
- Keeps the GUID-cached model refresh and `UNIT_MODEL_CHANGED` handling introduced in 2.0.103.


## 2.0.103 highlights

### Unit Frames
- Fixed 3D portrait framing to use the PlayerModel portrait camera with a slight pullback for a head-and-shoulders crop instead of the full-body model.
- Removed the model-position reset from the 3D portrait refresh path.
- Cached 3D model bindings by unit GUID so ordinary health/resource/name updates no longer call `SetUnit()` repeatedly.
- Added `UNIT_MODEL_CHANGED` refresh handling for shapeshifts and transformations.


## 2.0.102 highlights

### Unit Frames
- Added `Portrait type`: 2D Portrait, 3D Portrait, or Class Icon.
- Class Icon uses the stock class-icon atlas for the player and friendly player units, and automatically falls back to 2D portraits for enemies (including enemy players), NPCs, pets, and other non-player units.
- 3D Portrait uses a live PlayerModel in the existing portrait slot; frame layout and scaling are unchanged.

## 2.0.101 highlights

### Cast Bar
- Fixed duplicate player cast bars when DML Cast Bar is enabled.
- Blizzard's stock `CastingBarFrame` is now suppressed through its native 3.3.5 `showCastbar` flag and hidden immediately.
- Turning DML Cast Bar off restores the stock bar's previous state and resyncs an in-progress cast.

## 2.0.100 highlights

### Unit Frames
- Split `Show class` and `Show creature type` into separate options.
- Added a configurable `Name` color swatch. Player class colors override it only when `Use class color as name` is enabled.
- Added `Use class color for class text` independently from name coloring.
- Existing Unit Frames and Cast Bar behavior from 2.0.99 is preserved.

## 2.0.99 highlights

### Cast bars
- Rebuilt both the standalone DML Cast Bar and Unit Frames attached cast bars on Blizzard's stock Wrath 3.3.5 `CastingBarFrameTemplate` state/event engine.
- DML still owns width/height/position/color/border/text/time presentation; Blizzard's proven cast/channel timing engine now drives visibility and progress.
- Player/Target/Target-of-Target attached bars continue to respect their independent enable and Above/Below settings.

## 2.0.98 highlights

### Unit Frames
- Fixed the spell-range dropdown on stock WoW 3.3.5a by reading the original nine-value `GetSpellInfo` return layout correctly.
- Spellbook candidates are resolved from actual spellbook slots with `GetSpellName` / `GetSpellBookItemInfo`, then queried by spell ID when possible.
- Helpful/harmful range lists remain rank-collapsed, capped, and limited to meaningful ranged spells.
- Reworked aggro highlighting into a red overlay drawn outside the complete unit frame so portraits cannot cover it.
- Added `Aggro border intensity` slider + numeric field, clamped from 1-8.

Existing Unit Frames features remain available: player/target/focus/pet/target-of-target/party frames, scaling, freeform/grouped party positioning, spell-based range fading, combat icons, attached cast bars, configurable colors, class-colored names, and rare/elite classification art.

## Slash commands

- `/dmlui` - DMLUI launcher.
- `/dmluf` - Unit Frames settings.
- `/dmlcast` - Cast Bar settings.
