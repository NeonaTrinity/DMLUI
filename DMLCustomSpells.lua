-- DML Cooldown Bar custom spell metadata
-- World of Warcraft 3.3.5a
--
-- This file is intentionally separate from the main addon. It lets custom
-- spell IDs override misleading client rank text and add tooltip text without
-- modifying DMLCooldownBar.lua.
--
-- Supported fields:
--   name        = display name used by DML
--   family      = rank family; higher ranks in one family replace lower ranks
--   rank        = numeric rank used for sorting/replacement and tooltip text
--   custom_text = extra wrapped tooltip text, such as a missing damage range
--   icon        = optional normal icon name or full texture path
--   active_icon = optional override for a supported active form/stance/aura
--   secure_cast_by_id = optional true/false override for exact-ID casting
--   server_confirmed_cooldown = optional true/false; when true, DML ignores native/fallback 
--   cooldowns and waits for ALE START/COOLDOWN/RESET
--
-- Example:
--   [12345] = {
--       name = "Example Spell",
--       family = "example_spell",
--       rank = 1,
--       custom_text = "Deals 25 to 35 Holy damage.",
--       icon = "Spell_Holy_HolyBolt",
--       active_icon = "Spell_Holy_HolyBoltActive"
--   },

DMLCooldownBarCustomSpells = DMLCooldownBarCustomSpells or {}
local spells = DMLCooldownBarCustomSpells

spells[13953] = {
    name = "Holy Strike",
    family = "holy_strike",
    rank = 1,
    custom_text = "Deals 35 to 47 Holy damage.",
    icon = "Spell_holy_eyeforaneye"
}

spells[17143] = {
    name = "Holy Strike",
    family = "holy_strike",
    rank = 2,
    custom_text = "Deals 52 to 68 Holy damage.",
    icon = "Spell_holy_eyeforaneye"
}

spells[34232] = {
    name = "Holy Bolt",
    family = "holy_bolt",
    rank = 1,
    custom_text = "Deals 40 to 55 Holy damage. Refunds 40 mana after casting.",
    icon = "Inv_enchant_shardbrilliantlarge"
}

spells[34346] = {
    name = "Holy Bolt",
    family = "holy_bolt",
    rank = 2,
    custom_text = "Deals 65 to 80 Holy damage.",
    icon = "Inv_enchant_shardbrilliantlarge"
}

spells[59701] = {
    name = "Holy Nova",
    custom_text = "Damage scales with level",
    icon = "Spell_holy_holynova"
}


spells[16588] = {
    name = "Dark Mending",
    family = "dark_mending",
    rank = 1,
    custom_text = "Heals for 300 to 420."
}

spells[17613] = {
    name = "Dark Mending",
    family = "dark_mending",
    rank = 2,
    custom_text = "Heals for 650+ level scaling"
}

-- Holyform uses the shared Spell_Nature_WispSplode active-state icon.
spells[46565] = {
    name = "Holyform"
}


spells[41229] = {
    name = "Bloodbolt",
    custom_text = "Deals 20 base damage plus scaling damage. Also heals up to 4 allies for 25% of the damage dealt. The caster does not receive this healing. Refunds some mana after casting until level 20."
}

spells[15286] = {
    name = "Vampiric Embrace",
    custom_text = "Cultists also gain Prophecy of Blood, increasing damage taken by 20% and damage dealt by 5%."
}

spells[49701] = {
    name = "Blood Siphon",
    custom_text = "Deals 200 to 250 damage at level 40. Also heals the 2 lowest-health party members within 30 yards. Restores 50 mana below level 40.",
    icon = "Spell_DeathKnight_BloodBoil"
}

spells[24617] = {
    name = "Blood Funnel",
    custom_text = " 40yd range. Sacrifices the casters health to heal a friendly target for twice the amount drained.",
	icon = "Ability_Creature_Cursed_04"
}

spells[50452] = {
    name = "Blood Worm",
    icon = "Ability_Hunter_Pet_Worm"
}

spells[70445] = {
    name = "Blood Mirror",
custom_text = "Useable on friendly targets. lasts 15 seconds.",
    server_confirmed_cooldown = true
}

spells[16610] = {
    name = "Razorhide",
    custom_text = "Also grants 145% increased threat to Swashbuckler, 25% armor and 20% strength"
}


spells[31567] = {
    name = "Deterrence",
    custom_text = "Swashbuckler cooldown: 2 minutes. Reduced by 1 second per combo point spent.",
    server_confirmed_cooldown = true
}

spells[59395] = {
    name = "Abomination Hook",
    server_confirmed_cooldown = true,
    custom_text = "Requires a ranged weapon. Works as a grappling hook for the Swashbuckler, pulling the Swashbuckler to the target."
}

spells[52931] = {
    name = "Toxic Spit",
    custom_text = "Damage scales with level",
    icon = "ability_creature_poison_06"
}

spells[13526] = {
    name = "Corrosive Poison",
    custom_text = "Damage scales with level",
    icon = "ability_creature_disease_02"
}

spells[54593] = {
    name = "Serpent Strike",
    custom_text = "Damage scales with level",
    icon = "spell_nature_poisoncleansingtotem"
}

spells[25198] = {
    name = "Poison Cloud",
    custom_text = "Damage scales with level",
    icon = "spell_shadow_plaguecloud"
}

spells[34355] = {
    name = "Poison Shield",
    custom_text = "Damage scales with level",
    icon = "inv_armor_shield_naxxramas_d_01"
}

spells[53669] = {
    name = "Poisoned Fangs",
    custom_text = "Damage scales with level",
    icon = "ability_creature_poison_05"
}

spells[54601] = {
    name = "Serpent Form",
    server_confirmed_cooldown = true,
	icon = "inv_jewelcrafting_jadeserpent"
}

spells[59840] = {
    name = "Powerful Bite",
	custom_text = "Requires 5 stacks of blood tap."
}

spells[54790] = {
    name = "Blood Tap",
	custom_text = "Stacks up to 5 times and can be unleashed with Powerful bite"
}


spells[879] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 1,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[5614] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 2,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[5615] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 3,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[10312] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 4,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[10313] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 5,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[10314] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 6,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[27138] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 7,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[48800] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 8,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}

spells[48801] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 9,
    custom_text = "Applys a DoT that stacks up to 5 times.",
    server_confirmed_cooldown = true
}
















