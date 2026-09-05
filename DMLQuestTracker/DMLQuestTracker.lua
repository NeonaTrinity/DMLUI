-- DMLUI - Quest Tracker
-- World of Warcraft 3.3.5a / Interface 30300
-- Optional movable quest tracker with whole-tracker and per-quest collapsing.

DMLQuestTracker = DMLQuestTracker or {}
local QT = DMLQuestTracker

QT.VERSION = "2.0.117"
QT.WIDTH = 310
QT.HEADER_HEIGHT = 24
QT.CONTAINER_HEIGHT = QT.HEADER_HEIGHT + 5
QT.QUEST_MIN_HEIGHT = 18
QT.OBJECTIVE_MIN_HEIGHT = 16
QT.QUEST_GAP = 4
QT.OBJECTIVE_GAP = 1
QT.OBJECTIVE_INDENT = 22
QT.BOTTOM_PADDING = 8
QT.ANCHOR_HEIGHT = 18
QT.ANCHOR_WIDTH = 155
QT.ANCHOR_GAP = 3
QT.SCALE_MIN = 0.50
QT.SCALE_MAX = 2.00
QT.SCALE_STEP = 0.05

local defaults = {
    version = 3,
    enabled = false,
    showAnchors = true,
    locked = false,
    collapsed = false,
    useQuestLevelRangeColors = true,
    questHeaderColor = { r = 1.00, g = 0.82, b = 0.00 },
    questObjectiveColor = { r = 0.82, g = 0.82, b = 0.82 },
    useTrackerBackground = true,
    hideQuestHeaderBackground = false,
    trackerBackgroundColor = { r = 0.025, g = 0.025, b = 0.025 },
    trackerScale = 1.00,
    useQuestCompletionColor = true,
    questCompletionColor = { r = 0.25, g = 1.00, b = 0.25 },
    position = {
        point = "TOPRIGHT",
        relativePoint = "TOPRIGHT",
        x = -40,
        y = -180
    },
    questCollapsed = {}
}

local DB
local container
local tracker
local anchor
local headerButton
local headerToggle
local headerText
local headerBackground
local emptyText
local questRows = {}
local objectiveRows = {}
local configFrame
local controls = {}
local initialized = false
local stockHookInstalled = false
local watchMutationHooksInstalled = false
local watchRefreshPending = false
local refreshing = false
local configRefreshing = false
local PRINT_PREFIX = "|cff66ff99DMLUI Quest Tracker|r: "

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
    end
end

local function CopyTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = CopyTable(child)
    end
    return copy
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NormalizeColor(value, fallback)
    fallback = fallback or { r = 1, g = 1, b = 1 }
    if type(value) ~= "table" then value = {} end
    return {
        r = Clamp(value.r ~= nil and value.r or fallback.r, 0, 1),
        g = Clamp(value.g ~= nil and value.g or fallback.g, 0, 1),
        b = Clamp(value.b ~= nil and value.b or fallback.b, 0, 1)
    }
end

local function SnapScale(value)
    value = Clamp(value, QT.SCALE_MIN, QT.SCALE_MAX)
    local steps = math.floor(((value - QT.SCALE_MIN) / QT.SCALE_STEP) + 0.5)
    return QT.SCALE_MIN + (steps * QT.SCALE_STEP)
end

