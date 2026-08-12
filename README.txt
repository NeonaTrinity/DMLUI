DML COOLDOWN BAR 2.0.80
World of Warcraft 3.3.5a / AzerothCore / ALE

PURPOSE
-------
DML Cooldown Bar provides configurable Blizzard-style spell, item, macro, mount, and companion-pet bars.
It displays normal client spell/item cooldowns and custom AzerothCore spell
cooldowns supplied by an ALE server script. Actions are activated only by a
player click or saved DML keybind.

INSTALLATION
------------
1. Delete the previous DMLCooldownBar folder.
2. Copy the new DMLCooldownBar folder into:

   World of Warcraft/Interface/AddOns/

3. Confirm these files exist:

   Interface/AddOns/DMLCooldownBar/DMLCooldownBar.toc
   Interface/AddOns/DMLCooldownBar/DMLCustomItems.lua
   Interface/AddOns/DMLCooldownBar/DMLCooldownBar.lua

4. Restart the client or return to character selection.
5. Enable DML Cooldown Bar and log in.
6. Type:

   /dmlcd version

It should report version 2.0.80. Existing character settings and legacy character-layout snapshots migrate automatically. If a legacy snapshot conflicts with an existing named profile, it is preserved as Name-ac-2, Name-ac-3, and so on.

CONFIGURATION WINDOW
--------------------
Open or close it with:

  /dmlcd config

The minimap button also toggles the window.

The left Layout column contains:
- Number of bars
- Buttons per bar
- Rows and columns
- Button size
- Horizontal and vertical gaps
- Fallback delay
- Show slot numbers
- Blizzard bar dropdown
- Hide gryphons
- Show anchors
- Use DML aura bar
- Use DML pet bar
- Simple tooltips
- Use bar 1 as stance bar

The right Behavior column contains:
- Bar visibility and locking
- Background and auto-assign learned spells
- Native cooldown and ALE fallback settings
- Chat, minimap, and debug settings
- Locked-bar drag modifier

DML bars use the HIGH frame strata, so they can be positioned over the
remaining Blizzard main-bar artwork instead of rendering behind it.

SCREEN-EDGE PLACEMENT
---------------------
DML bars may extend their decorative frame/padding up to 6 pixels beyond the
bottom, left, or right screen edge. This lets the actual action-button edge sit
flush with the screen or Blizzard artwork. The drag anchor is kept on-screen,
so unlocking the bar always leaves a recoverable movement area when anchors are
shown. A bar that is
dropped too far outside the screen snaps back to the nearest allowed edge.


BAR ANCHORS
-----------
Show anchors is enabled by default and controls the visible draggable header
above each DML bar. Turning it off hides those headers without locking the bars.
This lets players keep normal unlocked action drag-and-drop behavior without
leaving the movement anchors visible.

To reposition a bar later, enable Show anchors again, move the bar, and hide the
anchors afterward if desired. Lock bars remains a separate setting.

Commands:

  /dmlcd anchors on
  /dmlcd anchors off

DML AURA / PET BARS
-------------------
Use DML aura bar replaces Blizzard's fixed stance/form/aura bar with a compact
movable DML bar. It mirrors the client's stance/form entries, including warrior
stances, druid shapeshifts, and paladin auras. Its movement header follows Show
anchors and Lock bars, and its position is saved in profiles.

Use DML pet bar replaces Blizzard's fixed pet action bar with a compact
ten-button DML bar. It uses the pet's real action slots, cooldowns, active
states, usability state, autocast state, tooltips, and existing pet-action
keybindings. Left-click activates a pet action; right-click uses Blizzard's
secure pet button to toggle autocast. Pet actions may be rearranged outside
combat while the bar is unlocked, or while holding the configured locked-bar
modifier.

The DML pet bar has its own saved screen position. Its movement header follows
Show anchors and Lock bars exactly like the normal DML bars. Reset Positions
recenters it together with Bars 1 through 5 and the DML aura bar. Disabling Use DML pet bar restores
Blizzard's original pet bar.

PROFILES
--------
DML uses one account-wide Saved Profile list while every character still keeps
its own active DML setup in the normal per-character SavedVariables. On first
use, DML creates a named profile using the character name. Named profiles are
snapshots: they change only when Save Current is explicitly pressed. Players
may also create manual profiles such as Healer, Tank, PvP, or Raid.

