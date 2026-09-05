DMLUI Unit Frames 2.0.125


New in 2.0.125:
- Fixed Interface Action Blocked/taint spam when a disabled secure DML unit frame (notably Target of Target) received unit update events during combat.
- Protected unit-frame Show/Hide state is now left unchanged during combat and continues to be applied safely out of combat through the existing unit-watch activation path.

New in 2.0.114:
- Fine-tuned rare/elite/world-boss dragon placement: slightly left, slightly down, and about 5% larger around the portrait.
- Dragon art remains a child of the unit frame, so it scales naturally with the complete Unit Frame scale slider.
- Added "Use classic name banner". Target, Focus, and Target-of-Target name-row backgrounds use reaction/hostility colors independently from name-text coloring, including hostile PvP players.
- Added a small public portrait attachment API used by the optional DMLBuffs module; Unit Frames remains fully functional without DMLBuffs installed.

New in 2.0.106:
- Added "Use alignment color for name". Non-player units use Wrath reaction colors: hostile/hated red, unfriendly orange, neutral yellow, friendly-or-better green.
- Player names remain independent: "Use class color as name" still affects player units only.
- Standalone DML Cast Bar no longer disables the attached Player cast bar; both may be visible together.
- Added "Hide Blizzard cast bar" under Attached cast bars. With standalone DML Cast Bar off, this independently hides or restores Blizzard's stock player cast bar.
- When standalone DML Cast Bar is enabled, Blizzard's stock cast bar is always hidden while the attached Unit Frame player cast bar remains controlled only by its own checkbox.

New in 2.0.105:
- Mirrored the rare, rare-elite, elite, and world-boss dragon portrait ornament horizontally so its wing extends left instead of right.
- Shifted the mirrored ornament slightly left to preserve its intended placement around the portrait.
- 3D portrait camera behavior from 2.0.104 is unchanged.

New in 2.0.104:
- Corrected 3D portraits for the actual WoW 3.3.5a model API: DML now selects Model camera 0, the native facial portrait camera, instead of trying to zoom the default full-body camera.
- The facial camera is reapplied after each real model bind and when the PlayerModel is shown again, preventing hide/show cycles from leaving the portrait on the body camera.
- Preserves the 2.0.103 GUID-cached model refresh and UNIT_MODEL_CHANGED handling.

New in 2.0.103:
- Fixed 3D portraits so PlayerModel uses the face/portrait camera with a slight camera-distance pullback for a head-and-shoulders crop instead of the full-body model.
- Removed the 3D portrait SetPosition reset that could disturb the portrait camera.
- 3D models are now rebound only when the unit GUID/model changes instead of on every health/resource/name refresh.
- Added UNIT_MODEL_CHANGED handling so shapeshifts, transformations, and other same-GUID model changes refresh correctly.

2.0.102 additions:
- Portrait type dropdown: 2D Portrait, 3D Portrait, Class Icon.
- Class Icon applies to the player/friendly player units; enemies (including enemy players) and non-player units fall back to 2D portraits.

DMLUI - Unit Frames 2.0.100

2.0.100 additions:
- Split Show class and Show creature type into independent display options.
- Added Name color picker; it is used whenever class-color name override does not apply.
- Added Use class color for class text as a separate option from class-colored names.
- Existing 2.0.99 cast-bar, range, aggro, party, scaling, classification, and color features are preserved.

Optional DMLUI unit-frame replacement module for WoW 3.3.5a.

2.0.99 additions/fixes:
- Rebuilt attached Player/Target/Target-of-Target cast bars on Blizzard's stock 3.3.5 CastingBarFrame engine so cast/channel graphics reliably appear.

2.0.98 additions/fixes:
- Fixed stock 3.3.5a spellbook range scanning. The client uses the original
  nine-value GetSpellInfo return layout, and DMLUI now reads cast/range values
  from their correct positions.
- Known ranged helpful/harmful spells populate the range dropdown correctly,
  remain collapsed to one entry per spell name, and are capped to keep menus compact.
- Aggro highlight is now a dedicated red overlay drawn outside the full unit frame
  so portraits cannot cover it.
- Added Aggro border intensity (1-8) with both slider and numeric entry.

Existing features include:
- Player, Target, Target of Target, Focus, Pet, Party and Party Pet frames.
- Grouped or freeform party layouts.
- Whole-frame scaling (0.50x-2.00x).
- Party/enemy range fading based on selected known spells.
- Aggro borders and combat icons.
- Attached Player, Target and Target-of-Target cast bars.
- Configurable frame/resource colors, class-colored names, and rare/elite art.
- Movable anchors and reset controls.

Slash command: /dmluf
2.0.123:
- Small Blizzard-style group leader crown on the portrait top-left.
- PvP faction/FFA badge on the portrait bottom-right for PvP-flagged player units.
- Shared DMLUI profile export/import support.
