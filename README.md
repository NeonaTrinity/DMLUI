# DMLUI 2.0.93

DMLUI is a modular World of Warcraft 3.3.5a interface project. Install only the modules you want.

Included folders:
- `DMLUI_Core/` - shared launcher/module framework.
- `DMLCooldownBar/` - Action Bars module (2.0.91; unchanged in this release).
- `DMLCooldownBar_J3Spells/` - optional J3Spells/ALE integration (2.0.91; unchanged in this release).
- `DMLUnitFrames/` - Unit Frames module (2.0.93).

## 2.0.93 highlights

Unit Frames scaling now resizes the complete selected unit frame instead of only its portrait. This includes the portrait, bars, text, backdrop, border, and secure clickable area.

The frame selector is simplified to:
- Player
- Target
- Target of Target
- Focus
- Pet
- Party Members
- Party Pets
- Party Group

Party Members share one complete-frame scale and Party Pets share another, in both grouped and freeform positioning modes. Individual Party 1-4 / pet entries are no longer shown in the selector; their freeform drag handles still work exactly as before.

Grouped party layout calculations now account for the scaled member/pet dimensions so enlarged frames do not overlap adjacent rows. Existing 2.0.91/2.0.92 saved slider values migrate from the old portrait-scale storage into the new frame-scale storage.

Action Bars and J3Spells behavior are unchanged from 2.0.91.