A profile saves:
- Bar count, button count, rows, and columns
- Button size and horizontal/vertical gaps
- Bar positions, pet-bar position and enable state, visibility, background, lock, and anchor-visibility settings
- Spell, item, macro, mount, and companion-pet assignments
- Manual fallback cooldown values
- DML keybindings
- Slot-number, Blizzard-bar, gryphon, minimap, chat, and cooldown settings

Active cooldown timers are not saved or copied.

The Profiles section in /dmlcd config provides:
- Profile name
- Save Current
- Saved-profile dropdown
- Load and Delete
- Copy-profile dropdown
- Copy To This Character

Saved Profile and Copy Profile display the same account-wide list. Deleting a
profile removes it from both dropdowns. Loading or copying a profile changes
only the current character's live layout and never rewrites any saved profile.
A saved profile changes only when Save Current is used.

Version 2.0.78 migrates the old Character-Realm character-layout snapshot
table into the normal profile list once. Existing names are preserved; a conflicting
legacy snapshot is renamed Name-ac-2, Name-ac-3, and so on before the old list is retired.

Commands:

  /dmlcd profile save My Layout
  /dmlcd profile load My Layout
  /dmlcd profile delete My Layout
  /dmlcd profile copy My Layout
  /dmlcd profile list

Profile loading or copying during combat is queued and applied when combat ends.


AUTO-ASSIGN ON LEARN
--------------------
When Auto-assign learned spells is enabled, the addon watches the player
spellbook. A newly learned active spell is placed in the first empty active
slot in this order:

  Bar 1, then Bar 2, then Bar 3, then Bar 4, then Bar 5.

Cooldown START messages no longer create assignments when a spell is first
used. Existing spells are recorded as the login baseline and are not dumped
onto the bars. Passive spells are ignored. Learning a higher rank replaces the
assigned rank of the same spell instead of consuming another slot.

Normal trainer learning should fire the client spellbook events automatically,
including cross-class spells that appear in the spellbook. For a custom ALE
learning path that does not fire those events, the addon also accepts:

  DMLCD|LEARN|spellId|0|0|spellName

The server fallback is only needed if in-game testing shows that the trainer
does not update the spellbook event.

COMBAT ASSIGNMENT LOCK
----------------------
DML spell and item assignments remain unchanged during combat. Dragging,
replacing, moving, swapping, clearing, slash-command assignment, and visible
auto-assignment are blocked until combat ends. Newly learned spells detected in
combat are queued internally and auto-assigned afterward.

This prevents a DML button from displaying one spell while its protected secure
click still points to a different spell. There is no pending icon or temporarily
unusable assignment state.

TOOLTIPS AND COOLDOWN DETAILS
-----------------------------
Custom spell damage text and rank metadata are loaded from DMLCustomSpells.lua.
Spell tooltips show the known total spell cooldown below the rank. While a spell
is cooling down, remaining cooldown appears directly below the total. ALE START
messages provide the authoritative custom duration, and native Blizzard cooldown
data is cached after first use when no total was previously known.

Enable Simple tooltips in the Layout column to hide DML tracking, fallback,
source, keybind, and drag-instruction lines while keeping the normal tooltip,
custom damage, rank, resource warning, and cooldown lines.

CLICK FALLBACK
--------------
Click fallback is a development safety net for custom ALE spell cooldowns.

When enabled, clicking a DML spell button does this:
1. The secure button attempts to cast the spell normally.
2. The addon waits for the configured Fallback delay (default 0.75 seconds).
3. If an ALE DMLCD|START message arrives, that server timer is authoritative.
4. If no START message arrives and the slot has a fallback cooldown greater
   than zero, the addon starts the local fallback timer.

Click fallback never casts automatically and does nothing when the slot's
fallback value is 0. Native Blizzard spell and item cooldowns do not require it.

Commands:

  /dmlcd clickfallback on
  /dmlcd clickfallback off
  /dmlcd fallbackdelay <0-5>
  /dmlcd autoassign on|off

CUSTOM ITEMS AND ICON OVERRIDES
-------------------------------
DML 2.0.83 keeps item metadata isolated from the Wrath client cache while also
recovering safely from missed/early item-info events. A normal assigned item gets
one initial metadata request and, only if still unresolved, one delayed recovery
attempt. DML never retries item metadata from BAG_UPDATE. A successful
GET_ITEM_INFO_RECEIVED for an item currently assigned to DML may complete that
item even when another Blizzard UI component initiated the request. Once a
normal item icon resolves, DML stores that icon with the assignment/profile so
future profile loads can draw it immediately. Entries defined in
DMLCustomItems.lua do not call GetItemInfo or GetItemIcon for DML display; their
local name/icon fields are used directly.

