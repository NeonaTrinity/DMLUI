DMLUI - Unit Frames 2.0.95

Optional DMLUI module for WoW 3.3.5a.
Install alongside DMLUI_Core. The Unit Frames button in the DMLUI launcher becomes active automatically.

Supported frames:
- Player
- Target
- Focus
- Pet
- Target of Target
- Party 1-4
- Party pets 1-4

Target-of-target controls:
- Show target's target is the master visibility switch.
- Override Blizzard target of target frame determines whether the visible ToT uses DML instead of Blizzard's stock ToT.

Behavior options:
- Highlight unit frame aggro: red border on Player / Party member frames with aggro.
- Display combat icon: crossed-swords icon on Player / Party member portrait corners while in combat.

Range fading:
- Party frame range: 15, 25, 30, 35, or 40 yd.
- Party fade-to opacity: 10-90%.
- A targeted party member also applies the party range/fade rule to the DML Target frame.
- Enemy Target has its own independent range and fade-to opacity settings.
- Range checks use known spell ranges first and stock 3.3.5 native fallbacks. No item metadata or item-based range library is queried.

Party controls:
- Use DML party frames
- Show party pets
- Move party frames as one anchor
- Party pet position: Right / Below (grouped mode)
- Party spacing: 0-150 pixels (grouped mode)

Grouped party mode:
- One large DML Party Frames anchor moves all party members and pets together.
- Vertical spacing applies to the managed stack.
- Party pets stay attached to their owner at Right or Below.

Freeform party mode:
- Group anchor is disabled.
- Each party member and pet has its own small drag handle beside the portrait.
- Party spacing and grouped pet-position controls are disabled/ignored.
- Freeform positions are saved separately from the grouped layout.

Frame / size adjustment selector:
- All
- Player
- Target
- Target of Target
- Focus
- Pet
- Party Members
- Party Pets
- Party Group

Unit-frame scaling:
- 0.50x through 2.00x.
- Numeric entry is clamped to the exact same range.
- Scaling resizes the complete selected unit frame.
- Party Members share one complete-frame scale; Party Pets share another.

Reset controls:
- Reset Frame: resets the currently selected frame/category to its default position and frame scale where applicable.
- Reset All Frames: resets all positions, party spacing/pet placement, and frame scales without changing enabled-frame checkboxes.
- Reset Settings: restores the full Unit Frames settings set to defaults.

Unit frames keep left-click targeting and Blizzard-style right-click unit menus.
Slash command: /dmluf
