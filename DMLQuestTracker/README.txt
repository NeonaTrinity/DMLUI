DMLUI - Quest Tracker 2.0.113
World of Warcraft 3.3.5a / Interface 30300

Optional DMLUI quest tracker module.

Features:
- Uses Blizzard's actual watched-quest list (GetNumQuestWatches/GetQuestIndexForWatch).
- Tracking/untracking quests in the normal quest log updates the DML tracker.
- Right-click a DML quest header to RemoveQuestWatch() and untrack it everywhere.
- Main tracker can be collapsed independently.
- Each quest can independently collapse/expand its objectives.
- Per-quest collapse state is saved by quest ID.
- Optional Wrath quest-level difficulty colors via GetQuestDifficultyColor().
- Custom quest-header, objective, background, and completed-quest colors.
- Optional quest completion color override.
- Optional tracker background.
- Independent Hide quest header background setting for the DML Quest Tracker header.
- Tracker scale from 0.50x to 2.00x.
- Compact half-width movable DML anchor aligned flush with the tracker's top-left edge, with Show anchors / Lock tracker. Screen-edge clamping follows the anchor itself, so the tracker body may extend off-screen.
- Disables Blizzard WatchFrame only while Use DML Quest Tracker is enabled.

Slash commands:
/dmlquest
/dmlqt

2.0.113
- Added real-time quest-log watch synchronization by securely hooking AddQuestWatch and RemoveQuestWatch.
- Manual track/untrack changes from Blizzard Quest Log now refresh DMLQuestTracker on the next UI frame without requiring DML interaction.