local function CopyDefaults(reset)
    if reset or type(DMLQuestTrackerDB) ~= "table" then
        DMLQuestTrackerDB = {}
    end

    DB = DMLQuestTrackerDB
    for key, value in pairs(defaults) do
        if reset or DB[key] == nil then
            DB[key] = CopyTable(value)
        end
    end

    DB.version = defaults.version
    DB.enabled = DB.enabled and true or false
    DB.showAnchors = DB.showAnchors ~= false
    DB.locked = DB.locked and true or false
    DB.collapsed = DB.collapsed and true or false
    DB.useQuestLevelRangeColors = DB.useQuestLevelRangeColors ~= false
    DB.useTrackerBackground = DB.useTrackerBackground ~= false
    DB.hideQuestHeaderBackground = DB.hideQuestHeaderBackground and true or false
    DB.useQuestCompletionColor = DB.useQuestCompletionColor ~= false
    DB.questHeaderColor = NormalizeColor(DB.questHeaderColor, defaults.questHeaderColor)
    DB.questObjectiveColor = NormalizeColor(DB.questObjectiveColor, defaults.questObjectiveColor)
    DB.trackerBackgroundColor = NormalizeColor(DB.trackerBackgroundColor, defaults.trackerBackgroundColor)
    DB.questCompletionColor = NormalizeColor(DB.questCompletionColor, defaults.questCompletionColor)
    DB.trackerScale = SnapScale(DB.trackerScale or defaults.trackerScale)

    if type(DB.position) ~= "table" then
        DB.position = CopyTable(defaults.position)
    end
    DB.position.point = DB.position.point or defaults.position.point
    DB.position.relativePoint = DB.position.relativePoint or defaults.position.relativePoint
    DB.position.x = tonumber(DB.position.x) or defaults.position.x
    DB.position.y = tonumber(DB.position.y) or defaults.position.y

    if type(DB.questCollapsed) ~= "table" then
        DB.questCollapsed = {}
    end
end

local function GetFontStringHeight(fontString, minimum)
    if not fontString then return minimum end
    -- Blizzard's 3.3.5 WatchFrame measures the FontString's rendered height
    -- after constraining its width, which correctly accounts for wrapping.
    local height = fontString:GetHeight()
    if (not height or height <= 0) and fontString.GetStringHeight then
        height = fontString:GetStringHeight()
    end
    height = tonumber(height) or minimum
    if height < minimum then height = minimum end
    return math.ceil(height)
end

local function UpdateAnchorClampInsets()
    if not container or not container.SetClampRectInsets then return end

    -- The movement boundary belongs to the compact drag anchor, not the
    -- full quest-tracker body.  The container itself is still the movable
    -- frame, so adjust its clamp rectangle to match the anchor's footprint:
    --   left   = anchor left edge (same as container left)
    --   right  = allow the tracker body beyond the anchor to leave the screen
    --   top    = keep the anchor's top edge on-screen
    --   bottom = allow the tracker body below the anchor to leave the screen
    local height = tonumber(container:GetHeight()) or QT.CONTAINER_HEIGHT
    local rightOverflow = math.max(0, QT.WIDTH - QT.ANCHOR_WIDTH)
    local anchorTopOffset = QT.ANCHOR_HEIGHT + QT.ANCHOR_GAP
    local bodyBelowAnchor = height + QT.ANCHOR_GAP

    container:SetClampRectInsets(
        0,
        -rightOverflow,
        anchorTopOffset,
        bodyBelowAnchor
    )
end

local function SavePosition()
    if not container or not DB then return end
    local point, _, relativePoint, x, y = container:GetPoint(1)
    DB.position = {
        point = point or defaults.position.point,
        relativePoint = relativePoint or defaults.position.relativePoint,
        x = tonumber(x) or defaults.position.x,
        y = tonumber(y) or defaults.position.y
    }
end

local function RestorePosition()
    if not container or not DB then return end
    UpdateAnchorClampInsets()
    container:ClearAllPoints()
    container:SetPoint(
        DB.position.point or defaults.position.point,
        UIParent,
        DB.position.relativePoint or defaults.position.relativePoint,
        tonumber(DB.position.x) or defaults.position.x,
        tonumber(DB.position.y) or defaults.position.y
    )
end

local function QuestKey(questIndex)
    local questID = select(9, GetQuestLogTitle(questIndex))
    questID = tonumber(questID)
    if questID and questID > 0 then
        return "q" .. tostring(questID), questID
    end

    -- 3.3.5a normally supplies questID as return 9. This fallback only keeps
    -- the UI functional on unusual private-server clients with a modified API.
    local title = GetQuestLogTitle(questIndex) or "Quest"
    return "fallback:" .. tostring(title), nil
end

local function IsQuestCollapsed(key)
    return DB and DB.questCollapsed and DB.questCollapsed[key] and true or false
end

