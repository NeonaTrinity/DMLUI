-- DMLUI Launcher
-- Main module menu plus the first core Profiles and Advanced pages.

local UI = DMLUI

local launcher
local launcherButtons = {}
local profilesFrame
local advancedFrame
local advancedStatusText
local advancedMinimapCheck

local function CreateBackdropFrame(name, titleText, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -18)
    title:SetText(titleText)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    frame:Hide()
    table.insert(UISpecialFrames, name)
    return frame
end

local function GetKnownModule(key)
    local i
    for i = 1, #UI.knownModules do
        if UI.knownModules[i].key == key then
            return UI.knownModules[i]
        end
    end
    return nil
end

function UI:RefreshLauncherButtons()
    local key, button
    for key, button in pairs(launcherButtons) do
        local available = UI:IsModuleAvailable(key)
        if available then
            button:Enable()
            if button.text then
                button.text:SetTextColor(1, 0.82, 0)
            end
        else
            button:Disable()
            if button.text then
                button.text:SetTextColor(0.45, 0.45, 0.45)
            end
        end
    end
end

local function CreateLauncher()
    if launcher then
        return
    end

    launcher = CreateBackdropFrame("DMLUILauncherFrame", "DMLUI", 330, 290)
    UI.launcherFrame = launcher

    local subtitle = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", launcher, "TOP", 0, -45)
    subtitle:SetText("Choose a DMLUI module")

    local entries = {
        { key = "ActionBars", label = "Action Bars" },
        { key = "UnitFrames", label = "Unit Frames" },
        { key = "Profiles", label = "Profiles" },
        { key = "Advanced", label = "Advanced" },
        { key = "BigBag", label = "DML BigBag" }
    }

    local i
    for i = 1, #entries do
        local entry = entries[i]
        local button = CreateFrame("Button", nil, launcher, "UIPanelButtonTemplate")
        button:SetWidth(190)
        button:SetHeight(30)
        button:SetPoint("TOP", launcher, "TOP", 0, -70 - ((i - 1) * 38))
        button:SetText(entry.label)
        button.dmlModuleKey = entry.key
        button.text = button:GetFontString()
        button:SetScript("OnClick", function(self)
            UI:OpenModule(self.dmlModuleKey)
        end)
        launcherButtons[entry.key] = button
    end

    local version = launcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOM", launcher, "BOTTOM", 0, 16)
    version:SetText("DMLUI " .. tostring(UI.VERSION))

    UI:RefreshLauncherButtons()
end

function UI:ShowLauncher()
    CreateLauncher()
    if profilesFrame then profilesFrame:Hide() end
    if advancedFrame then advancedFrame:Hide() end
    UI:RefreshLauncherButtons()
    launcher:Show()
end

function UI:ToggleLauncher()
    CreateLauncher()
    if launcher:IsShown() then
        launcher:Hide()
    else
        UI:ShowLauncher()
    end
end

local function CreateProfilesPage()
    if profilesFrame then
        return
    end

    profilesFrame = CreateBackdropFrame("DMLUIProfilesFrame", "DMLUI - Profiles", 430, 235)

    local body = profilesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 32, -58)
    body:SetPoint("TOPRIGHT", profilesFrame, "TOPRIGHT", -32, -58)
    body:SetJustifyH("LEFT")
    body:SetText(
        "DMLUI-wide profiles will live here as modules are migrated to the shared profile system.\n\n" ..
        "For now, Action Bars keeps its existing Saved Profile / Copy Profile controls so no current layouts are disturbed."
    )

    local actionBars = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    actionBars:SetWidth(170)
    actionBars:SetHeight(26)
    actionBars:SetPoint("BOTTOMLEFT", profilesFrame, "BOTTOMLEFT", 32, 28)
    actionBars:SetText("Open Action Bar Profiles")
    actionBars:SetScript("OnClick", function()
        if UI:IsModuleAvailable("ActionBars") then
            profilesFrame:Hide()
            UI:OpenModule("ActionBars")
        end
    end)

    local back = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    back:SetWidth(90)
    back:SetHeight(26)
    back:SetPoint("BOTTOMRIGHT", profilesFrame, "BOTTOMRIGHT", -32, 28)
    back:SetText("Back")
    back:SetScript("OnClick", function()
        profilesFrame:Hide()
        UI:ShowLauncher()
    end)
end

function UI:OpenProfilesPage()
    CreateProfilesPage()
    if launcher then launcher:Hide() end
    if advancedFrame then advancedFrame:Hide() end
    profilesFrame:Show()
end

local function BuildAdvancedStatusText()
    local lines = {
        "Installed DMLUI modules:"
    }

    local i
    for i = 1, #UI.knownModules do
        local known = UI.knownModules[i]
        if not known.core then
            local module = UI:GetModule(known.key)
            if module then
                local suffix = module.version and ("  v" .. tostring(module.version)) or ""
                table.insert(lines, "|cff66ff99Loaded|r  " .. known.name .. suffix)
            else
                table.insert(lines, "|cff888888Not installed / disabled|r  " .. known.name)
            end
        end
    end

    return table.concat(lines, "\n")
end

function UI:RefreshAdvancedPage()
    if advancedStatusText then
        advancedStatusText:SetText(BuildAdvancedStatusText())
    end
    if advancedMinimapCheck then
        advancedMinimapCheck:SetChecked(UI:IsMinimapButtonVisible() and 1 or nil)
    end
end

local function CreateAdvancedPage()
    if advancedFrame then
        return
    end

    advancedFrame = CreateBackdropFrame("DMLUIAdvancedFrame", "DMLUI - Advanced", 470, 315)

    advancedStatusText = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    advancedStatusText:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", 32, -58)
    advancedStatusText:SetPoint("TOPRIGHT", advancedFrame, "TOPRIGHT", -32, -58)
    advancedStatusText:SetJustifyH("LEFT")

    advancedMinimapCheck = CreateFrame("CheckButton", nil, advancedFrame, "UICheckButtonTemplate")
    advancedMinimapCheck:SetWidth(24)
    advancedMinimapCheck:SetHeight(24)
    advancedMinimapCheck:SetPoint("BOTTOMLEFT", advancedFrame, "BOTTOMLEFT", 28, 62)
    local label = advancedMinimapCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", advancedMinimapCheck, "RIGHT", 4, 0)
    label:SetText("Show DMLUI minimap button")
    advancedMinimapCheck:SetScript("OnClick", function(self)
        UI:SetMinimapButtonVisible(self:GetChecked() and true or false)
    end)

    local back = CreateFrame("Button", nil, advancedFrame, "UIPanelButtonTemplate")
    back:SetWidth(90)
    back:SetHeight(26)
    back:SetPoint("BOTTOMRIGHT", advancedFrame, "BOTTOMRIGHT", -32, 28)
    back:SetText("Back")
    back:SetScript("OnClick", function()
        advancedFrame:Hide()
        UI:ShowLauncher()
    end)

    UI:RefreshAdvancedPage()
end

function UI:OpenAdvancedPage()
    CreateAdvancedPage()
    if launcher then launcher:Hide() end
    if profilesFrame then profilesFrame:Hide() end
    UI:RefreshAdvancedPage()
    advancedFrame:Show()
end
