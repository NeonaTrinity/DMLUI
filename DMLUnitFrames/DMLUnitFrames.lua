-- DMLUI - Unit Frames
-- World of Warcraft 3.3.5a / Interface 30300
--
-- Optional DMLUI module. Installing this file changes nothing until individual
-- DML unit frames are enabled from the Unit Frames configuration page.

DMLUnitFrames = DMLUnitFrames or {}
local UF = DMLUnitFrames

UF.VERSION = "2.0.102"
UF.FRAME_WIDTH = 250
UF.FRAME_HEIGHT = 82
UF.ANCHOR_HEIGHT = 18
UF.ANCHOR_GAP = 3
UF.PARTY_FRAME_WIDTH = 220
UF.PARTY_FRAME_HEIGHT = 70
UF.PARTY_PET_WIDTH = 170
UF.PARTY_PET_HEIGHT = 54
UF.PARTY_HANDLE_SIZE = 18
UF.PARTY_GROUP_WIDTH = 220
UF.PARTY_GROUP_ANCHOR_HEIGHT = 20
UF.PARTY_GROUP_GAP = 4
UF.FRAME_SCALE_MIN = 0.50
UF.FRAME_SCALE_MAX = 2.00
UF.FRAME_SCALE_SLIDER_MAX = 100
UF.PARTY_SPACING_MIN = 0
UF.PARTY_SPACING_MAX = 150
UF.FADE_PERCENT_MIN = 10
UF.FADE_PERCENT_MAX = 90
UF.DYNAMIC_UPDATE_INTERVAL = 0.20
UF.RANGE_LIST_LIMIT = 18
UF.RANGE_MIN_YARDS = 20
UF.CAST_BAR_HEIGHT = 14
UF.CAST_BAR_GAP = 3
UF.AGGRO_BORDER_MIN = 1
UF.AGGRO_BORDER_MAX = 8
UF.AGGRO_BORDER_PAD = 2
UF.DYNAMIC_MEMBER_KEYS = { "player", "party1", "party2", "party3", "party4" }

local DB
local configFrame
local configControls = {}
local initialized = false
local adjustmentSelection = "player"
local adjustmentRefreshing = false
local partyLayoutRefreshing = false
local rangeControlsRefreshing = false
local aggroControlsRefreshing = false
local dynamicElapsed = 0
local rangeCacheDirty = false
local rangeCacheElapsed = 0
local PRINT_PREFIX = "|cff66ff99DMLUI Unit Frames|r: "

UF.definitions = {
    player = { unit = "player", label = "Player", setting = "usePlayerFrame", blizzard = "PlayerFrame", x = -280, y = -170 },
    target = { unit = "target", label = "Target", setting = "useTargetFrame", blizzard = "TargetFrame", x = 280, y = -170 },
    focus = { unit = "focus", label = "Focus", setting = "useFocusFrame", blizzard = "FocusFrame", x = 280, y = -275 },
    pet = { unit = "pet", label = "Pet", setting = "usePetFrame", blizzard = "PetFrame", x = -280, y = -275 },
    targettarget = { unit = "targettarget", label = "Target of Target", setting = "useTargetTargetFrame", blizzard = "TargetFrameToT", x = 0, y = -275 }
}

local i
for i = 1, 4 do
    UF.definitions["party" .. i] = {
        unit = "party" .. i,
        label = "Party " .. i,
        setting = "usePartyFrames",
        partyMember = true,
        partyIndex = i
    }
    UF.definitions["partypet" .. i] = {
        unit = "partypet" .. i,
        label = "Party " .. i .. " Pet",
        setting = "usePartyFrames",
        partyPet = true,
        partyIndex = i
    }
end

UF.baseOrder = { "player", "target", "focus", "pet", "targettarget" }
UF.partyOrder = {
    "party1", "partypet1",
    "party2", "partypet2",
    "party3", "partypet3",
    "party4", "partypet4"
}
UF.order = {
    "player", "target", "focus", "pet", "targettarget",
    "party1", "partypet1", "party2", "partypet2",
    "party3", "partypet3", "party4", "partypet4"
}
UF.adjustmentOrder = {
    "all", "player", "target", "targettarget", "focus", "pet",
    "party", "partypet", "partygroup"
}
UF.adjustmentLabels = {
    all = "All",
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    focus = "Focus",
    pet = "Pet",
    party = "Party Members",
    partypet = "Party Pets",
    partygroup = "Party Group"
}

UF.frames = {}
UF.movers = {}
UF.handles = {}
UF.blizzardStates = {}
UF.stockChildStates = {}
UF.partyGroupMover = nil
UF.partyGroupHandle = nil
UF.externalPlayerCastBarActive = false

local defaults = {
    version = 9,
    usePlayerFrame = false,
    useTargetFrame = false,
    useFocusFrame = false,
    usePetFrame = false,
    useTargetTargetFrame = false,
    showTargetTarget = true,
    usePartyFrames = false,
    showPartyPets = true,
    movePartyAsOne = true,
    partyPetPosition = "RIGHT",
    partySpacing = 8,
    showPortrait = true,
    portraitType = "2D",
    showHealthText = true,
    showResourceText = true,
    showLevel = true,
    showClass = true,
    showCreatureType = true,
    showAnchors = true,
    locked = false,
    highlightAggro = false,
    aggroBorderIntensity = 2,
    displayCombatIcon = false,
    fadePartyOutOfRange = false,
    partyRangeSpell = "",
    partyFadePercent = 35,
    fadeTargetOutOfRange = false,
    targetRangeSpell = "",
    targetFadePercent = 35,
    showPlayerCastBar = false,
    playerCastBarPosition = "BELOW",
    showTargetCastBar = false,
    targetCastBarPosition = "BELOW",
    showTargetTargetCastBar = false,
    targetTargetCastBarPosition = "BELOW",
    useClassColorNames = false,
    useClassColorClassText = false,
    useDragonPortraits = true,
    colors = {
        name = { r = 1.00, g = 0.82, b = 0.00 },
        background = { r = 0.035, g = 0.035, b = 0.035 },
        health = { r = 0.10, g = 0.75, b = 0.15 },
        mana = { r = 0.00, g = 0.45, b = 1.00 },
        rage = { r = 0.90, g = 0.10, b = 0.10 },
        energy = { r = 1.00, g = 0.82, b = 0.00 },
        runic = { r = 0.00, g = 0.82, b = 1.00 }
    },
    positions = {},
    frameScales = {},
    partyGroupPosition = nil,
    partyIndividualPositions = {}
}

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
    end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function ClampFrameScale(value)
    value = tonumber(value) or 1
    if value < UF.FRAME_SCALE_MIN then value = UF.FRAME_SCALE_MIN end
    if value > UF.FRAME_SCALE_MAX then value = UF.FRAME_SCALE_MAX end
    return value
end

local function ClampPartySpacing(value)
    value = tonumber(value) or defaults.partySpacing
    if value < UF.PARTY_SPACING_MIN then value = UF.PARTY_SPACING_MIN end
    if value > UF.PARTY_SPACING_MAX then value = UF.PARTY_SPACING_MAX end
    return math.floor(value + 0.5)
end

local function ClampFadePercent(value)
    value = tonumber(value) or 35
    if value < UF.FADE_PERCENT_MIN then value = UF.FADE_PERCENT_MIN end
    if value > UF.FADE_PERCENT_MAX then value = UF.FADE_PERCENT_MAX end
    return math.floor(value + 0.5)
end

local function ClampAggroBorderIntensity(value)
    value = tonumber(value) or defaults.aggroBorderIntensity
    if value < UF.AGGRO_BORDER_MIN then value = UF.AGGRO_BORDER_MIN end
    if value > UF.AGGRO_BORDER_MAX then value = UF.AGGRO_BORDER_MAX end
    return math.floor(value + 0.5)
end

local function CopyTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = CopyTable(child)
    end
    return copy
end

local function ClampColorChannel(value, fallback)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 1 end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return value
end

local function NormalizeColor(value, fallback)
    value = type(value) == "table" and value or {}
    fallback = type(fallback) == "table" and fallback or { r = 1, g = 1, b = 1 }
    return {
        r = ClampColorChannel(value.r, fallback.r),
        g = ClampColorChannel(value.g, fallback.g),
        b = ClampColorChannel(value.b, fallback.b)
    }
end

local function CopyDefaults(reset)
    if reset or type(DMLUnitFramesDB) ~= "table" then
        DMLUnitFramesDB = {}
    end
    DB = DMLUnitFramesDB

    local previousVersion = tonumber(DB.version) or 0
    local hadShowTargetTarget = DB.showTargetTarget ~= nil
    local hadShowCreatureType = DB.showCreatureType ~= nil
    local key, value
    for key, value in pairs(defaults) do
        if reset or DB[key] == nil then
            if type(value) == "table" then
                DB[key] = CopyTable(value)
            else
                DB[key] = value
            end
        end
    end

    DB.version = defaults.version
    DB.usePlayerFrame = DB.usePlayerFrame and true or false
    DB.useTargetFrame = DB.useTargetFrame and true or false
    DB.useFocusFrame = DB.useFocusFrame and true or false
    DB.usePetFrame = DB.usePetFrame and true or false
    DB.useTargetTargetFrame = DB.useTargetTargetFrame and true or false
    -- Before 2.0.95, the target-of-target replacement checkbox also controlled
    -- whether the DML target-of-target frame existed. Preserve that visible
    -- state once, then keep display and Blizzard override independent.
    if previousVersion < 4 and not hadShowTargetTarget then
        -- Before this setting existed, Blizzard or DML supplied a visible ToT
        -- by default. Preserve that behavior and make this the new master toggle.
        DB.showTargetTarget = true
    else
        DB.showTargetTarget = DB.showTargetTarget and true or false
    end
    DB.usePartyFrames = DB.usePartyFrames and true or false
    DB.showPartyPets = DB.showPartyPets ~= false
    DB.movePartyAsOne = DB.movePartyAsOne ~= false
    if DB.partyPetPosition ~= "BELOW" then DB.partyPetPosition = "RIGHT" end
    DB.partySpacing = ClampPartySpacing(DB.partySpacing)
    DB.showPortrait = DB.showPortrait ~= false
    if DB.portraitType ~= "3D" and DB.portraitType ~= "CLASS" then DB.portraitType = "2D" end
    DB.showHealthText = DB.showHealthText ~= false
    DB.showResourceText = DB.showResourceText ~= false
    DB.showLevel = DB.showLevel ~= false
    DB.showClass = DB.showClass ~= false
    -- Before 2.0.100 class and creature type shared one checkbox. Preserve
    -- the old visible behavior once, then allow them to be controlled separately.
    if previousVersion < 8 and not hadShowCreatureType then
        DB.showCreatureType = DB.showClass
    else
        DB.showCreatureType = DB.showCreatureType ~= false
    end
    DB.showAnchors = DB.showAnchors ~= false
    DB.locked = DB.locked and true or false
    DB.highlightAggro = DB.highlightAggro and true or false
    DB.aggroBorderIntensity = ClampAggroBorderIntensity(DB.aggroBorderIntensity)
    DB.displayCombatIcon = DB.displayCombatIcon and true or false
    DB.fadePartyOutOfRange = DB.fadePartyOutOfRange and true or false
    DB.partyRangeSpell = type(DB.partyRangeSpell) == "string" and DB.partyRangeSpell or ""
    DB.partyFadePercent = ClampFadePercent(DB.partyFadePercent)
    DB.fadeTargetOutOfRange = DB.fadeTargetOutOfRange and true or false
    DB.targetRangeSpell = type(DB.targetRangeSpell) == "string" and DB.targetRangeSpell or ""
    DB.targetFadePercent = ClampFadePercent(DB.targetFadePercent)
    DB.showPlayerCastBar = DB.showPlayerCastBar and true or false
    if DB.playerCastBarPosition ~= "ABOVE" then DB.playerCastBarPosition = "BELOW" end
    DB.showTargetCastBar = DB.showTargetCastBar and true or false
    if DB.targetCastBarPosition ~= "ABOVE" then DB.targetCastBarPosition = "BELOW" end
    DB.showTargetTargetCastBar = DB.showTargetTargetCastBar and true or false
    if DB.targetTargetCastBarPosition ~= "ABOVE" then DB.targetTargetCastBarPosition = "BELOW" end
    DB.useClassColorNames = DB.useClassColorNames and true or false
    DB.useClassColorClassText = DB.useClassColorClassText and true or false
    DB.useDragonPortraits = DB.useDragonPortraits ~= false
    if type(DB.colors) ~= "table" then DB.colors = {} end
    DB.colors.name = NormalizeColor(DB.colors.name, defaults.colors.name)
    DB.colors.background = NormalizeColor(DB.colors.background, defaults.colors.background)
    DB.colors.health = NormalizeColor(DB.colors.health, defaults.colors.health)
    DB.colors.mana = NormalizeColor(DB.colors.mana, defaults.colors.mana)
    DB.colors.rage = NormalizeColor(DB.colors.rage, defaults.colors.rage)
    DB.colors.energy = NormalizeColor(DB.colors.energy, defaults.colors.energy)
    DB.colors.runic = NormalizeColor(DB.colors.runic, defaults.colors.runic)

    if type(DB.positions) ~= "table" then DB.positions = {} end
    if type(DB.frameScales) ~= "table" then DB.frameScales = {} end
    -- 2.0.91/2.0.92 stored the slider values as portraitScales. The defaults
    -- pass above creates an empty frameScales table, so migrate only when the
    -- new table has not already been populated.
    if type(DB.portraitScales) == "table" and next(DB.frameScales) == nil then
        for scaleKey, scaleValue in pairs(DB.portraitScales) do
            DB.frameScales[scaleKey] = scaleValue
        end
    end
    if type(DB.partyIndividualPositions) ~= "table" then DB.partyIndividualPositions = {} end

    local scaleKeys = { "player", "target", "targettarget", "focus", "pet", "party", "partypet" }
    for i = 1, #scaleKeys do
        local scaleKey = scaleKeys[i]
        DB.frameScales[scaleKey] = ClampFrameScale(DB.frameScales[scaleKey] or 1)
    end
