-- DMLUI - Cast Bar
-- World of Warcraft 3.3.5a / Interface 30300
-- Standalone movable/customizable player cast bar module.

DMLCastBar = DMLCastBar or {}
local CB = DMLCastBar

CB.VERSION = "2.0.97"
CB.WIDTH_MIN = 100
CB.WIDTH_MAX = 800
CB.HEIGHT_MIN = 10
CB.HEIGHT_MAX = 80
CB.ANCHOR_HEIGHT = 18
CB.ANCHOR_GAP = 3

local defaults = {
    version = 1,
    enabled = false,
    showSpellName = true,
    showCastTime = true,
    borderless = false,
    showAnchor = true,
    locked = false,
    width = 300,
    height = 24,
    color = { r = 1.00, g = 0.70, b = 0.10 },
    position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -250 }
}

local DB
local mover
local handle
local bar
local configFrame
local controls = {}
local initialized = false
local stockState
local refreshing = false
local PRINT_PREFIX = "|cff66ff99DMLUI Cast Bar|r: "

local function Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message)) end
end

local function CopyTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = CopyTable(child) end
    return copy
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    if value < minimum then value = minimum end
    if value > maximum then value = maximum end
    return value
end

local function NormalizeColor(color)
    color = type(color) == "table" and color or defaults.color
    return {
        r = Clamp(color.r, 0, 1, defaults.color.r),
        g = Clamp(color.g, 0, 1, defaults.color.g),
        b = Clamp(color.b, 0, 1, defaults.color.b)
    }
end

local function CopyDefaults(reset)
    if reset or type(DMLCastBarDB) ~= "table" then DMLCastBarDB = {} end
    DB = DMLCastBarDB
    for key, value in pairs(defaults) do
        if reset or DB[key] == nil then DB[key] = CopyTable(value) end
    end
    DB.version = defaults.version
    DB.enabled = DB.enabled and true or false
    DB.showSpellName = DB.showSpellName ~= false
    DB.showCastTime = DB.showCastTime ~= false
    DB.borderless = DB.borderless and true or false
    DB.showAnchor = DB.showAnchor ~= false
    DB.locked = DB.locked and true or false
    DB.width = math.floor(Clamp(DB.width, CB.WIDTH_MIN, CB.WIDTH_MAX, defaults.width) + 0.5)
    DB.height = math.floor(Clamp(DB.height, CB.HEIGHT_MIN, CB.HEIGHT_MAX, defaults.height) + 0.5)
    DB.color = NormalizeColor(DB.color)
    if type(DB.position) ~= "table" then DB.position = CopyTable(defaults.position) end
    DB.position.point = DB.position.point or defaults.position.point
    DB.position.relativePoint = DB.position.relativePoint or defaults.position.relativePoint
    DB.position.x = tonumber(DB.position.x) or defaults.position.x
    DB.position.y = tonumber(DB.position.y) or defaults.position.y
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function SyncUnitFrames()
    if DMLUnitFrames and DMLUnitFrames.SetExternalPlayerCastBarActive then
        DMLUnitFrames:SetExternalPlayerCastBarActive(DB and DB.enabled)
    end
end

local function ApplyStockCastBarVisibility()
    local stock = _G.CastingBarFrame
    if not stock then return end
    if DB.enabled then
        if not stockState then
            stockState = {
                alpha = stock.GetAlpha and stock:GetAlpha() or 1,
                mouse = stock.IsMouseEnabled and stock:IsMouseEnabled() or nil
            }
        end
        if stock.SetAlpha then stock:SetAlpha(0) end
        if stock.EnableMouse then stock:EnableMouse(false) end
    elseif stockState then
        if stock.SetAlpha then stock:SetAlpha(stockState.alpha or 1) end
        if stock.EnableMouse and stockState.mouse ~= nil then stock:EnableMouse(stockState.mouse and true or false) end
        stockState = nil
    end
end

local function SavePosition()
    if not mover or not DB then return end
    local point, _, relativePoint, x, y = mover:GetPoint(1)
    DB.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = tonumber(x) or 0,
        y = tonumber(y) or -250
    }
end

local function RestorePosition()
    if not mover or not DB then return end
    mover:ClearAllPoints()
    mover:SetPoint(DB.position.point or "CENTER", UIParent, DB.position.relativePoint or "CENTER", DB.position.x or 0, DB.position.y or -250)
end

local function ApplyAnchorState()
    if not handle or not DB then return end
    if DB.enabled and DB.showAnchor and not DB.locked then handle:Show() else handle:Hide() end
end

