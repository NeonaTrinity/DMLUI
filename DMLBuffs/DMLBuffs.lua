-- DMLUI - Buffs
-- World of Warcraft 3.3.5a / Interface 30300
--
-- Optional DMLUI aura module. Mirrors the useful parts of Blizzard's Wrath
-- aura presentation while adding attach/detach layouts and unit-frame cleanse
-- highlighting. Installing the module does nothing until "Use DML Buffs" is
-- enabled from its settings page.

DMLBuffs = DMLBuffs or {}
local B = DMLBuffs

B.VERSION = "2.0.114"
B.ICON_SIZE = 24
B.PARTY_ICON_SIZE = 18
B.ICON_GAP = 2
B.GROUP_GAP = 3
B.MAJOR_COLUMNS = 6
B.PARTY_COLUMNS = 4
B.COMPACT_MAJOR_LIMIT = 6
B.EXPANDED_MAJOR_LIMIT = 16
B.COMPACT_PARTY_LIMIT = 4
B.EXPANDED_PARTY_LIMIT = 8
B.AURA_SCAN_LIMIT = 40
B.SCALE_MIN = 0.50
B.SCALE_MAX = 2.00
B.HOVER_LEAVE_DELAY = 0.12
B.DECURSE_BORDER_PAD = 5
B.DECURSE_BORDER_SIZE = 3

local DB
local initialized = false
local configFrame
local configControls = {}
local configRefreshing = false
local PRINT_PREFIX = "|cff66ff99DMLUI Buffs|r: "

B.displays = {}
B.movers = {}
B.hovered = {}
B.hoverPending = {}
B.highlightLayers = {}
B.debuffSeen = {}
B.blizzardAuraState = {}
B.layoutPending = false

local defaults = {
    version = 1,
    useDMLBuffs = false,
    showAnchors = true,
    locked = false,
    hideBlizzardPlayerBuffs = false,

    showPlayerAuras = true,
    detachPlayer = false,
    playerLocation = "ABOVE",
    playerScale = 1.00,

    showTargetAuras = true,
    detachTarget = false,
    targetLocation = "ABOVE",
    targetScale = 1.00,

    showTargetTargetAuras = true,
    detachTargetTarget = false,
    targetTargetLocation = "ABOVE",
    targetTargetScale = 1.00,

    showPartyAuras = true,
    partyLocation = "ABOVE",

    highlightDecurse = false,
    highlightStyle = "OVERLAY",
    decurseColors = {
        Magic = { r = 0.20, g = 0.60, b = 1.00 },
        Poison = { r = 0.10, g = 0.85, b = 0.20 },
        Disease = { r = 0.55, g = 0.65, b = 0.20 },
        Curse = { r = 0.65, g = 0.25, b = 0.85 }
    },

    positions = {
        player = { point = "CENTER", relativePoint = "CENTER", x = -360, y = 260 },
        target = { point = "CENTER", relativePoint = "CENTER", x = 360, y = 260 },
        targettarget = { point = "CENTER", relativePoint = "CENTER", x = 360, y = 105 }
    }
}

local displayDefinitions = {
    player = {
        unit = "player", label = "Player", showKey = "showPlayerAuras",
        detachKey = "detachPlayer", locationKey = "playerLocation",
        scaleKey = "playerScale", dmlKey = "player", stockFrame = "PlayerFrame"
    },
    target = {
        unit = "target", label = "Target", showKey = "showTargetAuras",
        detachKey = "detachTarget", locationKey = "targetLocation",
        scaleKey = "targetScale", dmlKey = "target", stockFrame = "TargetFrame"
    },
    targettarget = {
        unit = "targettarget", label = "Target of Target", showKey = "showTargetTargetAuras",
        detachKey = "detachTargetTarget", locationKey = "targetTargetLocation",
        scaleKey = "targetTargetScale", dmlKey = "targettarget", stockFrame = "TargetFrameToT"
    },
    party1 = { unit = "party1", label = "Party 1", showKey = "showPartyAuras", locationKey = "partyLocation", dmlKey = "party1", stockFrame = "PartyMemberFrame1", party = true },
    party2 = { unit = "party2", label = "Party 2", showKey = "showPartyAuras", locationKey = "partyLocation", dmlKey = "party2", stockFrame = "PartyMemberFrame2", party = true },
    party3 = { unit = "party3", label = "Party 3", showKey = "showPartyAuras", locationKey = "partyLocation", dmlKey = "party3", stockFrame = "PartyMemberFrame3", party = true },
    party4 = { unit = "party4", label = "Party 4", showKey = "showPartyAuras", locationKey = "partyLocation", dmlKey = "party4", stockFrame = "PartyMemberFrame4", party = true }
}

local displayOrder = { "player", "target", "targettarget", "party1", "party2", "party3", "party4" }
local movableOrder = { "player", "target", "targettarget" }
local highlightDefinitions = {
    { key = "player", unit = "player", dmlKey = "player", stockFrame = "PlayerFrame" },
    { key = "target", unit = "target", dmlKey = "target", stockFrame = "TargetFrame" },
    { key = "targettarget", unit = "targettarget", dmlKey = "targettarget", stockFrame = "TargetFrameToT" },
    { key = "focus", unit = "focus", dmlKey = "focus", stockFrame = "FocusFrame" },
    { key = "party1", unit = "party1", dmlKey = "party1", stockFrame = "PartyMemberFrame1" },
    { key = "party2", unit = "party2", dmlKey = "party2", stockFrame = "PartyMemberFrame2" },
    { key = "party3", unit = "party3", dmlKey = "party3", stockFrame = "PartyMemberFrame3" },
    { key = "party4", unit = "party4", dmlKey = "party4", stockFrame = "PartyMemberFrame4" }
}

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
    end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
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
    if value < minimum then value = minimum end
    if value > maximum then value = maximum end
    return value
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

local function NormalizeLocation(value)
    if value == "BELOW" then return "BELOW" end
    return "ABOVE"
end

local function NormalizeScale(value)
    return Clamp(value, B.SCALE_MIN, B.SCALE_MAX)
end

