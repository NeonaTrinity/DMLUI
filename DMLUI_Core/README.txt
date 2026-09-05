DMLUI Core 2.0.114
==================

DMLUI is the shared launcher/framework for modular WoW 3.3.5a UI addons.

Current module slots:
- Action Bars    -> provided by DMLCooldownBar
- Unit Frames    -> provided by optional DMLUnitFrames module
- Cast Bars      -> provided by optional DMLCastBar module
- Buffs          -> provided by optional DMLBuffs module
- Quest Tracker  -> provided by optional DMLQuestTracker module
- Profiles       -> DMLUI core page; Action Bars profiles remain intact for now
- Advanced       -> DMLUI core status/settings page
- DML BigBag     -> planned bag module

Install DMLUI_Core plus only the feature modules you want. Missing feature modules remain
visible but disabled in the DMLUI launcher.

The DMLUI minimap button opens the launcher. /dmlui also opens it.

2.0.107: Added the optional Quest Tracker launcher/module slot and expanded the launcher height for the additional button.

2.0.114: Added the optional Buffs launcher/module slot. Missing DMLBuffs remains visible but disabled.

2.0.123 shared profiles:
- Profiles now save Unit Frames, Cast Bars, Buffs, and Quest Tracker settings.
- Action Bars continue using their existing independent profile UI.
- Missing module sections are ignored when loading and preserved when updating an existing profile.