local function HideAllRows()
    local i
    for i = 1, #questRows do
        questRows[i]:Hide()
    end
    for i = 1, #objectiveRows do
        objectiveRows[i]:Hide()
    end
end

local function AcquireQuestRow(index)
    local row = questRows[index]
    if row then return row end

    row = CreateFrame("Button", nil, tracker)
    row:SetWidth(QT.WIDTH - 16)
    row:SetHeight(QT.QUEST_MIN_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.toggle:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.toggle:SetWidth(16)
    row.toggle:SetJustifyH("CENTER")

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 19, -1)
    row.title:SetWidth(QT.WIDTH - 42)
    row.title:SetJustifyH("LEFT")
    row.title:SetJustifyV("TOP")
    if row.title.SetNonSpaceWrap then row.title:SetNonSpaceWrap(true) end

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetAlpha(0.22)

    row:SetScript("OnClick", function(self, button)
        if not self.questKey or not DB then return end

        if button == "RightButton" then
            if self.questIndex and IsQuestWatched and IsQuestWatched(self.questIndex) and RemoveQuestWatch then
                RemoveQuestWatch(self.questIndex)
                if WatchFrame_Update then WatchFrame_Update() end
                if QuestLog_Update and QuestLogFrame and QuestLogFrame:IsShown() then QuestLog_Update() end
                QT:Refresh()
            end
            return
        end

        DB.questCollapsed[self.questKey] = not IsQuestCollapsed(self.questKey)
        QT:Refresh()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.questIndex then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.title:GetText() or "Quest")
        GameTooltip:AddLine("Left-click: expand/collapse objectives", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-click: stop tracking this quest", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    questRows[index] = row
    return row
end

local function AcquireObjectiveRow(index)
    local row = objectiveRows[index]
    if row then return row end

    row = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row:SetWidth(QT.WIDTH - QT.OBJECTIVE_INDENT - 18)
    row:SetJustifyH("LEFT")
    row:SetJustifyV("TOP")
    if row.SetNonSpaceWrap then row:SetNonSpaceWrap(true) end
    objectiveRows[index] = row
    return row
end

local function UpdateAnchorVisibility()
    if not anchor or not DB then return end
    if DB.enabled and DB.showAnchors and not DB.locked then
        anchor:Show()
        anchor:EnableMouse(true)
    else
        anchor:Hide()
        anchor:EnableMouse(false)
    end
end

local function InstallStockWatchFrameHook()
    if stockHookInstalled or not WatchFrame or not WatchFrame.HookScript then return end
    WatchFrame:HookScript("OnShow", function(self)
        if DMLQuestTrackerDB and DMLQuestTrackerDB.enabled then
            self:Hide()
        end
    end)
    stockHookInstalled = true
end

local function HideBlizzardTracker()
    if not WatchFrame then return end
    InstallStockWatchFrameHook()
    WatchFrame:Hide()
end

local function RestoreBlizzardTracker()
    if not WatchFrame then return end
    if WatchFrame_Update then
        WatchFrame_Update(WatchFrame)
    end
    WatchFrame:Show()
end

local watchRefreshFrame = CreateFrame("Frame")
watchRefreshFrame:Hide()
watchRefreshFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    watchRefreshPending = false

    if not initialized or not DB or not DB.enabled then return end
    HideBlizzardTracker()
    QT:Refresh()
end)

local function ScheduleQuestWatchRefresh()
    if watchRefreshPending then return end
    watchRefreshPending = true
    watchRefreshFrame:Show()
end

local function InstallQuestWatchMutationHooks()
    if watchMutationHooksInstalled or not hooksecurefunc then return end

    local installed = false
    if AddQuestWatch then
        hooksecurefunc("AddQuestWatch", ScheduleQuestWatchRefresh)
        installed = true
    end
    if RemoveQuestWatch then
        hooksecurefunc("RemoveQuestWatch", ScheduleQuestWatchRefresh)
        installed = true
    end

    watchMutationHooksInstalled = installed
end