local function CopyDefaults(reset)
    if reset or type(DMLBuffsDB) ~= "table" then
        DMLBuffsDB = {}
    end
    DB = DMLBuffsDB

    for key, value in pairs(defaults) do
        if reset or DB[key] == nil then
            DB[key] = type(value) == "table" and CopyTable(value) or value
        end
    end

    DB.version = defaults.version
    DB.useDMLBuffs = DB.useDMLBuffs and true or false
    DB.showAnchors = DB.showAnchors ~= false
    DB.locked = DB.locked and true or false
    DB.hideBlizzardPlayerBuffs = DB.hideBlizzardPlayerBuffs and true or false

    DB.showPlayerAuras = DB.showPlayerAuras ~= false
    DB.detachPlayer = DB.detachPlayer and true or false
    DB.playerLocation = NormalizeLocation(DB.playerLocation)
    DB.playerScale = NormalizeScale(DB.playerScale)

    DB.showTargetAuras = DB.showTargetAuras ~= false
    DB.detachTarget = DB.detachTarget and true or false
    DB.targetLocation = NormalizeLocation(DB.targetLocation)
    DB.targetScale = NormalizeScale(DB.targetScale)

    DB.showTargetTargetAuras = DB.showTargetTargetAuras ~= false
    DB.detachTargetTarget = DB.detachTargetTarget and true or false
    DB.targetTargetLocation = NormalizeLocation(DB.targetTargetLocation)
    DB.targetTargetScale = NormalizeScale(DB.targetTargetScale)

    DB.showPartyAuras = DB.showPartyAuras ~= false
    DB.partyLocation = NormalizeLocation(DB.partyLocation)

    DB.highlightDecurse = DB.highlightDecurse and true or false
    if DB.highlightStyle ~= "BORDER" then DB.highlightStyle = "OVERLAY" end
    if type(DB.decurseColors) ~= "table" then DB.decurseColors = {} end
    for dispelType, fallback in pairs(defaults.decurseColors) do
        DB.decurseColors[dispelType] = NormalizeColor(DB.decurseColors[dispelType], fallback)
    end

    if type(DB.positions) ~= "table" then DB.positions = CopyTable(defaults.positions) end
    for _, key in ipairs(movableOrder) do
        if type(DB.positions[key]) ~= "table" then
            DB.positions[key] = CopyTable(defaults.positions[key])
        end
    end
end

local function IsDetached(definition)
    return definition and definition.detachKey and DB and DB[definition.detachKey] and true or false
end

local function GetDMLUnitFrame(definition)
    if not definition or not definition.dmlKey then return nil end
    if not DMLUnitFrames or not DMLUnitFrames.GetFrame or not DMLUnitFrames.IsFrameActive then return nil end
    if not DMLUnitFrames:IsFrameActive(definition.dmlKey) then return nil end
    return DMLUnitFrames:GetFrame(definition.dmlKey)
end

local function ResolveAnchorFrame(definition)
    local frame = GetDMLUnitFrame(definition)
    if frame then
        if DMLUnitFrames and DMLUnitFrames.GetAuraAnchor and definition and definition.dmlKey then
            local portraitAnchor = DMLUnitFrames:GetAuraAnchor(definition.dmlKey)
            if portraitAnchor then return portraitAnchor end
        end
        return frame
    end
    return definition and definition.stockFrame and _G[definition.stockFrame] or nil
end

local function SaveMoverPosition(key)
    local mover = B.movers[key]
    if not mover or not DB then return end
    local point, _, relativePoint, x, y = mover:GetPoint(1)
    DB.positions[key] = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = tonumber(x) or 0,
        y = tonumber(y) or 0
    }
end

local function RestoreMoverPosition(key)
    local mover = B.movers[key]
    if not mover or not DB then return end
    local pos = DB.positions[key] or defaults.positions[key]
    mover:ClearAllPoints()
    mover:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 0)
end

local function CreateMover(key, definition)
    if B.movers[key] then return B.movers[key] end
    local mover = CreateFrame("Frame", "DMLUIBuffMover_" .. key, UIParent)
    mover:SetWidth(180)
    mover:SetHeight(18)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(80)

    local handle = CreateFrame("Frame", nil, mover)
    handle:SetAllPoints(mover)
    handle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    handle:SetBackdropColor(0.05, 0.35, 0.15, 0.88)
    handle:SetBackdropBorderColor(0.3, 1.0, 0.5, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", handle, "CENTER", 0, 0)
    text:SetText("DML " .. definition.label .. " Buffs - drag")

    handle:SetScript("OnDragStart", function()
        if not DB or DB.locked then return end
        mover:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        mover:StopMovingOrSizing()
        SaveMoverPosition(key)
    end)

    mover.dmlHandle = handle
    B.movers[key] = mover
    RestoreMoverPosition(key)
    mover:Hide()
    return mover
end

local function CancelHoverCollapse(key)
    B.hoverPending[key] = nil
    if not B.hovered[key] then
        B.hovered[key] = true
        if initialized then B:RefreshDisplay(key) end
    end
end

local function ScheduleHoverCollapse(key)
    if not GetTime then
        B.hovered[key] = false
        if initialized then B:RefreshDisplay(key) end
        return
    end
    B.hoverPending[key] = GetTime() + B.HOVER_LEAVE_DELAY
end

local function SetButtonTooltip(button)
    if not GameTooltip or not button or not button.unit or not button.auraIndex then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT", 12, -18)
    if button.filter == "HELPFUL" and GameTooltip.SetUnitBuff then
        GameTooltip:SetUnitBuff(button.unit, button.auraIndex)
    elseif button.filter == "HARMFUL" and GameTooltip.SetUnitDebuff then
        GameTooltip:SetUnitDebuff(button.unit, button.auraIndex)
    end
end

local function CreateAuraButton(parent, filter)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(B.ICON_SIZE)
    button:SetHeight(B.ICON_SIZE)
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 7,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    button:SetBackdropColor(0, 0, 0, 0.9)
    button:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:Hide()
    button.cooldown = cooldown

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, 0)
    button.countText = count

    button.filter = filter
    button:SetScript("OnEnter", function(self)
        if self.displayKey then CancelHoverCollapse(self.displayKey) end
        SetButtonTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        if self.displayKey then ScheduleHoverCollapse(self.displayKey) end
    end)
    button:Hide()
    return button
end

local function CreateAuraList(parent, filter, maxButtons)
    local list = CreateFrame("Frame", nil, parent)
    list:SetWidth(1)
    list:SetHeight(1)
    list.buttons = {}
    maxButtons = tonumber(maxButtons) or B.EXPANDED_MAJOR_LIMIT
    for i = 1, maxButtons do
        list.buttons[i] = CreateAuraButton(list, filter)
    end
    return list
end

local function CreateDisplay(key)
    if B.displays[key] then return B.displays[key] end
    local definition = displayDefinitions[key]
    if not definition then return nil end

    local container = CreateFrame("Frame", "DMLUIAuraContainer_" .. key, UIParent)
    container:SetWidth(1)
    container:SetHeight(1)
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(50)
    container:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    container:SetBackdropColor(0.02, 0.02, 0.02, 0)
    container:SetBackdropBorderColor(0.25, 0.25, 0.25, 0)
    container:SetScript("OnEnter", function() CancelHoverCollapse(key) end)
    container:SetScript("OnLeave", function() ScheduleHoverCollapse(key) end)

    local maxButtons = definition.party and B.EXPANDED_PARTY_LIMIT or B.EXPANDED_MAJOR_LIMIT
    local buffs = CreateAuraList(container, "HELPFUL", maxButtons)
    local debuffs = CreateAuraList(container, "HARMFUL", maxButtons)

    local display = {
        key = key,
        definition = definition,
        container = container,
        buffs = buffs,
        debuffs = debuffs,
        currentAnchor = nil,
        currentDetached = nil,
        currentLocation = nil
    }
    B.displays[key] = display

    if definition.detachKey then
        display.mover = CreateMover(key, definition)
    end

    container:Hide()
    return display
