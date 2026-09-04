# DMLUI 2.0.95

DMLUI is a modular World of Warcraft 3.3.5a interface project. Install only the modules you want.

Included folders:
- `DMLUI_Core/` - shared launcher/module framework (2.0.95).
- `DMLCooldownBar/` - Action Bars module (2.0.91; unchanged in this release).
- `DMLCooldownBar_J3Spells/` - optional J3Spells/ALE integration (2.0.91; unchanged in this release).
- `DMLUnitFrames/` - Unit Frames module (2.0.95).

## 2.0.95 highlights

Unit Frames adds a new Behavior / Range fading section:
- Show target's target: master visibility toggle for target-of-target. The existing Override Blizzard target of target frame option independently chooses whether DML replaces Blizzard's stock ToT frame.
- Highlight unit frame aggro: Player and Party 1-4 receive a red border while they have aggro.
- Display combat icon: Player and Party 1-4 show the crossed-swords combat icon at the portrait corner while in combat.
- Fade party frames when out of range: selectable 15 / 25 / 30 / 35 / 40 yd range and 10-90% resulting opacity. If the current Target is one of those party members, the Target frame follows the same party range/fade rule.
- Fade enemy target if out of range: separate 15 / 25 / 30 / 35 / 40 yd range and 10-90% resulting opacity for hostile targets.

Range checking is designed for the stock 3.3.5 API. DML uses known spell ranges when a suitable spell is available, then native UnitInRange / CheckInteractDistance fallbacks. It intentionally does not use item-based range checks or item-info queries. Because stock 3.3.5 does not expose arbitrary unit distance, some class/range combinations use the nearest safe native range check rather than exact yard measurement.

The complete-frame scale system remains clamped to 0.50x-2.00x with All, Player, Target, Target of Target, Focus, Pet, Party Members, Party Pets, and Party Group selections.
