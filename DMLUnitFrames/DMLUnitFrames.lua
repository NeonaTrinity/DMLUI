-- DMLUI - Unit Frames
-- World of Warcraft 3.3.5a / Interface 30300
--
-- Optional DMLUI module. Installing this file changes nothing until individual
-- DML unit frames are enabled from the Unit Frames configuration page.

DMLUnitFrames = DMLUnitFrames or {}
local UF = DMLUnitFrames

UF.VERSION = "2.0.92"
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
UF.PORTRAIT_SCALE_MIN = 0.02
UF.PORTRAIT_SCALE_MAX = 30.0
UF.PORTRAIT_SCALE_SLIDER_MAX = 100
UF.PARTY_SPACING_MIN = 0
UF.PARTY_SPACING_MAX = 150

local DB
local configFrame
local configControls = {}
local initialized = false
local adjustmentSelection = "player"
local adjustmentRefreshing = false
local partyLayoutRefreshing = false
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
    "player", "target", "targettarget", "focus", "pet",
    "party", "partypet", "partygroup",
    "party1", "partypet1", "party2", "partypet2",
    "party3", "partypet3", "party4", "partypet4"
}
UF.adjustmentLabels = {
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    focus = "Focus",
    pet = "Pet",
    party = "Party Members",
    partypet = "Party Pets",
    partygroup = "Party Group",
    party1 = "Party 1",
    partypet1 = "Party 1 Pet",
    party2 = "Party 2",
    partypet2 = "Party 2 Pet",
    party3 = "Party 3",
    partypet3 = "Party 3 Pet",
    party4 = "Party 4",
    partypet4 = "Party 4 Pet"
}

UF.frames = {}
UF.movers = {}
UF.handles = {}
UF.blizzardStates = {}
UF.stockChildStates = {}
UF.partyGroupMover = nil
UF.partyGroupHandle = nil

