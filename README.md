# DMLUI 2.0.98

DMLUI is a modular WoW 3.3.5a UI project. Install only the folders for the modules you want.

## Included modules

- `DMLUI_Core/` - shared minimap launcher and module framework (2.0.97).
- `DMLCooldownBar/` - Action Bars module (unchanged from 2.0.91).
- `DMLCooldownBar_J3Spells/` - optional J3Spells integration for Action Bars (unchanged from 2.0.91).
- `DMLUnitFrames/` - Unit Frames module (2.0.98).
- `DMLCastBar/` - optional movable/customizable player cast bar (unchanged from 2.0.97).

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
