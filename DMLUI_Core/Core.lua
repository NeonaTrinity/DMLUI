-- DMLUI Core
-- WoW 3.3.5a / Interface 30300
--
-- Shared module registry, SavedVariables, minimap launcher, and public API.
-- Feature modules (Action Bars, Unit Frames, BigBag, etc.) register themselves
-- with DMLUI when they are installed and loaded.

DMLUI = DMLUI or {}
local UI = DMLUI

UI.VERSION = "2.0.123"
UI.modules = UI.modules or {}
UI.knownModules = UI.knownModules or {
    { key = "ActionBars", name = "Action Bars", order = 10 },
    { key = "UnitFrames", name = "Unit Frames", order = 20 },
    { key = "Buffs", name = "Buffs", order = 25 },
    { key = "CastBars", name = "Cast Bars", order = 30 },
    { key = "QuestTracker", name = "Quest Tracker", order = 40 },
    { key = "Profiles", name = "Profiles", order = 50, core = true },
    { key = "Advanced", name = "Advanced", order = 60, core = true },
    { key = "BigBag", name = "DML BigBag", order = 70 }
}

local defaults = {
    version = 2,
    showMinimapButton = true,
    minimapAngle = 225
}

UI.profileModuleOrder = UI.profileModuleOrder or { "UnitFrames", "CastBars", "Buffs", "QuestTracker" }
UI.profileModuleLabels = UI.profileModuleLabels or {
    UnitFrames = "Unit Frames",
    CastBars = "Cast Bars",
    Buffs = "Buffs",
    QuestTracker = "Quest Tracker"
}

local DB
local minimapButton
local initialized = false
local PRINT_PREFIX = "|cff66ff99DMLUI|r: "

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
    end
end

UI.Print = Print

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[DeepCopy(key)] = DeepCopy(child)
    end
    return copy
end