end

local function GetDefinition(key)
    return UF.definitions[key]
end

local function IsPartyKey(key)
    return key and (string.sub(key, 1, 5) == "party")
end

local function IsDefinitionEnabled(key, definition)
    definition = definition or GetDefinition(key)
    if not definition or not DB then return false end
    if key == "targettarget" then
        return DB.showTargetTarget and DB.useTargetTargetFrame and true or false
    end
    if definition.partyPet then
        return DB.usePartyFrames and DB.showPartyPets
    end
    if definition.partyMember then
        return DB.usePartyFrames
    end
    return DB[definition.setting] and true or false
end

local function GetFrameScaleKey(key)
    local definition = GetDefinition(key)
    if definition and definition.partyPet then return "partypet" end
    if definition and definition.partyMember then return "party" end
    if key == "party" or key == "partypet" then return key end
    if key == "partygroup" then return nil end
    return key
end

local function GetFrameScale(key)
    local scaleKey = GetFrameScaleKey(key)
    if not scaleKey or not DB or type(DB.frameScales) ~= "table" then
        return 1
    end
    return ClampFrameScale(DB.frameScales[scaleKey])
end

local function ApplyFrameScale(key)
    if key == "party" then
        for i = 1, 4 do ApplyFrameScale("party" .. i) end
        return
    elseif key == "partypet" then
        for i = 1, 4 do ApplyFrameScale("partypet" .. i) end
        return
    end

    local frame = UF.frames[key]
    if not frame then return end
    frame:SetScale(GetFrameScale(key))
end

local function ApplyAllFrameScales()
    for i = 1, #UF.order do ApplyFrameScale(UF.order[i]) end
end

local function ScaleToSliderValue(scale)
    scale = ClampFrameScale(scale)
    local minValue = UF.FRAME_SCALE_MIN
    local maxValue = UF.FRAME_SCALE_MAX
    return UF.FRAME_SCALE_SLIDER_MAX * (math.log(scale / minValue) / math.log(maxValue / minValue))
end

local function SliderValueToScale(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > UF.FRAME_SCALE_SLIDER_MAX then value = UF.FRAME_SCALE_SLIDER_MAX end
    local minValue = UF.FRAME_SCALE_MIN
    local maxValue = UF.FRAME_SCALE_MAX
    return ClampFrameScale(minValue * math.exp(math.log(maxValue / minValue) * (value / UF.FRAME_SCALE_SLIDER_MAX)))
end

local function FormatFrameScale(scale)
    scale = ClampFrameScale(scale)
    if scale < 0.1 then return string.format("%.3f", scale) end
    if scale < 10 then return string.format("%.2f", scale) end
    return string.format("%.1f", scale)
end

local function SavePosition(key)
    local mover = UF.movers[key]
    if not mover or not DB or IsPartyKey(key) then return end
    local point, _, relativePoint, x, y = mover:GetPoint(1)
    DB.positions[key] = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = tonumber(x) or 0,
        y = tonumber(y) or 0
    }
end

local function RestorePosition(key)
    local mover = UF.movers[key]
    local definition = GetDefinition(key)
    if not mover or not definition or not DB or IsPartyKey(key) then return end

    local saved = DB.positions[key]
    local point = saved and saved.point or "CENTER"
    local relativePoint = saved and saved.relativePoint or "CENTER"
    local x = saved and tonumber(saved.x) or definition.x
    local y = saved and tonumber(saved.y) or definition.y

    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relativePoint, x, y)
end

local function SavePartyGroupPosition()
    local mover = UF.partyGroupMover
    if not mover or not DB then return end
    local point, _, relativePoint, x, y = mover:GetPoint(1)
    DB.partyGroupPosition = {
        point = point or "TOPLEFT",
        relativePoint = relativePoint or "TOPLEFT",
        x = tonumber(x) or 35,
        y = tonumber(y) or -190
    }
end

local function RestorePartyGroupPosition()
    local mover = UF.partyGroupMover
    if not mover or not DB then return end
    local saved = DB.partyGroupPosition
    mover:ClearAllPoints()
    mover:SetPoint(
        saved and saved.point or "TOPLEFT",
        UIParent,
        saved and saved.relativePoint or "TOPLEFT",
        saved and tonumber(saved.x) or 35,
        saved and tonumber(saved.y) or -190
    )
end

local function GetDefaultPartyIndividualPosition(key)
    local definition = GetDefinition(key)
    local idx = definition and definition.partyIndex or 1
    local rowY = -210 - ((idx - 1) * (UF.PARTY_FRAME_HEIGHT + defaults.partySpacing))
    if definition and definition.partyPet then
        return "TOPLEFT", "TOPLEFT", 263, rowY
    end
    return "TOPLEFT", "TOPLEFT", 35, rowY
end

local function SavePartyIndividualPosition(key)
    local mover = UF.movers[key]
    if not mover or not DB then return end
    local point, _, relativePoint, x, y = mover:GetPoint(1)
    DB.partyIndividualPositions[key] = {
        point = point or "TOPLEFT",
        relativePoint = relativePoint or "TOPLEFT",
        x = tonumber(x) or 0,
        y = tonumber(y) or 0
    }
end

local function RestorePartyIndividualPosition(key)
    local mover = UF.movers[key]
    if not mover or not DB then return end
    local saved = DB.partyIndividualPositions[key]
    local point, relativePoint, x, y
    if saved then
        point = saved.point or "TOPLEFT"
        relativePoint = saved.relativePoint or "TOPLEFT"
        x = tonumber(saved.x) or 0
        y = tonumber(saved.y) or 0
    else
        point, relativePoint, x, y = GetDefaultPartyIndividualPosition(key)
    end
    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relativePoint, x, y)
end

local function ApplyPartyLayout()
    if not DB or not UF.partyGroupMover then return end

    if DB.movePartyAsOne then
        RestorePartyGroupPosition()
        local memberScale = GetFrameScale("party")
        local petScale = GetFrameScale("partypet")
        local memberHeight = UF.PARTY_FRAME_HEIGHT * memberScale
        local memberWidth = UF.PARTY_FRAME_WIDTH * memberScale
        local petHeight = UF.PARTY_PET_HEIGHT * petScale
        local rowHeight = memberHeight
        if DB.showPartyPets then
            if DB.partyPetPosition == "BELOW" then
                rowHeight = memberHeight + 4 + petHeight
            elseif petHeight > rowHeight then
                rowHeight = petHeight
            end
        end
        rowHeight = rowHeight + DB.partySpacing

        for i = 1, 4 do
            local memberKey = "party" .. i
            local petKey = "partypet" .. i
            local memberMover = UF.movers[memberKey]
            local petMover = UF.movers[petKey]
            if memberMover then
                memberMover:ClearAllPoints()
                memberMover:SetPoint("TOPLEFT", UF.partyGroupMover, "BOTTOMLEFT", 0, -UF.PARTY_GROUP_GAP - ((i - 1) * rowHeight))
            end
            if petMover and memberMover then
                petMover:ClearAllPoints()
                if DB.partyPetPosition == "BELOW" then
                    petMover:SetPoint("TOPLEFT", memberMover, "TOPLEFT", 0, -(memberHeight + 4))
                else
                    petMover:SetPoint("TOPLEFT", memberMover, "TOPLEFT", memberWidth + 8, 0)
                end
            end
        end
    else
        for i = 1, #UF.partyOrder do
            RestorePartyIndividualPosition(UF.partyOrder[i])
        end
    end
end

local function SetBlizzardFrameHidden(name, hidden)
    local frame = _G[name]
    if not frame then return end

    local state = UF.blizzardStates[frame]
    if hidden then
        if not state then
            state = {
                alpha = frame.GetAlpha and frame:GetAlpha() or 1,
                mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or nil
            }
            UF.blizzardStates[frame] = state
        end
        if frame.SetAlpha then frame:SetAlpha(0) end
        if frame.EnableMouse then frame:EnableMouse(false) end
    elseif state then
        if frame.SetAlpha then frame:SetAlpha(state.alpha or 1) end
        if frame.EnableMouse and state.mouse ~= nil then frame:EnableMouse(state.mouse and true or false) end
        UF.blizzardStates[frame] = nil
    end
end

local function SetStockChildDetached(name, detached)
    local frame = _G[name]
    if not frame then return end
    local state = UF.stockChildStates[frame]
    if detached then
        if not state then
            state = { parent = frame:GetParent() }
            UF.stockChildStates[frame] = state
        end
        if frame:GetParent() ~= UIParent then frame:SetParent(UIParent) end
    elseif state then
        frame:SetParent(state.parent or UIParent)
        UF.stockChildStates[frame] = nil
    end
end

local function ApplyBlizzardFrameVisibility()
    if InCombat() then return end

    SetStockChildDetached("PetFrame", DB.usePlayerFrame and not DB.usePetFrame)
    SetStockChildDetached("TargetFrameToT", DB.useTargetFrame and not DB.useTargetTargetFrame)
    SetStockChildDetached("FocusFrameToT", DB.useFocusFrame and true or false)

    for i = 1, #UF.baseOrder do
        local key = UF.baseOrder[i]
        local definition = GetDefinition(key)
        local hideStock
        if key == "targettarget" then
            hideStock = (not DB.showTargetTarget) or (DB.useTargetTargetFrame and true or false)
        else
            hideStock = IsDefinitionEnabled(key, definition)
        end
        SetBlizzardFrameHidden(definition.blizzard, hideStock)
    end

    for i = 1, 4 do
        SetBlizzardFrameHidden("PartyMemberFrame" .. i, DB.usePartyFrames and true or false)
    end
end

local function GetPowerValues(unit)
    if UnitPower and UnitPowerMax then
        return tonumber(UnitPower(unit)) or 0, tonumber(UnitPowerMax(unit)) or 0
    end
    return tonumber(UnitMana(unit)) or 0, tonumber(UnitManaMax(unit)) or 0
end

local function GetDBColor(key, fallback)
    if DB and DB.colors and DB.colors[key] then return DB.colors[key] end
    return fallback or { r = 1, g = 1, b = 1 }
end

local function SetPowerColor(statusBar, unit)
    local powerType, powerToken
    if UnitPowerType then powerType, powerToken = UnitPowerType(unit) end
    local key
    if powerToken == "MANA" or powerType == 0 then key = "mana"
    elseif powerToken == "RAGE" or powerType == 1 then key = "rage"
    elseif powerToken == "ENERGY" or powerType == 3 then key = "energy"
    elseif powerToken == "RUNIC_POWER" or powerType == 6 then key = "runic" end

    if key then
        local color = GetDBColor(key)
        statusBar:SetStatusBarColor(color.r or 0, color.g or 0.4, color.b or 1)
        return
    end

    local color
    if ManaBarColor then
        color = ManaBarColor[powerType]
        if not color and powerToken then color = ManaBarColor[powerToken] end
    end
    if color then
        statusBar:SetStatusBarColor(color.r or 0, color.g or 0.4, color.b or 1)
    else
        statusBar:SetStatusBarColor(0, 0.45, 1)
    end
end

local function GetClassificationSuffix(unit)
    if not UnitClassification then return "" end
    local classification = UnitClassification(unit)
    if classification == "rareelite" then return "R+" end
    if classification == "rare" then return "R" end
    if classification == "elite" or classification == "worldboss" then return "+" end
    return ""
end

local function GetClassificationDragonTexture(unit)
    if not DB or not DB.useDragonPortraits or not UnitClassification then return nil end
    local classification = UnitClassification(unit)
    if classification == "rareelite" then
        return "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite"
    elseif classification == "rare" then
        return "Interface\\TargetingFrame\\UI-TargetingFrame-Rare"
    elseif classification == "elite" or classification == "worldboss" then
        return "Interface\\TargetingFrame\\UI-TargetingFrame-Elite"
    end
    return nil
end

local function GetUnitClassColor(unit)
    if not UnitIsPlayer or not UnitIsPlayer(unit) or not UnitClass then return nil end
    local _, classToken = UnitClass(unit)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    return colors and classToken and colors[classToken] or nil
end

local function ApplyNameColor(frame, unit)
    if not frame or not frame.nameText then return end
    if DB and DB.useClassColorNames then
        local color = GetUnitClassColor(unit)
        if color then
            frame.nameText:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
            return
        end
    end
    local color = GetDBColor("name", defaults.colors.name)
    frame.nameText:SetTextColor(color.r or 1, color.g or 0.82, color.b or 0)
end

local function UpdateClassCreatureText(frame, unit)
    if not frame or not frame.classText or not DB then return end
    local isPlayer = UnitIsPlayer and UnitIsPlayer(unit)
    if isPlayer and DB.showClass then
        local classDisplay = UnitClass and UnitClass(unit) or ""
        frame.classText:SetText(classDisplay or "")
        if DB.useClassColorClassText then
            local color = GetUnitClassColor(unit)
            if color then
                frame.classText:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
            else
                frame.classText:SetTextColor(1, 1, 1)
            end
        else
            frame.classText:SetTextColor(1, 1, 1)
        end
        frame.classText:Show()
    elseif (not isPlayer) and DB.showCreatureType then
        local creatureType = UnitCreatureType and UnitCreatureType(unit) or ""
        frame.classText:SetText(creatureType or "")
        frame.classText:SetTextColor(1, 1, 1)
        frame.classText:Show()
    else
        frame.classText:SetText("")
        frame.classText:Hide()
    end