DMLCustomItems.lua contains a separate editable map:

  DMLCooldownBarCustomItems[itemId] = {
      name = "Item name",
      icon = "Macro_Icon_Name"
  }

The icon may be a macro-style name such as INV_Misc_Book_09 or a full texture
path. The included map defines IDs 990100 through 990112.

These icon overrides apply only to DML buttons. DML does not hook Bagnon or any
other bag addon. If custom bag icons are desired, patch that bag addon separately
or use a dedicated bag addon.

PROFILE LOADING AND COPYING (2.0.81)
------------------------
The addon creates an initial profile for the current character using that
character's name. The Profile name field is prefilled with that name. Loading a
saved profile changes the working Profile name field to that profile, but never
overwrites it until Save Current is pressed. Copy To This Character applies a
profile without changing the working Profile name field.

To copy a layout to another character:
1. Log into the source character with DML Cooldown Bar enabled and arrange its layout.
2. Log into the destination character.
3. Open /dmlcd config.
4. Choose the source character profile (or any custom profile) under Copy profile.
5. Click Copy To This Character.

The source profile is never changed. The destination character's live setup
receives the copied settings, bar positions, assignments, fallback values, and
DML keybinds. No named profile is overwritten until Save Current is explicitly
pressed. Active cooldown timers are not copied. Saved Profile and Copy Profile
use the same list, so stale or unused character profiles can be removed with
the normal Delete button.

CUSTOM SPELL RANKS AND TOOLTIP TEXT (v1.8.0)

DMLCustomSpells.lua is the editable client-side metadata map. It is useful when
custom spell records all display the wrong client rank or omit damage text.

  DMLCooldownBarCustomSpells[13953] = {
      name = "Holy Strike",
      family = "holy_strike",
      rank = 1,
      custom_text = "Deals your finalized Rank 1 damage range here."
  }

  DMLCooldownBarCustomSpells[17143] = {
      name = "Holy Strike",
      family = "holy_strike",
      rank = 2,
      custom_text = "Deals your finalized Rank 2 damage range here."
  }

The family joins related ranks. When Rank 2 is learned it replaces Rank 1 in
the same DML slot; learning an older numeric rank cannot downgrade the slot.
The custom_text is added to the DML tooltip, followed by the custom rank line.
When multiple custom spell IDs share one family, DML uses the exact numeric ID
for secure casting so duplicate client rank text cannot select the wrong rank.
Other spells use their normal client cast name so toggle behavior is preserved.
Set secure_cast_by_id = true or false in an individual metadata entry to
override that automatic choice.

The ALE protocol may optionally send the same metadata:

  DMLCD|LEARN|spellId|0|0|spellName|rank|customText|family
  DMLCD|META|spellId|0|0|spellName|rank|customText|family
  DMLCD|START|spellId|cooldownMs|token|spellName|rank|customText|family
  DMLCD|READY|spellId|0|token|spellName|rank|customText|family
  DMLCD|BONUS|spellId|bonusDamage
  DMLCD|MANA|spellId|extraManaCost

Old five-field messages remain compatible. Editable server text must not
contain a pipe character; the supplied cooldown tracker replaces pipes with
slashes.

DYNAMIC SPELL SCALING (v1.9.9)
------------------------------

The server may send spell-specific bonus damage and extra mana cost without
replacing the local custom_text:

  DMLCD|BONUS|34346|50
  DMLCD|MANA|34346|20

The addon caches each number by exact spell ID for the current UI session. When
the spell tooltip is shown, the local custom_text remains first and one combined
dynamic line is inserted immediately beneath it:

  Deals 65 to 80 Holy damage.
  Level scaling: +50 bonus damage, +20 mana cost
  Rank 2

Either value may appear independently. A value of 0 clears only that value for
the specified spell ID. The caches change only when BONUS or MANA messages
arrive. There is no OnUpdate polling, repeating timer, combat-log parsing, level
scan, or aura scan for this feature. The server scaling script should resend the
current values on login and whenever either value changes.

LOW-RESOURCE FADING (v1.8.0)

With Fade when resource is low enabled, spell icons fade to 35 percent opacity
when the client reports insufficient mana or another spell resource. This uses
IsUsableSpell, so it supports mana, rage, energy, and runic power for normal
spells and custom spells that exist in the client Spell.dbc. Display-only
server spell IDs that the client cannot resolve cannot expose a resource cost.

  /dmlcd resourcefade on
  /dmlcd resourcefade off

