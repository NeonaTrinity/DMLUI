DMLUI - Buffs 2.0.122

Optional DMLUI aura module for WoW 3.3.5a.

Features:
- Player, Target, Target-of-Target, and Party buff/debuff displays.
- Player/Target/ToT aura panels can attach to the unit-frame portrait area or detach into movable DML anchors.
- Above/Below attachment placement. Debuffs remain closest to the unit frame.
- Shared Attached aura spacing control (0-40 px, default 3) adjusts the gap between attached aura rows and DML unit frames without affecting detached panels.
- Attached aura sets stay compact and expand on unit-frame/aura mouseover.
- Detached Player/Target/ToT aura panels show the expanded aura set and have independent 0.50x-2.00x scale.
- Blizzard-style aura icon, stack count, cooldown spiral, tooltip, and debuff-type borders.
- Optional hiding of Blizzard's player BuffFrame while DML Buffs is enabled.
- Party aura presentation uses compact Blizzard-style icons and mouseover expansion.
- Optional player-unit-frame cleanse highlighting for Magic, Poison, Disease, and Curse.
- Cleanse highlight style can be Overlay or Border.
- Border highlight is separate from DML Unit Frames' aggro border.
- If more than one supported debuff is present, the most recently applied effect controls the highlight color.
- Per-character settings and detached aura positions.

Slash command:
/dmlbuffs

Standalone mode (DMLUnitFrames not installed):
- Player, Target, and Target-of-Target aura displays automatically use detached movable/scalable panels.
- Saved attach/detach preferences are preserved and become active again if DMLUnitFrames is restored.
- Hide Blizzard player buffs remains available.
- Unit-frame attachment controls, Party aura attachment, and cleanse highlighting are disabled/grayed out.
- DMLBuffs never falls back to attaching/highlighting Blizzard stock unit frames.



2.0.122 - Attached aura spacing
- Added a shared Attached aura spacing slider from 0-40 px, default 3 px.
- The setting controls the gap between attached Player/Target/Target-of-Target/Party aura groups and their DML unit frames.
- Above attachments move farther upward as spacing increases; Below attachments move farther downward.
- Detached aura panels are unaffected.
- The control is disabled when no compatible DML unit frame is active.

2.0.119 - Decurse highlight strength controls
- Added Highlight opacity text entry, clamped to 0.05-1.00 (default 0.60).
- Overlay mode uses this value as the full-frame tint opacity.
- Border mode uses the same value as border opacity/brightness.
- Added Border thickness slider from 1-8 px (default 3); it is enabled only in Border mode.
- Highlight changes preview immediately and retain the existing per-debuff colors/newest-effect behavior.

2.0.116 - Per-frame standalone fallback
- DMLBuffs now checks whether each DMLUnitFrames replacement is actually enabled, not merely whether the addon is loaded.
- Player/Target/Target-of-Target aura panels automatically behave as detached panels when their corresponding DML unit frame is disabled, without overwriting the saved attach preference.
- Party aura controls are disabled and party aura rows are hidden when DML party frames are disabled.
- Decurse highlight controls are disabled when no relevant DML unit frame is active; highlighting never falls back to Blizzard frames.
- Re-enabling a DML unit frame restores the player's saved attachment/highlight behavior.

2.0.123:
- Shared DMLUI profile export/import support. Missing Unit Frames behavior remains module-safe.
