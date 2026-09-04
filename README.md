# DMLUI 2.0.94

DMLUI is a modular World of Warcraft 3.3.5a interface project. Install only the modules you want.

Included folders:
- `DMLUI_Core/` - shared launcher/module framework.
- `DMLCooldownBar/` - Action Bars module (2.0.91; unchanged in this release).
- `DMLCooldownBar_J3Spells/` - optional J3Spells/ALE integration (2.0.91; unchanged in this release).
- `DMLUnitFrames/` - Unit Frames module (2.0.94).

## 2.0.94 highlights

Unit Frames scale controls are now clamped to a practical **0.50x-2.00x** range. The slider and manually typed numeric value use the exact same clamp, and older saved extreme values are clamped automatically on load.

The frame selector now begins with **All**:
- All
- Player
- Target
- Target of Target
- Focus
- Pet
- Party Members
- Party Pets
- Party Group

Choosing All applies one uniform complete-frame scale to Player, Target, Target of Target, Focus, Pet, Party Members, and Party Pets. If the individual categories currently use different sizes, the value box shows `Mixed` until a new All value is chosen. Party Group remains position/spacing only.

Party Members and Party Pets still share their respective scales in both grouped and freeform positioning modes. Individual Party 1-4 / pet positions remain controlled by their freeform drag handles rather than cluttering the scale selector.

Action Bars and J3Spells behavior are unchanged from 2.0.91.