local defaults = {
    version = 2,
    usePlayerFrame = false,
    useTargetFrame = false,
    useFocusFrame = false,
    usePetFrame = false,
    useTargetTargetFrame = false,
    usePartyFrames = false,
    showPartyPets = true,
    movePartyAsOne = true,
    partyPetPosition = "RIGHT",
    partySpacing = 8,
    showPortrait = true,
    showHealthText = true,
    showResourceText = true,
    showLevel = true,
    showClass = true,
    showAnchors = true,
    locked = false,
    positions = {},
    portraitScales = {},
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

local function ClampPortraitScale(value)
    value = tonumber(value) or 1
    if value < UF.PORTRAIT_SCALE_MIN then value = UF.PORTRAIT_SCALE_MIN end
    if value > UF.PORTRAIT_SCALE_MAX then value = UF.PORTRAIT_SCALE_MAX end
    return value
end

local function ClampPartySpacing(value)
    value = tonumber(value) or defaults.partySpacing
    if value < UF.PARTY_SPACING_MIN then value = UF.PARTY_SPACING_MIN end
    if value > UF.PARTY_SPACING_MAX then value = UF.PARTY_SPACING_MAX end
    return math.floor(value + 0.5)
end

local function CopyDefaults(reset)
    if reset or type(DMLUnitFramesDB) ~= "table" then
        DMLUnitFramesDB = {}
    end
    DB = DMLUnitFramesDB

    local key, value
    for key, value in pairs(defaults) do
        if reset or DB[key] == nil then
            if type(value) == "table" then
                DB[key] = {}
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
    DB.usePartyFrames = DB.usePartyFrames and true or false
    DB.showPartyPets = DB.showPartyPets ~= false
    DB.movePartyAsOne = DB.movePartyAsOne ~= false
    if DB.partyPetPosition ~= "BELOW" then DB.partyPetPosition = "RIGHT" end
    DB.partySpacing = ClampPartySpacing(DB.partySpacing)
    DB.showPortrait = DB.showPortrait ~= false
    DB.showHealthText = DB.showHealthText ~= false
    DB.showResourceText = DB.showResourceText ~= false
    DB.showLevel = DB.showLevel ~= false
    DB.showClass = DB.showClass ~= false
    DB.showAnchors = DB.showAnchors ~= false
    DB.locked = DB.locked and true or false

    if type(DB.positions) ~= "table" then DB.positions = {} end
    if type(DB.portraitScales) ~= "table" then DB.portraitScales = {} end
    if type(DB.partyIndividualPositions) ~= "table" then DB.partyIndividualPositions = {} end

    local scaleKeys = { "player", "target", "targettarget", "focus", "pet", "party", "partypet" }
    for i = 1, #scaleKeys do
        local scaleKey = scaleKeys[i]
        DB.portraitScales[scaleKey] = ClampPortraitScale(DB.portraitScales[scaleKey] or 1)
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
    if definition.partyPet then
        return DB.usePartyFrames and DB.showPartyPets
    end
    if definition.partyMember then
        return DB.usePartyFrames
    end
    return DB[definition.setting] and true or false
end

local function GetPortraitScaleKey(key)
    local definition = GetDefinition(key)
    if definition and definition.partyPet then return "partypet" end
    if definition and definition.partyMember then return "party" end
    if key == "party" or key == "partypet" then return key end
    if key == "partygroup" then return nil end
    return key
end

local function GetPortraitScale(key)
    local scaleKey = GetPortraitScaleKey(key)
    if not scaleKey or not DB or type(DB.portraitScales) ~= "table" then
        return 1
    end
    return ClampPortraitScale(DB.portraitScales[scaleKey])
end

local function ApplyPortraitScale(key)
    if key == "party" then
        for i = 1, 4 do ApplyPortraitScale("party" .. i) end
        return
    elseif key == "partypet" then
        for i = 1, 4 do ApplyPortraitScale("partypet" .. i) end
        return
    end

    local frame = UF.frames[key]
    if not frame or not frame.portrait or not frame.portraitBorder then return end

    local scale = GetPortraitScale(key)
    local borderBase = frame.dmlPortraitBorderBase or 72
    local portraitBase = frame.dmlPortraitBase or 66
    frame.portraitBorder:SetWidth(borderBase * scale)
    frame.portraitBorder:SetHeight(borderBase * scale)
    frame.portrait:SetWidth(portraitBase * scale)
    frame.portrait:SetHeight(portraitBase * scale)
end

local function ApplyAllPortraitScales()
    for i = 1, #UF.order do ApplyPortraitScale(UF.order[i]) end
end

local function ScaleToSliderValue(scale)
    scale = ClampPortraitScale(scale)
    local minValue = UF.PORTRAIT_SCALE_MIN
    local maxValue = UF.PORTRAIT_SCALE_MAX
    return UF.PORTRAIT_SCALE_SLIDER_MAX * (math.log(scale / minValue) / math.log(maxValue / minValue))
end

local function SliderValueToScale(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > UF.PORTRAIT_SCALE_SLIDER_MAX then value = UF.PORTRAIT_SCALE_SLIDER_MAX end
    local minValue = UF.PORTRAIT_SCALE_MIN
    local maxValue = UF.PORTRAIT_SCALE_MAX
    return ClampPortraitScale(minValue * math.exp(math.log(maxValue / minValue) * (value / UF.PORTRAIT_SCALE_SLIDER_MAX)))
end

local function FormatPortraitScale(scale)
    scale = ClampPortraitScale(scale)
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
        local extraBelow = 0
        if DB.showPartyPets and DB.partyPetPosition == "BELOW" then
            extraBelow = UF.PARTY_PET_HEIGHT + 4
        end
        local rowHeight = UF.PARTY_FRAME_HEIGHT + extraBelow + DB.partySpacing

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
                    petMover:SetPoint("TOPLEFT", memberMover, "BOTTOMLEFT", 0, -4)
                else
                    petMover:SetPoint("LEFT", memberMover, "RIGHT", 8, 0)
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
        SetBlizzardFrameHidden(definition.blizzard, IsDefinitionEnabled(key, definition))
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

local function SetPowerColor(statusBar, unit)
    local powerType, powerToken
    if UnitPowerType then powerType, powerToken = UnitPowerType(unit) end
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

local function UpdateFrame(key)
    local frame = UF.frames[key]
    local definition = GetDefinition(key)
    if not frame or not definition or not DB then return end

    local unit = definition.unit
    if not IsDefinitionEnabled(key, definition) then
        frame:Hide()
        return
    end

    if not UnitExists(unit) then
        if not RegisterUnitWatch then frame:Hide() end
        return
    end

    if not RegisterUnitWatch then frame:Show() end

    frame.nameText:SetText(UnitName(unit) or definition.label)

    local level = UnitLevel(unit)
    if DB.showLevel and frame.levelText then
        if tonumber(level) and tonumber(level) < 0 then frame.levelText:SetText("??") else frame.levelText:SetText(tostring(level or "")) end
        frame.levelText:Show()
    elseif frame.levelText then
        frame.levelText:Hide()
    end

    if DB.showClass and frame.classText then
        local classDisplay = UnitClass and UnitClass(unit) or nil
        if not classDisplay or classDisplay == "" then classDisplay = UnitCreatureType and UnitCreatureType(unit) or "" end
        frame.classText:SetText(classDisplay or "")
        frame.classText:Show()
    elseif frame.classText then
        frame.classText:Hide()
    end

    if DB.showPortrait then
        if SetPortraitTexture then SetPortraitTexture(frame.portrait, unit) end
        frame.portrait:Show()
        frame.portraitBorder:Show()
    else
        frame.portrait:Hide()
        frame.portraitBorder:Hide()
    end

    local health = tonumber(UnitHealth(unit)) or 0
    local healthMax = tonumber(UnitHealthMax(unit)) or 0
    if healthMax < 1 then healthMax = 1 end
    frame.healthBar:SetMinMaxValues(0, healthMax)
    frame.healthBar:SetValue(math.max(0, health))
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        frame.healthBar:SetStatusBarColor(0.35, 0.35, 0.35)
    else
        frame.healthBar:SetStatusBarColor(0.1, 0.75, 0.15)
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
    ApplyAllPortraitScales()
    UpdateAllFrames()
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
    frame:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
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

    local nameText = frame:CreateFontString(nil, "OVERLAY", isParty and "GameFontNormalSmall" or "GameFontNormal")
    nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.textX, metrics.nameY)
    nameText:SetWidth(metrics.barWidth - 30)
    nameText:SetJustifyH("LEFT")

    local levelText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    levelText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", metrics.levelRight, metrics.levelY)
    levelText:SetJustifyH("RIGHT")

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
    frame.portraitBorder = portraitBorder
    frame.nameText = nameText
    frame.levelText = levelText
    frame.classText = classText
    frame.healthBar = healthBar
    frame.healthText = healthText
    frame.powerBar = powerBar
    frame.powerText = powerText
    frame.dmlPortraitBorderBase = metrics.portraitBorder
    frame.dmlPortraitBase = metrics.portrait

    UF.movers[key] = mover
    UF.frames[key] = frame
    UF.handles[key] = handle
    ApplyPortraitScale(key)

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

local function GetAdjustmentScaleKey(selection)
    if selection == "partygroup" then return nil end
    if selection == "party" or selection == "partypet" then return selection end
    local definition = GetDefinition(selection)
    if definition and definition.partyMember then return "party" end
    if definition and definition.partyPet then return "partypet" end
    return selection
end

local function RefreshAdjustmentControls()
    if not configFrame or not DB then return end
    local dropdown = configControls.adjustmentUnit
    local slider = configControls.portraitScaleSlider
    local edit = configControls.portraitScaleEdit
    if not dropdown or not slider or not edit then return end

    local label = UF.adjustmentLabels[adjustmentSelection] or adjustmentSelection
    local scaleKey = GetAdjustmentScaleKey(adjustmentSelection)
    adjustmentRefreshing = true
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dropdown, adjustmentSelection) end
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, label) end

    if scaleKey then
        local scale = GetPortraitScale(scaleKey)
        if slider.Enable then slider:Enable() end
        if edit.Enable then edit:Enable() end
        slider:SetValue(ScaleToSliderValue(scale))
        edit:SetText(FormatPortraitScale(scale))
    else
        if slider.Disable then slider:Disable() end
        if edit.Disable then edit:Disable() end
        edit:SetText("N/A")
    end
    adjustmentRefreshing = false