local function ApplyAppearance()
    if not bar or not mover or not DB then return end
    mover:SetWidth(DB.width)
    mover:SetHeight(DB.height + CB.ANCHOR_HEIGHT + CB.ANCHOR_GAP)
    bar:SetWidth(DB.width)
    bar:SetHeight(DB.height)
    bar:SetStatusBarColor(DB.color.r, DB.color.g, DB.color.b)
    if DB.borderless then
        bar:SetBackdropBorderColor(0, 0, 0, 0)
    else
        bar:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    end
    if bar.nameText then
        if DB.showSpellName then bar.nameText:Show() else bar.nameText:Hide() end
        bar.nameText:SetWidth(math.max(20, DB.width - 82))
    end
    if bar.timeText then
        if DB.showCastTime then bar.timeText:Show() else bar.timeText:Hide() end
    end
    ApplyAnchorState()
end

local function StopCast()
    if not bar then return end
    bar.startTime = nil
    bar.endTime = nil
    bar.channeling = false
    bar:Hide()
end

local function UpdateCast()
    if not DB or not bar then return end
    ApplyStockCastBarVisibility()
    SyncUnitFrames()
    if not DB.enabled then StopCast(); return end

    local name, rank, displayName, icon, startMS, endMS = UnitCastingInfo and UnitCastingInfo("player")
    local channeling = false
    if not name and UnitChannelInfo then
        name, rank, displayName, icon, startMS, endMS = UnitChannelInfo("player")
        channeling = name and true or false
    end
    if not name or not startMS or not endMS then StopCast(); return end

    bar.startTime = tonumber(startMS) / 1000
    bar.endTime = tonumber(endMS) / 1000
    bar.channeling = channeling
    bar:SetMinMaxValues(0, math.max(0.001, bar.endTime - bar.startTime))
    bar:SetStatusBarColor(DB.color.r, DB.color.g, DB.color.b)
    if bar.nameText then bar.nameText:SetText((displayName and displayName ~= "" and displayName) or name) end
    bar:Show()
end

local function CreateFrames()
    if mover then return end
    mover = CreateFrame("Frame", "DMLUICastBarMover", UIParent)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(false)

    bar = CreateFrame("StatusBar", "DMLUICastBarFrame", mover)
    bar:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, -(CB.ANCHOR_HEIGHT + CB.ANCHOR_GAP))
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(50)
    bar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    bar:SetBackdropColor(0.02, 0.02, 0.02, 0.92)

    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", bar, "LEFT", 5, 0)
    nameText:SetJustifyH("LEFT")
    bar.nameText = nameText

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    timeText:SetJustifyH("RIGHT")
    bar.timeText = timeText

    bar:SetScript("OnUpdate", function(self)
        if not self.startTime or not self.endTime then return end
        local now = GetTime and GetTime() or 0
        local duration = math.max(0.001, self.endTime - self.startTime)
        local remaining = math.max(0, self.endTime - now)
        self:SetMinMaxValues(0, duration)
        if self.channeling then self:SetValue(remaining) else self:SetValue(math.max(0, now - self.startTime)) end
        if self.timeText and DB.showCastTime then self.timeText:SetText(string.format("%.1f", remaining)) end
        if remaining <= 0 then StopCast() end
    end)

    handle = CreateFrame("Frame", "DMLUICastBarHandle", mover)
    handle:SetHeight(CB.ANCHOR_HEIGHT)
    handle:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, CB.ANCHOR_GAP)
    handle:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, CB.ANCHOR_GAP)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    handle:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)
    local handleText = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handleText:SetPoint("CENTER", handle, "CENTER", 0, 0)
    handleText:SetText("DML Cast Bar - drag to move")
    handle:SetScript("OnDragStart", function()
        if DB.locked or InCombat() then return end
        mover:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        mover:StopMovingOrSizing()
        SavePosition()
    end)

    RestorePosition()
    ApplyAppearance()
    bar:Hide()
end

local function CreateCheck(parent, key, text, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24); check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 3, 0)
    label:SetText(text)
    controls[key] = check
    return check
end

local function RefreshColorSwatch()
    if controls.color and DB then controls.color:SetBackdropColor(DB.color.r, DB.color.g, DB.color.b, 1) end
end

local function OpenColorPicker()
    if not ColorPickerFrame then return end
    local previous = { r = DB.color.r, g = DB.color.g, b = DB.color.b }
    local function ApplyColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        DB.color = NormalizeColor({ r = r, g = g, b = b })
        RefreshColorSwatch()
        ApplyAppearance()
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.func = ApplyColor
    ColorPickerFrame.cancelFunc = function()
        DB.color = previous
        RefreshColorSwatch()
        ApplyAppearance()
    end
    ColorPickerFrame:SetColorRGB(DB.color.r, DB.color.g, DB.color.b)
    if ShowUIPanel then ShowUIPanel(ColorPickerFrame) else ColorPickerFrame:Show() end