local function ApplyAppearance()
    if not DB then return end

    if container and container.SetScale then
        container:SetScale(SnapScale(DB.trackerScale))
        UpdateAnchorClampInsets()
    end

    if tracker and tracker.SetBackdropColor then
        local bg = NormalizeColor(DB.trackerBackgroundColor, defaults.trackerBackgroundColor)
        if DB.useTrackerBackground then
            tracker:SetBackdropColor(bg.r, bg.g, bg.b, 0.84)
            tracker:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.92)
        else
            tracker:SetBackdropColor(bg.r, bg.g, bg.b, 0)
            tracker:SetBackdropBorderColor(0.28, 0.28, 0.28, 0)
        end
    end

    if headerBackground then
        if DB.hideQuestHeaderBackground then
            headerBackground:Hide()
        else
            headerBackground:Show()
        end
    end
end

local function GetQuestHeaderColor(level, isComplete)
    if DB and DB.useQuestCompletionColor and isComplete == 1 then
        local complete = NormalizeColor(DB.questCompletionColor, defaults.questCompletionColor)
        return complete.r, complete.g, complete.b
    end

    if DB and DB.useQuestLevelRangeColors and GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(tonumber(level) or 0)
        if color then
            return color.r or 1, color.g or 0.82, color.b or 0
        end
    end

    local header = NormalizeColor(DB and DB.questHeaderColor, defaults.questHeaderColor)
    return header.r, header.g, header.b
end

local function RefreshColorSwatches()
    if not DB then return end
    local map = {
        questHeaderColor = defaults.questHeaderColor,
        questObjectiveColor = defaults.questObjectiveColor,
        trackerBackgroundColor = defaults.trackerBackgroundColor,
        questCompletionColor = defaults.questCompletionColor
    }
    for key, fallback in pairs(map) do
        local swatch = controls["color_" .. key]
        local color = NormalizeColor(DB[key], fallback)
        if swatch and swatch.SetBackdropColor then
            swatch:SetBackdropColor(color.r, color.g, color.b, 1)
        end
    end
end

local function OpenColorPicker(colorKey)
    if not DB or not ColorPickerFrame then return end
    local fallback = defaults[colorKey] or { r = 1, g = 1, b = 1 }
    local current = NormalizeColor(DB[colorKey], fallback)
    local previous = { r = current.r, g = current.g, b = current.b }

    local function ApplyPickerColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        DB[colorKey] = NormalizeColor({ r = r, g = g, b = b }, fallback)
        RefreshColorSwatches()
        ApplyAppearance()
        QT:Refresh()
    end

    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.func = ApplyPickerColor
    ColorPickerFrame.cancelFunc = function()
        DB[colorKey] = previous
        RefreshColorSwatches()
        ApplyAppearance()
        QT:Refresh()
    end
    ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)
    if ShowUIPanel then ShowUIPanel(ColorPickerFrame) else ColorPickerFrame:Show() end
end