end

local rangeSpellLists = { friend = {}, harm = {} }
local rangeSpellLookup = { friend = {}, harm = {} }

local function GetSpellBookRangeCandidate(slot)
    -- Stock Wrath 3.3.5 GetSpellInfo uses the old nine-return signature:
    -- name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange.
    -- Do not use the modern 6/7-return layout here. Resolve the spellbook slot
    -- first, then query metadata by spell ID (or name as a fallback).
    if not GetSpellName or not GetSpellInfo then return nil end

    local bookName, bookRank = GetSpellName(slot, BOOKTYPE_SPELL)
    if not bookName then return nil end

    local spellID
    if GetSpellBookItemInfo then
        local spellType, id = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
        if spellType == "SPELL" then spellID = tonumber(id) end
    end

    local name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange
    if spellID then
        name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange = GetSpellInfo(spellID)
    else
        name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange = GetSpellInfo(bookName)
    end

    name = name or bookName
    rank = rank or bookRank or ""
    if not icon and GetSpellTexture then icon = GetSpellTexture(slot, BOOKTYPE_SPELL) end
    maxRange = tonumber(maxRange) or 0
    minRange = tonumber(minRange) or 0
    if not name or maxRange < UF.RANGE_MIN_YARDS then return nil end

    return {
        name = name,
        rank = rank,
        icon = icon,
        castTime = tonumber(castTime) or 0,
        minRange = minRange,
        range = maxRange,
        spellID = spellID,
        slot = slot
    }
end

local function AddRangeCandidate(kind, candidate, byName)
    if not candidate then return end
    local existing = byName[candidate.name]
    -- Spellbook ranks are normally ordered low -> high. Prefer the latest slot;
    -- this keeps one entry per spell name and tracks the highest known rank.
    if not existing or candidate.slot > existing.slot then
        byName[candidate.name] = candidate
    end
end

local function SortAndLimitRangeCandidates(byName)
    local list = {}
    for _, candidate in pairs(byName) do table.insert(list, candidate) end
    table.sort(list, function(a, b)
        if a.range ~= b.range then return a.range > b.range end
        return tostring(a.name) < tostring(b.name)
    end)
    while #list > UF.RANGE_LIST_LIMIT do table.remove(list) end
    return list
end

local function ChooseDefaultRangeSpell(list)
    local best, bestDiff
    for idx = 1, #list do
        local candidate = list[idx]
        local diff = math.abs((candidate.range or 0) - 40)
        if not best or diff < bestDiff or (diff == bestDiff and candidate.range > best.range) then
            best = candidate
            bestDiff = diff
        end
    end
    return best and best.name or ""
end

local function RebuildRangeSpellCache()
    rangeSpellLists = { friend = {}, harm = {} }
    rangeSpellLookup = { friend = {}, harm = {} }
    if not GetNumSpellTabs or not GetSpellTabInfo or not IsSpellInRange then return end

    local friendByName, harmByName = {}, {}
    local tabs = tonumber(GetNumSpellTabs()) or 0
    for tab = 1, tabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset = tonumber(offset) or 0
        numSpells = tonumber(numSpells) or 0
        for slot = offset + 1, offset + numSpells do
            local spellType
            if GetSpellBookItemInfo then spellType = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL) end
            if not spellType or spellType == "SPELL" then
                local candidate = GetSpellBookRangeCandidate(slot)
                if candidate then
                    if IsHelpfulSpell and IsHelpfulSpell(slot, BOOKTYPE_SPELL) then
                        AddRangeCandidate("friend", candidate, friendByName)
                    end
                    if IsHarmfulSpell and IsHarmfulSpell(slot, BOOKTYPE_SPELL) then
                        AddRangeCandidate("harm", candidate, harmByName)
                    end
                end
            end
        end
    end

    rangeSpellLists.friend = SortAndLimitRangeCandidates(friendByName)
    rangeSpellLists.harm = SortAndLimitRangeCandidates(harmByName)
    for idx = 1, #rangeSpellLists.friend do
        local candidate = rangeSpellLists.friend[idx]
        rangeSpellLookup.friend[candidate.name] = candidate
    end
    for idx = 1, #rangeSpellLists.harm do
        local candidate = rangeSpellLists.harm[idx]
        rangeSpellLookup.harm[candidate.name] = candidate
    end

    if DB then
        if DB.partyRangeSpell == "" or not rangeSpellLookup.friend[DB.partyRangeSpell] then
            DB.partyRangeSpell = ChooseDefaultRangeSpell(rangeSpellLists.friend)
        end
        if DB.targetRangeSpell == "" or not rangeSpellLookup.harm[DB.targetRangeSpell] then
            DB.targetRangeSpell = ChooseDefaultRangeSpell(rangeSpellLists.harm)
        end
    end
end

local function GetSelectedRangeCandidate(kind)
    if not DB then return nil end
    local selectedName = kind == "friend" and DB.partyRangeSpell or DB.targetRangeSpell
    return rangeSpellLookup[kind] and rangeSpellLookup[kind][selectedName] or nil
end

local function IsUnitWithinSelectedSpellRange(unit, kind)
    if not UnitExists(unit) then return true end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    local candidate = GetSelectedRangeCandidate(kind)
    if not candidate or not IsSpellInRange then return true end
    local result = IsSpellInRange(candidate.slot, BOOKTYPE_SPELL, unit)
    if result == 1 or result == true then return true end
    if result == 0 or result == false then return false end
    -- The spell cannot be meaningfully checked against this unit right now.
    -- Do not falsely fade the frame.
    return true
end

local function HasUnitAggro(unit)
    if not UnitExists(unit) then return false end
    if UnitAffectingCombat and not UnitAffectingCombat(unit) then return false end
    if UnitThreatSituation then
        local status = UnitThreatSituation(unit)
        if tonumber(status) and tonumber(status) >= 2 then return true end
    end
    -- Social pulls can report threat status 0 even while the unit is the mob's
    -- actual target, so also recognize the current hostile target's target.
    if UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") and UnitIsUnit and UnitIsUnit("targettarget", unit) then
        return true
    end
    return false
end

local function ApplyAggroBorderGeometry(frame)
    if not frame or not frame.aggroBorder then return end
    local thickness = ClampAggroBorderIntensity(DB and DB.aggroBorderIntensity or defaults.aggroBorderIntensity)
    local pad = UF.AGGRO_BORDER_PAD
    local alpha = math.min(1, 0.58 + (thickness * 0.055))
    local border = frame.aggroBorder

    border.top:ClearAllPoints()
    border.top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -pad, pad)
    border.top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", pad, pad)
    border.top:SetHeight(thickness)

    border.bottom:ClearAllPoints()
    border.bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -pad, -pad)
    border.bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    border.bottom:SetHeight(thickness)

    border.left:ClearAllPoints()
    border.left:SetPoint("TOPRIGHT", frame, "TOPLEFT", -pad, pad)
    border.left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -pad, -pad)
    border.left:SetWidth(thickness)

    border.right:ClearAllPoints()
    border.right:SetPoint("TOPLEFT", frame, "TOPRIGHT", pad, pad)
    border.right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", pad, -pad)
    border.right:SetWidth(thickness)

    for _, texture in pairs(border) do
        texture:SetTexture(1, 0.03, 0.03, alpha)
    end
end

local function SetUnitAggroBorder(frame, highlighted)
    if not frame or not frame.aggroBorder then return end
    ApplyAggroBorderGeometry(frame)
    for _, texture in pairs(frame.aggroBorder) do
        if highlighted then texture:Show() else texture:Hide() end
    end
end

local function ApplyAllAggroBorderGeometry()
    for idx = 1, #UF.DYNAMIC_MEMBER_KEYS do
        local frame = UF.frames[UF.DYNAMIC_MEMBER_KEYS[idx]]
        if frame then ApplyAggroBorderGeometry(frame) end
    end
end

local function UpdateDynamicStates()
    if not DB then return end

    for idx = 1, #UF.DYNAMIC_MEMBER_KEYS do
        local key = UF.DYNAMIC_MEMBER_KEYS[idx]
        local frame = UF.frames[key]
        local definition = GetDefinition(key)
        if frame and definition then
            local unit = definition.unit
            local aggro = DB.highlightAggro and HasUnitAggro(unit) or false
            SetUnitAggroBorder(frame, aggro)
            if frame.combatIcon then
                local inCombat = DB.displayCombatIcon and UnitExists(unit) and UnitAffectingCombat and UnitAffectingCombat(unit)
                if inCombat then frame.combatIcon:Show() else frame.combatIcon:Hide() end
            end
        end
    end

    local partyAlpha = ClampFadePercent(DB.partyFadePercent) / 100
    for idx = 1, 4 do
        local key = "party" .. idx
        local frame = UF.frames[key]
        if frame then
            local alpha = 1
            if DB.fadePartyOutOfRange and UnitExists(key) and not IsUnitWithinSelectedSpellRange(key, "friend") then
                alpha = partyAlpha
            end
            frame:SetAlpha(alpha)
        end
    end

    local targetFrame = UF.frames.target
    if targetFrame then
        local alpha = 1
        if UnitExists("target") then
            local targetIsParty = false
            if UnitIsUnit then
                for idx = 1, 4 do
                    if UnitExists("party" .. idx) and UnitIsUnit("target", "party" .. idx) then
                        targetIsParty = true
                        break
                    end
                end
            end
            if targetIsParty and DB.fadePartyOutOfRange then
                if not IsUnitWithinSelectedSpellRange("target", "friend") then alpha = partyAlpha end
            elseif DB.fadeTargetOutOfRange and UnitCanAttack and UnitCanAttack("player", "target") then
                if not IsUnitWithinSelectedSpellRange("target", "harm") then
                    alpha = ClampFadePercent(DB.targetFadePercent) / 100
                end
            end
        end
        targetFrame:SetAlpha(alpha)
    end
end

local function HideUnitCastTemplateArtwork(bar)
    if not bar or not bar.GetName then return end
    local base = bar:GetName()
    local suffixes = { "Border", "BorderShield", "Spark", "Flash", "Icon", "Text" }
    for _, suffix in ipairs(suffixes) do
        local region = _G[base .. suffix]
        if region and region.Hide then region:Hide() end
    end
end

local function RefreshUnitCastOverlay(bar)
    if not bar then return end
    HideUnitCastTemplateArtwork(bar)
    local unit = bar.unit
    local name, text
    if bar.channeling and UnitChannelInfo then
        name, _, text = UnitChannelInfo(unit)
    elseif bar.casting and UnitCastingInfo then
        name, _, text = UnitCastingInfo(unit)
    end
    if bar.text then
        if bar.casting or bar.channeling then
            bar.text:SetText((text and text ~= "" and text) or name or "")
            bar.text:Show()
        else
            bar.text:Hide()
        end
    end
    if bar.timeText then
        if bar.casting or bar.channeling then
            local value = tonumber(bar.value) or 0
            local maximum = tonumber(bar.maxValue) or 0
            local remaining = bar.channeling and value or math.max(0, maximum - value)
            bar.timeText:SetText(string.format("%.1f", math.max(0, remaining)))
            bar.timeText:Show()
        else
            bar.timeText:Hide()
        end
    end
end

local function GetCastBarConfig(key)
    if key == "player" then
        if UF.externalPlayerCastBarActive then return false, DB.playerCastBarPosition end
        return DB.showPlayerCastBar, DB.playerCastBarPosition
    end
    if key == "target" then return DB.showTargetCastBar, DB.targetCastBarPosition end
    if key == "targettarget" then return DB.showTargetTargetCastBar, DB.targetTargetCastBarPosition end
    return false, "BELOW"
end

local function ApplyCastBarPosition(key)
    local frame = UF.frames[key]
    if not frame or not frame.castBar or not DB then return end
    local _, position = GetCastBarConfig(key)
    local bar = frame.castBar
    bar:ClearAllPoints()
    if position == "ABOVE" then
        bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, UF.CAST_BAR_GAP)
    else
        bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -UF.CAST_BAR_GAP)
    end
end

local function UpdateCastBar(key)
    local frame = UF.frames[key]
    local definition = GetDefinition(key)
    if not frame or not frame.castBar or not definition or not DB then return end
    local enabled = GetCastBarConfig(key)
    local bar = frame.castBar
    bar.showCastbar = (enabled and IsDefinitionEnabled(key, definition)) and true or false
    if not bar.showCastbar or not UnitExists(definition.unit) then
        bar:Hide()
        return
    end

    ApplyCastBarPosition(key)
    local unit = definition.unit
    local channelName = UnitChannelInfo and UnitChannelInfo(unit)
    local castName = UnitCastingInfo and UnitCastingInfo(unit)
    if channelName and CastingBarFrame_OnEvent then
        CastingBarFrame_OnEvent(bar, "UNIT_SPELLCAST_CHANNEL_START", unit)
    elseif castName and CastingBarFrame_OnEvent then
        CastingBarFrame_OnEvent(bar, "UNIT_SPELLCAST_START", unit)
    else
        bar.casting = nil
        bar.channeling = nil
        bar:Hide()
    end
    RefreshUnitCastOverlay(bar)
