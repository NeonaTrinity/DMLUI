-- DML Cooldown Bar custom item icon map
-- World of Warcraft 3.3.5a
--
-- This file is intentionally separate from the main addon. Add or change an
-- entry without editing DMLCooldownBar.lua. The icon may be either a full
-- texture path or a macro-style icon name such as "INV_Misc_Book_09".
--
-- Format:
--   [itemId] = { name = "Item name", icon = "Macro_Icon_Name" },

DMLCooldownBarCustomItems = DMLCooldownBarCustomItems or {}
local items = DMLCooldownBarCustomItems

items[990100] = {
    name = "Cleric Trial Sigil",
    icon = "INV_Misc_Rune_01"
}

items[990113] = {
    name = "Warden Trial Sigil",
    icon = "INV_Misc_Rune_01"
}


items[990101] = {
    name = "Doctrine of Holy Shock",
    icon = "Spell_Holy_SearingLight"
}

items[990102] = {
    name = "Templar Trial Sigil",
    icon = "INV_Misc_Rune_05"
}

items[990103] = {
    name = "Doctrine of Counterattack",
    icon = "Ability_Warrior_Revenge"
}

items[990104] = {
    name = "Doctrine of Reckoning: Chapter 1",
    icon = "INV_Misc_Book_09"
}

items[990105] = {
    name = "Doctrine of Reckoning: Chapter 2",
    icon = "INV_Misc_Book_09"
}

items[990106] = {
    name = "Doctrine of Reckoning: Chapter 3",
    icon = "INV_Misc_Book_09"
}

items[990107] = {
    name = "Doctrine of Reckoning: Chapter 4",
    icon = "INV_Misc_Book_09"
}

items[990108] = {
    name = "Doctrine of Reckoning: Chapter 5",
    icon = "INV_Misc_Book_09"
}

items[990109] = {
    name = "Blessed Warhorse Reins",
    icon = "Spell_Nature_Swiftness"
}

items[990110] = {
    name = "Blessed Charger Reins",
    icon = "Ability_Mount_Charger"
}

items[990111] = {
    name = "Recovered Argent Warhorse",
    icon = "Ability_Mount_RidingHorse"
}

items[990112] = {
    name = "Recovered Argent Charger",
    icon = "Ability_Mount_Charger"
}

items[990119] = {
    name = "Tome of Lichborne",
    icon = "INV_Misc_Book_09"
}

items[990120] = {
    name = "Tome of Raise Dead",
    icon = "INV_Misc_Book_09"
}

items[990121] = {
    name = "Tome of Raise Ally",
    icon = "INV_Misc_Book_09"
}