local function CreateTrackerFrames()
    if container then return end

    container = CreateFrame("Frame", "DMLUIQuestTrackerContainer", UIParent)
    container:SetWidth(QT.WIDTH)
    container:SetHeight(QT.CONTAINER_HEIGHT)
    container:SetMovable(true)
    container:SetClampedToScreen(true)

    tracker = CreateFrame("Frame", "DMLUIQuestTrackerFrame", container)
    tracker:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    tracker:SetWidth(QT.WIDTH)
    tracker:SetHeight(QT.CONTAINER_HEIGHT)
    tracker:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    tracker:SetBackdropColor(0.025, 0.025, 0.025, 0.84)
    tracker:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.92)

    headerButton = CreateFrame("Button", nil, tracker)
    headerButton:SetPoint("TOPLEFT", tracker, "TOPLEFT", 5, -4)
    headerButton:SetWidth(QT.WIDTH - 10)
    headerButton:SetHeight(QT.HEADER_HEIGHT - 4)
    headerButton:RegisterForClicks("LeftButtonUp")

    headerBackground = headerButton:CreateTexture(nil, "BACKGROUND")
    headerBackground:SetAllPoints(headerButton)
    headerBackground:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    headerBackground:SetVertexColor(0.10, 0.10, 0.10, 0.92)

    local headerHighlight = headerButton:CreateTexture(nil, "HIGHLIGHT")
    headerHighlight:SetAllPoints(headerButton)
    headerHighlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    headerHighlight:SetBlendMode("ADD")
    headerHighlight:SetAlpha(0.28)

    headerToggle = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerToggle:SetPoint("LEFT", headerButton, "LEFT", 4, 0)
    headerToggle:SetWidth(18)
    headerToggle:SetJustifyH("CENTER")

    headerText = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", headerToggle, "RIGHT", 3, 0)
    headerText:SetText("DML Quest Tracker")

    headerButton:SetScript("OnClick", function()
        if not DB then return end
        DB.collapsed = not DB.collapsed
        QT:Refresh()
    end)

    emptyText = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetWidth(QT.WIDTH - 28)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("No tracked quests.")

    anchor = CreateFrame("Frame", "DMLUIQuestTrackerAnchor", container)
    anchor:SetWidth(QT.ANCHOR_WIDTH)
    anchor:SetHeight(QT.ANCHOR_HEIGHT)
    anchor:SetPoint("BOTTOMLEFT", tracker, "TOPLEFT", 0, QT.ANCHOR_GAP)
    anchor:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    anchor:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
    anchor:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchorText:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    anchorText:SetText("DML Quest Tracker - drag")

    anchor:SetScript("OnDragStart", function()
        if not DB or DB.locked or not DB.showAnchors then return end
        container:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SavePosition()
    end)

    UpdateAnchorClampInsets()
    RestorePosition()
    ApplyAppearance()
    container:Hide()
    anchor:Hide()
end

function QT:Refresh()
    if not initialized or not DB or not tracker or refreshing then return end
    refreshing = true

    ApplyAppearance()
    HideAllRows()
    emptyText:Hide()
    headerToggle:SetText(DB.collapsed and "+" or "-")

    if not DB.enabled then
        container:Hide()
        UpdateAnchorVisibility()
        refreshing = false
        return
    end

    container:Show()
    HideBlizzardTracker()

    if DB.collapsed then
        -- The container is a fixed-height top origin. Only the tracker body
        -- collapses, so the DML Quest Tracker header never moves.
        tracker:SetHeight(QT.CONTAINER_HEIGHT)
        UpdateAnchorClampInsets()
        UpdateAnchorVisibility()
        refreshing = false
        return
    end

    local y = -(QT.HEADER_HEIGHT + 6)
    local questRowIndex = 0
    local objectiveRowIndex = 0
    local trackedCount = 0
    local numWatches = GetNumQuestWatches and GetNumQuestWatches() or 0
    local i

    for i = 1, numWatches do
        local questIndex = GetQuestIndexForWatch and GetQuestIndexForWatch(i)
        if questIndex then
            local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete = GetQuestLogTitle(questIndex)
            if title and not isHeader then
                trackedCount = trackedCount + 1
                questRowIndex = questRowIndex + 1

                local key = QuestKey(questIndex)
                local collapsed = IsQuestCollapsed(key)
                local row = AcquireQuestRow(questRowIndex)
                row.questKey = key
                row.questIndex = questIndex
                row.toggle:SetText(collapsed and "+" or "-")

                local displayTitle = title
                if tonumber(level) and tonumber(level) > 0 then
                    displayTitle = "[" .. tostring(level) .. "] " .. title
                end
                row.title:SetText(displayTitle)

                local qr, qg, qb = GetQuestHeaderColor(level, isComplete)
                row.title:SetTextColor(qr, qg, qb)

                local questHeight = GetFontStringHeight(row.title, QT.QUEST_MIN_HEIGHT)
                row:SetHeight(questHeight)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", tracker, "TOPLEFT", 9, y)
                row:Show()
                y = y - questHeight

                if not collapsed then
                    local numObjectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(questIndex) or 0
                    local j
                    for j = 1, numObjectives do
                        local text, objectiveType, finished = GetQuestLogLeaderBoard(j, questIndex)
                        if text and text ~= "" then
                            objectiveRowIndex = objectiveRowIndex + 1
                            local objective = AcquireObjectiveRow(objectiveRowIndex)
                            objective:SetText("- " .. tostring(text))
                            local objectiveColor = NormalizeColor(DB.questObjectiveColor, defaults.questObjectiveColor)
                            objective:SetTextColor(objectiveColor.r, objectiveColor.g, objectiveColor.b)
                            local objectiveHeight = GetFontStringHeight(objective, QT.OBJECTIVE_MIN_HEIGHT)
                            objective:ClearAllPoints()
                            objective:SetPoint("TOPLEFT", tracker, "TOPLEFT", QT.OBJECTIVE_INDENT, y - QT.OBJECTIVE_GAP)
                            objective:Show()
                            y = y - objectiveHeight - QT.OBJECTIVE_GAP
                        end
                    end
                end

                y = y - QT.QUEST_GAP
            end
        end
    end

    if trackedCount == 0 then
        emptyText:ClearAllPoints()
        emptyText:SetPoint("TOPLEFT", tracker, "TOPLEFT", 14, y)
        emptyText:Show()
        y = y - 18
    end

    local neededHeight = math.max(QT.HEADER_HEIGHT + 5, -y + QT.BOTTOM_PADDING)
    -- Grow only the tracker body downward from the fixed container/header
    -- origin. Resizing the movable container itself would make a CENTER- or
    -- BOTTOM-anchored frame shift as quests are added/removed.
    tracker:SetHeight(neededHeight)
    UpdateAnchorClampInsets()
    UpdateAnchorVisibility()
    refreshing = false