end

local function RefreshConfig()
    if not configFrame or not DB then return end
    refreshing = true
    controls.enabled:SetChecked(DB.enabled and 1 or nil)
    controls.showSpellName:SetChecked(DB.showSpellName and 1 or nil)
    controls.showCastTime:SetChecked(DB.showCastTime and 1 or nil)
    controls.borderless:SetChecked(DB.borderless and 1 or nil)
    controls.showAnchor:SetChecked(DB.showAnchor and 1 or nil)
    controls.locked:SetChecked(DB.locked and 1 or nil)
    controls.widthSlider:SetValue(DB.width)
    controls.widthEdit:SetText(tostring(DB.width))
    controls.heightSlider:SetValue(DB.height)
    controls.heightEdit:SetText(tostring(DB.height))
    RefreshColorSwatch()
    refreshing = false
end

local function ApplyConfig()
    DB.enabled = controls.enabled:GetChecked() and true or false
    DB.showSpellName = controls.showSpellName:GetChecked() and true or false
    DB.showCastTime = controls.showCastTime:GetChecked() and true or false
    DB.borderless = controls.borderless:GetChecked() and true or false
    DB.showAnchor = controls.showAnchor:GetChecked() and true or false
    DB.locked = controls.locked:GetChecked() and true or false
    ApplyAppearance()
    ApplyStockCastBarVisibility()
    SyncUnitFrames()
    UpdateCast()
    RefreshConfig()
end