end

local function SetSelectedPortraitScale(value)
    if not DB then return end
    local scaleKey = GetAdjustmentScaleKey(adjustmentSelection)
    if not scaleKey then return end
    local scale = ClampPortraitScale(value)
    DB.portraitScales[scaleKey] = scale
    ApplyPortraitScale(scaleKey)
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

local function RefreshConfig()
    if not configFrame then return end
    configControls.usePlayerFrame:SetChecked(DB.usePlayerFrame and 1 or nil)
    configControls.useTargetFrame:SetChecked(DB.useTargetFrame and 1 or nil)
    configControls.useFocusFrame:SetChecked(DB.useFocusFrame and 1 or nil)
    configControls.usePetFrame:SetChecked(DB.usePetFrame and 1 or nil)
    configControls.useTargetTargetFrame:SetChecked(DB.useTargetTargetFrame and 1 or nil)
    configControls.usePartyFrames:SetChecked(DB.usePartyFrames and 1 or nil)
    configControls.showPartyPets:SetChecked(DB.showPartyPets and 1 or nil)
    configControls.movePartyAsOne:SetChecked(DB.movePartyAsOne and 1 or nil)
    configControls.showPortrait:SetChecked(DB.showPortrait and 1 or nil)
    configControls.showHealthText:SetChecked(DB.showHealthText and 1 or nil)
    configControls.showResourceText:SetChecked(DB.showResourceText and 1 or nil)
    configControls.showLevel:SetChecked(DB.showLevel and 1 or nil)
    configControls.showClass:SetChecked(DB.showClass and 1 or nil)
    configControls.showAnchors:SetChecked(DB.showAnchors and 1 or nil)
    configControls.locked:SetChecked(DB.locked and 1 or nil)
    RefreshPartyLayoutControls()
    RefreshAdjustmentControls()
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
    DB.usePartyFrames = configControls.usePartyFrames:GetChecked() and true or false
    DB.showPartyPets = configControls.showPartyPets:GetChecked() and true or false
    DB.movePartyAsOne = configControls.movePartyAsOne:GetChecked() and true or false
    DB.showPortrait = configControls.showPortrait:GetChecked() and true or false
    DB.showHealthText = configControls.showHealthText:GetChecked() and true or false
    DB.showResourceText = configControls.showResourceText:GetChecked() and true or false
    DB.showLevel = configControls.showLevel:GetChecked() and true or false
    DB.showClass = configControls.showClass:GetChecked() and true or false
    DB.showAnchors = configControls.showAnchors:GetChecked() and true or false
    DB.locked = configControls.locked:GetChecked() and true or false

    ApplyFrameActivation()
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
    if scaleKey then DB.portraitScales[scaleKey] = 1 end

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

    if scaleKey then ApplyPortraitScale(scaleKey) end
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
    DB.portraitScales = {
        player = 1, target = 1, targettarget = 1, focus = 1, pet = 1,
        party = 1, partypet = 1
    }
    for i = 1, #UF.baseOrder do RestorePosition(UF.baseOrder[i]) end
    RestorePartyGroupPosition()
    ApplyAllPortraitScales()
    ApplyPartyLayout()
    ApplyAnchorState()
    RefreshConfig()
    Print("All DML unit frame positions and portrait sizes reset.")