end

local function UpdateAllCastBars()
    UpdateCastBar("player")
    UpdateCastBar("target")
    UpdateCastBar("targettarget")
end

local CLASS_ICON_COORDS_FALLBACK = {
    WARRIOR = { 0, 0.25, 0, 0.25 },
    MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 },
    SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
    WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
    DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 }
}

local function Show2DPortrait(frame, unit)
    if frame.portraitModel then frame.portraitModel:Hide() end
    frame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if SetPortraitTexture then SetPortraitTexture(frame.portrait, unit) end
    frame.portrait:Show()
end

local function ShowClassPortrait(frame, unit)
    -- Class icons are for the player/friendly player units. Hostile units,
    -- including enemy players, intentionally keep their normal 2D portrait.
    if not (UnitIsPlayer and UnitIsPlayer(unit)) or (UnitCanAttack and UnitCanAttack("player", unit)) then
        Show2DPortrait(frame, unit)
        return
    end
    local _, classToken = UnitClass(unit)
    local coords = classToken and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]) or CLASS_ICON_COORDS_FALLBACK[classToken])
    if not coords then
        Show2DPortrait(frame, unit)
        return
    end
    if frame.portraitModel then frame.portraitModel:Hide() end
    frame.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    frame.portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    frame.portrait:Show()
end

local function Show3DPortrait(frame, unit)
    local model = frame.portraitModel
    if not model or not model.SetUnit then
        Show2DPortrait(frame, unit)
        return
    end
    frame.portrait:Hide()
    model:Show()
    model:SetUnit(unit)
    if model.SetPortraitZoom then model:SetPortraitZoom(1) end
    if model.SetPosition then model:SetPosition(0, 0, 0) end
end

local function UpdatePortraitDisplay(frame, unit)
    if not DB.showPortrait then
        frame.portrait:Hide()
        if frame.portraitModel then frame.portraitModel:Hide() end
        frame.portraitBorder:Hide()
        if frame.classificationDragon then frame.classificationDragon:Hide() end
        return
    end

    frame.portraitBorder:Show()
    if DB.portraitType == "3D" then
        Show3DPortrait(frame, unit)
    elseif DB.portraitType == "CLASS" then
        ShowClassPortrait(frame, unit)
    else
        Show2DPortrait(frame, unit)
    end

    if frame.classificationDragon then
        local dragonTexture = GetClassificationDragonTexture(unit)
        if dragonTexture then
            frame.classificationDragon:SetTexture(dragonTexture)
            frame.classificationDragon:Show()
        else
            frame.classificationDragon:Hide()
        end
    end
end

local function UpdateFrame(key)
    local frame = UF.frames[key]
    local definition = GetDefinition(key)
    if not frame or not definition or not DB then return end

    local unit = definition.unit
    if not IsDefinitionEnabled(key, definition) then
        if frame.castBar then frame.castBar:Hide() end
        frame:Hide()
        return
    end

    if not UnitExists(unit) then
        if frame.castBar then frame.castBar:Hide() end
        if not RegisterUnitWatch then frame:Hide() end
        return
    end

    if not RegisterUnitWatch then frame:Show() end

    frame.nameText:SetText(UnitName(unit) or definition.label)
    ApplyNameColor(frame, unit)
    local backgroundColor = GetDBColor("background", defaults.colors.background)
    frame:SetBackdropColor(backgroundColor.r, backgroundColor.g, backgroundColor.b, 0.92)

    local level = UnitLevel(unit)
    if DB.showLevel and frame.levelText then
        if tonumber(level) and tonumber(level) < 0 then
            frame.levelText:Hide()
            if frame.levelSkull then frame.levelSkull:Show() end
        else
            if frame.levelSkull then frame.levelSkull:Hide() end
            frame.levelText:SetText(tostring(level or "") .. GetClassificationSuffix(unit))
            if UnitCanAttack and UnitCanAttack("player", unit) and tonumber(level) then
                local colorFunc = GetQuestDifficultyColor or GetDifficultyColor
                local color = colorFunc and colorFunc(tonumber(level)) or nil
                if color then frame.levelText:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
                else frame.levelText:SetTextColor(1, 1, 1) end
            else
                frame.levelText:SetTextColor(1, 0.82, 0)
            end
            frame.levelText:Show()
        end
    elseif frame.levelText then
        frame.levelText:Hide()
        if frame.levelSkull then frame.levelSkull:Hide() end
    end

    UpdateClassCreatureText(frame, unit)

    UpdatePortraitDisplay(frame, unit)

    local health = tonumber(UnitHealth(unit)) or 0
    local healthMax = tonumber(UnitHealthMax(unit)) or 0
    if healthMax < 1 then healthMax = 1 end
    frame.healthBar:SetMinMaxValues(0, healthMax)
    frame.healthBar:SetValue(math.max(0, health))
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        frame.healthBar:SetStatusBarColor(0.35, 0.35, 0.35)
    else
        local healthColor = GetDBColor("health", defaults.colors.health)
        frame.healthBar:SetStatusBarColor(healthColor.r, healthColor.g, healthColor.b)
    end
    if DB.showHealthText then
        frame.healthText:SetText(tostring(health) .. " / " .. tostring(healthMax))
        frame.healthText:Show()
    else
        frame.healthText:Hide()
    end

    local power, powerMax = GetPowerValues(unit)
    if powerMax > 0 then
        frame.powerBar:SetMinMaxValues(0, powerMax)
        frame.powerBar:SetValue(math.max(0, power))
        SetPowerColor(frame.powerBar, unit)
        frame.powerBar:Show()
        if DB.showResourceText then
            frame.powerText:SetText(tostring(power) .. " / " .. tostring(powerMax))
            frame.powerText:Show()
        else
            frame.powerText:Hide()
        end
    else
        frame.powerBar:Hide()
        frame.powerText:Hide()
    end
    if frame.castBar then UpdateCastBar(key) end
end

local function UpdateAllFrames()
    for i = 1, #UF.order do UpdateFrame(UF.order[i]) end
end

local function SetHandleShown(handle, shown)
    if not handle then return end
    if shown then handle:Show() else handle:Hide() end
end

local function ApplyAnchorState()
    if not DB then return end

    for i = 1, #UF.baseOrder do
        local key = UF.baseOrder[i]
        local definition = GetDefinition(key)
        local mover = UF.movers[key]
        local handle = UF.handles[key]
        if mover and handle then
            if IsDefinitionEnabled(key, definition) then
                mover:Show()
                SetHandleShown(handle, DB.showAnchors and not DB.locked)
            else
                handle:Hide()
                mover:Hide()
            end
        end
    end

    if DB.usePartyFrames then
        for i = 1, 4 do
            local memberMover = UF.movers["party" .. i]
            local petMover = UF.movers["partypet" .. i]
            if memberMover then memberMover:Show() end
            if petMover then
                if DB.showPartyPets then petMover:Show() else petMover:Hide() end
            end
        end

        if DB.movePartyAsOne then
            SetHandleShown(UF.partyGroupMover, DB.showAnchors and not DB.locked)
            for i = 1, #UF.partyOrder do SetHandleShown(UF.handles[UF.partyOrder[i]], false) end
        else
            SetHandleShown(UF.partyGroupMover, false)
            for i = 1, 4 do
                SetHandleShown(UF.handles["party" .. i], DB.showAnchors and not DB.locked)
                SetHandleShown(UF.handles["partypet" .. i], DB.showPartyPets and DB.showAnchors and not DB.locked)
            end
        end
    else
        SetHandleShown(UF.partyGroupMover, false)
        for i = 1, #UF.partyOrder do
            local key = UF.partyOrder[i]
            if UF.handles[key] then UF.handles[key]:Hide() end
            if UF.movers[key] then UF.movers[key]:Hide() end
        end
    end
end

local function ApplyFrameActivation()
    if InCombat() then
        Print("Unit frame enable/disable changes cannot be applied during combat.")
        return false
    end

    ApplyAllFrameScales()
    ApplyPartyLayout()
    ApplyAnchorState()

    for i = 1, #UF.order do
        local key = UF.order[i]
        local definition = GetDefinition(key)
        local frame = UF.frames[key]
        if frame then
            if IsDefinitionEnabled(key, definition) then
                if RegisterUnitWatch then
                    RegisterUnitWatch(frame)
                elseif UnitExists(definition.unit) then
                    frame:Show()
                end
            else
                if UnregisterUnitWatch then UnregisterUnitWatch(frame) end
                frame:Hide()
            end
        end
    end

    ApplyBlizzardFrameVisibility()
    UpdateAllFrames()
    UpdateAllCastBars()
    UpdateDynamicStates()
    return true
end

local function PopulateUnitPopup(dropdown, key)
    local definition = GetDefinition(key)
    if not definition or not UnitPopup_ShowMenu then return end
    local unit = definition.unit

    if key == "focus" then
        UnitPopup_ShowMenu(dropdown, "FOCUS", unit, SET_FOCUS)
        return
    end

    local menu
    local name
    local id
    if UnitIsUnit and UnitIsUnit(unit, "player") then
        menu = "SELF"
    elseif UnitIsUnit and UnitIsUnit(unit, "vehicle") then
        menu = "VEHICLE"
    elseif UnitIsUnit and UnitIsUnit(unit, "pet") then
        menu = "PET"
    elseif UnitIsPlayer and UnitIsPlayer(unit) then
        id = UnitInRaid and UnitInRaid(unit) or nil
        if id then
            menu = "RAID_PLAYER"
            if GetRaidRosterInfo then name = GetRaidRosterInfo(id + 1) end
        elseif UnitInParty and UnitInParty(unit) then
            menu = "PARTY"
        else
            menu = "PLAYER"
        end
    else
        menu = "TARGET"
        name = RAID_TARGET_ICON
    end
    UnitPopup_ShowMenu(dropdown, menu, unit, name, id)
end

local function CreateUnitMenu(frame, key)
    local definition = GetDefinition(key)
    if not definition then return end

    local dropdown = CreateFrame("Frame", "DMLUIUnitFrameDropDown_" .. key, UIParent, "UIDropDownMenuTemplate")
    dropdown:Hide()
    UIDropDownMenu_Initialize(dropdown, function(self) PopulateUnitPopup(self, key) end, "MENU")

    local showMenu = function()
        if UnitExists(definition.unit) then
            ToggleDropDownMenu(1, nil, dropdown, frame:GetName(), 120, 10)
        end
    end

    if SecureUnitButton_OnLoad then
        SecureUnitButton_OnLoad(frame, definition.unit, showMenu)
    else
        frame:SetAttribute("unit", definition.unit)
        frame:SetAttribute("*type1", "target")
        frame:SetAttribute("*type2", "menu")
        frame.menu = showMenu
    end

    frame.unit = definition.unit
    frame.dmlMenuDropDown = dropdown
end

local function GetFrameMetrics(definition)
    if definition.partyPet then
        return {
            width = UF.PARTY_PET_WIDTH, height = UF.PARTY_PET_HEIGHT,
            portraitBorder = 42, portrait = 36, portraitX = 4,
            textX = 52, nameY = -7, classY = -22,
            barWidth = 110, healthY = -31, healthH = 11,
            powerY = -45, powerH = 8,
            levelRight = -7, levelY = -7
        }
    elseif definition.partyMember then
        return {
            width = UF.PARTY_FRAME_WIDTH, height = UF.PARTY_FRAME_HEIGHT,
            portraitBorder = 58, portrait = 52, portraitX = 5,
            textX = 68, nameY = -7, classY = -23,
            barWidth = 143, healthY = -39, healthH = 13,
            powerY = -56, powerH = 9,
            levelRight = -8, levelY = -8
        }
    end
    return {
        width = UF.FRAME_WIDTH, height = UF.FRAME_HEIGHT,
        portraitBorder = 72, portrait = 66, portraitX = 5,
        textX = 82, nameY = -8, classY = -25,
        barWidth = 160, healthY = -42, healthH = 16,
        powerY = -62, powerH = 12,
        levelRight = -9, levelY = -9
    }
end