end

local function ApplyEnabledState()
    if not DB or not container then return end
    if DB.enabled then
        HideBlizzardTracker()
        container:Show()
        QT:Refresh()
    else
        container:Hide()
        RestoreBlizzardTracker()
    end
    UpdateAnchorVisibility()
end

local function SetControlEnabled(widget, enabled)
    if not widget then return end
    if enabled then
        if widget.Enable then widget:Enable() end
        if widget.SetAlpha then widget:SetAlpha(1) end
    else
        if widget.Disable then widget:Disable() end
        if widget.SetAlpha then widget:SetAlpha(0.45) end
    end
end

local function RefreshConditionalControls()
    if not controls.useQuestLevelRangeColors then return end
    local usingDifficulty = controls.useQuestLevelRangeColors:GetChecked() and true or false
    SetControlEnabled(controls.color_questHeaderColor, not usingDifficulty)

    local useBackground = controls.useTrackerBackground and controls.useTrackerBackground:GetChecked() and true or false
    SetControlEnabled(controls.color_trackerBackgroundColor, useBackground)

    local useCompletion = controls.useQuestCompletionColor and controls.useQuestCompletionColor:GetChecked() and true or false
    SetControlEnabled(controls.color_questCompletionColor, useCompletion)
end

local function RefreshConfig()
    if not configFrame or not DB then return end
    configRefreshing = true
    controls.enabled:SetChecked(DB.enabled and 1 or nil)
    controls.showAnchors:SetChecked(DB.showAnchors and 1 or nil)
    controls.locked:SetChecked(DB.locked and 1 or nil)
    controls.useQuestLevelRangeColors:SetChecked(DB.useQuestLevelRangeColors and 1 or nil)
    controls.useTrackerBackground:SetChecked(DB.useTrackerBackground and 1 or nil)
    controls.hideQuestHeaderBackground:SetChecked(DB.hideQuestHeaderBackground and 1 or nil)
    controls.useQuestCompletionColor:SetChecked(DB.useQuestCompletionColor and 1 or nil)
    controls.scaleSlider:SetValue(DB.trackerScale)
    controls.scaleValue:SetText(string.format("%.2fx", DB.trackerScale))
    RefreshColorSwatches()
    RefreshConditionalControls()
    configRefreshing = false
end

