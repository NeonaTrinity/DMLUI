-- DMLUI - Unit Frames
-- World of Warcraft 3.3.5a / Interface 30300
--
-- Optional DMLUI module. Installing this file changes nothing until individual
-- DML unit frames are enabled from the Unit Frames configuration page.

DMLUnitFrames = DMLUnitFrames or {}
local UF = DMLUnitFrames

UF.VERSION = "2.0.90"
UF.FRAME_WIDTH = 250
UF.FRAME_HEIGHT = 82
UF.ANCHOR_HEIGHT = 18
UF.ANCHOR_GAP = 3

local DB
local configFrame
local configControls = {}
local initialized = false
local PRINT_PREFIX = "|cff66ff99DMLUI Unit Frames|r: "

UF.definitions = {
    player = {
        unit = "player",
        label = "Player",
        setting = "usePlayerFrame",
        blizzard = "PlayerFrame",
        x = -280,
        y = -170
    },
    target = {
        unit = "target",
        label = "Target",
        setting = "useTargetFrame",
        blizzard = "TargetFrame",
        x = 280,
        y = -170
    },
    focus = {
        unit = "focus",
        label = "Focus",
        setting = "useFocusFrame",
        blizzard = "FocusFrame",
        x = 280,
        y = -275
    },
    pet = {
        unit = "pet",
        label = "Pet",
        setting = "usePetFrame",
        blizzard = "PetFrame",
        x = -280,
        y = -275
    },
    targettarget = {
        unit = "targettarget",
        label = "Target of Target",
        setting = "useTargetTargetFrame",
        blizzard = "TargetFrameToT",
        x = 0,
        y = -275
    }
}

UF.order = { "player", "target", "focus", "pet", "targettarget" }
UF.frames = {}
UF.movers = {}
UF.handles = {}
UF.blizzardStates = {}
UF.stockChildStates = {}

local defaults = {
    version = 1,
    usePlayerFrame = false,
    useTargetFrame = false,
    useFocusFrame = false,
    usePetFrame = false,
    useTargetTargetFrame = false,
    showPortrait = true,
    showHealthText = true,
    showResourceText = true,
    showLevel = true,
    showClass = true,
    showAnchors = true,
    locked = false,
    positions = {}
}

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
    end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
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
    DB.showPortrait = DB.showPortrait ~= false
    DB.showHealthText = DB.showHealthText ~= false
    DB.showResourceText = DB.showResourceText ~= false
    DB.showLevel = DB.showLevel ~= false
    DB.showClass = DB.showClass ~= false
    DB.showAnchors = DB.showAnchors ~= false
    DB.locked = DB.locked and true or false
    if type(DB.positions) ~= "table" then
        DB.positions = {}
    end
end

local function GetDefinition(key)
    return UF.definitions[key]
end

local function SavePosition(key)
    local mover = UF.movers[key]
    if not mover or not DB then
        return
    end
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
    if not mover or not definition or not DB then
        return
    end

    local saved = DB.positions[key]
    local point = saved and saved.point or "CENTER"
    local relativePoint = saved and saved.relativePoint or "CENTER"
    local x = saved and tonumber(saved.x) or definition.x
    local y = saved and tonumber(saved.y) or definition.y

    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relativePoint, x, y)
end

local function ResetPositions()
    if InCombat() then
        Print("Unit frame positions cannot be reset during combat.")
        return
    end
    DB.positions = {}
    local i
    for i = 1, #UF.order do
        RestorePosition(UF.order[i])
    end
    Print("DML unit frame positions reset.")
end

local function SetBlizzardFrameHidden(name, hidden)
    local frame = _G[name]
    if not frame then
        return
    end

    local state = UF.blizzardStates[frame]
    if hidden then
        if not state then
            state = {
                alpha = frame.GetAlpha and frame:GetAlpha() or 1,
                mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or nil
            }
            UF.blizzardStates[frame] = state
        end
        if frame.SetAlpha then
            frame:SetAlpha(0)
        end
        if frame.EnableMouse then
            frame:EnableMouse(false)
        end
    elseif state then
        if frame.SetAlpha then
            frame:SetAlpha(state.alpha or 1)
        end
        if frame.EnableMouse and state.mouse ~= nil then
            frame:EnableMouse(state.mouse and true or false)
        end
        UF.blizzardStates[frame] = nil
    end
