DMLUI - ACTION BARS 2.0.88 - UNIVERSAL MODULE

2.0.85 shared bar updates
-------------------------
- Assigned items show their current bag quantity. Charged items use Wrath's
  GetItemCount(..., includeUses=true) behavior so available uses can be shown.
- Item buttons fade when the item is no longer in the player's bags or has no
  remaining uses/charges. BAG_UPDATE only refreshes counts; it does not re-run
  item metadata queries.
- Optional Use DML totem bar setting for Wrath shamans. DML moves Blizzard's
  native MultiCastActionBarFrame to a saved movable DML anchor instead of
  recreating the protected totem controls, preserving elemental slot flyouts,
  Call summon pages, recall, and SetMultiCastSpell selection behavior.

World of Warcraft 3.3.5a

PURPOSE
-------
DML Cooldown Bar is now one universal addon. Native Blizzard cooldown APIs are
always the default and are sufficient for ordinary 3.3.5a servers.

The ZIP also includes a separate optional addon folder:

  DMLCooldownBar_J3Spells/

That optional module contains the J3Spells/ALE server integration. The main
DMLCooldownBar addon does not require it and continues to work if the folder is
missing or disabled.

INSTALLATION
------------
Copy DMLCooldownBar/ into Interface/AddOns/ on every server.

For a server running the J3Spells module, also copy:

  DMLCooldownBar_J3Spells/

Then open DML config and check:

  J3Spells Lua (use with j3spells module only)

If the optional integration addon is missing or disabled at character select,
that checkbox is greyed out and cannot be checked.

COOLDOWN BEHAVIOR
-----------------
Native mode:
- Spells use GetSpellCooldown.
- Items use GetItemCooldown.
- Mounts/companions use normal client APIs.
- No DMLCD/ALE system-message listener exists in the core addon.

J3Spells mode:
- Native cooldowns REMAIN the baseline.
- Ordinary spells still use normal server/client cooldowns.
- DMLCD START/COOLDOWN/READY/RESET timers override a spell only when J3 sends
  such a timer.
- A spell marked server_confirmed_cooldown waits for J3 timer messages while
  J3 integration is enabled.
- LEARN/META/BONUS/MANA messages are handled only by the optional J3 addon.
- Turning the checkbox off unregisters the J3 system-message listener/filter
  and immediately returns DML to native cooldown behavior.

UPGRADING FROM THE OLD TWO BUILDS
---------------------------------
The universal build keeps the same DMLCooldownBar SavedVariables.

When upgrading from the old private-server/ALE build, legacy J3 cooldown,
metadata, fallback, and message settings are migrated into j3-prefixed storage.
The J3 integration checkbox is automatically enabled for those characters when
the optional integration addon is installed.

When upgrading from the Native fork, J3 remains disabled by default.

Profiles do not save or change the J3 integration checkbox. It is treated as a
server/environment setting rather than a bar-layout profile setting.

OPTIONAL J3 COMMANDS
--------------------
/dmlj3                 - status/help
/dmlj3 messages on|off - cooldown-start chat messages
/dmlj3 ready on|off    - cooldown-ready chat messages
/dmlj3 fallback on|off - old click-fallback compatibility
/dmlj3 delay <0-5>     - click-fallback delay

The optional J3 folder can be removed entirely for a portable/native install.