end

local function HookHoverFrame(frame, key)
    if not frame or not frame.HookScript then return end
    frame.dmlBuffsHoverKeys = frame.dmlBuffsHoverKeys or {}
    if frame.dmlBuffsHoverKeys[key] then return end
    frame.dmlBuffsHoverKeys[key] = true
    frame:HookScript("OnEnter", function() CancelHoverCollapse(key) end)
    frame:HookScript("OnLeave", function() ScheduleHoverCollapse(key) end)
end

local function ApplyAnchorState()
    if not DB then return end
    for _, key in ipairs(movableOrder) do
        local mover = B.movers[key]
        local display = B.displays[key]
        local definition = displayDefinitions[key]
        local detached = definition and IsDetached(definition)
        if mover then
            if DB.useDMLBuffs and detached then
                mover:Show()
                if mover.dmlHandle then
                    if DB.showAnchors then mover.dmlHandle:Show() else mover.dmlHandle:Hide() end
                    mover.dmlHandle:EnableMouse(DB.showAnchors and not DB.locked)
                end
            else
                mover:Hide()
            end
        end
    end
end

local function ApplyDisplayLayout(display, force)
    if not display or not DB then return false end
    local definition = display.definition
    local detached = IsDetached(definition)
    local location = NormalizeLocation(DB[definition.locationKey])
    local anchor

    if detached then
        anchor = display.mover or CreateMover(display.key, definition)
    else
        anchor = ResolveAnchorFrame(definition)
    end

    if not anchor then
        display.container:Hide()
        return false
    end

    if force or display.currentAnchor ~= anchor or display.currentDetached ~= detached or display.currentLocation ~= location then
        display.container:SetParent(anchor)
        display.container:ClearAllPoints()
        if detached then
            display.container:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
            display.container:SetScale(NormalizeScale(DB[definition.scaleKey]))
            display.container:SetFrameStrata("HIGH")
            display.container:SetFrameLevel(anchor:GetFrameLevel() + 2)
            display.container:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
            display.container:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.80)
        else
            display.container:SetScale(1)
            if location == "ABOVE" then
                display.container:SetPoint("BOTTOM", anchor, "TOP", 0, 3)
            else
                display.container:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
            end
            if anchor.GetFrameStrata and display.container.SetFrameStrata then
                display.container:SetFrameStrata(anchor:GetFrameStrata())
            end
            display.container:SetFrameLevel((anchor.GetFrameLevel and anchor:GetFrameLevel() or 20) + 12)
            display.container:SetBackdropColor(0, 0, 0, 0)
            display.container:SetBackdropBorderColor(0, 0, 0, 0)
            -- The actual portrait attachment region does not need mouse input;
            -- expand the compact aura list when the whole unit frame is hovered.
            HookHoverFrame(GetDMLUnitFrame(definition) or anchor, display.key)
        end
        display.currentAnchor = anchor
        display.currentDetached = detached
        display.currentLocation = location
    elseif detached then
        display.container:SetScale(NormalizeScale(DB[definition.scaleKey]))
    end

    return true
end

local function ApplyAllLayouts(force)
    for _, key in ipairs(displayOrder) do
        local display = B.displays[key]
        if display then ApplyDisplayLayout(display, force) end
    end
    ApplyAnchorState()
end

local function SetCooldown(button, duration, expirationTime)
    duration = tonumber(duration) or 0
    expirationTime = tonumber(expirationTime) or 0
    if duration > 0 and expirationTime > 0 then
        local startTime = expirationTime - duration
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(button.cooldown, startTime, duration, 1)
        elseif button.cooldown.SetCooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        button.cooldown:Show()
    else
        button.cooldown:Hide()
    end
end

local function UpdateAuraButton(button, display, auraIndex, filter, icon, count, debuffType, duration, expirationTime)
    button.displayKey = display.key
    button.unit = display.definition.unit
    button.auraIndex = auraIndex
    button.filter = filter
    button.icon:SetTexture(icon)
    if tonumber(count) and tonumber(count) > 1 then
        button.countText:SetText(tostring(count))
        button.countText:Show()
    else
        button.countText:Hide()
    end

    if filter == "HARMFUL" then
        local color = DebuffTypeColor and DebuffTypeColor[debuffType or "none"] or nil
        if color then button:SetBackdropBorderColor(color.r or 1, color.g or 1, color.b or 1, 1)
        else button:SetBackdropBorderColor(0.65, 0.15, 0.15, 1) end
    else
        button:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
    SetCooldown(button, duration, expirationTime)
    button:Show()
end

local function PopulateAuraList(display, list, filter, limit)
    local unit = display.definition.unit
    local getter = filter == "HELPFUL" and UnitBuff or UnitDebuff
    if not getter then return 0 end
    local shown = 0

    for auraIndex = 1, B.AURA_SCAN_LIMIT do
        local name, rank, icon, count, debuffType, duration, expirationTime = getter(unit, auraIndex)
        if not name then break end
        shown = shown + 1
        if shown > limit or shown > #list.buttons then
            shown = shown - 1
            break
        end
        UpdateAuraButton(list.buttons[shown], display, auraIndex, filter, icon, count, debuffType, duration, expirationTime)
    end

    for i = shown + 1, #list.buttons do
        list.buttons[i]:Hide()
        list.buttons[i].auraIndex = nil
    end
    return shown
end

local function LayoutAuraList(display, list, count, location)
    if count < 1 then
        list:SetWidth(1)
        list:SetHeight(1)
        list:Hide()
        return 1, 0
    end

    list:Show()
    local party = display.definition.party
    local size = party and B.PARTY_ICON_SIZE or B.ICON_SIZE
    local columns = party and B.PARTY_COLUMNS or B.MAJOR_COLUMNS
    local gap = B.ICON_GAP
    local step = size + gap
    local rows = math.ceil(count / columns)
    local usedColumns = math.min(count, columns)
    local width = usedColumns * size + math.max(0, usedColumns - 1) * gap
    local height = rows * size + math.max(0, rows - 1) * gap
    list:SetWidth(width)
    list:SetHeight(height)

    for i = 1, count do
        local button = list.buttons[i]
        local column = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        button:ClearAllPoints()
        button:SetWidth(size)
        button:SetHeight(size)
        if location == "ABOVE" then
            button:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", column * step, row * step)
        else
            button:SetPoint("TOPLEFT", list, "TOPLEFT", column * step, -(row * step))
        end
    end
    return width, height
end

