# DMLUI 2.0.91

DMLUI is a modular user-interface project for World of Warcraft 3.3.5a.

## Addon folders

- `DMLUI_Core/` — shared DMLUI launcher, minimap icon, module registry, Profiles/Advanced core pages.
- `DMLCooldownBar/` — Action Bars module. Works natively on ordinary 3.3.5a servers.
- `DMLCooldownBar_J3Spells/` — optional J3Spells/ALE extension for Action Bars.
- `DMLUnitFrames/` — optional movable Player, Target, Focus, Pet, and Target-of-Target frames.

Future modules such as `DMLBigBag/` can register with DMLUI and automatically activate their launcher buttons.

Install `DMLUI_Core/` plus only the feature modules you want. The Action Bars module still has a standalone fallback if DMLUI is absent, but DMLUI is the intended umbrella configuration experience.

## 2.0.91 highlights

- DML Unit Frames now use Blizzard-compatible right-click unit popup menus on Wrath 3.3.5a.
- Unit Frames adds per-unit portrait scaling for Player, Target, Target of Target, Focus, and Pet, with a logarithmic slider plus clamped numeric input (0.02x-30x).

- Stabilizes the movable shaman totem bar by isolating Blizzard's multicast frame and Y-offset manager entries only while DML controls the bar, then restoring them when disabled.
- Assigned items at zero quantity/uses now show `0` on the DML action button while faded.

## 2.0.89 highlights

- Action Bars: added `Hide totem bar background`, directly below `Fade when resource is low`. It removes only the DML totem host backdrop while retaining Blizzard's native totem icons and flyouts.
- Added the first `DMLUnitFrames/` module. Installing it activates the Unit Frames launcher button; no Blizzard unit frame is replaced until the player enables that specific DML frame.