WHERE TO SEND DMLCD|LEARN

The addon normally learns about trainer purchases through SPELLS_CHANGED and
LEARNED_SPELL_IN_TAB, so no ALE message is required for a normal trainer list.
For a Lua path that explicitly calls player:LearnSpell(), send DMLCD|LEARN
immediately after the successful LearnSpell call. Do not put it in the trainer
hello function before the player actually learns the spell.


ACTIVE FORMS, STANCES, AURAS, AND QUEUED SPELLS
------------------------------------------------
DML shows the existing pale-yellow state border while a supported persistent
form/stance/aura is active or while an on-next-melee spell is queued. Holy
Strike ranks are checked by exact spell ID so only the queued rank is
highlighted.

Supported active form/stance/aura behavior:

- Holyform spell 46565
- Shadowform
- Warrior stances
- Druid shapeshifts
- Paladin auras

When one of these supported spells is inactive, its DML button shows that
spell's own normal spell-ID texture. When it becomes active, only that matching
DML button changes to:

  Interface\Icons\Spell_Nature_WispSplode

and receives the pale-yellow state border. When it deactivates, the normal
spell-ID texture returns and the border disappears.

The addon identifies normal built-in forms, stances, and paladin auras through
the client's stance/form bar state. Holyform spell 46565 and Shadowform spell
15473 also have exact aura fallbacks for clients that do not expose them as
stance-bar entries. Ordinary timed buffs, blessings, and procs are not changed
merely because they are present on the player.

Queued on-next-melee attacks keep their own spell icon and use only the state
border.

CONDITIONAL / PROC-GATED SPELL FADING
-------------------------------------
DML mirrors the client usability state for assigned spells. If IsUsableSpell
reports that a spell is unavailable because a combat condition is not currently
met (for example a parry/block/proc, execute-style threshold, stance, or similar
requirement), its icon fades to 35% alpha until ACTIONBAR_UPDATE_USABLE reports
that it is usable again. This conditional fade is independent of the optional
Resource fade setting. Resource shortages continue to fade only when Resource
fade is enabled.

A supported form, stance, or aura may optionally use a different active icon by
adding active_icon to that spell in DMLCustomSpells.lua:

  spells[SPELL_ID] = {
      name = "Spell Name",
      active_icon = "Spell_Holy_ExampleActive"
  }

Without an active_icon override, Spell_Nature_WispSplode is always used.

RANGE FINDER (v1.9.2)
---------------------
The Behavior column includes a Range finder dropdown:

- Off: no target-range visual changes.
- Border: the icon remains normal unless the target is out of range, when a
  full-size red inner border appears around the icon.
- Fade: the icon remains normal unless the target is out of range, when it
  fades to 35 percent opacity.

Actions that expose no range result remain neutral rather than being marked
out of range. The selected mode is saved with the current character profile and named profiles.


Version 1.9.0 per-bar layout
----------------------------
The config window has a Number of bars dropdown and a Bar settings dropdown.
Select a bar, edit its button count, rows, columns, button size, and gaps, then
switch to another bar. Each draft is retained until Apply and is saved in the
current character profile and named profiles.

MACROS
------
Drag a global or character macro from Blizzard's macro window onto any normal
DML bar slot. DML stores the macro name, icon, and body with the assignment, so
saved profiles remain usable after copying SavedVariables to another computer
even when macro indices differ. Clicking the button or using
its DML keybind executes the saved body through a secure macro action. Macros
can be moved, swapped, cleared, and assigned separately on Bar 1 stance pages.
When a matching live macro exists, UPDATE_MACROS refreshes the DML assignment
outside combat after the macro is edited.

MOUNTS AND NON-COMBAT COMPANION PETS
------------------------------------
Drag a mount or companion pet from the Companion tab onto any normal DML bar
slot. The assignment can be clicked or keybound like a spell or item. The
separate optional DML pet bar remains dedicated to combat-pet commands and
abilities. Mount and companion-pet assignments are included in saved profiles, stance
pages, and normal drag/swap behavior.

TRANSFERRING DML SETTINGS TO ANOTHER COMPUTER
----------------------------------------------
DMLCooldownBarGlobalDB is account-wide and contains the unified Saved Profile
list. DMLCooldownBarDB is per-character and contains the character's live layout. With WoW fully closed, copy both DMLCooldownBar.lua
SavedVariables files from the old computer to the matching account, realm, and
character folders on the new computer. Copying the entire WTF folder also
transfers these settings, but includes settings for every addon and character.