local function LayoutDisplay(display, buffCount, debuffCount)
    local location = NormalizeLocation(DB[display.definition.locationKey])
    local buffWidth, buffHeight = LayoutAuraList(display, display.buffs, buffCount, location)
    local debuffWidth, debuffHeight = LayoutAuraList(display, display.debuffs, debuffCount, location)
    local hasBuffs = buffCount > 0
    local hasDebuffs = debuffCount > 0
    local totalHeight = buffHeight + debuffHeight
    if hasBuffs and hasDebuffs then totalHeight = totalHeight + B.GROUP_GAP end
    if not hasBuffs then totalHeight = debuffHeight end
    if not hasDebuffs then totalHeight = buffHeight end
    if totalHeight < 1 then totalHeight = 1 end

    local width = math.max(buffWidth, debuffWidth, 1)
    display.container:SetWidth(width)
    display.container:SetHeight(totalHeight)
    display.buffs:ClearAllPoints()
    display.debuffs:ClearAllPoints()

    if location == "ABOVE" then
        -- Closest to the unit frame is the container bottom: put debuffs there,
        -- then stack buffs farther outward/upward.
        if hasDebuffs then
            display.debuffs:SetPoint("BOTTOM", display.container, "BOTTOM", 0, 0)
            if hasBuffs then display.buffs:SetPoint("BOTTOM", display.debuffs, "TOP", 0, B.GROUP_GAP) end
        elseif hasBuffs then
            display.buffs:SetPoint("BOTTOM", display.container, "BOTTOM", 0, 0)
        end
    else
        -- Below the frame the container top is closest, so debuffs remain the
        -- inner row and buffs continue downward/outward.
        if hasDebuffs then
            display.debuffs:SetPoint("TOP", display.container, "TOP", 0, 0)
            if hasBuffs then display.buffs:SetPoint("TOP", display.debuffs, "BOTTOM", 0, -B.GROUP_GAP) end
        elseif hasBuffs then
            display.buffs:SetPoint("TOP", display.container, "TOP", 0, 0)
        end
    end
end

function B:RefreshDisplay(key)
    local display = B.displays[key]
    if not display or not DB then return end
    local definition = display.definition

    if not DB.useDMLBuffs or not DB[definition.showKey] or not UnitExists or not UnitExists(definition.unit) then
        display.container:Hide()
        return
    end

    if not display.currentAnchor and not ApplyDisplayLayout(display, true) then
        display.container:Hide()
        return
    end

    local detached = IsDetached(definition)
    local expanded = detached or B.hovered[key]
    local limit
    if definition.party then
        limit = expanded and B.EXPANDED_PARTY_LIMIT or B.COMPACT_PARTY_LIMIT
    else
        limit = expanded and B.EXPANDED_MAJOR_LIMIT or B.COMPACT_MAJOR_LIMIT
    end

    local debuffCount = PopulateAuraList(display, display.debuffs, "HARMFUL", limit)
    local buffCount = PopulateAuraList(display, display.buffs, "HELPFUL", limit)
    LayoutDisplay(display, buffCount, debuffCount)
    display.container:Show()
end

local function HideAllDisplays()
    for _, key in ipairs(displayOrder) do
        local display = B.displays[key]
        if display then display.container:Hide() end
    end
end

local function GetStockFrameStateKey(frameName)
    return tostring(frameName or "")
end

local function CaptureStockFrameState(frameName, frame)
    local key = GetStockFrameStateKey(frameName)
    if B.blizzardAuraState[key] then return B.blizzardAuraState[key] end
    local state = {
        shown = frame.IsShown and frame:IsShown() or false,
        alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or nil
    }
    B.blizzardAuraState[key] = state
    return state
end

local function SetStockAuraFrameHidden(frameName, hidden)
    local frame = _G[frameName]
    if not frame then return end
    local state = CaptureStockFrameState(frameName, frame)
    if hidden then
        if frame.SetAlpha then frame:SetAlpha(0) end
        if frame.EnableMouse then frame:EnableMouse(false) end
        frame:Hide()
    else
        if frame.SetAlpha then frame:SetAlpha(state.alpha or 1) end
        if frame.EnableMouse and state.mouse ~= nil then frame:EnableMouse(state.mouse) end
        if state.shown then frame:Show() else frame:Hide() end
    end
end

local function ShouldHideBlizzardPlayerBuffs()
    return DB and DB.useDMLBuffs and DB.hideBlizzardPlayerBuffs
end

local function ApplyBlizzardAuraVisibility()
    local hidden = ShouldHideBlizzardPlayerBuffs()
    if hidden then
        SetStockAuraFrameHidden("BuffFrame", true)
        SetStockAuraFrameHidden("TemporaryEnchantFrame", true)
        B.blizzardHiddenApplied = true
    elseif B.blizzardHiddenApplied then
        -- Restore only when DML previously hid the stock aura frames. When DML
        -- is not hiding them, leave Blizzard completely in charge of whether
        -- they should currently be shown.
        SetStockAuraFrameHidden("BuffFrame", false)
        SetStockAuraFrameHidden("TemporaryEnchantFrame", false)
        B.blizzardAuraState = {}
        B.blizzardHiddenApplied = false
        -- Let Blizzard immediately recompute its normal presentation instead
        -- of relying on a stale pre-hide shown/hidden snapshot.
        if type(BuffFrame_Update) == "function" then pcall(BuffFrame_Update) end
        if type(TemporaryEnchantFrame_Update) == "function" then pcall(TemporaryEnchantFrame_Update) end
    end
end

local function InstallBlizzardBuffHooks()
    if B.blizzardBuffHooksInstalled then return end
    B.blizzardBuffHooksInstalled = true
    if hooksecurefunc and type(BuffFrame_Update) == "function" then
        hooksecurefunc("BuffFrame_Update", function()
            if ShouldHideBlizzardPlayerBuffs() then
                if BuffFrame then BuffFrame:Hide() end
                if TemporaryEnchantFrame then TemporaryEnchantFrame:Hide() end
            end
        end)
    end
    if hooksecurefunc and type(TemporaryEnchantFrame_Update) == "function" then
        hooksecurefunc("TemporaryEnchantFrame_Update", function()
            if ShouldHideBlizzardPlayerBuffs() and TemporaryEnchantFrame then
                TemporaryEnchantFrame:Hide()
            end
        end)
    end
end

local function GetHighlightLayer(frame)
    if not frame then return nil end
    local layer = B.highlightLayers[frame]
    if layer then return layer end
    if InCombat() then return nil end

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 20) + 40)
    holder:EnableMouse(false)

    local overlay = holder:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints(holder)
    overlay:SetTexture(1, 1, 1, 1)
    overlay:Hide()

    local border = {}
    border.top = holder:CreateTexture(nil, "OVERLAY")
    border.bottom = holder:CreateTexture(nil, "OVERLAY")
    border.left = holder:CreateTexture(nil, "OVERLAY")
    border.right = holder:CreateTexture(nil, "OVERLAY")
    for _, texture in pairs(border) do
        texture:SetTexture(1, 1, 1, 1)
        texture:Hide()
    end

    local pad = B.DECURSE_BORDER_PAD
    local size = B.DECURSE_BORDER_SIZE
    border.top:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", -pad, pad)
    border.top:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", pad, pad)
    border.top:SetHeight(size)
    border.bottom:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", -pad, -pad)
    border.bottom:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", pad, -pad)
    border.bottom:SetHeight(size)
    border.left:SetPoint("TOPRIGHT", holder, "TOPLEFT", -pad, pad)
    border.left:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", -pad, -pad)
    border.left:SetWidth(size)
    border.right:SetPoint("TOPLEFT", holder, "TOPRIGHT", pad, pad)
    border.right:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", pad, -pad)
    border.right:SetWidth(size)

    layer = { holder = holder, overlay = overlay, border = border }
    B.highlightLayers[frame] = layer
    return layer