end

local function ResetDefaults()
    if InCombat() then
        Print("Unit frame configuration cannot be reset during combat.")
        return
    end
    CopyDefaults(true)
    for i = 1, #UF.baseOrder do RestorePosition(UF.baseOrder[i]) end
    RestorePartyGroupPosition()
    ApplyFrameActivation()
    RefreshConfig()
    Print("Unit frame settings reset to defaults.")
end

local function CreateConfigFrame()
    if configFrame then return end

    configFrame = CreateFrame("Frame", "DMLUIUnitFramesConfigFrame", UIParent)
    configFrame:SetWidth(560)
    configFrame:SetHeight(730)
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

    local section1 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section1:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -58)
    section1:SetText("Frame replacements")
    CreateCheckField(configFrame, "usePlayerFrame", "Use DML player frame", 40, -78)
    CreateCheckField(configFrame, "useTargetFrame", "Use DML target frame", 40, -108)
    CreateCheckField(configFrame, "useFocusFrame", "Use DML focus frame", 40, -138)
    CreateCheckField(configFrame, "usePetFrame", "Use DML pet frame", 40, -168)
    CreateCheckField(configFrame, "useTargetTargetFrame", "Use DML target of target frame", 40, -198)
    local useParty = CreateCheckField(configFrame, "usePartyFrames", "Use DML party frames", 40, -228)
    local showPartyPets = CreateCheckField(configFrame, "showPartyPets", "Show party pets", 40, -258)
    local movePartyAsOne = CreateCheckField(configFrame, "movePartyAsOne", "Move party frames as one anchor", 40, -288)
    useParty:SetScript("OnClick", RefreshPartyControlEnableState)
    showPartyPets:SetScript("OnClick", RefreshPartyControlEnableState)
    movePartyAsOne:SetScript("OnClick", RefreshPartyControlEnableState)

    local section2 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section2:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 304, -58)
    section2:SetText("Display")
    CreateCheckField(configFrame, "showPortrait", "Show portrait", 310, -78)
    CreateCheckField(configFrame, "showHealthText", "Show health text", 310, -108)
    CreateCheckField(configFrame, "showResourceText", "Show resource text", 310, -138)
    CreateCheckField(configFrame, "showLevel", "Show level", 310, -168)
    CreateCheckField(configFrame, "showClass", "Show class / creature type", 310, -198)

    local section3 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section3:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 304, -242)
    section3:SetText("Positioning")
    CreateCheckField(configFrame, "showAnchors", "Show anchors", 310, -262)
    CreateCheckField(configFrame, "locked", "Lock frames", 310, -292)

    local petPosLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    petPosLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 310, -332)
    petPosLabel:SetText("Party pet position:")
    configControls.partyPetPositionLabel = petPosLabel
    local petPosDropDown = CreateFrame("Frame", "DMLUIUnitFramesPartyPetPositionDropDown", configFrame, "UIDropDownMenuTemplate")
    petPosDropDown:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 410, -314)
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
    spacingLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 310, -375)
    spacingLabel:SetText("Party spacing:")
    configControls.partySpacingLabel = spacingLabel
    local spacingSlider = CreateFrame("Slider", "DMLUIUnitFramesPartySpacingSlider", configFrame, "OptionsSliderTemplate")
    spacingSlider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 318, -397)
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
    spacingEdit:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 430, -447)
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

    local section4 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section4:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -344)
    section4:SetText("Frame / portrait adjustment")
    local unitLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unitLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -376)
    unitLabel:SetText("Frame:")
    local unitDropDown = CreateFrame("Frame", "DMLUIUnitFramesAdjustmentDropDown", configFrame, "UIDropDownMenuTemplate")
    unitDropDown:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 84, -359)
    UIDropDownMenu_SetWidth(unitDropDown, 185)
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
    scaleLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -425)
    scaleLabel:SetText("Portrait scale:")
    local slider = CreateFrame("Slider", "DMLUIUnitFramesPortraitScaleSlider", configFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 123, -417)
    slider:SetWidth(155)
    slider:SetHeight(16)
    slider:SetMinMaxValues(0, UF.PORTRAIT_SCALE_SLIDER_MAX)
    slider:SetValueStep(1)
    _G[slider:GetName() .. "Low"]:SetText(tostring(UF.PORTRAIT_SCALE_MIN))
    _G[slider:GetName() .. "High"]:SetText(tostring(UF.PORTRAIT_SCALE_MAX))
    _G[slider:GetName() .. "Text"]:SetText("Portrait size")
    slider:SetScript("OnValueChanged", function(_, value)
        if adjustmentRefreshing then return end
        SetSelectedPortraitScale(SliderValueToScale(value))
    end)
    configControls.portraitScaleSlider = slider

    local valueLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 93, -470)
    valueLabel:SetText("Scale value:")
    local scaleEdit = CreateFrame("EditBox", "DMLUIUnitFramesPortraitScaleEdit", configFrame, "InputBoxTemplate")
    scaleEdit:SetWidth(80)
    scaleEdit:SetHeight(22)
    scaleEdit:SetPoint("LEFT", valueLabel, "RIGHT", 8, 0)
    scaleEdit:SetAutoFocus(false)
    scaleEdit:SetNumeric(false)
    scaleEdit:SetMaxLetters(8)
    local function CommitScale(self)
        local value = tonumber(self:GetText())
        if value then SetSelectedPortraitScale(value) else RefreshAdjustmentControls() end
        self:ClearFocus()
    end
    scaleEdit:SetScript("OnEnterPressed", CommitScale)
    scaleEdit:SetScript("OnEditFocusLost", function(self)
        if adjustmentRefreshing then return end
        local value = tonumber(self:GetText())
        if value then SetSelectedPortraitScale(value) else RefreshAdjustmentControls() end
    end)
    scaleEdit:SetScript("OnEscapePressed", function(self) RefreshAdjustmentControls(); self:ClearFocus() end)
    configControls.portraitScaleEdit = scaleEdit

    local adjustmentNote = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    adjustmentNote:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -510)
    adjustmentNote:SetWidth(470)
    adjustmentNote:SetJustifyH("LEFT")
    adjustmentNote:SetText("Party Members share one portrait scale; Party Pets share another. Party Group has position/spacing only. Individual party entries expose their saved freeform position while using the shared party scale.")

    local note = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -558)
    note:SetWidth(480)
    note:SetJustifyH("LEFT")
    note:SetText("Grouped party mode uses the large Party anchor and vertical spacing. Freeform mode ignores spacing and shows a small drag handle beside each party member and pet portrait. Both layouts are saved separately.")

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(75)
    apply:SetHeight(24)
    apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 28, 28)
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
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "DMLUnitFrames" then Initialize() end
        return
    end
    if not initialized then return end

    if event == "PLAYER_ENTERING_WORLD" then
        UpdateAllFrames()
        ApplyBlizzardFrameVisibility()
        ApplyPartyLayout()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateFrame("target")
        UpdateFrame("targettarget")
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
end)
