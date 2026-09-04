# DMLUI 2.0.116

DMLUI is a modular WoW 3.3.5a UI project. Install only the folders for the modules you want.

## Included modules

- `DMLUI_Core/` - shared minimap launcher and module framework (2.0.114).
- `DMLCooldownBar/` - Action Bars module (unchanged from 2.0.91).
- `DMLCooldownBar_J3Spells/` - optional J3Spells integration for Action Bars (unchanged from 2.0.91).
- `DMLUnitFrames/` - Unit Frames module (2.0.114).
- `DMLCastBar/` - optional movable/customizable player cast bar (2.0.106).
- `DMLBuffs/` - optional attached/detached aura and cleanse-highlighting module (2.0.116).
- `DMLQuestTracker/` - optional movable/collapsible quest tracker (2.0.113).




## 2.0.116 highlights

### DML Buffs
- Standalone fallback is now evaluated per DML unit frame, not only by whether `DMLUnitFrames/` is loaded.
- If Player, Target, or Target-of-Target DML frames are disabled in Unit Frames settings, their aura groups automatically use the detached movable/scalable panels.
- Attach/detach and Above/Below controls gray independently for whichever DML frame is disabled; detached scale remains available.
- DML Party aura controls gray and Party aura rows hide whenever DML party frames are disabled.
- Decurse highlight controls gray when no relevant DML unit frame is active, and highlighting never falls back to Blizzard unit frames.
- Saved attachment, Party, and highlight preferences are preserved while a DML frame is disabled and return when that frame is re-enabled.
- Buffs settings refresh immediately when Unit Frames settings change.

## 2.0.115 highlights

### DML Buffs
- Added true standalone operation when `DMLUnitFrames/` is not installed.
- Player, Target, and Target-of-Target auras automatically use detached movable/scalable panels in standalone mode.
- Unit-frame attachment, Party aura attachment, and cleanse highlighting controls are gray/disabled without DML Unit Frames.
- `Hide Blizzard player buffs`, detached aura visibility, anchors, locking, and detached scales remain fully functional.
- Saved attach/detach/Party/highlight settings are preserved rather than overwritten, so they return if Unit Frames is installed again.
- Removed fallback attachment/highlighting of Blizzard stock unit frames; those features are now strictly DMLUnitFrames integrations.

## 2.0.114 highlights

### DML Buffs
- New optional `DMLBuffs/` module and launcher entry.
- Player, Target, Target-of-Target, and Party buffs/debuffs with compact attached presentation and mouseover expansion.
- Player/Target/ToT aura groups attach to the portrait area or detach into independent movable/scalable DML anchors.
- Above/Below placement keeps debuffs closest to the associated unit frame and buffs stacking outward.
- Optional hiding of Blizzard player buffs while DML Buffs is enabled.
- Optional friendly-player cleanse highlighting for Magic, Poison, Disease, and Curse with editable colors and Overlay/Border styles.
- If several supported debuffs are active, the most recently applied effect determines the highlight color.

### Unit Frames
- Fine-tuned mirrored rare/elite dragon placement and size; the ornament scales with the complete unit frame.
- Added **Use classic name banner** for reaction-colored Target/Focus/Target-of-Target name backgrounds, including hostile PvP players, independently from name-text color.
- Added a portrait attachment point for the optional Buffs module without making Unit Frames depend on it.

### DMLUI Core
- Added the optional **Buffs** launcher entry; it is gray/disabled when `DMLBuffs/` is not installed.



## 2.0.107 highlights

### DMLUI Core
- Added a permanent **Quest Tracker** launcher entry.
- The button is active when `DMLQuestTracker/` is installed and loaded, and gray/disabled when the optional module is absent.
- Expanded the launcher vertically to fit the additional module entry cleanly.

### Quest Tracker
- New optional `DMLQuestTracker/` module.
- **Use DML Quest Tracker** replaces Blizzard's `WatchFrame` with the DML tracker.
- Reads Wrath's existing watched-quest list without changing which quests are tracked.
- Uses the standard **DML Quest Tracker - drag to move** anchor with **Show anchors** and **Lock tracker**.
- The complete tracker minimizes under its **DML Quest Tracker** header.
- Every quest is its own `+ / -` sub-header and independently expands/collapses its objectives.
- Rows below an expanded/collapsed quest immediately reflow to remove unused space.
- Individual quest collapse state is saved by Wrath quest ID rather than quest-log index.
- Objective progress refreshes from normal Wrath quest-log/watch events.
- Disabling DML Quest Tracker restores Blizzard's WatchFrame.


## 2.0.106 highlights