local function CreateUnitFrame(key)
    if UF.frames[key] then return UF.frames[key] end
    local definition = GetDefinition(key)
    if not definition then return nil end
    local metrics = GetFrameMetrics(definition)
    local isParty = definition.partyMember or definition.partyPet

    local mover = CreateFrame("Frame", "DMLUIUnitFrameMover_" .. key, UIParent)
    mover:SetWidth(metrics.width)
    mover:SetHeight(isParty and metrics.height or (metrics.height + UF.ANCHOR_HEIGHT + UF.ANCHOR_GAP))
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(false)

    local frame = CreateFrame("Button", "DMLUIUnitFrame_" .. key, mover, "SecureUnitButtonTemplate")
    frame:SetWidth(metrics.width)
    frame:SetHeight(metrics.height)
    -- Anchor from the top-left so changing the complete unit-frame scale keeps
    -- its saved position stable and grows/shrinks down and to the right.
    if isParty then
        frame:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, -(UF.ANCHOR_HEIGHT + UF.ANCHOR_GAP))
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:RegisterForClicks("AnyUp")
    CreateUnitMenu(frame, key)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.035, 0.035, 0.035, 0.92)
    frame:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)

    -- Aggro highlight is an overlay outside the unit frame rather than the
    -- frame's normal backdrop border. This keeps the portrait from covering it
    -- and lets intensity change the visible border thickness.
    local aggroBorder = {}
    aggroBorder.top = frame:CreateTexture(nil, "OVERLAY")
    aggroBorder.bottom = frame:CreateTexture(nil, "OVERLAY")
    aggroBorder.left = frame:CreateTexture(nil, "OVERLAY")
    aggroBorder.right = frame:CreateTexture(nil, "OVERLAY")
    frame.aggroBorder = aggroBorder
    ApplyAggroBorderGeometry(frame)
    for _, texture in pairs(aggroBorder) do texture:Hide() end

    local portraitBorder = frame:CreateTexture(nil, "BACKGROUND")
    portraitBorder:SetWidth(metrics.portraitBorder)
    portraitBorder:SetHeight(metrics.portraitBorder)
    portraitBorder:SetPoint("LEFT", frame, "LEFT", metrics.portraitX, 0)
    portraitBorder:SetTexture(0.12, 0.12, 0.12, 1)

    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetWidth(metrics.portrait)
    portrait:SetHeight(metrics.portrait)
    portrait:SetPoint("CENTER", portraitBorder, "CENTER", 0, 0)
    portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local portraitModel = CreateFrame("PlayerModel", nil, frame)
    portraitModel:SetWidth(metrics.portrait)
    portraitModel:SetHeight(metrics.portrait)
    portraitModel:SetPoint("CENTER", portraitBorder, "CENTER", 0, 0)
    portraitModel:SetFrameLevel(frame:GetFrameLevel() + 1)
    portraitModel:Hide()

    -- Keep classification/combat artwork above the 3D model as well as the 2D texture.
    local portraitOverlay = CreateFrame("Frame", nil, frame)
    portraitOverlay:SetWidth(metrics.portraitBorder * 1.75)
    portraitOverlay:SetHeight(metrics.portraitBorder * 1.65)
    portraitOverlay:SetPoint("CENTER", portraitBorder, "CENTER", 4, 0)
    portraitOverlay:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Blizzard's rare/elite target-frame textures contain the stock silver/gold
    -- dragon ornament around the portrait area. Crop the right side so the
    -- ornament can sit around DML's portrait without replacing the whole frame.
    local classificationDragon = portraitOverlay:CreateTexture(nil, "OVERLAY")
    classificationDragon:SetWidth(metrics.portraitBorder * 1.65)
    classificationDragon:SetHeight(metrics.portraitBorder * 1.55)
    classificationDragon:SetPoint("CENTER", portraitBorder, "CENTER", 5, 0)
    classificationDragon:SetTexCoord(0.57, 1.0, 0.0, 0.78)
    classificationDragon:Hide()

    local combatIcon
    if key == "player" or definition.partyMember then
        combatIcon = portraitOverlay:CreateTexture(nil, "OVERLAY")
        combatIcon:SetWidth(isParty and 15 or 18)
        combatIcon:SetHeight(isParty and 15 or 18)
        combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        combatIcon:SetTexCoord(0.58, 0.90, 0.08, 0.41)
        combatIcon:SetPoint("TOPRIGHT", portraitBorder, "TOPRIGHT", 3, 3)
        combatIcon:Hide()
    end

    local nameText = frame:CreateFontString(nil, "OVERLAY", isParty and "GameFontNormalSmall" or "GameFontNormal")
    nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.textX, metrics.nameY)
    nameText:SetWidth(metrics.barWidth - 30)
    nameText:SetJustifyH("LEFT")

    local levelText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    levelText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", metrics.levelRight, metrics.levelY)
    levelText:SetJustifyH("RIGHT")
    local levelSkull = frame:CreateTexture(nil, "OVERLAY")
    local skullSize = isParty and 12 or 16
    levelSkull:SetWidth(skullSize)
    levelSkull:SetHeight(skullSize)
    levelSkull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    levelSkull:SetPoint("CENTER", levelText, "CENTER", -1, 0)
    levelSkull:Hide()

    local classText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classText:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.textX, metrics.classY)
    classText:SetWidth(metrics.barWidth)
    classText:SetJustifyH("LEFT")

    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetWidth(metrics.barWidth)
    healthBar:SetHeight(metrics.healthH)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.textX, metrics.healthY)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetMinMaxValues(0, 1)
    healthBar:SetValue(1)
    local healthBackground = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBackground:SetAllPoints(healthBar)
    healthBackground:SetTexture(0.08, 0.08, 0.08, 0.9)
    local healthText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)

    local powerBar = CreateFrame("StatusBar", nil, frame)
    powerBar:SetWidth(metrics.barWidth)
    powerBar:SetHeight(metrics.powerH)
    powerBar:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.textX, metrics.powerY)
    powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    powerBar:SetMinMaxValues(0, 1)
    powerBar:SetValue(1)
    local powerBackground = powerBar:CreateTexture(nil, "BACKGROUND")
    powerBackground:SetAllPoints(powerBar)
    powerBackground:SetTexture(0.08, 0.08, 0.08, 0.9)
    local powerText = powerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)

    frame:SetScript("OnEnter", function(self)
        if UnitExists(definition.unit) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetUnit then GameTooltip:SetUnit(definition.unit) else GameTooltip:SetText(UnitName(definition.unit) or definition.label) end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local castBar
    if key == "player" or key == "target" or key == "targettarget" then
        castBar = CreateFrame("StatusBar", "DMLUIUnitCastBar_" .. key, frame, "CastingBarFrameTemplate")
        if CastingBarFrame_OnLoad then CastingBarFrame_OnLoad(castBar, definition.unit, false, false) end
        castBar:SetWidth(metrics.width)
        castBar:SetHeight(UF.CAST_BAR_HEIGHT)
        castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        castBar:SetStatusBarColor(1.0, 0.70, 0.10)
        castBar:SetMinMaxValues(0, 1)
        castBar:SetValue(0)
        castBar:SetFrameLevel(frame:GetFrameLevel() + 4)
        castBar:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        castBar:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
        castBar:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        local castText = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castText:SetPoint("LEFT", castBar, "LEFT", 4, 0)
        castText:SetWidth(metrics.width - 48)
        castText:SetJustifyH("LEFT")
        local castTime = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castTime:SetPoint("RIGHT", castBar, "RIGHT", -4, 0)
        castTime:SetJustifyH("RIGHT")
        castBar.text = castText
        castBar.timeText = castTime
        castBar.unit = definition.unit
        castBar.ownerKey = key
        castBar:Hide()
        -- Let Blizzard's 3.3.5 CastingBarFrameTemplate drive cast/channel
        -- state and timing; keep only DMLUI's compact overlay/placement here.
        castBar:HookScript("OnEvent", function(self)
            RefreshUnitCastOverlay(self)
        end)
        castBar:HookScript("OnUpdate", function(self)
            if self.casting or self.channeling then RefreshUnitCastOverlay(self) end
        end)
        castBar:HookScript("OnShow", function(self)
            RefreshUnitCastOverlay(self)
        end)
        HideUnitCastTemplateArtwork(castBar)
    end

    local handle = CreateFrame("Frame", "DMLUIUnitFrameHandle_" .. key, mover)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = isParty and 8 or 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    handle:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)

    local handleText = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handleText:SetPoint("CENTER", handle, "CENTER", 0, 0)
    if isParty then
        handle:SetWidth(UF.PARTY_HANDLE_SIZE)
        handle:SetHeight(UF.PARTY_HANDLE_SIZE)
        handle:SetPoint("TOPRIGHT", frame, "TOPLEFT", -3, -2)
        handleText:SetText("+")
        handle:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Drag " .. definition.label)
            GameTooltip:Show()
        end)
        handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        handle:SetHeight(UF.ANCHOR_HEIGHT)
        handle:SetWidth(metrics.width)
        handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, UF.ANCHOR_GAP)
        handleText:SetText("DML " .. definition.label .. " Frame - drag to move")
    end

    handle:SetScript("OnDragStart", function()
        if DB.locked or InCombat() then return end
        if isParty and DB.movePartyAsOne then return end
        mover:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        mover:StopMovingOrSizing()
        if isParty then SavePartyIndividualPosition(key) else SavePosition(key) end
    end)

    frame.portrait = portrait
    frame.portraitModel = portraitModel
    frame.portraitOverlay = portraitOverlay
    frame.portraitBorder = portraitBorder
    frame.classificationDragon = classificationDragon
    frame.combatIcon = combatIcon
    frame.nameText = nameText
    frame.levelText = levelText
    frame.levelSkull = levelSkull
    frame.classText = classText
    frame.healthBar = healthBar
    frame.healthText = healthText
    frame.powerBar = powerBar
    frame.powerText = powerText
    frame.castBar = castBar
    UF.movers[key] = mover
    UF.frames[key] = frame
    UF.handles[key] = handle
    ApplyFrameScale(key)

    if isParty then RestorePartyIndividualPosition(key) else RestorePosition(key) end
    mover:Hide()
    frame:Hide()
    handle:Hide()
    return frame
end

local function CreatePartyGroupAnchor()
    if UF.partyGroupMover then return end
    local mover = CreateFrame("Frame", "DMLUIUnitFramePartyGroupMover", UIParent)
    mover:SetWidth(UF.PARTY_GROUP_WIDTH)
    mover:SetHeight(UF.PARTY_GROUP_ANCHOR_HEIGHT)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    mover:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
    mover:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", mover, "CENTER", 0, 0)
    text:SetText("DML Party Frames - drag to move")
    mover:SetScript("OnDragStart", function(self)
        if DB.locked or InCombat() or not DB.movePartyAsOne then return end
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePartyGroupPosition()
    end)
    UF.partyGroupMover = mover
    UF.partyGroupHandle = mover
    RestorePartyGroupPosition()
    mover:Hide()
end

local function CreateAllFrames()
    CreatePartyGroupAnchor()
    for i = 1, #UF.order do CreateUnitFrame(UF.order[i]) end
end

local function CreateCheckField(parent, key, labelText, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 3, 0)
    label:SetText(labelText)
    check.dmlLabel = label
    configControls[key] = check
    return check
end

local function SetWidgetEnabled(widget, enabled)
    if not widget then return end
    if widget.dmlIsDropDown then
        if enabled then
            if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(widget) end
        else
            if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(widget) end
        end
    elseif enabled then
        if widget.Enable then widget:Enable() end
    else
        if widget.Disable then widget:Disable() end
    end
    if widget.dmlLabel then
        if enabled then widget.dmlLabel:SetTextColor(1, 0.82, 0, 1) else widget.dmlLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
    end
end

local function RefreshColorControls()
    if not DB or not DB.colors then return end
    local keys = { "name", "background", "health", "mana", "rage", "energy", "runic" }
    for i = 1, #keys do
        local key = keys[i]
        local swatch = configControls["color_" .. key]
        local color = DB.colors[key]
        if swatch and color and swatch.SetBackdropColor then
            swatch:SetBackdropColor(color.r or 1, color.g or 1, color.b or 1, 1)
        end
    end
end

local function OpenColorPicker(colorKey)
    if not DB or not DB.colors or not ColorPickerFrame then return end
    local current = NormalizeColor(DB.colors[colorKey], defaults.colors[colorKey])
    local previous = { r = current.r, g = current.g, b = current.b }
    local function ApplyPickerColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        DB.colors[colorKey] = NormalizeColor({ r = r, g = g, b = b }, defaults.colors[colorKey])
        RefreshColorControls()
        UpdateAllFrames()
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.func = ApplyPickerColor
    ColorPickerFrame.cancelFunc = function()
        DB.colors[colorKey] = previous
        RefreshColorControls()
        UpdateAllFrames()
    end
    ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)
    if ShowUIPanel then ShowUIPanel(ColorPickerFrame) else ColorPickerFrame:Show() end
end

local function GetAdjustmentScaleKey(selection)
    if selection == "all" then return "all" end
    if selection == "partygroup" then return nil end
    if selection == "party" or selection == "partypet" then return selection end
    local definition = GetDefinition(selection)
    if definition and definition.partyMember then return "party" end
    if definition and definition.partyPet then return "partypet" end
    return selection
end

local function GetAllFrameScale()
    local keys = { "player", "target", "targettarget", "focus", "pet", "party", "partypet" }
    local first = GetFrameScale(keys[1])
    for i = 2, #keys do
        if math.abs(GetFrameScale(keys[i]) - first) > 0.0001 then
            return nil
        end
    end
    return first
end

local function RefreshAdjustmentControls()
    if not configFrame or not DB then return end
    local dropdown = configControls.adjustmentUnit
    local slider = configControls.frameScaleSlider
    local edit = configControls.frameScaleEdit
    if not dropdown or not slider or not edit then return end

    local label = UF.adjustmentLabels[adjustmentSelection] or adjustmentSelection
    local scaleKey = GetAdjustmentScaleKey(adjustmentSelection)
    adjustmentRefreshing = true
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dropdown, adjustmentSelection) end
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, label) end

    if scaleKey then
        local scale
        if scaleKey == "all" then scale = GetAllFrameScale() else scale = GetFrameScale(scaleKey) end
        if slider.Enable then slider:Enable() end
        if edit.Enable then edit:Enable() end
        if scale then
            slider:SetValue(ScaleToSliderValue(scale))
            edit:SetText(FormatFrameScale(scale))
        else
            -- Mixed individual sizes: keep the control neutral until the player
            -- chooses a new value, then that value is applied to every frame.
            slider:SetValue(ScaleToSliderValue(1))
            edit:SetText("Mixed")
        end
    else
        if slider.Disable then slider:Disable() end
        if edit.Disable then edit:Disable() end
        edit:SetText("N/A")
    end
    adjustmentRefreshing = false
end