end

local function HideHighlightLayer(layer)
    if not layer then return end
    if layer.overlay then layer.overlay:Hide() end
    if layer.border then
        for _, texture in pairs(layer.border) do texture:Hide() end
    end
end

local function HideAllHighlights()
    for _, layer in pairs(B.highlightLayers) do HideHighlightLayer(layer) end
end

local function ResolveHighlightFrame(definition)
    if DMLUnitFrames and DMLUnitFrames.GetFrame and DMLUnitFrames.IsFrameActive and definition.dmlKey and DMLUnitFrames:IsFrameActive(definition.dmlKey) then
        local frame = DMLUnitFrames:GetFrame(definition.dmlKey)
        if frame then return frame end
    end
    return definition.stockFrame and _G[definition.stockFrame] or nil
end

local function PrepareHighlightLayers()
    if InCombat() then return end
    for _, definition in ipairs(highlightDefinitions) do
        local frame = ResolveHighlightFrame(definition)
        if frame then GetHighlightLayer(frame) end
    end
end

local function IsFriendlyPlayerUnit(unit)
    if not UnitExists or not UnitExists(unit) then return false end
    if not UnitIsPlayer or not UnitIsPlayer(unit) then return false end
    if unit == "player" then return true end
    if UnitCanAssist then return UnitCanAssist("player", unit) and true or false end
    if UnitCanAttack then return not UnitCanAttack("player", unit) end
    return true
end

local function AuraSeenKey(name, spellId, caster, expirationTime)
    return tostring(spellId or name or "") .. "|" .. tostring(caster or "") .. "|" .. tostring(expirationTime or 0)
end

local function FindMostRecentDispelDebuff(unit)
    if not UnitDebuff then return nil end
    local now = GetTime and GetTime() or 0
    local oldSeen = B.debuffSeen[unit] or {}
    local newSeen = {}
    local bestType, bestTime, bestIndex

    for index = 1, B.AURA_SCAN_LIMIT do
        local name, rank, icon, count, debuffType, duration, expirationTime, caster, isStealable, shouldConsolidate, spellId = UnitDebuff(unit, index)
        if not name then break end
        if debuffType and defaults.decurseColors[debuffType] then
            local key = AuraSeenKey(name, spellId, caster, expirationTime)
            local seenAt = oldSeen[key]
            if not seenAt then seenAt = now - (index * 0.000001) end
            newSeen[key] = seenAt

            local appliedAt = seenAt
            duration = tonumber(duration) or 0
            expirationTime = tonumber(expirationTime) or 0
            if duration > 0 and expirationTime > 0 then
                appliedAt = expirationTime - duration
            end

            if not bestTime or appliedAt > bestTime or (appliedAt == bestTime and index < (bestIndex or 999)) then
                bestType = debuffType
                bestTime = appliedAt
                bestIndex = index
            end
        end
    end

    B.debuffSeen[unit] = newSeen
    return bestType
end

local function ShowHighlight(frame, dispelType)
    local layer = GetHighlightLayer(frame)
    if not layer then return end
    local fallback = defaults.decurseColors[dispelType]
    local color = NormalizeColor(DB.decurseColors[dispelType], fallback)

    if DB.highlightStyle == "BORDER" then
        layer.overlay:Hide()
        for _, texture in pairs(layer.border) do
            texture:SetVertexColor(color.r, color.g, color.b, 1)
            texture:Show()
        end
    else
        for _, texture in pairs(layer.border) do texture:Hide() end
        layer.overlay:SetVertexColor(color.r, color.g, color.b, 0.27)
        layer.overlay:Show()
    end
end

local function RefreshHighlights()
    HideAllHighlights()
    if not DB or not DB.useDMLBuffs or not DB.highlightDecurse then return end

    for _, definition in ipairs(highlightDefinitions) do
        if IsFriendlyPlayerUnit(definition.unit) then
            local dispelType = FindMostRecentDispelDebuff(definition.unit)
            if dispelType then
                local frame = ResolveHighlightFrame(definition)
                if frame then ShowHighlight(frame, dispelType) end
            else
                B.debuffSeen[definition.unit] = {}
            end
        else
            B.debuffSeen[definition.unit] = {}
        end
    end
end

function B:RefreshAll(forceLayout)
    if not initialized or not DB then return end
    if forceLayout then ApplyAllLayouts(true) end
    if not DB.useDMLBuffs then
        HideAllDisplays()
        HideAllHighlights()
        ApplyAnchorState()
        ApplyBlizzardAuraVisibility()
        return
    end
    for _, key in ipairs(displayOrder) do B:RefreshDisplay(key) end
    RefreshHighlights()
    ApplyAnchorState()
    ApplyBlizzardAuraVisibility()
end

function B:OnUnitFramesLayoutChanged()
    if not initialized then return end
    if InCombat() then
        B.layoutPending = true
        return
    end
    B.layoutPending = false
    ApplyAllLayouts(true)
    PrepareHighlightLayers()
    B:RefreshAll(false)
end

local function ResetPositions()
    if InCombat() then
        Print("Buff frame positions cannot be reset during combat.")
        return
    end
    DB.positions = CopyTable(defaults.positions)
    for _, key in ipairs(movableOrder) do RestoreMoverPosition(key) end
    Print("Detached buff frame positions reset.")
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
        widget.dmlLabel:SetTextColor(enabled and 1 or 0.5, enabled and 0.82 or 0.5, enabled and 0 or 0.5, 1)
    end
end