local function ApplyConfig()
    if not DB then return end
    DB.enabled = controls.enabled:GetChecked() and true or false
    DB.showAnchors = controls.showAnchors:GetChecked() and true or false
    DB.locked = controls.locked:GetChecked() and true or false
    DB.useQuestLevelRangeColors = controls.useQuestLevelRangeColors:GetChecked() and true or false
    DB.useTrackerBackground = controls.useTrackerBackground:GetChecked() and true or false
    DB.hideQuestHeaderBackground = controls.hideQuestHeaderBackground:GetChecked() and true or false
    DB.useQuestCompletionColor = controls.useQuestCompletionColor:GetChecked() and true or false
    DB.trackerScale = SnapScale(controls.scaleSlider:GetValue())
    ApplyAppearance()
    ApplyEnabledState()
    QT:Refresh()
    RefreshConfig()
end

local function ResetPosition()
    DB.position = CopyTable(defaults.position)
    RestorePosition()
    Print("Quest Tracker position reset.")
end

local function ResetSettings()
    local wasEnabled = DB and DB.enabled
    CopyDefaults(true)
    RestorePosition()
    ApplyAppearance()
    ApplyEnabledState()
    RefreshConfig()
    if wasEnabled and not DB.enabled then
        Print("Quest Tracker settings reset; DML Quest Tracker is disabled.")
    else
        Print("Quest Tracker settings reset.")
    end
end

local function CreateCheck(parent, key, labelText, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(labelText)
    controls[key] = check
    return check
end

local function CreateColorSwatch(parent, key, labelText, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(labelText)

    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetWidth(30)
    swatch:SetHeight(20)
    swatch:SetPoint("LEFT", label, "RIGHT", 12, 0)
    swatch:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    swatch:SetScript("OnClick", function() OpenColorPicker(key) end)
    controls["color_" .. key] = swatch
    return swatch
end

local function CreateConfigFrame()
    if configFrame then return end

    configFrame = CreateFrame("Frame", "DMLUIQuestTrackerConfigFrame", UIParent)
    configFrame:SetWidth(620)
    configFrame:SetHeight(575)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetFrameLevel(100)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    configFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    configFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", configFrame, "TOP", 0, -18)
    title:SetText("DMLUI - Quest Tracker")

    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    local description = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -55)
    description:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -34, -55)
    description:SetJustifyH("LEFT")
    description:SetText("Replaces Blizzard's WatchFrame with a movable DML tracker. It uses the same watched-quest list as the quest log; right-click a quest header in DML to stop tracking it.")

    CreateCheck(configFrame, "enabled", "Use DML Quest Tracker", 34, -92)
    CreateCheck(configFrame, "showAnchors", "Show anchors", 34, -125)
    CreateCheck(configFrame, "locked", "Lock tracker", 260, -125)

    local appearanceTitle = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    appearanceTitle:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 38, -171)
    appearanceTitle:SetText("Quest appearance")

    local difficultyCheck = CreateCheck(configFrame, "useQuestLevelRangeColors", "Use quest level range colors", 34, -190)
    difficultyCheck:SetScript("OnClick", RefreshConditionalControls)
    CreateColorSwatch(configFrame, "questHeaderColor", "Quest header color", 64, -231)
    CreateColorSwatch(configFrame, "questObjectiveColor", "Quest objective color", 64, -265)

    local completionCheck = CreateCheck(configFrame, "useQuestCompletionColor", "Use quest completion color", 34, -295)
    completionCheck:SetScript("OnClick", RefreshConditionalControls)
    CreateColorSwatch(configFrame, "questCompletionColor", "Completion color", 64, -336)

    local trackerTitle = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackerTitle:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 335, -171)
    trackerTitle:SetText("Tracker appearance")

    local backgroundCheck = CreateCheck(configFrame, "useTrackerBackground", "Use quest tracker background", 330, -190)
    backgroundCheck:SetScript("OnClick", RefreshConditionalControls)
    CreateCheck(configFrame, "hideQuestHeaderBackground", "Hide quest header background", 330, -223)
    CreateColorSwatch(configFrame, "trackerBackgroundColor", "Tracker background color", 360, -264)

    local scaleLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 360, -308)
    scaleLabel:SetText("Quest tracker scale")

    local scaleSlider = CreateFrame("Slider", "DMLUIQuestTrackerScaleSlider", configFrame, "OptionsSliderTemplate")
    scaleSlider:SetWidth(205)
    scaleSlider:SetHeight(16)
    scaleSlider:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 357, -338)
    scaleSlider:SetMinMaxValues(QT.SCALE_MIN, QT.SCALE_MAX)
    if scaleSlider.SetValueStep then scaleSlider:SetValueStep(QT.SCALE_STEP) end
    _G[scaleSlider:GetName() .. "Low"]:SetText(string.format("%.2f", QT.SCALE_MIN))
    _G[scaleSlider:GetName() .. "High"]:SetText(string.format("%.2f", QT.SCALE_MAX))
    _G[scaleSlider:GetName() .. "Text"]:SetText("")
    controls.scaleSlider = scaleSlider

    local scaleValue = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleValue:SetPoint("TOP", scaleSlider, "BOTTOM", 0, -4)
    scaleValue:SetText("1.00x")
    controls.scaleValue = scaleValue
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = SnapScale(value)
        if controls.scaleValue then controls.scaleValue:SetText(string.format("%.2fx", value)) end
    end)

    local hint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 38, -390)
    hint:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -38, -390)
    hint:SetJustifyH("LEFT")
    hint:SetText("Left-click [+] / [-] on a quest to collapse or expand its objectives. Right-click a quest header to untrack it from both DML and Blizzard's quest log. Quest difficulty colors use the same GetQuestDifficultyColor() system as the Wrath quest log.")

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(80)
    apply:SetHeight(24)
    apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 105, 31)
    apply:SetText("Apply")
    apply:SetScript("OnClick", ApplyConfig)

    local resetPosition = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetPosition:SetWidth(110)
    resetPosition:SetHeight(24)
    resetPosition:SetPoint("LEFT", apply, "RIGHT", 8, 0)
    resetPosition:SetText("Reset Position")
    resetPosition:SetScript("OnClick", ResetPosition)

    local resetSettings = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetSettings:SetWidth(105)
    resetSettings:SetHeight(24)
    resetSettings:SetPoint("LEFT", resetPosition, "RIGHT", 8, 0)
    resetSettings:SetText("Reset Settings")
    resetSettings:SetScript("OnClick", ResetSettings)

    local closeBottom = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    closeBottom:SetWidth(70)
    closeBottom:SetHeight(24)
    closeBottom:SetPoint("LEFT", resetSettings, "RIGHT", 8, 0)
    closeBottom:SetText("Close")
    closeBottom:SetScript("OnClick", function() configFrame:Hide() end)

    table.insert(UISpecialFrames, "DMLUIQuestTrackerConfigFrame")
    configFrame:Hide()
