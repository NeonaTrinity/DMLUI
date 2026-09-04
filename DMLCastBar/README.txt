DMLUI - Cast Bar 2.0.101

Optional standalone player cast-bar module for WoW 3.3.5a.

Features:
- Enable/disable the DML player cast bar.
- Movable DML anchor with show/lock controls.
- Width and height controls.
- Spell name and cast-time toggles.
- Bordered or borderless appearance.
- Cast bar color using Blizzard's color picker.
- Automatically hides Blizzard's stock player cast bar while enabled.
- Automatically suppresses DMLUnitFrames' attached Player cast bar while enabled.

Slash command: /dmlcast


2.0.101 fix:
- Enabling DML Cast Bar now suppresses Blizzard's stock player CastingBarFrame using the stock 3.3.5 showCastbar flag plus an immediate Hide(), rather than alpha-only hiding.
- Disabling DML Cast Bar restores Blizzard's previous showCastbar/alpha/mouse state and immediately resyncs the stock bar if a cast is already in progress.

2.0.99 fix:
- Rebuilt cast detection/display on Blizzard 3.3.5 CastingBarFrameTemplate/engine while retaining DML sizing, color, border, text/time, and anchor controls.
