# DMLUI 2.0.96

DMLUI is a modular World of Warcraft 3.3.5a interface project. Install only the modules you want.

Included folders:
- `DMLUI_Core/` - shared launcher/module framework (2.0.96).
- `DMLCooldownBar/` - Action Bars module (2.0.91; unchanged in this release).
- `DMLCooldownBar_J3Spells/` - optional J3Spells/ALE integration (2.0.91; unchanged in this release).
- `DMLUnitFrames/` - Unit Frames module (2.0.96).

## 2.0.96 highlights

Unit Frames:
- Party and hostile Target range fading now use a player-selected spell from the character's own spellbook instead of artificial yard presets.
- Range menus are filtered to known ranged helpful/harmful spells, collapse duplicate ranks, cap the menu size, and show spell icon/name/max range.
- Party range fading also applies to the DML Target frame when the selected target is that party member.
- Hostile unit levels use Blizzard's gray/green/yellow/orange/red difficulty colors; unknown/boss levels use the stock skull texture.
- Optional cast bars for Player, Target, and Target of Target, each independently placed Above or Below its DML unit frame.
- Existing aggro highlight, combat icon, target-of-target visibility, party layout, freeform positioning, and 0.50x-2.00x complete-frame scaling remain intact.

Range checking uses `IsSpellInRange` with a spell the character actually knows. It does not use item-based range checks or item-info queries.