local function CreateLocationDropDown(name, parent, x, y, dbKey)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText("Display location:")
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 90, y + 16)
    UIDropDownMenu_SetWidth(dropdown, 100)
    dropdown.dmlIsDropDown = true
    dropdown.dmlLabel = label
    UIDropDownMenu_Initialize(dropdown, function()
        local options = { { value = "ABOVE", text = "Above" }, { value = "BELOW", text = "Below" } }
        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = DB[dbKey] == option.value
            info.func = function(button)
                DB[dbKey] = button.value
                UIDropDownMenu_SetSelectedValue(dropdown, button.value)
                UIDropDownMenu_SetText(dropdown, button.value == "BELOW" and "Below" or "Above")
                if initialized and not InCombat() then
                    ApplyAllLayouts(true)
                    B:RefreshAll(false)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return dropdown
end

local function CreateStyleDropDown(parent, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText("Highlight style:")
    local dropdown = CreateFrame("Frame", "DMLUIBuffsHighlightStyleDropDown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 88, y + 16)
    UIDropDownMenu_SetWidth(dropdown, 100)
    dropdown.dmlIsDropDown = true
    dropdown.dmlLabel = label
    UIDropDownMenu_Initialize(dropdown, function()
        local options = { { value = "OVERLAY", text = "Overlay" }, { value = "BORDER", text = "Border" } }
        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = DB.highlightStyle == option.value
            info.func = function(button)
                DB.highlightStyle = button.value
                UIDropDownMenu_SetSelectedValue(dropdown, button.value)
                UIDropDownMenu_SetText(dropdown, button.value == "BORDER" and "Border" or "Overlay")
                RefreshHighlights()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return dropdown
end

local function CreateScaleSlider(parent, name, x, y, dbKey, displayKey)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(160)
    slider:SetHeight(16)
    slider:SetMinMaxValues(B.SCALE_MIN, B.SCALE_MAX)
    slider:SetValueStep(0.05)
    _G[slider:GetName() .. "Low"]:SetText("0.50")
    _G[slider:GetName() .. "High"]:SetText("2.00")
    _G[slider:GetName() .. "Text"]:SetText("Detached aura scale")
    slider:SetScript("OnValueChanged", function(_, value)
        if configRefreshing or not DB then return end
        DB[dbKey] = NormalizeScale(value)
        local display = B.displays[displayKey]
        if initialized and display and IsDetached(display.definition) and not InCombat() then
            ApplyDisplayLayout(display, true)
            B:RefreshDisplay(displayKey)
        end
    end)
    return slider
end

local function RefreshColorSwatches()
    if not DB then return end
    for dispelType, fallback in pairs(defaults.decurseColors) do
        local swatch = configControls["color_" .. dispelType]
        local color = NormalizeColor(DB.decurseColors[dispelType], fallback)
        if swatch then swatch:SetBackdropColor(color.r, color.g, color.b, 1) end
    end
end

local function OpenDecurseColorPicker(dispelType)
    if not ColorPickerFrame or not DB then return end
    local fallback = defaults.decurseColors[dispelType]
    local current = NormalizeColor(DB.decurseColors[dispelType], fallback)
    local previous = { r = current.r, g = current.g, b = current.b }
    local function ApplyColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        DB.decurseColors[dispelType] = NormalizeColor({ r = r, g = g, b = b }, fallback)
        RefreshColorSwatches()
        RefreshHighlights()
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.func = ApplyColor
    ColorPickerFrame.cancelFunc = function()
        DB.decurseColors[dispelType] = previous
        RefreshColorSwatches()
        RefreshHighlights()
    end
    ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)
    if ShowUIPanel then ShowUIPanel(ColorPickerFrame) else ColorPickerFrame:Show() end
end

local function CreateColorRow(parent, dispelType, labelText, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(labelText)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetWidth(28)
    swatch:SetHeight(20)
    swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 105, y + 4)
    swatch:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    swatch:SetScript("OnClick", function() OpenDecurseColorPicker(dispelType) end)
    swatch.dmlLabel = label
    configControls["color_" .. dispelType] = swatch
    return swatch
end

local RefreshControlEnableState

local function SelectAttachmentMode(attachKey, detachKey, detached)
    local attach = configControls[attachKey]
    local detach = configControls[detachKey]
    if attach then attach:SetChecked(not detached and 1 or nil) end
    if detach then detach:SetChecked(detached and 1 or nil) end
    RefreshControlEnableState()
end

RefreshControlEnableState = function()
    if not configFrame or not DB then return end
    local enabled = configControls.useDMLBuffs:GetChecked() and true or false
    local playerShown = configControls.showPlayerAuras:GetChecked() and true or false
    local targetShown = configControls.showTargetAuras:GetChecked() and true or false
    local totShown = configControls.showTargetTargetAuras:GetChecked() and true or false
    local playerDetached = configControls.detachPlayer:GetChecked() and true or false
    local targetDetached = configControls.detachTarget:GetChecked() and true or false
    local totDetached = configControls.detachTargetTarget:GetChecked() and true or false
    local decurse = configControls.highlightDecurse:GetChecked() and true or false

    SetWidgetEnabled(configControls.showAnchors, enabled)
    SetWidgetEnabled(configControls.locked, enabled)
    SetWidgetEnabled(configControls.hideBlizzardPlayerBuffs, enabled)
    SetWidgetEnabled(configControls.showPlayerAuras, enabled)
    SetWidgetEnabled(configControls.attachPlayer, enabled and playerShown)
    SetWidgetEnabled(configControls.detachPlayer, enabled and playerShown)
    SetWidgetEnabled(configControls.playerLocation, enabled and playerShown and not playerDetached)
    SetWidgetEnabled(configControls.playerScale, enabled and playerShown and playerDetached)
    SetWidgetEnabled(configControls.showTargetAuras, enabled)
    SetWidgetEnabled(configControls.attachTarget, enabled and targetShown)
    SetWidgetEnabled(configControls.detachTarget, enabled and targetShown)
    SetWidgetEnabled(configControls.targetLocation, enabled and targetShown and not targetDetached)
    SetWidgetEnabled(configControls.targetScale, enabled and targetShown and targetDetached)
    SetWidgetEnabled(configControls.showTargetTargetAuras, enabled)
    SetWidgetEnabled(configControls.attachTargetTarget, enabled and totShown)
    SetWidgetEnabled(configControls.detachTargetTarget, enabled and totShown)
    SetWidgetEnabled(configControls.targetTargetLocation, enabled and totShown and not totDetached)
    SetWidgetEnabled(configControls.targetTargetScale, enabled and totShown and totDetached)
    SetWidgetEnabled(configControls.showPartyAuras, enabled)
    SetWidgetEnabled(configControls.partyLocation, enabled)
    SetWidgetEnabled(configControls.highlightDecurse, enabled)
    SetWidgetEnabled(configControls.highlightStyle, enabled and decurse)
    for dispelType in pairs(defaults.decurseColors) do
        SetWidgetEnabled(configControls["color_" .. dispelType], enabled and decurse)
    end
end

local function RefreshConfig()
    if not configFrame or not DB then return end
    configRefreshing = true
    configControls.useDMLBuffs:SetChecked(DB.useDMLBuffs and 1 or nil)
    configControls.showAnchors:SetChecked(DB.showAnchors and 1 or nil)
    configControls.locked:SetChecked(DB.locked and 1 or nil)
    configControls.hideBlizzardPlayerBuffs:SetChecked(DB.hideBlizzardPlayerBuffs and 1 or nil)

    configControls.showPlayerAuras:SetChecked(DB.showPlayerAuras and 1 or nil)
    configControls.attachPlayer:SetChecked(not DB.detachPlayer and 1 or nil)
    configControls.detachPlayer:SetChecked(DB.detachPlayer and 1 or nil)
    UIDropDownMenu_SetSelectedValue(configControls.playerLocation, DB.playerLocation)
    UIDropDownMenu_SetText(configControls.playerLocation, DB.playerLocation == "BELOW" and "Below" or "Above")
    configControls.playerScale:SetValue(DB.playerScale)

    configControls.showTargetAuras:SetChecked(DB.showTargetAuras and 1 or nil)
    configControls.attachTarget:SetChecked(not DB.detachTarget and 1 or nil)
    configControls.detachTarget:SetChecked(DB.detachTarget and 1 or nil)
    UIDropDownMenu_SetSelectedValue(configControls.targetLocation, DB.targetLocation)
    UIDropDownMenu_SetText(configControls.targetLocation, DB.targetLocation == "BELOW" and "Below" or "Above")
    configControls.targetScale:SetValue(DB.targetScale)

    configControls.showTargetTargetAuras:SetChecked(DB.showTargetTargetAuras and 1 or nil)
    configControls.attachTargetTarget:SetChecked(not DB.detachTargetTarget and 1 or nil)
    configControls.detachTargetTarget:SetChecked(DB.detachTargetTarget and 1 or nil)
    UIDropDownMenu_SetSelectedValue(configControls.targetTargetLocation, DB.targetTargetLocation)
    UIDropDownMenu_SetText(configControls.targetTargetLocation, DB.targetTargetLocation == "BELOW" and "Below" or "Above")
    configControls.targetTargetScale:SetValue(DB.targetTargetScale)

    configControls.showPartyAuras:SetChecked(DB.showPartyAuras and 1 or nil)
    UIDropDownMenu_SetSelectedValue(configControls.partyLocation, DB.partyLocation)
    UIDropDownMenu_SetText(configControls.partyLocation, DB.partyLocation == "BELOW" and "Below" or "Above")

    configControls.highlightDecurse:SetChecked(DB.highlightDecurse and 1 or nil)
    UIDropDownMenu_SetSelectedValue(configControls.highlightStyle, DB.highlightStyle)
    UIDropDownMenu_SetText(configControls.highlightStyle, DB.highlightStyle == "BORDER" and "Border" or "Overlay")
    RefreshColorSwatches()
    configRefreshing = false
    RefreshControlEnableState()
end

local function ApplyConfig()
    if InCombat() then
        Print("Buff configuration cannot be changed during combat.")
        return false
    end

    DB.useDMLBuffs = configControls.useDMLBuffs:GetChecked() and true or false
    DB.showAnchors = configControls.showAnchors:GetChecked() and true or false
    DB.locked = configControls.locked:GetChecked() and true or false
    DB.hideBlizzardPlayerBuffs = configControls.hideBlizzardPlayerBuffs:GetChecked() and true or false

    DB.showPlayerAuras = configControls.showPlayerAuras:GetChecked() and true or false
    DB.detachPlayer = configControls.detachPlayer:GetChecked() and true or false
    DB.playerScale = NormalizeScale(configControls.playerScale:GetValue())

    DB.showTargetAuras = configControls.showTargetAuras:GetChecked() and true or false
    DB.detachTarget = configControls.detachTarget:GetChecked() and true or false
    DB.targetScale = NormalizeScale(configControls.targetScale:GetValue())

    DB.showTargetTargetAuras = configControls.showTargetTargetAuras:GetChecked() and true or false
    DB.detachTargetTarget = configControls.detachTargetTarget:GetChecked() and true or false
    DB.targetTargetScale = NormalizeScale(configControls.targetTargetScale:GetValue())

    DB.showPartyAuras = configControls.showPartyAuras:GetChecked() and true or false
    DB.highlightDecurse = configControls.highlightDecurse:GetChecked() and true or false

    ApplyAllLayouts(true)
    B:RefreshAll(false)
    RefreshConfig()
    Print("Buff settings applied.")
    return true
end

local function ResetSettings()
    if InCombat() then
        Print("Buff settings cannot be reset during combat.")
        return
    end
    CopyDefaults(true)
    for _, key in ipairs(movableOrder) do RestoreMoverPosition(key) end
    ApplyAllLayouts(true)
    B:RefreshAll(false)
    RefreshConfig()
    Print("Buff settings reset to defaults.")
end

local function CreateConfigFrame()
    if configFrame then return end
    configFrame = CreateFrame("Frame", "DMLUIBuffsConfigFrame", UIParent)
    configFrame:SetWidth(930)
    configFrame:SetHeight(760)
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
    title:SetText("DMLUI - Buffs")
    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    -- Column 1: general/player.
    local general = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    general:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -58)
    general:SetText("General")
    local use = CreateCheckField(configFrame, "useDMLBuffs", "Use DML Buffs", 40, -78)
    local showAnchors = CreateCheckField(configFrame, "showAnchors", "Show anchors", 40, -108)
    local locked = CreateCheckField(configFrame, "locked", "Lock aura frames", 40, -138)
    CreateCheckField(configFrame, "hideBlizzardPlayerBuffs", "Hide Blizzard player buffs", 40, -168)
    use:SetScript("OnClick", RefreshControlEnableState)
    showAnchors:SetScript("OnClick", RefreshControlEnableState)
    locked:SetScript("OnClick", RefreshControlEnableState)

    local playerHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerHeader:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, -220)
    playerHeader:SetText("Player")
    local showPlayer = CreateCheckField(configFrame, "showPlayerAuras", "Show player buffs/debuffs", 40, -242)
    local attachPlayer = CreateCheckField(configFrame, "attachPlayer", "Attach player buffs/debuffs to portrait", 40, -272)
    local detachPlayer = CreateCheckField(configFrame, "detachPlayer", "Detach player buffs/debuffs", 40, -302)
    showPlayer:SetScript("OnClick", RefreshControlEnableState)
    attachPlayer:SetScript("OnClick", function() SelectAttachmentMode("attachPlayer", "detachPlayer", false) end)
    detachPlayer:SetScript("OnClick", function() SelectAttachmentMode("attachPlayer", "detachPlayer", true) end)
    configControls.playerLocation = CreateLocationDropDown("DMLUIBuffsPlayerLocationDropDown", configFrame, 40, -345, "playerLocation")
    configControls.playerScale = CreateScaleSlider(configFrame, "DMLUIBuffsPlayerScaleSlider", 48, -402, "playerScale", "player")

    local mouseNote = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mouseNote:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -450)
    mouseNote:SetWidth(245)
    mouseNote:SetJustifyH("LEFT")
    mouseNote:SetText("Attached auras stay compact; mouse over the unit frame or aura icons to reveal more. Detached panels show the expanded aura set.")

    -- Column 2: target / target-of-target.
    local targetHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetHeader:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 330, -58)
    targetHeader:SetText("Target")
    local showTarget = CreateCheckField(configFrame, "showTargetAuras", "Show target buffs/debuffs", 336, -80)
    local attachTarget = CreateCheckField(configFrame, "attachTarget", "Attach target buffs/debuffs to portrait", 336, -110)
    local detachTarget = CreateCheckField(configFrame, "detachTarget", "Detach target buffs/debuffs", 336, -140)
    showTarget:SetScript("OnClick", RefreshControlEnableState)
    attachTarget:SetScript("OnClick", function() SelectAttachmentMode("attachTarget", "detachTarget", false) end)
    detachTarget:SetScript("OnClick", function() SelectAttachmentMode("attachTarget", "detachTarget", true) end)
    configControls.targetLocation = CreateLocationDropDown("DMLUIBuffsTargetLocationDropDown", configFrame, 336, -183, "targetLocation")
    configControls.targetScale = CreateScaleSlider(configFrame, "DMLUIBuffsTargetScaleSlider", 344, -240, "targetScale", "target")

    local totHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totHeader:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 330, -330)
    totHeader:SetText("Target of Target")
    local showTot = CreateCheckField(configFrame, "showTargetTargetAuras", "Show target-of-target buffs/debuffs", 336, -352)
    local attachTot = CreateCheckField(configFrame, "attachTargetTarget", "Attach target-of-target buffs/debuffs to portrait", 336, -382)
    local detachTot = CreateCheckField(configFrame, "detachTargetTarget", "Detach target-of-target buffs/debuffs", 336, -412)
    showTot:SetScript("OnClick", RefreshControlEnableState)
    attachTot:SetScript("OnClick", function() SelectAttachmentMode("attachTargetTarget", "detachTargetTarget", false) end)
    detachTot:SetScript("OnClick", function() SelectAttachmentMode("attachTargetTarget", "detachTargetTarget", true) end)
    configControls.targetTargetLocation = CreateLocationDropDown("DMLUIBuffsTargetTargetLocationDropDown", configFrame, 336, -455, "targetTargetLocation")
    configControls.targetTargetScale = CreateScaleSlider(configFrame, "DMLUIBuffsTargetTargetScaleSlider", 344, -512, "targetTargetScale", "targettarget")

    -- Column 3: party + cleanse highlighting.
    local partyHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyHeader:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 630, -58)
    partyHeader:SetText("Party")
    CreateCheckField(configFrame, "showPartyAuras", "Show party buffs/debuffs", 636, -80)
    configControls.partyLocation = CreateLocationDropDown("DMLUIBuffsPartyLocationDropDown", configFrame, 636, -123, "partyLocation")

    local partyNote = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    partyNote:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 636, -175)
    partyNote:SetWidth(245)
    partyNote:SetJustifyH("LEFT")
    partyNote:SetText("Party auras use compact Blizzard-style icons. Mouse over a party frame to expand the visible aura set.")

    local cleanseHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cleanseHeader:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 630, -244)
    cleanseHeader:SetText("Decurse / cleanse highlighting")
    local highlight = CreateCheckField(configFrame, "highlightDecurse", "Highlight player unit frames for decurse", 636, -266)
    highlight:SetScript("OnClick", RefreshControlEnableState)
    configControls.highlightStyle = CreateStyleDropDown(configFrame, 636, -309)

    CreateColorRow(configFrame, "Magic", "Magic", 646, -368)
    CreateColorRow(configFrame, "Poison", "Poison", 646, -402)
    CreateColorRow(configFrame, "Disease", "Disease", 646, -436)
    CreateColorRow(configFrame, "Curse", "Curse", 646, -470)

    local cleanseNote = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cleanseNote:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 636, -520)
    cleanseNote:SetWidth(245)
    cleanseNote:SetJustifyH("LEFT")
    cleanseNote:SetText("If multiple cleanseable effects are present, the most recently applied effect controls the highlight color. Border mode is drawn outside the frame separately from DML aggro highlighting.")

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(80)
    apply:SetHeight(24)
    apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 270, 28)
    apply:SetText("Apply")
    apply:SetScript("OnClick", ApplyConfig)

    local resetPos = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetPos:SetWidth(115)
    resetPos:SetHeight(24)
    resetPos:SetPoint("LEFT", apply, "RIGHT", 8, 0)
    resetPos:SetText("Reset Positions")
    resetPos:SetScript("OnClick", ResetPositions)

    local resetSettings = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetSettings:SetWidth(110)
    resetSettings:SetHeight(24)
    resetSettings:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)
    resetSettings:SetText("Reset Settings")
    resetSettings:SetScript("OnClick", ResetSettings)

    local closeBottom = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    closeBottom:SetWidth(75)
    closeBottom:SetHeight(24)
    closeBottom:SetPoint("LEFT", resetSettings, "RIGHT", 8, 0)
    closeBottom:SetText("Close")
    closeBottom:SetScript("OnClick", function() configFrame:Hide() end)

    table.insert(UISpecialFrames, "DMLUIBuffsConfigFrame")
    configFrame:Hide()
