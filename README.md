# DMLUI 2.0.88

DMLUI is a modular user-interface project for World of Warcraft 3.3.5a.

## Addon folders

- `DMLUI_Core/` — shared DMLUI launcher, minimap icon, module registry, Profiles/Advanced core pages.
- `DMLCooldownBar/` — Action Bars module. Works natively on ordinary 3.3.5a servers.
- `DMLCooldownBar_J3Spells/` — optional J3Spells/ALE extension for Action Bars.

Future modules such as `DMLUnitFrames/` and `DMLBigBag/` can register with DMLUI and automatically activate their launcher buttons.

Install `DMLUI_Core/` plus only the feature modules you want. The Action Bars module still has a standalone fallback if DMLUI is absent, but DMLUI is the intended umbrella configuration experience.
