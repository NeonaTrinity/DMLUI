DMLUI Unit Frames 2.0.102

New in 2.0.102:
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