### Unit Frames
- Added **Use alignment color for name** for non-player units using Wrath reaction colors (red hostile/hated, orange unfriendly, yellow neutral, green friendly+).
- Added **Hide Blizzard cast bar** under Attached cast bars.
- Attached Player cast bar is now independent from the standalone DML Cast Bar module.

### Cast Bar
- Enabling the standalone DML Cast Bar hides only Blizzard's stock player cast bar; it no longer disables the Unit Frames attached Player cast bar.
- When Unit Frames is installed, the two modules coordinate Blizzard-bar visibility so the new Unit Frames hide option remains authoritative whenever the standalone DML Cast Bar is off.

## 2.0.105 highlights

### Unit Frames
- Mirrored the rare/elite dragon portrait ornament horizontally so its wing points left rather than right.
- Shifted the mirrored ornament slightly left for matching placement around the portrait.
- The 2.0.104 Wrath facial-camera 3D portrait fix is unchanged.

## 2.0.104 highlights

### Unit Frames
- Corrected 3D portraits for WoW 3.3.5a by selecting Model camera 0, the client's native facial portrait camera, after binding the unit model.
- Reapplies the facial camera when a portrait model is shown again so the client cannot leave it in the full-body view after UI/model visibility changes.
- Keeps the GUID-cached model refresh and `UNIT_MODEL_CHANGED` handling introduced in 2.0.103.


## 2.0.103 highlights

### Unit Frames
- Fixed 3D portrait framing to use the PlayerModel portrait camera with a slight pullback for a head-and-shoulders crop instead of the full-body model.
- Removed the model-position reset from the 3D portrait refresh path.
- Cached 3D model bindings by unit GUID so ordinary health/resource/name updates no longer call `SetUnit()` repeatedly.
- Added `UNIT_MODEL_CHANGED` refresh handling for shapeshifts and transformations.


## 2.0.102 highlights

### Unit Frames
- Added `Portrait type`: 2D Portrait, 3D Portrait, or Class Icon.
- Class Icon uses the stock class-icon atlas for the player and friendly player units, and automatically falls back to 2D portraits for enemies (including enemy players), NPCs, pets, and other non-player units.
- 3D Portrait uses a live PlayerModel in the existing portrait slot; frame layout and scaling are unchanged.

## 2.0.101 highlights

### Cast Bar
- Fixed duplicate player cast bars when DML Cast Bar is enabled.
- Blizzard's stock `CastingBarFrame` is now suppressed through its native 3.3.5 `showCastbar` flag and hidden immediately.
- Turning DML Cast Bar off restores the stock bar's previous state and resyncs an in-progress cast.

## 2.0.100 highlights

### Unit Frames
- Split `Show class` and `Show creature type` into separate options.
- Added a configurable `Name` color swatch. Player class colors override it only when `Use class color as name` is enabled.
- Added `Use class color for class text` independently from name coloring.
- Existing Unit Frames and Cast Bar behavior from 2.0.99 is preserved.

## 2.0.99 highlights

### Cast bars
- Rebuilt both the standalone DML Cast Bar and Unit Frames attached cast bars on Blizzard's stock Wrath 3.3.5 `CastingBarFrameTemplate` state/event engine.
- DML still owns width/height/position/color/border/text/time presentation; Blizzard's proven cast/channel timing engine now drives visibility and progress.
- Player/Target/Target-of-Target attached bars continue to respect their independent enable and Above/Below settings.

## 2.0.98 highlights

### Unit Frames
- Fixed the spell-range dropdown on stock WoW 3.3.5a by reading the original nine-value `GetSpellInfo` return layout correctly.
- Spellbook candidates are resolved from actual spellbook slots with `GetSpellName` / `GetSpellBookItemInfo`, then queried by spell ID when possible.
- Helpful/harmful range lists remain rank-collapsed, capped, and limited to meaningful ranged spells.
- Reworked aggro highlighting into a red overlay drawn outside the complete unit frame so portraits cannot cover it.
- Added `Aggro border intensity` slider + numeric field, clamped from 1-8.

Existing Unit Frames features remain available: player/target/focus/pet/target-of-target/party frames, scaling, freeform/grouped party positioning, spell-based range fading, combat icons, attached cast bars, configurable colors, class-colored names, and rare/elite classification art.

## Slash commands

- `/dmlui` - DMLUI launcher.
- `/dmluf` - Unit Frames settings.
- `/dmlcast` - Cast Bar settings.
- `/dmlbuffs` - Buffs settings.
- `/dmlquest` or `/dmlqt` - Quest Tracker settings.


## 2.0.108

DMLQuestTracker now mirrors the quest log watched list bidirectionally, supports right-click untracking, Wrath quest difficulty colors or custom header/objective colors, optional background color, tracker scaling, and a configurable completed-quest color.