end

local function SetStockChildDetached(name, detached)
    local frame = _G[name]
    if not frame then
        return
    end

    local state = UF.stockChildStates[frame]
    if detached then
        if not state then
            state = { parent = frame:GetParent() }
            UF.stockChildStates[frame] = state
        end
        if frame:GetParent() ~= UIParent then
            frame:SetParent(UIParent)
        end
    elseif state then
        frame:SetParent(state.parent or UIParent)
        UF.stockChildStates[frame] = nil
    end
end

local function ApplyBlizzardFrameVisibility()
    if InCombat() then
        return
    end

    -- PetFrame is parented to PlayerFrame in stock Wrath, and the target/focus
    -- target-of-target frames are parented to their respective target frames.
    -- Detach stock children that the player did NOT replace so hiding a parent
    -- DML replacement does not accidentally hide an otherwise-stock child.
    SetStockChildDetached("PetFrame", DB.usePlayerFrame and not DB.usePetFrame)
    SetStockChildDetached("TargetFrameToT", DB.useTargetFrame and not DB.useTargetTargetFrame)
    SetStockChildDetached("FocusFrameToT", DB.useFocusFrame and true or false)

    local i
    for i = 1, #UF.order do
        local key = UF.order[i]
        local definition = GetDefinition(key)
        SetBlizzardFrameHidden(definition.blizzard, DB[definition.setting] and true or false)
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
    if UnitPowerType then
        powerType, powerToken = UnitPowerType(unit)
    end
    local color
    if ManaBarColor then
        color = ManaBarColor[powerType]
        if not color and powerToken then
            color = ManaBarColor[powerToken]
        end
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
    if not frame or not definition or not DB then
        return
    end

    local unit = definition.unit
    if not DB[definition.setting] then
        frame:Hide()
        return
    end

    if not UnitExists(unit) then
        if not RegisterUnitWatch then
            frame:Hide()
        end
        return
    end

    if not RegisterUnitWatch then
        frame:Show()
    end

    local name = UnitName(unit) or definition.label
    frame.nameText:SetText(name)

    local level = UnitLevel(unit)
    if DB.showLevel then
        if tonumber(level) and tonumber(level) < 0 then
            frame.levelText:SetText("??")
        else
            frame.levelText:SetText(tostring(level or ""))
        end
        frame.levelText:Show()
    else
        frame.levelText:Hide()
    end

    if DB.showClass then
        local classDisplay = UnitClass and UnitClass(unit) or nil
        if not classDisplay or classDisplay == "" then
            classDisplay = UnitCreatureType and UnitCreatureType(unit) or ""
        end
        frame.classText:SetText(classDisplay or "")
        frame.classText:Show()
    else
        frame.classText:Hide()
    end

    if DB.showPortrait then
        if SetPortraitTexture then
            SetPortraitTexture(frame.portrait, unit)
        end
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
    local i
    for i = 1, #UF.order do
        UpdateFrame(UF.order[i])
    end
end

local function ApplyAnchorState()
    local i
    for i = 1, #UF.order do
        local key = UF.order[i]
        local definition = GetDefinition(key)
        local mover = UF.movers[key]
        local handle = UF.handles[key]
        if mover and handle then
            if DB[definition.setting] then
                mover:Show()
                if DB.showAnchors and not DB.locked then
                    handle:Show()
                else
                    handle:Hide()
                end
            else
                handle:Hide()
                mover:Hide()
            end
        end
    end
end

local function ApplyFrameActivation()
    if InCombat() then
        Print("Unit frame enable/disable changes cannot be applied during combat.")
        return false
    end

    -- Show each enabled mover before registering the secure unit watch. This
    -- gives RegisterUnitWatch a visible parent when it evaluates the current
    -- unit state, while disabled movers remain completely dormant.
    ApplyAnchorState()

    local i
    for i = 1, #UF.order do
        local key = UF.order[i]
        local definition = GetDefinition(key)
        local frame = UF.frames[key]
        if frame then
            if DB[definition.setting] then
                if RegisterUnitWatch then
                    RegisterUnitWatch(frame)
                elseif UnitExists(definition.unit) then
                    frame:Show()
                end
            else
                if UnregisterUnitWatch then
                    UnregisterUnitWatch(frame)
                end
                frame:Hide()
            end
        end
    end

    ApplyBlizzardFrameVisibility()
    UpdateAllFrames()
    return true