local function SetSelectedFrameScale(value)
    if not DB then return end
    if InCombat() then
        RefreshAdjustmentControls()
        return
    end
    local scaleKey = GetAdjustmentScaleKey(adjustmentSelection)
    if not scaleKey then return end
    local scale = ClampFrameScale(value)
    if scaleKey == "all" then
        DB.frameScales.player = scale
        DB.frameScales.target = scale
        DB.frameScales.targettarget = scale
        DB.frameScales.focus = scale
        DB.frameScales.pet = scale
        DB.frameScales.party = scale
        DB.frameScales.partypet = scale
        ApplyAllFrameScales()
        ApplyPartyLayout()
    else
        DB.frameScales[scaleKey] = scale
        ApplyFrameScale(scaleKey)
        if scaleKey == "party" or scaleKey == "partypet" then ApplyPartyLayout() end
    end
    RefreshAdjustmentControls()
end

local function ApplyPartySpacing(value)
    if not DB then return end
    DB.partySpacing = ClampPartySpacing(value)
    ApplyPartyLayout()
    if configControls.partySpacingEdit then configControls.partySpacingEdit:SetText(tostring(DB.partySpacing)) end
end

local function RefreshPartyControlEnableState()
    if not configFrame then return end
    local useParty = configControls.usePartyFrames and configControls.usePartyFrames:GetChecked()
    local grouped = configControls.movePartyAsOne and configControls.movePartyAsOne:GetChecked()
    SetWidgetEnabled(configControls.showPartyPets, useParty and true or false)
    SetWidgetEnabled(configControls.movePartyAsOne, useParty and true or false)
    local layoutEnabled = useParty and grouped
    SetWidgetEnabled(configControls.partySpacingSlider, layoutEnabled and true or false)
    SetWidgetEnabled(configControls.partySpacingEdit, layoutEnabled and true or false)
    SetWidgetEnabled(configControls.partyPetPosition, layoutEnabled and true or false)
    if configControls.partySpacingLabel then
        if layoutEnabled then configControls.partySpacingLabel:SetTextColor(1, 1, 1, 1) else configControls.partySpacingLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
    end
    if configControls.partyPetPositionLabel then
        if layoutEnabled then configControls.partyPetPositionLabel:SetTextColor(1, 1, 1, 1) else configControls.partyPetPositionLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
    end
end

local function RefreshPartyLayoutControls()
    if not configFrame or not DB then return end
    partyLayoutRefreshing = true
    if configControls.partySpacingSlider then configControls.partySpacingSlider:SetValue(DB.partySpacing) end
    if configControls.partySpacingEdit then configControls.partySpacingEdit:SetText(tostring(DB.partySpacing)) end
    if configControls.partyPetPosition then
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(configControls.partyPetPosition, DB.partyPetPosition) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(configControls.partyPetPosition, DB.partyPetPosition == "BELOW" and "Below" or "Right") end
    end
    partyLayoutRefreshing = false
    RefreshPartyControlEnableState()
end

local function SetRangeDropDownSelectedIcon(dropdown, candidate)
    if not dropdown or not dropdown.dmlSelectedIcon then return end
    if candidate and candidate.icon then
        dropdown.dmlSelectedIcon:SetTexture(candidate.icon)
        dropdown.dmlSelectedIcon:Show()
    else
        dropdown.dmlSelectedIcon:Hide()
    end
end

local function FormatRangeCandidate(candidate)
    if not candidate then return "No ranged spell" end
    return tostring(candidate.name) .. " - " .. tostring(math.floor((candidate.range or 0) + 0.5)) .. " yd"
end

local function RefreshRangeControlEnableState()
    if not configFrame then return end
    local partyEnabled = configControls.fadePartyOutOfRange and configControls.fadePartyOutOfRange:GetChecked()
    local targetEnabled = configControls.fadeTargetOutOfRange and configControls.fadeTargetOutOfRange:GetChecked()
    SetWidgetEnabled(configControls.partyRangeDropDown, partyEnabled and true or false)
    SetWidgetEnabled(configControls.partyFadeEdit, partyEnabled and true or false)
    SetWidgetEnabled(configControls.targetRangeDropDown, targetEnabled and true or false)
    SetWidgetEnabled(configControls.targetFadeEdit, targetEnabled and true or false)
end

local function RefreshRangeControls()
    if not configFrame or not DB then return end
    rangeControlsRefreshing = true
    local partyCandidate = GetSelectedRangeCandidate("friend")
    local targetCandidate = GetSelectedRangeCandidate("harm")
    if configControls.partyRangeDropDown then
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(configControls.partyRangeDropDown, DB.partyRangeSpell) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(configControls.partyRangeDropDown, FormatRangeCandidate(partyCandidate)) end
        SetRangeDropDownSelectedIcon(configControls.partyRangeDropDown, partyCandidate)
    end
    if configControls.targetRangeDropDown then
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(configControls.targetRangeDropDown, DB.targetRangeSpell) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(configControls.targetRangeDropDown, FormatRangeCandidate(targetCandidate)) end
        SetRangeDropDownSelectedIcon(configControls.targetRangeDropDown, targetCandidate)
    end
    if configControls.partyFadeEdit then configControls.partyFadeEdit:SetText(tostring(DB.partyFadePercent)) end
    if configControls.targetFadeEdit then configControls.targetFadeEdit:SetText(tostring(DB.targetFadePercent)) end
    rangeControlsRefreshing = false
    RefreshRangeControlEnableState()
end

local function RefreshCastBarControlEnableState()
    if not configFrame then return end
    local playerOn = configControls.showPlayerCastBar and configControls.showPlayerCastBar:GetChecked()
    local targetOn = configControls.showTargetCastBar and configControls.showTargetCastBar:GetChecked()
    local totOn = configControls.showTargetTargetCastBar and configControls.showTargetTargetCastBar:GetChecked()
    SetWidgetEnabled(configControls.playerCastBarPosition, playerOn and true or false)
    SetWidgetEnabled(configControls.targetCastBarPosition, targetOn and true or false)
    SetWidgetEnabled(configControls.targetTargetCastBarPosition, totOn and true or false)
end

local function RefreshCastBarControls()
    if not configFrame or not DB then return end
    local rows = {
        { key = "player", value = DB.playerCastBarPosition },
        { key = "target", value = DB.targetCastBarPosition },
        { key = "targetTarget", value = DB.targetTargetCastBarPosition }
    }
    for i = 1, #rows do
        local row = rows[i]
        local dd = configControls[row.key .. "CastBarPosition"]
        if dd then
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dd, row.value) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, row.value == "ABOVE" and "Above" or "Below") end
        end
    end
    RefreshCastBarControlEnableState()
end

local function RefreshConfig()
    if not configFrame then return end
    configControls.usePlayerFrame:SetChecked(DB.usePlayerFrame and 1 or nil)
    configControls.useTargetFrame:SetChecked(DB.useTargetFrame and 1 or nil)
    configControls.useFocusFrame:SetChecked(DB.useFocusFrame and 1 or nil)
    configControls.usePetFrame:SetChecked(DB.usePetFrame and 1 or nil)
    configControls.useTargetTargetFrame:SetChecked(DB.useTargetTargetFrame and 1 or nil)
    configControls.showTargetTarget:SetChecked(DB.showTargetTarget and 1 or nil)
    configControls.usePartyFrames:SetChecked(DB.usePartyFrames and 1 or nil)
    configControls.showPartyPets:SetChecked(DB.showPartyPets and 1 or nil)
    configControls.movePartyAsOne:SetChecked(DB.movePartyAsOne and 1 or nil)
    configControls.showPortrait:SetChecked(DB.showPortrait and 1 or nil)
    if configControls.portraitType then
        UIDropDownMenu_SetSelectedValue(configControls.portraitType, DB.portraitType)
        local portraitLabels = { ["2D"] = "2D Portrait", ["3D"] = "3D Portrait", ["CLASS"] = "Class Icon" }
        UIDropDownMenu_SetText(configControls.portraitType, portraitLabels[DB.portraitType] or "2D Portrait")
        SetWidgetEnabled(configControls.portraitType, DB.showPortrait)
    end
    configControls.showHealthText:SetChecked(DB.showHealthText and 1 or nil)
    configControls.showResourceText:SetChecked(DB.showResourceText and 1 or nil)
    configControls.showLevel:SetChecked(DB.showLevel and 1 or nil)
    configControls.showClass:SetChecked(DB.showClass and 1 or nil)
    configControls.showCreatureType:SetChecked(DB.showCreatureType and 1 or nil)
    configControls.showAnchors:SetChecked(DB.showAnchors and 1 or nil)
    configControls.locked:SetChecked(DB.locked and 1 or nil)
    configControls.highlightAggro:SetChecked(DB.highlightAggro and 1 or nil)
    if configControls.aggroBorderSlider and configControls.aggroBorderEdit then
        aggroControlsRefreshing = true
        configControls.aggroBorderSlider:SetValue(DB.aggroBorderIntensity)
        configControls.aggroBorderEdit:SetText(tostring(DB.aggroBorderIntensity))
        aggroControlsRefreshing = false
    end
    configControls.displayCombatIcon:SetChecked(DB.displayCombatIcon and 1 or nil)
    configControls.fadePartyOutOfRange:SetChecked(DB.fadePartyOutOfRange and 1 or nil)
    configControls.fadeTargetOutOfRange:SetChecked(DB.fadeTargetOutOfRange and 1 or nil)
    configControls.showPlayerCastBar:SetChecked(DB.showPlayerCastBar and 1 or nil)
    configControls.showTargetCastBar:SetChecked(DB.showTargetCastBar and 1 or nil)
    configControls.showTargetTargetCastBar:SetChecked(DB.showTargetTargetCastBar and 1 or nil)
    configControls.useClassColorNames:SetChecked(DB.useClassColorNames and 1 or nil)
    configControls.useClassColorClassText:SetChecked(DB.useClassColorClassText and 1 or nil)
    configControls.useDragonPortraits:SetChecked(DB.useDragonPortraits and 1 or nil)
    RefreshColorControls()
    RefreshPartyLayoutControls()
    RefreshAdjustmentControls()
    RefreshRangeControls()
    RefreshCastBarControls()
end

local function ApplyConfig()
    if InCombat() then
        Print("Unit frame configuration cannot be changed during combat.")
        return false
    end

    DB.usePlayerFrame = configControls.usePlayerFrame:GetChecked() and true or false
    DB.useTargetFrame = configControls.useTargetFrame:GetChecked() and true or false
    DB.useFocusFrame = configControls.useFocusFrame:GetChecked() and true or false
    DB.usePetFrame = configControls.usePetFrame:GetChecked() and true or false
    DB.useTargetTargetFrame = configControls.useTargetTargetFrame:GetChecked() and true or false
    DB.showTargetTarget = configControls.showTargetTarget:GetChecked() and true or false
    DB.usePartyFrames = configControls.usePartyFrames:GetChecked() and true or false
    DB.showPartyPets = configControls.showPartyPets:GetChecked() and true or false
    DB.movePartyAsOne = configControls.movePartyAsOne:GetChecked() and true or false
    DB.showPortrait = configControls.showPortrait:GetChecked() and true or false
    if DB.portraitType ~= "3D" and DB.portraitType ~= "CLASS" then DB.portraitType = "2D" end
    DB.showHealthText = configControls.showHealthText:GetChecked() and true or false
    DB.showResourceText = configControls.showResourceText:GetChecked() and true or false
    DB.showLevel = configControls.showLevel:GetChecked() and true or false
    DB.showClass = configControls.showClass:GetChecked() and true or false
    DB.showCreatureType = configControls.showCreatureType:GetChecked() and true or false
    DB.showAnchors = configControls.showAnchors:GetChecked() and true or false
    DB.locked = configControls.locked:GetChecked() and true or false
    DB.highlightAggro = configControls.highlightAggro:GetChecked() and true or false
    if configControls.aggroBorderEdit then DB.aggroBorderIntensity = ClampAggroBorderIntensity(configControls.aggroBorderEdit:GetText()) end
    DB.displayCombatIcon = configControls.displayCombatIcon:GetChecked() and true or false
    DB.fadePartyOutOfRange = configControls.fadePartyOutOfRange:GetChecked() and true or false
    DB.fadeTargetOutOfRange = configControls.fadeTargetOutOfRange:GetChecked() and true or false
    DB.showPlayerCastBar = configControls.showPlayerCastBar:GetChecked() and true or false
    DB.showTargetCastBar = configControls.showTargetCastBar:GetChecked() and true or false
    DB.showTargetTargetCastBar = configControls.showTargetTargetCastBar:GetChecked() and true or false
    DB.useClassColorNames = configControls.useClassColorNames:GetChecked() and true or false
    DB.useClassColorClassText = configControls.useClassColorClassText:GetChecked() and true or false
    DB.useDragonPortraits = configControls.useDragonPortraits:GetChecked() and true or false
    if DB.fadePartyOutOfRange or DB.fadeTargetOutOfRange then RebuildRangeSpellCache() end

    ApplyAllAggroBorderGeometry()
    ApplyFrameActivation()
    UpdateAllCastBars()
    RefreshConfig()
    Print("Unit frame configuration applied.")
    return true
end

