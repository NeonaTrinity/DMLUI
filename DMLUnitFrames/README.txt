DMLUI - Unit Frames 2.0.91

Optional DMLUI module for WoW 3.3.5a.

Install alongside DMLUI_Core. The Unit Frames button in the DMLUI launcher becomes active automatically.

Initial supported frames:
- Player
- Target
- Focus
- Pet
- Target of Target

Installing the module does not replace Blizzard frames automatically. Enable the individual DML replacements in Unit Frames settings.

Current display controls:
- Portrait
- Health text
- Resource text
- Level
- Class / creature type
- Movable anchors
- Frame locking

Slash command: /dmluf

2.0.91 additions:
- Fixed right-click unit menus using Wrath 3.3.5 SecureUnitButton_OnLoad/menu behavior.
- Player, Target, Focus, Pet, and Target of Target now open Blizzard-style unit popup menus.
- Added a bottom Portrait scale section with a per-unit selector.
- Each unit type stores its own portrait scale.
- Slider range is logarithmic from 0.02x to 30.00x for fine normal-size control plus extreme small/large values.
- Numeric scale entry is clamped to the same range and updates the selected portrait immediately.