end

function QT:OpenConfig()
    if not configFrame then CreateConfigFrame() end
    RefreshConfig()
    configFrame:Show()
    return true
end

local function RegisterWithCore()
    if DMLUI and DMLUI.RegisterModule then
        DMLUI:RegisterModule("QuestTracker", {
            name = "Quest Tracker",
            version = QT.VERSION,
            openConfig = function() return QT:OpenConfig() end
        })
    end
end

local function RegisterSlashCommand()
    SLASH_DMLQUESTTRACKER1 = "/dmlquest"
    SLASH_DMLQUESTTRACKER2 = "/dmlqt"
    SlashCmdList["DMLQUESTTRACKER"] = function()
        QT:OpenConfig()
    end
end

local function Initialize()
    if initialized then return end
    CopyDefaults(false)
    CreateTrackerFrames()
    CreateConfigFrame()
    InstallStockWatchFrameHook()
    InstallQuestWatchMutationHooks()
    RegisterWithCore()
    RegisterSlashCommand()
    initialized = true
    ApplyEnabledState()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "DMLQuestTracker" then
            Initialize()
        end
        return
    end

    if not initialized then return end

    if event == "PLAYER_ENTERING_WORLD" then
        ApplyEnabledState()
    elseif event == "PLAYER_LEVEL_UP" or event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or
           event == "QUEST_ACCEPTED" or (event == "UNIT_QUEST_LOG_CHANGED" and arg1 == "player") then
        if DB.enabled then
            HideBlizzardTracker()
            QT:Refresh()
        end
    end
end)