local function CreateConfig()
    if configFrame then return end
    configFrame = CreateFrame("Frame", "DMLUICastBarConfigFrame", UIParent)
    configFrame:SetWidth(520); configFrame:SetHeight(540)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    configFrame:SetFrameStrata("DIALOG"); configFrame:SetFrameLevel(100)
    configFrame:SetMovable(true); configFrame:EnableMouse(true); configFrame:RegisterForDrag("LeftButton")
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
    title:SetPoint("TOP", configFrame, "TOP", 0, -18); title:SetText("DMLUI - Cast Bar")
    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    CreateCheck(configFrame, "enabled", "Enable DML cast bar", 38, -68)
    CreateCheck(configFrame, "showSpellName", "Show spell name", 38, -102)
    CreateCheck(configFrame, "showCastTime", "Show cast time", 38, -136)
    CreateCheck(configFrame, "borderless", "Borderless", 270, -102)
    CreateCheck(configFrame, "showAnchor", "Show anchor", 270, -68)
    CreateCheck(configFrame, "locked", "Lock cast bar", 270, -136)

    local widthLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    widthLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 38, -190); widthLabel:SetText("Width")
    local widthSlider = CreateFrame("Slider", "DMLUICastBarWidthSlider", configFrame, "OptionsSliderTemplate")
    widthSlider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 55, -220); widthSlider:SetWidth(320); widthSlider:SetHeight(16)
    widthSlider:SetMinMaxValues(CB.WIDTH_MIN, CB.WIDTH_MAX); widthSlider:SetValueStep(1)
    _G[widthSlider:GetName() .. "Low"]:SetText(tostring(CB.WIDTH_MIN)); _G[widthSlider:GetName() .. "High"]:SetText(tostring(CB.WIDTH_MAX)); _G[widthSlider:GetName() .. "Text"]:SetText("Cast bar width")
    controls.widthSlider = widthSlider
    local widthEdit = CreateFrame("EditBox", "DMLUICastBarWidthEdit", configFrame, "InputBoxTemplate")
    widthEdit:SetWidth(58); widthEdit:SetHeight(22); widthEdit:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 410, -213)
    widthEdit:SetAutoFocus(false); widthEdit:SetNumeric(true); widthEdit:SetMaxLetters(3); controls.widthEdit = widthEdit

    local heightLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heightLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 38, -280); heightLabel:SetText("Height")
    local heightSlider = CreateFrame("Slider", "DMLUICastBarHeightSlider", configFrame, "OptionsSliderTemplate")
    heightSlider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 55, -310); heightSlider:SetWidth(320); heightSlider:SetHeight(16)
    heightSlider:SetMinMaxValues(CB.HEIGHT_MIN, CB.HEIGHT_MAX); heightSlider:SetValueStep(1)
    _G[heightSlider:GetName() .. "Low"]:SetText(tostring(CB.HEIGHT_MIN)); _G[heightSlider:GetName() .. "High"]:SetText(tostring(CB.HEIGHT_MAX)); _G[heightSlider:GetName() .. "Text"]:SetText("Cast bar height")
    controls.heightSlider = heightSlider
    local heightEdit = CreateFrame("EditBox", "DMLUICastBarHeightEdit", configFrame, "InputBoxTemplate")
    heightEdit:SetWidth(58); heightEdit:SetHeight(22); heightEdit:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 410, -303)
    heightEdit:SetAutoFocus(false); heightEdit:SetNumeric(true); heightEdit:SetMaxLetters(2); controls.heightEdit = heightEdit

    local function ApplyWidth(value)
        DB.width = math.floor(Clamp(value, CB.WIDTH_MIN, CB.WIDTH_MAX, defaults.width) + 0.5)
        ApplyAppearance(); RefreshConfig()
    end
    local function ApplyHeight(value)
        DB.height = math.floor(Clamp(value, CB.HEIGHT_MIN, CB.HEIGHT_MAX, defaults.height) + 0.5)
        ApplyAppearance(); RefreshConfig()
    end
    widthSlider:SetScript("OnValueChanged", function(_, value) if not refreshing then ApplyWidth(value) end end)
    heightSlider:SetScript("OnValueChanged", function(_, value) if not refreshing then ApplyHeight(value) end end)
    local function CommitWidth(self) if not refreshing then ApplyWidth(tonumber(self:GetText())) end self:ClearFocus() end
    local function CommitHeight(self) if not refreshing then ApplyHeight(tonumber(self:GetText())) end self:ClearFocus() end
    widthEdit:SetScript("OnEnterPressed", CommitWidth); widthEdit:SetScript("OnEditFocusLost", CommitWidth)
    heightEdit:SetScript("OnEnterPressed", CommitHeight); heightEdit:SetScript("OnEditFocusLost", CommitHeight)

    local colorLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 38, -378); colorLabel:SetText("Cast bar color")
    local swatch = CreateFrame("Button", nil, configFrame)
    swatch:SetWidth(42); swatch:SetHeight(24); swatch:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 150, -370)
    swatch:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1); swatch:SetScript("OnClick", OpenColorPicker); controls.color = swatch

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(80); apply:SetHeight(24); apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 55, 35); apply:SetText("Apply"); apply:SetScript("OnClick", ApplyConfig)
    local resetPos = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetPos:SetWidth(110); resetPos:SetHeight(24); resetPos:SetPoint("LEFT", apply, "RIGHT", 8, 0); resetPos:SetText("Reset Position")
    resetPos:SetScript("OnClick", function() DB.position = CopyTable(defaults.position); RestorePosition(); Print("Cast bar position reset.") end)
    local resetAll = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetAll:SetWidth(110); resetAll:SetHeight(24); resetAll:SetPoint("LEFT", resetPos, "RIGHT", 8, 0); resetAll:SetText("Reset Settings")
    resetAll:SetScript("OnClick", function() CopyDefaults(true); RestorePosition(); ApplyAppearance(); ApplyStockCastBarVisibility(); SyncUnitFrames(); UpdateCast(); RefreshConfig(); Print("Cast bar settings reset.") end)
    local closeBottom = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    closeBottom:SetWidth(70); closeBottom:SetHeight(24); closeBottom:SetPoint("LEFT", resetAll, "RIGHT", 8, 0); closeBottom:SetText("Close"); closeBottom:SetScript("OnClick", function() configFrame:Hide() end)

    table.insert(UISpecialFrames, "DMLUICastBarConfigFrame")
    configFrame:Hide()
end

function CB:OpenConfig()
    if not configFrame then CreateConfig() end
    RefreshConfig()
    configFrame:Show()
    return true
end

local function RegisterWithCore()
    if DMLUI and DMLUI.RegisterModule then
        DMLUI:RegisterModule("CastBars", {
            name = "Cast Bars",
            version = CB.VERSION,
            openConfig = function() return CB:OpenConfig() end
        })
    end
end

local function Initialize()
    if initialized then return end
    CopyDefaults(false)
    CreateFrames()
    CreateConfig()
    ApplyAppearance()
    ApplyStockCastBarVisibility()
    SyncUnitFrames()
    UpdateCast()
    RegisterWithCore()
    SLASH_DMLCASTBAR1 = "/dmlcast"
    SlashCmdList["DMLCASTBAR"] = function() CB:OpenConfig() end
    initialized = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        if arg1 == "DMLCastBar" then Initialize()
        elseif initialized and arg1 == "DMLUnitFrames" then SyncUnitFrames() end
        return
    end
    if not initialized then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        ApplyStockCastBarVisibility(); SyncUnitFrames(); UpdateCast()
    elseif string.find(event, "UNIT_SPELLCAST", 1, true) == 1 and arg1 == "player" then
        UpdateCast()
    end
end)