local function NormalizeProfileName(name)
    name = tostring(name or "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if string.len(name) > 40 then name = string.sub(name, 1, 40) end
    return name
end

local function CopyDefaults()
    if type(DMLUIDB) ~= "table" then
        DMLUIDB = {}
    end

    DB = DMLUIDB
    local key, value
    for key, value in pairs(defaults) do
        if DB[key] == nil then
            DB[key] = value
        end
    end

    if type(DB.profiles) ~= "table" then DB.profiles = {} end
    DB.lastProfileName = NormalizeProfileName(DB.lastProfileName)

    DB.version = defaults.version
    DB.showMinimapButton = DB.showMinimapButton ~= false
    DB.minimapAngle = tonumber(DB.minimapAngle) or defaults.minimapAngle
end

function UI:GetDB()
    return DB
end

function UI:RegisterModule(key, info)
    key = tostring(key or "")
    if key == "" or type(info) ~= "table" then
        return false
    end

    local record = UI.modules[key] or {}
    local field, value
    for field, value in pairs(info) do
        record[field] = value
    end
    record.key = key
    record.loaded = true
    UI.modules[key] = record

    if UI.RefreshLauncherButtons then
        UI:RefreshLauncherButtons()
    end
    if UI.RefreshAdvancedPage then
        UI:RefreshAdvancedPage()
    end
    if UI.RefreshProfilesPage then
        UI:RefreshProfilesPage()
    end
    return true
end

function UI:UnregisterModule(key)
    key = tostring(key or "")
    UI.modules[key] = nil
    if UI.RefreshLauncherButtons then
        UI:RefreshLauncherButtons()
    end
    if UI.RefreshAdvancedPage then
        UI:RefreshAdvancedPage()
    end
    if UI.RefreshProfilesPage then
        UI:RefreshProfilesPage()
    end
end

function UI:GetModule(key)
    return UI.modules[tostring(key or "")]
end

function UI:IsModuleAvailable(key)
    key = tostring(key or "")
    if key == "Profiles" or key == "Advanced" then
        return true
    end
    local module = UI.modules[key]
    return type(module) == "table" and module.loaded ~= false
end

function UI:OpenModule(key)
    key = tostring(key or "")
    if key == "Profiles" and UI.OpenProfilesPage then
        UI:OpenProfilesPage()
        return true
    elseif key == "Advanced" and UI.OpenAdvancedPage then
        UI:OpenAdvancedPage()
        return true
    end

    local module = UI.modules[key]
    if not module or module.loaded == false or type(module.openConfig) ~= "function" then
        return false
    end

    if UI.launcherFrame then
        UI.launcherFrame:Hide()
    end

    local ok, errorMessage = pcall(module.openConfig)
    if not ok then
        Print((module.name or key) .. " configuration failed to open: " .. tostring(errorMessage))
        return false
    end
    return true
end

function UI:GetSharedProfiles()
    if not DB then return {} end
    if type(DB.profiles) ~= "table" then DB.profiles = {} end
    return DB.profiles
end

function UI:GetSharedProfileNames()
    local names = {}
    local profiles = UI:GetSharedProfiles()
    for name, profile in pairs(profiles) do
        if type(name) == "string" and name ~= "" and type(profile) == "table" then
            table.insert(names, name)
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

function UI:GetLastSharedProfileName()
    return DB and NormalizeProfileName(DB.lastProfileName) or ""
end

function UI:SetLastSharedProfileName(name)
    if not DB then return end
    DB.lastProfileName = NormalizeProfileName(name)
end

function UI:SaveSharedProfile(name)
    if not DB then return false, "DMLUI is not initialized." end
    name = NormalizeProfileName(name)
    if name == "" then return false, "Enter a profile name first." end

    local profiles = UI:GetSharedProfiles()
    local profile = profiles[name]
    if type(profile) ~= "table" then
        profile = { version = 1, modules = {} }
    end
    if type(profile.modules) ~= "table" then profile.modules = {} end

    local saved = 0
    for _, key in ipairs(UI.profileModuleOrder) do
        local module = UI:GetModule(key)
        if module and type(module.profileExport) == "function" then
            local ok, data = pcall(module.profileExport)
            if ok and type(data) == "table" then
                -- Crucial modular behavior: update only installed modules.
                -- Sections belonging to missing modules remain untouched.
                profile.modules[key] = DeepCopy(data)
                saved = saved + 1
            elseif not ok then
                Print("Could not save " .. (UI.profileModuleLabels[key] or key) .. " settings: " .. tostring(data))
            end
        end
    end

    profile.version = 1
    profile.updated = date and date("%Y-%m-%d %H:%M") or nil
    profiles[name] = profile
    DB.lastProfileName = name
    if UI.RefreshProfilesPage then UI:RefreshProfilesPage(name) end
    return true, saved
end

function UI:LoadSharedProfile(name)
    if not DB then return false, "DMLUI is not initialized." end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Profiles cannot be loaded during combat."
    end

    name = NormalizeProfileName(name)
    local profile = UI:GetSharedProfiles()[name]
    if type(profile) ~= "table" or type(profile.modules) ~= "table" then
        return false, "That profile does not exist."
    end

    local loaded = 0
    local skipped = 0
    local errors = {}
    for _, key in ipairs(UI.profileModuleOrder) do
        local data = profile.modules[key]
        if type(data) == "table" then
            local module = UI:GetModule(key)
            if module and type(module.profileImport) == "function" then
                local ok, result, reason = pcall(module.profileImport, DeepCopy(data))
                if ok and result ~= false then
                    loaded = loaded + 1
                else
                    table.insert(errors, (UI.profileModuleLabels[key] or key) .. ": " .. tostring(ok and reason or result))
                end
            else
                -- Missing modules are intentionally ignored. Their saved profile
                -- sections remain intact for a future reinstall.
                skipped = skipped + 1
            end
        end
    end

    DB.lastProfileName = name
    if UI.RefreshProfilesPage then UI:RefreshProfilesPage(name) end
    if #errors > 0 then
        return false, "Some module settings could not be loaded: " .. table.concat(errors, "; "), loaded, skipped
    end
    return true, loaded, skipped
end

function UI:DeleteSharedProfile(name)
    if not DB then return false end
    name = NormalizeProfileName(name)
    if name == "" or type(DB.profiles) ~= "table" or DB.profiles[name] == nil then return false end
    DB.profiles[name] = nil
    if DB.lastProfileName == name then DB.lastProfileName = "" end
    if UI.RefreshProfilesPage then UI:RefreshProfilesPage() end
    return true
end

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function PositionMinimapButton()
    if not minimapButton or not Minimap or not DB then
        return
    end

    local angle = math.rad(tonumber(DB.minimapAngle) or defaults.minimapAngle)
    local radius = 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(angle) * radius,
        math.sin(angle) * radius
    )