end

function B:OpenConfig()
    if not configFrame then CreateConfigFrame() end
    RefreshConfig()
    configFrame:Show()
    return true
end

local function RegisterWithCore()
    if DMLUI and DMLUI.RegisterModule then
        DMLUI:RegisterModule("Buffs", {
            name = "Buffs",
            version = B.VERSION,
            openConfig = function() return B:OpenConfig() end
        })
    end
end

local function RegisterSlashCommand()
    SLASH_DMLBUFFS1 = "/dmlbuffs"
    SlashCmdList["DMLBUFFS"] = function() B:OpenConfig() end
end

local function Initialize()
    if initialized then return end
    CopyDefaults(false)
    for _, key in ipairs(displayOrder) do CreateDisplay(key) end
    CreateConfigFrame()
    InstallBlizzardBuffHooks()
    ApplyAllLayouts(true)
    PrepareHighlightLayers()
    initialized = true
    RegisterWithCore()
    RegisterSlashCommand()
    B:RefreshAll(false)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("UNIT_FACTION")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "DMLBuffs" then
            Initialize()
        elseif arg1 == "DMLUnitFrames" and initialized then
            B:OnUnitFramesLayoutChanged()
        end
        return
    end
    if not initialized then return end

    if event == "PLAYER_ENTERING_WORLD" then
        ApplyAllLayouts(true)
        PrepareHighlightLayers()
        B:RefreshAll(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if B.layoutPending then B:OnUnitFramesLayoutChanged() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        B:RefreshDisplay("target")
        B:RefreshDisplay("targettarget")
        RefreshHighlights()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        RefreshHighlights()
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
        for i = 1, 4 do B:RefreshDisplay("party" .. i) end
        RefreshHighlights()
    elseif event == "UNIT_TARGET" and arg1 == "target" then
        B:RefreshDisplay("targettarget")
        RefreshHighlights()
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then B:RefreshDisplay("player")
        elseif arg1 == "target" then B:RefreshDisplay("target")
        elseif arg1 == "targettarget" then B:RefreshDisplay("targettarget")
        elseif arg1 then
            for i = 1, 4 do
                if arg1 == "party" .. i then B:RefreshDisplay("party" .. i); break end
            end
        end
        RefreshHighlights()
    elseif event == "UNIT_FACTION" then
        RefreshHighlights()
    end
end)

eventFrame:SetScript("OnUpdate", function()
    if not initialized or not next(B.hoverPending) or not GetTime then return end
    local now = GetTime()
    local expired = {}
    for key, deadline in pairs(B.hoverPending) do
        if now >= deadline then expired[#expired + 1] = key end
    end
    for _, key in ipairs(expired) do
        B.hoverPending[key] = nil
        if B.hovered[key] then
            B.hovered[key] = false
            B:RefreshDisplay(key)
        end
    end
end)
