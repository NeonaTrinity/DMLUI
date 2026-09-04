# DMLUI 2.0.92

DMLUI is a modular World of Warcraft 3.3.5a interface project. Install only the modules you want.

Included folders:
- `DMLUI_Core/` - shared launcher/module framework.
- `DMLCooldownBar/` - Action Bars module (2.0.91; unchanged in this release).
- `DMLCooldownBar_J3Spells/` - optional J3Spells/ALE integration (2.0.91; unchanged in this release).
- `DMLUnitFrames/` - Unit Frames module (2.0.92).

## 2.0.92 highlights

Unit Frames now adds DML party and party-pet frames with two positioning modes:
- Grouped mode: one large party anchor moves the entire stack, party spacing applies, and party pets can be placed Right or Below their owner.
- Freeform mode: each party member and each party pet gets its own small drag handle; spacing and grouped pet placement are ignored. Grouped and freeform positions are saved independently.

The frame-adjustment selector now includes Party Members, Party Pets, Party Group, and each individual party member/pet. Party members share one portrait scale; party pets share another. Reset Frame restores the currently selected frame/category, while Reset All Frames restores every frame position and portrait scale without changing which DML replacements are enabled.

Action Bars and J3Spells behavior are unchanged from 2.0.91.