end

local function CreateUnitFrame(key)
    if UF.frames[key] then
        return UF.frames[key]
    end

    local definition = GetDefinition(key)
    if not definition then
        return nil
    end

    local mover = CreateFrame("Frame", "DMLUIUnitFrameMover_" .. key, UIParent)
    mover:SetWidth(UF.FRAME_WIDTH)
    mover:SetHeight(UF.FRAME_HEIGHT + UF.ANCHOR_HEIGHT + UF.ANCHOR_GAP)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(false)

    local frame = CreateFrame("Button", "DMLUIUnitFrame_" .. key, mover, "SecureUnitButtonTemplate")
    frame:SetWidth(UF.FRAME_WIDTH)
    frame:SetHeight(UF.FRAME_HEIGHT)
    frame:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("unit", definition.unit)
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.035, 0.035, 0.035, 0.92)
    frame:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)

    local portraitBorder = frame:CreateTexture(nil, "BACKGROUND")
    portraitBorder:SetWidth(72)
    portraitBorder:SetHeight(72)
    portraitBorder:SetPoint("LEFT", frame, "LEFT", 5, 0)
    portraitBorder:SetTexture(0.12, 0.12, 0.12, 1)

    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetWidth(66)
    portrait:SetHeight(66)
    portrait:SetPoint("CENTER", portraitBorder, "CENTER", 0, 0)
    portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", 82, -8)
    nameText:SetWidth(126)
    nameText:SetJustifyH("LEFT")

    local levelText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    levelText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -9)
    levelText:SetJustifyH("RIGHT")

    local classText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classText:SetPoint("TOPLEFT", frame, "TOPLEFT", 82, -25)
    classText:SetWidth(155)
    classText:SetJustifyH("LEFT")

    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetWidth(160)
    healthBar:SetHeight(16)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 82, -42)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetMinMaxValues(0, 1)
    healthBar:SetValue(1)

    local healthBackground = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBackground:SetAllPoints(healthBar)
    healthBackground:SetTexture(0.08, 0.08, 0.08, 0.9)

    local healthText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)

    local powerBar = CreateFrame("StatusBar", nil, frame)
    powerBar:SetWidth(160)
    powerBar:SetHeight(12)
    powerBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 82, -62)
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
            if GameTooltip.SetUnit then
                GameTooltip:SetUnit(definition.unit)
            else
                GameTooltip:SetText(UnitName(definition.unit) or definition.label)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local handle = CreateFrame("Frame", "DMLUIUnitFrameHandle_" .. key, mover)
    handle:SetHeight(UF.ANCHOR_HEIGHT)
    handle:SetWidth(UF.FRAME_WIDTH)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, UF.ANCHOR_GAP)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    handle:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)

    local handleText = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handleText:SetPoint("CENTER", handle, "CENTER", 0, 0)
    handleText:SetText("DML " .. definition.label .. " Frame - drag to move")

    handle:SetScript("OnDragStart", function()
        if DB.locked or InCombat() then
            return
        end
        mover:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        mover:StopMovingOrSizing()
        SavePosition(key)
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

    UF.movers[key] = mover
    UF.frames[key] = frame
    UF.handles[key] = handle
    RestorePosition(key)
    mover:Hide()
    frame:Hide()
    handle:Hide()
    return frame
end

local function CreateAllFrames()
    local i
    for i = 1, #UF.order do
        CreateUnitFrame(UF.order[i])
    end
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

local function RefreshConfig()
    if not configFrame then
        return
    end
    configControls.usePlayerFrame:SetChecked(DB.usePlayerFrame and 1 or nil)
    configControls.useTargetFrame:SetChecked(DB.useTargetFrame and 1 or nil)
    configControls.useFocusFrame:SetChecked(DB.useFocusFrame and 1 or nil)
    configControls.usePetFrame:SetChecked(DB.usePetFrame and 1 or nil)
    configControls.useTargetTargetFrame:SetChecked(DB.useTargetTargetFrame and 1 or nil)
    configControls.showPortrait:SetChecked(DB.showPortrait and 1 or nil)
    configControls.showHealthText:SetChecked(DB.showHealthText and 1 or nil)
    configControls.showResourceText:SetChecked(DB.showResourceText and 1 or nil)
    configControls.showLevel:SetChecked(DB.showLevel and 1 or nil)
    configControls.showClass:SetChecked(DB.showClass and 1 or nil)
    configControls.showAnchors:SetChecked(DB.showAnchors and 1 or nil)
    configControls.locked:SetChecked(DB.locked and 1 or nil)
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

local function ResetDefaults()
    if InCombat() then
        Print("Unit frame configuration cannot be reset during combat.")
        return
    end
    CopyDefaults(true)
    ResetPositions()
    ApplyFrameActivation()
    RefreshConfig()
    Print("Unit frame settings reset to defaults.")
end

local function CreateConfigFrame()
    if configFrame then
        return
    end

    configFrame = CreateFrame("Frame", "DMLUIUnitFramesConfigFrame", UIParent)
    configFrame:SetWidth(560)
    configFrame:SetHeight(535)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetFrameLevel(100)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetClampedToScreen(true)
    configFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
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

    local section2 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section2:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 304, -58)
    section2:SetText("Display")

    CreateCheckField(configFrame, "showPortrait", "Show portrait", 310, -78)
    CreateCheckField(configFrame, "showHealthText", "Show health text", 310, -108)
    CreateCheckField(configFrame, "showResourceText", "Show resource text", 310, -138)
    CreateCheckField(configFrame, "showLevel", "Show level", 310, -168)
    CreateCheckField(configFrame, "showClass", "Show class / creature type", 310, -198)

    local section3 = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section3:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -252)
    section3:SetText("Positioning")

    CreateCheckField(configFrame, "showAnchors", "Show anchors", 40, -272)
    CreateCheckField(configFrame, "locked", "Lock frames", 40, -302)

    local note = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -352)
    note:SetWidth(480)
    note:SetJustifyH("LEFT")
    note:SetText(
        "Installing this module does not replace Blizzard frames automatically. Enable only the DML frames you want. " ..
        "DML frames support normal left-click targeting and right-click unit menus. Frame enable/disable changes are blocked during combat."
    )

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(100)
    apply:SetHeight(24)
    apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 34, 30)
    apply:SetText("Apply")
    apply:SetScript("OnClick", ApplyConfig)

    local resetPositions = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetPositions:SetWidth(120)
    resetPositions:SetHeight(24)
    resetPositions:SetPoint("LEFT", apply, "RIGHT", 10, 0)
    resetPositions:SetText("Reset Positions")
    resetPositions:SetScript("OnClick", ResetPositions)

    local resetDefaults = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetDefaults:SetWidth(110)
    resetDefaults:SetHeight(24)
    resetDefaults:SetPoint("LEFT", resetPositions, "RIGHT", 10, 0)
    resetDefaults:SetText("Reset Defaults")
    resetDefaults:SetScript("OnClick", ResetDefaults)

    local closeBottom = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    closeBottom:SetWidth(80)
    closeBottom:SetHeight(24)
    closeBottom:SetPoint("LEFT", resetDefaults, "RIGHT", 10, 0)
    closeBottom:SetText("Close")
    closeBottom:SetScript("OnClick", function() configFrame:Hide() end)

    table.insert(UISpecialFrames, "DMLUIUnitFramesConfigFrame")
    configFrame:Hide()
end

function UF:OpenConfig()
    if not configFrame then
        CreateConfigFrame()
    end
    RefreshConfig()
    configFrame:Show()
    return true
end

local function RegisterWithCore()
    if DMLUI and DMLUI.RegisterModule then
        DMLUI:RegisterModule("UnitFrames", {
            name = "Unit Frames",
            version = UF.VERSION,
            openConfig = function()
                return UF:OpenConfig()
            end
        })
    end
end

local function RegisterSlashCommand()
    SLASH_DMLUNITFRAMES1 = "/dmluf"
    SlashCmdList["DMLUNITFRAMES"] = function()
        UF:OpenConfig()
    end
end

local function Initialize()
    if initialized then
        return
    end
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
        if arg1 == "DMLUnitFrames" then
            Initialize()
        end
        return
    end

    if not initialized then
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        UpdateAllFrames()
        ApplyBlizzardFrameVisibility()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateFrame("target")
        UpdateFrame("targettarget")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UpdateFrame("focus")
    elseif event == "UNIT_PET" then
        UpdateFrame("pet")
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
    else
        UpdateAllFrames()
    end
end)