end

local function UpdateMinimapFromCursor()
    if not minimapButton or not Minimap or not GetCursorPosition then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    if not scale or scale == 0 then
        scale = 1
    end
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then
        return
    end

    DB.minimapAngle = math.deg(Atan2(cursorY - centerY, cursorX - centerX))
    PositionMinimapButton()
end

function UI:IsMinimapButtonVisible()
    if not DB then
        return true
    end
    return DB.showMinimapButton ~= false
end

function UI:SetMinimapButtonVisible(shown)
    if not DB then
        return
    end
    DB.showMinimapButton = shown and true or false
    if not minimapButton then
        return
    end
    if DB.showMinimapButton then
        PositionMinimapButton()
        minimapButton:Show()
    else
        minimapButton:Hide()
    end
end

function UI:GetMinimapButton()
    return minimapButton
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then
        return
    end

    minimapButton = CreateFrame("Button", "DMLUIMinimapButton", Minimap)
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 5)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetWidth(54)
    border:SetHeight(54)
    border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetWidth(32)
    highlight:SetHeight(32)
    highlight:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("DMLUI")
        GameTooltip:AddLine("Left-click: open DMLUI", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton:SetScript("OnClick", function(self)
        if self.dragStopTime and (GetTime() - self.dragStopTime) < 0.2 then
            self.dragStopTime = nil
            return
        end
        self.dragStopTime = nil
        if UI.ToggleLauncher then
            UI:ToggleLauncher()
        end
    end)

    minimapButton:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", UpdateMinimapFromCursor)
    end)

    minimapButton:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self.dragStopTime = GetTime()
        self:SetScript("OnUpdate", nil)
        UpdateMinimapFromCursor()
    end)

    PositionMinimapButton()
    UI:SetMinimapButtonVisible(DB.showMinimapButton)
end

local function HandleSlash(message)
    message = string.lower(tostring(message or ""))
    if message == "hide" then
        UI:SetMinimapButtonVisible(false)
        Print("Minimap button hidden. Use /dmlui show to restore it.")
    elseif message == "show" then
        UI:SetMinimapButtonVisible(true)
        Print("Minimap button shown.")
    elseif message == "advanced" and UI.OpenAdvancedPage then
        UI:OpenAdvancedPage()
    elseif message == "profiles" and UI.OpenProfilesPage then
        UI:OpenProfilesPage()
    elseif UI.ToggleLauncher then
        UI:ToggleLauncher()
    end
end

local function RegisterSlashCommands()
    SLASH_DMLUI1 = "/dmlui"
    SlashCmdList["DMLUI"] = HandleSlash
end

local function Initialize()
    if initialized then
        return
    end
    CopyDefaults()
    CreateMinimapButton()
    RegisterSlashCommands()
    initialized = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "DMLUI_Core" then
        Initialize()
    elseif event == "ADDON_LOADED" and initialized then
        if UI.RefreshLauncherButtons then
            UI:RefreshLauncherButtons()
        end
        if UI.RefreshAdvancedPage then
            UI:RefreshAdvancedPage()
        end
    end
end)