local function ResetSelectedFrame()
    if InCombat() then
        Print("Unit frame layout cannot be reset during combat.")
        return
    end
    local key = adjustmentSelection
    local scaleKey = GetAdjustmentScaleKey(key)
    if scaleKey == "all" then
        DB.frameScales.player = 1
        DB.frameScales.target = 1
        DB.frameScales.targettarget = 1
        DB.frameScales.focus = 1
        DB.frameScales.pet = 1
        DB.frameScales.party = 1
        DB.frameScales.partypet = 1
    elseif scaleKey then
        DB.frameScales[scaleKey] = 1
    end

    if key == "partygroup" then
        DB.partyGroupPosition = nil
        DB.partySpacing = defaults.partySpacing
        DB.partyPetPosition = defaults.partyPetPosition
        RestorePartyGroupPosition()
    elseif key == "party" then
        for i = 1, 4 do DB.partyIndividualPositions["party" .. i] = nil end
    elseif key == "partypet" then
        for i = 1, 4 do DB.partyIndividualPositions["partypet" .. i] = nil end
    elseif IsPartyKey(key) then
        DB.partyIndividualPositions[key] = nil
    elseif GetDefinition(key) then
        DB.positions[key] = nil
        RestorePosition(key)
    end

    if scaleKey == "all" then ApplyAllFrameScales() elseif scaleKey then ApplyFrameScale(scaleKey) end
    ApplyPartyLayout()
    ApplyAnchorState()
    RefreshConfig()
    Print((UF.adjustmentLabels[key] or key) .. " frame reset.")
end

local function ResetAllFrames()
    if InCombat() then
        Print("Unit frame layouts cannot be reset during combat.")
        return
    end
    DB.positions = {}
    DB.partyGroupPosition = nil
    DB.partyIndividualPositions = {}
    DB.partySpacing = defaults.partySpacing
    DB.partyPetPosition = defaults.partyPetPosition
    DB.frameScales = {
        player = 1, target = 1, targettarget = 1, focus = 1, pet = 1,
        party = 1, partypet = 1
    }
    for i = 1, #UF.baseOrder do RestorePosition(UF.baseOrder[i]) end
    RestorePartyGroupPosition()
    ApplyAllFrameScales()
    ApplyPartyLayout()
    ApplyAnchorState()
    RefreshConfig()
    Print("All DML unit frame positions and frame sizes reset.")
end

local function ResetDefaults()
    if InCombat() then
        Print("Unit frame configuration cannot be reset during combat.")
        return
    end
    CopyDefaults(true)
    ApplyAllAggroBorderGeometry()
    for i = 1, #UF.baseOrder do RestorePosition(UF.baseOrder[i]) end
    RestorePartyGroupPosition()
    ApplyFrameActivation()
    RefreshConfig()
    Print("Unit frame settings reset to defaults.")
end

local function CreateConfigFrame()
    if configFrame then return end

    configFrame = CreateFrame("Frame", "DMLUIUnitFramesConfigFrame", UIParent)
    configFrame:SetWidth(850)
    configFrame:SetHeight(810)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetFrameLevel(100)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetClampedToScreen(true)
    configFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    configFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    configFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", configFrame, "TOP", 0, -18)
    title:SetText("DMLUI - Unit Frames")
    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    -- Column 1: replacement switches, global behavior, and frame scaling.
    local section1 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section1:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -58)
    section1:SetText("Frame replacements")
    CreateCheckField(configFrame, "usePlayerFrame", "Use DML player frame", 40, -78)
    CreateCheckField(configFrame, "useTargetFrame", "Use DML target frame", 40, -108)
    CreateCheckField(configFrame, "useFocusFrame", "Use DML focus frame", 40, -138)
    CreateCheckField(configFrame, "usePetFrame", "Use DML pet frame", 40, -168)
    CreateCheckField(configFrame, "useTargetTargetFrame", "Override Blizzard target of target frame", 40, -198)
    local useParty = CreateCheckField(configFrame, "usePartyFrames", "Use DML party frames", 40, -228)
    local showPartyPets = CreateCheckField(configFrame, "showPartyPets", "Show party pets", 40, -258)
    local movePartyAsOne = CreateCheckField(configFrame, "movePartyAsOne", "Move party frames as one anchor", 40, -288)
    useParty:SetScript("OnClick", RefreshPartyControlEnableState)
    showPartyPets:SetScript("OnClick", RefreshPartyControlEnableState)
    movePartyAsOne:SetScript("OnClick", RefreshPartyControlEnableState)

    local section4 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section4:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -334)
    section4:SetText("Frame / size adjustment")
    local unitLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unitLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -366)
    unitLabel:SetText("Frame:")
    local unitDropDown = CreateFrame("Frame", "DMLUIUnitFramesAdjustmentDropDown", configFrame, "UIDropDownMenuTemplate")
    unitDropDown:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 84, -349)
    UIDropDownMenu_SetWidth(unitDropDown, 175)
    UIDropDownMenu_Initialize(unitDropDown, function()
        for j = 1, #UF.adjustmentOrder do
            local key = UF.adjustmentOrder[j]
            local info = UIDropDownMenu_CreateInfo()
            info.text = UF.adjustmentLabels[key] or key
            info.value = key
            info.checked = (adjustmentSelection == key)
            info.func = function(button)
                adjustmentSelection = button.value or key
                RefreshAdjustmentControls()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    configControls.adjustmentUnit = unitDropDown

    local scaleLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -415)
    scaleLabel:SetText("Frame scale:")
    local slider = CreateFrame("Slider", "DMLUIUnitFramesFrameScaleSlider", configFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 123, -407)
    slider:SetWidth(145)
    slider:SetHeight(16)
    slider:SetMinMaxValues(0, UF.FRAME_SCALE_SLIDER_MAX)
    slider:SetValueStep(1)
    _G[slider:GetName() .. "Low"]:SetText("0.50")
    _G[slider:GetName() .. "High"]:SetText("2.00")
    _G[slider:GetName() .. "Text"]:SetText("Unit frame size")
    slider:SetScript("OnValueChanged", function(_, value)
        if adjustmentRefreshing then return end
        SetSelectedFrameScale(SliderValueToScale(value))
    end)
    configControls.frameScaleSlider = slider

    local valueLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 83, -460)
    valueLabel:SetText("Scale value:")
    local scaleEdit = CreateFrame("EditBox", "DMLUIUnitFramesFrameScaleEdit", configFrame, "InputBoxTemplate")
    scaleEdit:SetWidth(72)
    scaleEdit:SetHeight(22)
    scaleEdit:SetPoint("LEFT", valueLabel, "RIGHT", 8, 0)
    scaleEdit:SetAutoFocus(false)
    scaleEdit:SetNumeric(false)
    scaleEdit:SetMaxLetters(8)
    local function CommitScale(self)
        local value = tonumber(self:GetText())
        if value then SetSelectedFrameScale(value) else RefreshAdjustmentControls() end
        self:ClearFocus()
    end
    scaleEdit:SetScript("OnEnterPressed", CommitScale)
    scaleEdit:SetScript("OnEditFocusLost", function(self)
        if adjustmentRefreshing then return end
        local value = tonumber(self:GetText())
        if value then SetSelectedFrameScale(value) else RefreshAdjustmentControls() end
    end)
    scaleEdit:SetScript("OnEscapePressed", function(self) RefreshAdjustmentControls(); self:ClearFocus() end)
    configControls.frameScaleEdit = scaleEdit

    local behaviorSection = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    behaviorSection:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -505)
    behaviorSection:SetText("Behavior")
    CreateCheckField(configFrame, "showTargetTarget", "Show target's target", 40, -525)
    CreateCheckField(configFrame, "highlightAggro", "Highlight unit frame aggro", 40, -555)

    local aggroLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aggroLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -592)
    aggroLabel:SetText("Aggro border intensity:")
    local aggroSlider = CreateFrame("Slider", "DMLUIUnitFramesAggroBorderSlider", configFrame, "OptionsSliderTemplate")
    aggroSlider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 45, -614)
    aggroSlider:SetWidth(150)
    aggroSlider:SetHeight(16)
    aggroSlider:SetMinMaxValues(UF.AGGRO_BORDER_MIN, UF.AGGRO_BORDER_MAX)
    aggroSlider:SetValueStep(1)
    _G[aggroSlider:GetName() .. "Low"]:SetText(tostring(UF.AGGRO_BORDER_MIN))
    _G[aggroSlider:GetName() .. "High"]:SetText(tostring(UF.AGGRO_BORDER_MAX))
    _G[aggroSlider:GetName() .. "Text"]:SetText("Border width / glow")
    local aggroEdit = CreateFrame("EditBox", "DMLUIUnitFramesAggroBorderEdit", configFrame, "InputBoxTemplate")
    aggroEdit:SetWidth(42)
    aggroEdit:SetHeight(20)
    aggroEdit:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 205, -610)
    aggroEdit:SetAutoFocus(false)
    aggroEdit:SetNumeric(true)
    aggroEdit:SetMaxLetters(1)
    local function SetAggroIntensity(value)
        if aggroControlsRefreshing then return end
        value = ClampAggroBorderIntensity(value)
        DB.aggroBorderIntensity = value
        aggroControlsRefreshing = true
        aggroSlider:SetValue(value)
        aggroEdit:SetText(tostring(value))
        aggroControlsRefreshing = false
        ApplyAllAggroBorderGeometry()
        UpdateDynamicStates()
    end
    aggroSlider:SetScript("OnValueChanged", function(_, value) SetAggroIntensity(value) end)
    aggroEdit:SetScript("OnEnterPressed", function(self) SetAggroIntensity(self:GetText()); self:ClearFocus() end)
    aggroEdit:SetScript("OnEditFocusLost", function(self) if not aggroControlsRefreshing then SetAggroIntensity(self:GetText()) end end)
    aggroEdit:SetScript("OnEscapePressed", function(self) self:SetText(tostring(DB.aggroBorderIntensity)); self:ClearFocus() end)
    configControls.aggroBorderSlider = aggroSlider
    configControls.aggroBorderEdit = aggroEdit

    CreateCheckField(configFrame, "displayCombatIcon", "Display combat icon", 40, -660)
    CreateCheckField(configFrame, "useClassColorNames", "Use class color as name", 40, -690)
    CreateCheckField(configFrame, "useDragonPortraits", "Use dragon portraits", 40, -720)

    -- Column 2: display and party placement.
    local section2 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section2:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 304, -58)
    section2:SetText("Display")
    local showPortraitCheck = CreateCheckField(configFrame, "showPortrait", "Show portrait", 310, -78)
    showPortraitCheck:SetScript("OnClick", function()
        DB.showPortrait = showPortraitCheck:GetChecked() and true or false
        SetWidgetEnabled(configControls.portraitType, DB.showPortrait)
        UpdateAllFrames()
    end)

    local portraitTypeLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    portraitTypeLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 310, -116)
    portraitTypeLabel:SetText("Portrait type:")
    local portraitTypeDropDown = CreateFrame("Frame", "DMLUIUnitFramesPortraitTypeDropDown", configFrame, "UIDropDownMenuTemplate")
    portraitTypeDropDown:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 390, -100)
    UIDropDownMenu_SetWidth(portraitTypeDropDown, 115)
    UIDropDownMenu_Initialize(portraitTypeDropDown, function()
        local options = {
            { value = "2D", text = "2D Portrait" },
            { value = "3D", text = "3D Portrait" },
            { value = "CLASS", text = "Class Icon" }
        }
        for j = 1, #options do
            local option = options[j]
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (DB.portraitType == option.value)
            info.func = function(button)
                DB.portraitType = button.value or option.value
                UIDropDownMenu_SetSelectedValue(portraitTypeDropDown, DB.portraitType)
                UIDropDownMenu_SetText(portraitTypeDropDown, option.text)
                UpdateAllFrames()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    portraitTypeDropDown.dmlIsDropDown = true
    portraitTypeDropDown.dmlLabel = portraitTypeLabel
    configControls.portraitType = portraitTypeDropDown

    CreateCheckField(configFrame, "showHealthText", "Show health text", 310, -148)
    CreateCheckField(configFrame, "showResourceText", "Show resource text", 310, -178)
    CreateCheckField(configFrame, "showLevel", "Show level", 310, -208)
    CreateCheckField(configFrame, "showClass", "Show class", 310, -238)
    CreateCheckField(configFrame, "useClassColorClassText", "Use class color for class text", 310, -268)
    CreateCheckField(configFrame, "showCreatureType", "Show creature type", 310, -298)

    local section3 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section3:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 304, -342)
    section3:SetText("Positioning")
    CreateCheckField(configFrame, "showAnchors", "Show anchors", 310, -362)
    CreateCheckField(configFrame, "locked", "Lock frames", 310, -392)

    local petPosLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    petPosLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 310, -432)
    petPosLabel:SetText("Party pet position:")
    configControls.partyPetPositionLabel = petPosLabel
    local petPosDropDown = CreateFrame("Frame", "DMLUIUnitFramesPartyPetPositionDropDown", configFrame, "UIDropDownMenuTemplate")
    petPosDropDown:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 410, -414)
    UIDropDownMenu_SetWidth(petPosDropDown, 90)
    UIDropDownMenu_Initialize(petPosDropDown, function()
        local options = { { value = "RIGHT", text = "Right" }, { value = "BELOW", text = "Below" } }
        for j = 1, #options do
            local option = options[j]
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (DB.partyPetPosition == option.value)
            info.func = function(button)
                DB.partyPetPosition = button.value or option.value
                ApplyPartyLayout()
                RefreshPartyLayoutControls()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    petPosDropDown.dmlIsDropDown = true
    configControls.partyPetPosition = petPosDropDown

    local spacingLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spacingLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 310, -475)
    spacingLabel:SetText("Party spacing:")
    configControls.partySpacingLabel = spacingLabel
    local spacingSlider = CreateFrame("Slider", "DMLUIUnitFramesPartySpacingSlider", configFrame, "OptionsSliderTemplate")
    spacingSlider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 318, -497)
    spacingSlider:SetWidth(180)
    spacingSlider:SetHeight(16)
    spacingSlider:SetMinMaxValues(UF.PARTY_SPACING_MIN, UF.PARTY_SPACING_MAX)
    spacingSlider:SetValueStep(1)
    _G[spacingSlider:GetName() .. "Low"]:SetText("0")
    _G[spacingSlider:GetName() .. "High"]:SetText("150")
    _G[spacingSlider:GetName() .. "Text"]:SetText("Vertical spacing")
    spacingSlider:SetScript("OnValueChanged", function(_, value)
        if partyLayoutRefreshing then return end
        ApplyPartySpacing(value)
    end)
    configControls.partySpacingSlider = spacingSlider
    local spacingEdit = CreateFrame("EditBox", "DMLUIUnitFramesPartySpacingEdit", configFrame, "InputBoxTemplate")
    spacingEdit:SetWidth(55)
    spacingEdit:SetHeight(22)
    spacingEdit:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 430, -547)
    spacingEdit:SetAutoFocus(false)
    spacingEdit:SetNumeric(true)
    spacingEdit:SetMaxLetters(3)
    local function CommitSpacing(self)
        local value = tonumber(self:GetText())
        if value then ApplyPartySpacing(value) else RefreshPartyLayoutControls() end
        self:ClearFocus()
    end
    spacingEdit:SetScript("OnEnterPressed", CommitSpacing)
    spacingEdit:SetScript("OnEditFocusLost", function(self)
        if partyLayoutRefreshing then return end
        local value = tonumber(self:GetText())
        if value then ApplyPartySpacing(value) else RefreshPartyLayoutControls() end
    end)
    spacingEdit:SetScript("OnEscapePressed", function(self) RefreshPartyLayoutControls(); self:ClearFocus() end)
    configControls.partySpacingEdit = spacingEdit

    local castSection = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    castSection:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 304, -600)
    castSection:SetText("Attached cast bars")

    local function CreateCastBarRow(controlKey, labelText, y, dbPositionKey)
        local check = CreateCheckField(configFrame, controlKey, labelText, 310, y)
        check:SetScript("OnClick", RefreshCastBarControlEnableState)
        local dd = CreateFrame("Frame", "DMLUIUnitFrames" .. controlKey .. "PositionDropDown", configFrame, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 455, y + 17)
        UIDropDownMenu_SetWidth(dd, 78)
        UIDropDownMenu_Initialize(dd, function()
            local options = { { value = "ABOVE", text = "Above" }, { value = "BELOW", text = "Below" } }
            for j = 1, #options do
                local option = options[j]
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.text
                info.value = option.value
                info.checked = (DB[dbPositionKey] == option.value)
                info.func = function(button)
                    DB[dbPositionKey] = button.value or option.value
                    RefreshCastBarControls()
                    UpdateAllCastBars()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        dd.dmlIsDropDown = true
        configControls[dbPositionKey] = dd
        return check, dd
    end

    CreateCastBarRow("showPlayerCastBar", "Player cast bar", -625, "playerCastBarPosition")
    CreateCastBarRow("showTargetCastBar", "Target cast bar", -655, "targetCastBarPosition")
    CreateCastBarRow("showTargetTargetCastBar", "Target's target cast bar", -685, "targetTargetCastBarPosition")

    -- Column 3: colors and range fading.
    local colorSection = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorSection:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 574, -58)
    colorSection:SetText("Colors")

    local function CreateColorRow(key, labelText, y)
        local label = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 580, y)
        label:SetText(labelText)
        local swatch = CreateFrame("Button", nil, configFrame)
        swatch:SetWidth(28)
        swatch:SetHeight(20)
        swatch:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 760, y + 4)
        swatch:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
        swatch:SetScript("OnClick", function() OpenColorPicker(key) end)
        configControls["color_" .. key] = swatch
        return swatch
    end

    CreateColorRow("name", "Name", -82)
    CreateColorRow("background", "Frame background", -116)
    CreateColorRow("health", "Health bar", -150)
    CreateColorRow("mana", "Mana", -184)
    CreateColorRow("rage", "Rage", -218)
    CreateColorRow("energy", "Energy", -252)
    CreateColorRow("runic", "Runic power", -286)

    local rangeSection = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rangeSection:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 574, -339)
    rangeSection:SetText("Range fading")

    local fadePartyCheck = CreateCheckField(configFrame, "fadePartyOutOfRange", "Fade party frames when out of range", 580, -359)
    fadePartyCheck:SetScript("OnClick", RefreshRangeControlEnableState)
    local fadeTargetCheck = CreateCheckField(configFrame, "fadeTargetOutOfRange", "Fade enemy target if out of range", 580, -519)
    fadeTargetCheck:SetScript("OnClick", RefreshRangeControlEnableState)

    local function CreateSpellRangeRow(prefix, kind, y, spellKey, fadeKey)
        local spellLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        spellLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 590, y)
        spellLabel:SetText("Spell:")

        local icon = configFrame:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(18)
        icon:SetHeight(18)
        icon:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 630, y + 5)
        icon:Hide()

        local dd = CreateFrame("Frame", "DMLUIUnitFrames" .. prefix .. "RangeDropDown", configFrame, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 640, y + 19)
        UIDropDownMenu_SetWidth(dd, 155)
        UIDropDownMenu_Initialize(dd, function()
            local list = rangeSpellLists[kind] or {}
            if #list == 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "No suitable known spells"
                info.disabled = true
                UIDropDownMenu_AddButton(info)
                return
            end
            for r = 1, #list do
                local candidate = list[r]
                local info = UIDropDownMenu_CreateInfo()
                info.text = FormatRangeCandidate(candidate)
                info.value = candidate.name
                info.icon = candidate.icon
                info.checked = (DB[spellKey] == candidate.name)
                info.func = function(button)
                    DB[spellKey] = button.value or candidate.name
                    RefreshRangeControls()
                    UpdateDynamicStates()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        dd.dmlIsDropDown = true
        dd.dmlLabel = spellLabel
        dd.dmlSelectedIcon = icon

        local fadeLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fadeLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 590, y - 31)
        fadeLabel:SetText("Fade to:")

        local edit = CreateFrame("EditBox", "DMLUIUnitFrames" .. prefix .. "FadeEdit", configFrame, "InputBoxTemplate")
        edit:SetWidth(42)
        edit:SetHeight(20)
        edit:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 645, y - 27)
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)
        edit:SetMaxLetters(2)
        edit.dmlLabel = fadeLabel
        local pct = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pct:SetPoint("LEFT", edit, "RIGHT", 2, 0)
        pct:SetText("%")

        local function CommitFade(self)
            local value = tonumber(self:GetText())
            if value then DB[fadeKey] = ClampFadePercent(value) end
            RefreshRangeControls()
            UpdateDynamicStates()
            self:ClearFocus()
        end
        edit:SetScript("OnEnterPressed", CommitFade)
        edit:SetScript("OnEditFocusLost", function(self)
            if rangeControlsRefreshing then return end
            local value = tonumber(self:GetText())
            if value then DB[fadeKey] = ClampFadePercent(value) end
            RefreshRangeControls()
            UpdateDynamicStates()
        end)
        edit:SetScript("OnEscapePressed", function(self) RefreshRangeControls(); self:ClearFocus() end)
        return dd, edit
    end

    configControls.partyRangeDropDown, configControls.partyFadeEdit = CreateSpellRangeRow("Party", "friend", -391, "partyRangeSpell", "partyFadePercent")
    configControls.targetRangeDropDown, configControls.targetFadeEdit = CreateSpellRangeRow("Target", "harm", -551, "targetRangeSpell", "targetFadePercent")

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(75)
    apply:SetHeight(24)
    apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 174, 28)
    apply:SetText("Apply")
    apply:SetScript("OnClick", ApplyConfig)

    local resetFrame = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetFrame:SetWidth(100)
    resetFrame:SetHeight(24)
    resetFrame:SetPoint("LEFT", apply, "RIGHT", 7, 0)
    resetFrame:SetText("Reset Frame")
    resetFrame:SetScript("OnClick", ResetSelectedFrame)

    local resetAll = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetAll:SetWidth(115)
    resetAll:SetHeight(24)
    resetAll:SetPoint("LEFT", resetFrame, "RIGHT", 7, 0)
    resetAll:SetText("Reset All Frames")
    resetAll:SetScript("OnClick", ResetAllFrames)

    local resetSettings = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetSettings:SetWidth(100)
    resetSettings:SetHeight(24)
    resetSettings:SetPoint("LEFT", resetAll, "RIGHT", 7, 0)
    resetSettings:SetText("Reset Settings")
    resetSettings:SetScript("OnClick", ResetDefaults)

    local closeBottom = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    closeBottom:SetWidth(70)
    closeBottom:SetHeight(24)
    closeBottom:SetPoint("LEFT", resetSettings, "RIGHT", 7, 0)
    closeBottom:SetText("Close")
    closeBottom:SetScript("OnClick", function() configFrame:Hide() end)

    table.insert(UISpecialFrames, "DMLUIUnitFramesConfigFrame")
    configFrame:Hide()
