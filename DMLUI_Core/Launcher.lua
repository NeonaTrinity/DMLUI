-- DMLUI Launcher
-- Main module menu plus the first core Profiles and Advanced pages.

local UI = DMLUI

local launcher
local launcherButtons = {}
local profilesFrame
local advancedFrame
local advancedStatusText
local advancedMinimapCheck
local profileDropDown
local profileNameEdit
local profileStatusText
local profileSelectedName
local profileLoadButton
local profileDeleteButton

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

    launcher = CreateBackdropFrame("DMLUILauncherFrame", "DMLUI", 330, 410)
    UI.launcherFrame = launcher

    local subtitle = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", launcher, "TOP", 0, -45)
    subtitle:SetText("Choose a DMLUI module")

    local entries = {
        { key = "ActionBars", label = "Action Bars" },
        { key = "UnitFrames", label = "Unit Frames" },
        { key = "Buffs", label = "Buffs" },
        { key = "CastBars", label = "Cast Bars" },
        { key = "QuestTracker", label = "Quest Tracker" },
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

local function GetProfileSelection()
    local typed = profileNameEdit and profileNameEdit:GetText() or ""
    typed = tostring(typed or "")
    typed = string.gsub(typed, "^%s+", "")
    typed = string.gsub(typed, "%s+$", "")
    if typed ~= "" then return typed end
    return profileSelectedName or ""
end

local function BuildProfileStatus(name)
    local profiles = UI.GetSharedProfiles and UI:GetSharedProfiles() or {}
    local profile = profiles[name or ""]
    local lines = {
        "Shared profiles include Unit Frames, Cast Bars, Buffs, and Quest Tracker.",
        "Action Bars keep their existing independent profile system."
    }
    if type(profile) ~= "table" or type(profile.modules) ~= "table" then
        table.insert(lines, "")
        table.insert(lines, "Enter a name and click Save Profile to create one.")
        return table.concat(lines, "\n")
    end

    table.insert(lines, "")
    table.insert(lines, "Profile contents:")
    for _, key in ipairs(UI.profileModuleOrder or {}) do
        local label = (UI.profileModuleLabels and UI.profileModuleLabels[key]) or key
        local hasData = type(profile.modules[key]) == "table"
        local installed = UI:IsModuleAvailable(key)
        if hasData and installed then
            table.insert(lines, "|cff66ff99Saved + installed|r  " .. label)
        elseif hasData then
            table.insert(lines, "|cffffcc66Saved; module not installed|r  " .. label)
        elseif installed then
            table.insert(lines, "|cffaaaaaaInstalled; no saved section|r  " .. label)
        else
            table.insert(lines, "|cff666666No saved section|r  " .. label)
        end
    end
    return table.concat(lines, "\n")
end

function UI:RefreshProfilesPage(preferredName)
    if not profilesFrame then return end
    local names = UI:GetSharedProfileNames()
    local profiles = UI:GetSharedProfiles()
    local desired = tostring(preferredName or profileSelectedName or UI:GetLastSharedProfileName() or "")
    if desired == "" or type(profiles[desired]) ~= "table" then
        desired = names[1] or ""
    end
    profileSelectedName = desired
    UI:SetLastSharedProfileName(desired)

    if profileDropDown then
        if desired ~= "" then
            UIDropDownMenu_SetSelectedValue(profileDropDown, desired)
            UIDropDownMenu_SetText(profileDropDown, desired)
        else
            UIDropDownMenu_SetSelectedValue(profileDropDown, nil)
            UIDropDownMenu_SetText(profileDropDown, "No saved profiles")
        end
    end
    if profileNameEdit and not profileNameEdit:HasFocus() then
        profileNameEdit:SetText(desired)
    end
    if profileStatusText then profileStatusText:SetText(BuildProfileStatus(desired)) end
    if profileLoadButton then
        if desired ~= "" then profileLoadButton:Enable() else profileLoadButton:Disable() end
    end
    if profileDeleteButton then
        if desired ~= "" then profileDeleteButton:Enable() else profileDeleteButton:Disable() end
    end
end

local function CreateProfilesPage()
    if profilesFrame then return end

    profilesFrame = CreateBackdropFrame("DMLUIProfilesFrame", "DMLUI - Profiles", 560, 455)

    local profileLabel = profilesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 32, -60)
    profileLabel:SetText("Saved profile:")

    profileDropDown = CreateFrame("Frame", "DMLUISharedProfileDropDown", profilesFrame, "UIDropDownMenuTemplate")
    profileDropDown:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 122, -43)
    UIDropDownMenu_SetWidth(profileDropDown, 180)
    UIDropDownMenu_Initialize(profileDropDown, function()
        local names = UI:GetSharedProfileNames()
        for _, name in ipairs(names) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.checked = profileSelectedName == name
            info.func = function(button)
                profileSelectedName = button.value
                UI:SetLastSharedProfileName(button.value)
                UIDropDownMenu_SetSelectedValue(profileDropDown, button.value)
                UIDropDownMenu_SetText(profileDropDown, button.value)
                if profileNameEdit then profileNameEdit:SetText(button.value) end
                UI:RefreshProfilesPage(button.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local nameLabel = profilesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 32, -108)
    nameLabel:SetText("Profile name:")

    profileNameEdit = CreateFrame("EditBox", "DMLUISharedProfileNameEdit", profilesFrame, "InputBoxTemplate")
    profileNameEdit:SetWidth(190)
    profileNameEdit:SetHeight(24)
    profileNameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    profileNameEdit:SetAutoFocus(false)
    profileNameEdit:SetMaxLetters(40)
    profileNameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    profileNameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    save:SetWidth(110); save:SetHeight(25)
    save:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 330, -102)
    save:SetText("Save Profile")
    save:SetScript("OnClick", function()
        local name = GetProfileSelection()
        local ok, savedOrMessage = UI:SaveSharedProfile(name)
        if ok then
            profileSelectedName = name
            if profileNameEdit then profileNameEdit:ClearFocus() end
            UI.Print("Saved shared profile '" .. name .. "' (" .. tostring(savedOrMessage or 0) .. " installed module sections updated).")
        else
            UI.Print(tostring(savedOrMessage))
        end
    end)

    profileLoadButton = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    profileLoadButton:SetWidth(110); profileLoadButton:SetHeight(25)
    profileLoadButton:SetPoint("LEFT", save, "RIGHT", 8, 0)
    profileLoadButton:SetText("Load Profile")
    profileLoadButton:SetScript("OnClick", function()
        local name = GetProfileSelection()
        local ok, result, skipped = UI:LoadSharedProfile(name)
        if ok then
            UI.Print("Loaded shared profile '" .. name .. "' (" .. tostring(result or 0) .. " module sections applied" .. ((skipped or 0) > 0 and (", " .. tostring(skipped) .. " unavailable sections ignored") or "") .. ").")
        else
            UI.Print(tostring(result))
        end
    end)

    profileDeleteButton = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    profileDeleteButton:SetWidth(110); profileDeleteButton:SetHeight(25)
    profileDeleteButton:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 330, -140)
    profileDeleteButton:SetText("Delete Profile")
    profileDeleteButton:SetScript("OnClick", function()
        local name = profileSelectedName or ""
        if name ~= "" and UI:DeleteSharedProfile(name) then
            UI.Print("Deleted shared profile '" .. name .. "'.")
            profileSelectedName = nil
            if profileNameEdit then profileNameEdit:SetText("") end
            UI:RefreshProfilesPage()
        end
    end)

    profileStatusText = profilesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileStatusText:SetPoint("TOPLEFT", profilesFrame, "TOPLEFT", 32, -180)
    profileStatusText:SetPoint("TOPRIGHT", profilesFrame, "TOPRIGHT", -32, -180)
    profileStatusText:SetJustifyH("LEFT")
    profileStatusText:SetJustifyV("TOP")

    local preservation = profilesFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    preservation:SetPoint("BOTTOMLEFT", profilesFrame, "BOTTOMLEFT", 32, 80)
    preservation:SetWidth(496)
    preservation:SetJustifyH("LEFT")
    preservation:SetText("Missing modules are ignored when loading. Saving an existing profile updates only installed modules, so saved settings for an uninstalled module are preserved until it is installed again.")

    local actionBars = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    actionBars:SetWidth(180); actionBars:SetHeight(26)
    actionBars:SetPoint("BOTTOMLEFT", profilesFrame, "BOTTOMLEFT", 32, 30)
    actionBars:SetText("Open Action Bar Profiles")
    actionBars:SetScript("OnClick", function()
        if UI:IsModuleAvailable("ActionBars") then
            profilesFrame:Hide()
            UI:OpenModule("ActionBars")
        end
    end)

    local back = CreateFrame("Button", nil, profilesFrame, "UIPanelButtonTemplate")
    back:SetWidth(90); back:SetHeight(26)
    back:SetPoint("BOTTOMRIGHT", profilesFrame, "BOTTOMRIGHT", -32, 30)
    back:SetText("Back")
    back:SetScript("OnClick", function()
        profilesFrame:Hide()
        UI:ShowLauncher()
    end)

    UI:RefreshProfilesPage()
end

function UI:OpenProfilesPage()
    CreateProfilesPage()
    if launcher then launcher:Hide() end
    if advancedFrame then advancedFrame:Hide() end
    UI:RefreshProfilesPage()
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