end

function UF:SetExternalPlayerCastBarActive(active)
    UF.externalPlayerCastBarActive = active and true or false
    if initialized then UpdateCastBar("player") end
end

function UF:OpenConfig()
    if not configFrame then CreateConfigFrame() end
    RefreshConfig()
    configFrame:Show()
    return true
end

local function RegisterWithCore()
    if DMLUI and DMLUI.RegisterModule then
        DMLUI:RegisterModule("UnitFrames", {
            name = "Unit Frames",
            version = UF.VERSION,
            openConfig = function() return UF:OpenConfig() end
        })
    end
end

local function RegisterSlashCommand()
    SLASH_DMLUNITFRAMES1 = "/dmluf"
    SlashCmdList["DMLUNITFRAMES"] = function() UF:OpenConfig() end
end

local function Initialize()
    if initialized then return end
    CopyDefaults(false)
    RebuildRangeSpellCache()
    CreateAllFrames()
    CreateConfigFrame()
    ApplyFrameActivation()
    RegisterWithCore()
    RegisterSlashCommand()
    initialized = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_MANA")
eventFrame:RegisterEvent("UNIT_MAXMANA")
eventFrame:RegisterEvent("UNIT_RAGE")
eventFrame:RegisterEvent("UNIT_ENERGY")
eventFrame:RegisterEvent("UNIT_FOCUS")
eventFrame:RegisterEvent("UNIT_RUNIC_POWER")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("UNIT_LEVEL")
eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "DMLUnitFrames" then Initialize() end
        return
    end
    if not initialized then return end

    if event == "PLAYER_ENTERING_WORLD" then
        RebuildRangeSpellCache()
        UpdateAllFrames()
        ApplyBlizzardFrameVisibility()
        ApplyPartyLayout()
        UpdateAllCastBars()
        UpdateDynamicStates()
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        rangeCacheDirty = true
        rangeCacheElapsed = 0
    elseif string.find(event, "UNIT_SPELLCAST", 1, true) == 1 then
        if arg1 == "player" then UpdateCastBar("player")
        elseif arg1 == "target" then UpdateCastBar("target")
        elseif arg1 == "targettarget" then UpdateCastBar("targettarget") end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateDynamicStates()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateFrame("target")
        UpdateFrame("targettarget")
        UpdateCastBar("target")
        UpdateCastBar("targettarget")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UpdateFrame("focus")
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
        for j = 1, 4 do
            UpdateFrame("party" .. j)
            UpdateFrame("partypet" .. j)
        end
        ApplyBlizzardFrameVisibility()
    elseif event == "UNIT_PET" then
        if arg1 == "player" then
            UpdateFrame("pet")
        else
            for j = 1, 4 do
                if arg1 == "party" .. j then UpdateFrame("partypet" .. j) end
            end
        end
    elseif event == "UNIT_TARGET" and arg1 == "target" then
        UpdateFrame("targettarget")
        UpdateCastBar("targettarget")
    elseif arg1 == "player" then
        UpdateFrame("player")
    elseif arg1 == "target" then
        UpdateFrame("target")
        UpdateFrame("targettarget")
    elseif arg1 == "focus" then
        UpdateFrame("focus")
    elseif arg1 == "pet" then
        UpdateFrame("pet")
    elseif arg1 == "targettarget" then
        UpdateFrame("targettarget")
    elseif arg1 then
        local matched = false
        for j = 1, 4 do
            if arg1 == "party" .. j then UpdateFrame("party" .. j); matched = true; break end
            if arg1 == "partypet" .. j then UpdateFrame("partypet" .. j); matched = true; break end
        end
        if not matched then UpdateAllFrames() end
    else
        UpdateAllFrames()
    end
    UpdateDynamicStates()
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not initialized or not DB then return end
    elapsed = tonumber(elapsed) or 0
    if rangeCacheDirty then
        rangeCacheElapsed = rangeCacheElapsed + elapsed
        if rangeCacheElapsed >= 0.50 then
            rangeCacheDirty = false
            rangeCacheElapsed = 0
            RebuildRangeSpellCache()
            if configFrame then RefreshRangeControls() end
        end
    end
    if not (DB.highlightAggro or DB.displayCombatIcon or DB.fadePartyOutOfRange or DB.fadeTargetOutOfRange) then return end
    dynamicElapsed = dynamicElapsed + elapsed
    if dynamicElapsed < UF.DYNAMIC_UPDATE_INTERVAL then return end
    dynamicElapsed = 0
    UpdateDynamicStates()
end)
