-- DML Cooldown Bar
-- World of Warcraft 3.3.5a / Interface 30300
--
-- Receives server messages in this form:
--   DMLCD|START|spellId|cooldownMs|castToken|spellName[|rank|customText|family]
--   DMLCD|READY|spellId|0|castToken|spellName[|rank|customText|family]
--   DMLCD|LEARN|spellId|0|0|spellName[|rank|customText|family]
--   DMLCD|META|spellId|0|0|spellName[|rank|customText|family]
--   DMLCD|COOLDOWN|spellId|cooldownMs
--   DMLCD|RESET|spellId
--   DMLCD|BONUS|spellId|bonusDamage
--   DMLCD|MANA|spellId|extraManaCost
--
-- The addon never casts automatically. Assigned buttons use Blizzard's
-- SecureActionButtonTemplate and only cast in response to a hardware click.

DMLCooldownBar = DMLCooldownBar or {}
local DMLCD = DMLCooldownBar

-- Server-supplied scaling values are intentionally session-cached.
-- The authoritative scaling script resends them on login, level changes, or
-- learning the spell. No OnUpdate polling or combat-log scanning is used.
DMLCD.scalingBonusDamage = {}
DMLCD.scalingManaCost = {}

-- Item information is session-cached so assigned consumables do not repeatedly
-- re-query the 3.3.5 client item cache during BAG_UPDATE and Bagnon refreshes.
-- Failed lookups use a short retry delay instead of immediately requesting the
-- same item again on every bag event.
DMLCD.itemInfoCache = DMLCD.itemInfoCache or {}
DMLCD.itemInfoRetryAt = DMLCD.itemInfoRetryAt or {}
DMLCD.itemIconFallbackCache = DMLCD.itemIconFallbackCache or {}
DMLCD.ITEM_INFO_RETRY_DELAY = 5

local ADDON_NAME = "DMLCooldownBar"
local ADDON_VERSION = "2.0.80"
local CHAT_PREFIX = "DMLCD|"
local PRINT_PREFIX = "|cff66ff99DML Cooldown Bar|r: "
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local DB

-- Optional user-editable custom item definitions are loaded from
-- DMLCustomItems.lua before this file. Each entry may provide a name and
-- Blizzard icon texture path for an item ID that the unpatched client cannot
-- resolve normally.
local function GetCustomItemDefinitions()
    if type(DMLCooldownBarCustomItems) == "table" then
        return DMLCooldownBarCustomItems
    end
    return {}
end

-- Optional user-editable spell metadata is loaded from DMLCustomSpells.lua.
-- Server LEARN/META messages may add per-character metadata at runtime.
function DMLCD.GetCustomSpellDefinitions()
    if type(DMLCooldownBarCustomSpells) == "table" then
        return DMLCooldownBarCustomSpells
    end
    return {}
end

function DMLCD:IsBagnonCompatibilityEnabled()
    if DB then
        return DB.bagnonCompatibility ~= false
    end
    if type(DMLCooldownBarDB) == "table" then
        return DMLCooldownBarDB.bagnonCompatibility ~= false
    end
    return true
end
local MAX_BUTTONS = 48
local MAX_BARS = 5
local MAX_TOTAL_BUTTONS = MAX_BUTTONS * MAX_BARS

-- The bar frame has six pixels of padding around its buttons. Allowing the
-- frame to extend by the same amount lets the actual button edge sit flush
-- with the bottom or side of the screen while the drag handle remains safe.
local BAR_PADDING = 6
local BAR_EDGE_OVERHANG = 6
local BAR_DRAG_HANDLE_HEIGHT = 18
local BAR_DRAG_HANDLE_GAP = 2

local defaults = {
    version = 22,
    locked = false,
    shown = true,
    barCount = 1,
    buttonCount = 12,
    rows = 2,
    columns = 6,
    buttonSize = 36,
    -- Spacing is the edge-to-edge gap between button frames. Zero means
    -- neighboring button borders touch.
    spacingX = 0,
    spacingY = 0,
    background = true,
    showSlotNumbers = true,
    autoAssign = true,
    clickFallback = true,
    nativeCooldowns = true,
    resourceFade = true,
    rangeFinder = "OFF",
    simpleTooltips = false,
    bagnonCompatibility = true,
    showMessages = false,
    showReadyMessages = false,
    debugMessages = false,
    blizzardBarMode = "SHOW",
    hideGryphons = false,
    useDMLAuraBar = false,
    useDMLPetBar = false,
    useBar1AsStanceBar = false,
    showAnchors = true,
    barLockKey = "SHIFT",
    showMinimapButton = true,
    minimapAngle = 225,
    fallbackDelay = 0.75,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0
}

local bar
local dragHandle
local bars = {}
local dragHandles = {}
local buttons = {}
local updateFrame
local initialized = false
local updateElapsed = 0
local pendingFallbacks = {}
local pendingSecureRefresh = false
local pendingBindingRefresh = false
local chatFilterInstalled = false
local configFrame
local configControls = {}
local keybindOwner
local keybindPrompt
local keybindCapture
local keybindMode = false
local keybindHoverIndex
local keybindWorking = {}
local keybindRestoreConfig = false
local keybindRestoreBarShown = true
local minimapButton
local activeAssignmentDrag
local pendingBlizzardBarRefresh = false
local blizzardBarRefreshDue
local blizzardElementStates = {}
local globalDB
local pendingProfileApply
local knownSpellbookSpells = {}
local spellbookSnapshotReady = false
local pendingCombatAssignments = {}
local pendingLearnedSpells = {}

local ApplySavedKeybinds
local RefreshKeybindLabels
local RefreshKeybindOverlays
local StartKeybindMode
local FinishKeybindMode
local ShowConfigWindow
local RefreshConfigFields
local SetShown
local UpdateMinimapButtonVisibility
local ApplyBlizzardBarSettings
local RefreshProfileControls
local SaveCharacterLayoutSnapshot
local RequestProfileApply

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
end

-- Debug messages describe automatic/internal activity such as drag operations,
-- auto-assignment, and addon startup. User-requested slash-command feedback,
-- config confirmations, keybind-mode prompts, and explicit cooldown/ready
-- announcements continue to use Print and are not suppressed by this setting.
local function DebugPrint(message)
    if DB and DB.debugMessages then
        Print(message)
    end
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value)
    if not value then
        return nil
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function RoundUp(value)
    return math.ceil(value - 0.000001)
end

-- Reusable scratch tables prevent the 0.1-second visual update loop from
-- allocating fresh garbage continuously while the addon is otherwise idle.
DMLCD.updateExpiredCooldowns = DMLCD.updateExpiredCooldowns or {}
DMLCD.updateResourceCache = DMLCD.updateResourceCache or {}
DMLCD.updateRangeCache = DMLCD.updateRangeCache or {}

function DMLCD.ClearScratchTable(tbl)
    local key
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

-- Each DML bar now owns its own geometry. These helpers live on the addon
-- table instead of adding more top-level locals, keeping the WoW 3.3.5 Lua
-- chunk below its local-variable compiler limit.
function DMLCD.NormalizeBarSettings(settings, fallback)
    settings = type(settings) == "table" and settings or {}
    fallback = type(fallback) == "table" and fallback or defaults

    local normalized = {
        buttonCount = math.floor(Clamp(settings.buttonCount, 1, MAX_BUTTONS) or
            Clamp(fallback.buttonCount, 1, MAX_BUTTONS) or defaults.buttonCount),
        rows = math.floor(Clamp(settings.rows, 1, MAX_BUTTONS) or
            Clamp(fallback.rows, 1, MAX_BUTTONS) or defaults.rows),
        columns = math.floor(Clamp(settings.columns, 1, MAX_BUTTONS) or
            Clamp(fallback.columns, 1, MAX_BUTTONS) or defaults.columns),
        buttonSize = math.floor(Clamp(settings.buttonSize, 24, 64) or
            Clamp(fallback.buttonSize, 24, 64) or defaults.buttonSize),
        spacingX = math.floor(Clamp(settings.spacingX, 0, 40) or
            Clamp(fallback.spacingX, 0, 40) or defaults.spacingX),
        spacingY = math.floor(Clamp(settings.spacingY, 0, 40) or
            Clamp(fallback.spacingY, 0, 40) or defaults.spacingY)
    }

    local cells = normalized.rows * normalized.columns
    if cells < normalized.buttonCount or cells > MAX_BUTTONS then
        normalized.rows = math.max(1, math.ceil(normalized.buttonCount / normalized.columns))
        if (normalized.rows * normalized.columns) > MAX_BUTTONS then
            normalized.columns = math.min(normalized.columns, normalized.buttonCount)
            normalized.rows = math.max(1, math.ceil(normalized.buttonCount / normalized.columns))
        end
    end

    return normalized
end

function DMLCD.GetBarSettings(barIndex)
    barIndex = math.floor(Clamp(barIndex, 1, MAX_BARS) or 1)
    if not DB then
        return DMLCD.NormalizeBarSettings(nil, defaults)
    end

    if type(DB.barSettings) ~= "table" then
        DB.barSettings = {}
    end

    local fallback
    if barIndex == 1 then
        fallback = {
            buttonCount = DB.buttonCount,
            rows = DB.rows,
            columns = DB.columns,
            buttonSize = DB.buttonSize,
            spacingX = DB.spacingX,
            spacingY = DB.spacingY
        }
    else
        fallback = DB.barSettings[1] or {
            buttonCount = DB.buttonCount,
            rows = DB.rows,
            columns = DB.columns,
            buttonSize = DB.buttonSize,
            spacingX = DB.spacingX,
            spacingY = DB.spacingY
        }
    end

    local saved = DB.barSettings[barIndex] or DB.barSettings[tostring(barIndex)]
    DB.barSettings[barIndex] = DMLCD.NormalizeBarSettings(saved, fallback)
    DB.barSettings[tostring(barIndex)] = nil
    return DB.barSettings[barIndex]
end

-- The original scalar fields remain mirrors of Bar 1 for old profiles, slash
-- commands, and manual SavedVariables edits.
function DMLCD.SyncLegacyBarSettings()
    if not DB then
        return
    end
    local settings = DMLCD.GetBarSettings(1)
    DB.buttonCount = settings.buttonCount
    DB.rows = settings.rows
    DB.columns = settings.columns
    DB.buttonSize = settings.buttonSize
    DB.spacingX = settings.spacingX
    DB.spacingY = settings.spacingY
end

function DMLCD.SyncBarOneFromLegacySettings()
    if not DB then
        return
    end
    DB.barSettings = type(DB.barSettings) == "table" and DB.barSettings or {}
    DB.barSettings[1] = DMLCD.NormalizeBarSettings({
        buttonCount = DB.buttonCount,
        rows = DB.rows,
        columns = DB.columns,
        buttonSize = DB.buttonSize,
        spacingX = DB.spacingX,
        spacingY = DB.spacingY
    }, DB.barSettings[1] or defaults)
end

-- New bars begin in a small cascade around the middle of the screen. This
-- keeps every unlocked drag handle visible instead of stacking all bars in
-- exactly the same place. Saved positions are never overwritten.
local function GetDefaultBarPosition(barIndex)
    local offset = (math.max(1, tonumber(barIndex) or 1) - 1) * 28
    return "CENTER", "CENTER", offset, -offset
end

local function GlobalIndex(barIndex, slotIndex)
    return ((barIndex - 1) * MAX_BUTTONS) + slotIndex
end

local function GetButtonLocation(index)
    index = tonumber(index) or 1
    local barIndex = math.floor((index - 1) / MAX_BUTTONS) + 1
    local slotIndex = ((index - 1) % MAX_BUTTONS) + 1
    return barIndex, slotIndex
end

-- Bar 1 can optionally page with the same normal/bonus-page rules used by
-- Blizzard's main action bar. Page 1 continues to use the original assignment
-- table, while pages 2-10 are stored separately so existing layouts remain
-- untouched when the option is disabled.
function DMLCD.GetBarOneActionPage()
    local bonusOffset = GetBonusBarOffset and tonumber(GetBonusBarOffset()) or 0
    if bonusOffset and bonusOffset > 0 then
        return math.max(7, math.min(10, 6 + bonusOffset))
    end

    local page = GetActionBarPage and tonumber(GetActionBarPage()) or 1
    return math.max(1, math.min(6, page or 1))
end

function DMLCD.GetAssignmentPageForIndex(index)
    local barIndex = GetButtonLocation(index)
    if DB and DB.useBar1AsStanceBar and barIndex == 1 then
        return DMLCD.GetBarOneActionPage()
    end
    return 1
end

function DMLCD.GetAssignmentForIndex(index, pageOverride)
    if not DB then
        return nil
    end

    index = tonumber(index)
    if not index then
        return nil
    end

    local barIndex, slotIndex = GetButtonLocation(index)
    if DB.useBar1AsStanceBar and barIndex == 1 then
        local page = tonumber(pageOverride) or DMLCD.GetBarOneActionPage()
        if page > 1 then
            local pages = DB.stanceBarAssignments
            local pageAssignments = type(pages) == "table" and pages[page] or nil
            return type(pageAssignments) == "table" and pageAssignments[slotIndex] or nil
        end
    end

    return DB.assignments[index]
end

function DMLCD.SetAssignmentForIndex(index, assignment, pageOverride)
    index = tonumber(index)
    if not DB or not index then
        return
    end

    local barIndex, slotIndex = GetButtonLocation(index)
    if DB.useBar1AsStanceBar and barIndex == 1 then
        local page = tonumber(pageOverride) or DMLCD.GetBarOneActionPage()
        if page > 1 then
            DB.stanceBarAssignments = type(DB.stanceBarAssignments) == "table" and
                DB.stanceBarAssignments or {}
            DB.stanceBarAssignments[page] = type(DB.stanceBarAssignments[page]) == "table" and
                DB.stanceBarAssignments[page] or {}
            DB.stanceBarAssignments[page][slotIndex] = assignment
            return
        end
    end

    DB.assignments[index] = assignment
end

function DMLCD.ClearAssignmentForIndex(index, pageOverride)
    DMLCD.SetAssignmentForIndex(index, nil, pageOverride)
end

local function IsActiveButtonIndex(index)
    if not DB then
        return false
    end
    local barIndex, slotIndex = GetButtonLocation(index)
    local settings = DMLCD.GetBarSettings(barIndex)
    return barIndex >= 1 and barIndex <= DB.barCount and
        slotIndex >= 1 and slotIndex <= settings.buttonCount
end

local function FormatButtonRef(index)
    local barIndex, slotIndex = GetButtonLocation(index)
    if DB and DB.barCount == 1 then
        return "Button " .. tostring(slotIndex)
    end
    return "Bar " .. tostring(barIndex) .. " button " .. tostring(slotIndex)
end

local function ForEachActiveButton(callback)
    local barIndex, slotIndex
    for barIndex = 1, DB.barCount do
        local settings = DMLCD.GetBarSettings(barIndex)
        for slotIndex = 1, settings.buttonCount do
            local index = GlobalIndex(barIndex, slotIndex)
            callback(index, buttons[index], barIndex, slotIndex)
        end
    end
end

local function CopyDefaults(reset)
    if reset or type(DMLCooldownBarDB) ~= "table" then
        DMLCooldownBarDB = {}
    end

    DB = DMLCooldownBarDB
    local savedVersion = tonumber(DB.version) or 0

    -- Migrate the single 1.0.x spacing value before filling the new defaults.
    local legacySpacing = tonumber(DB.spacing)
    if reset then
        legacySpacing = nil
    end

    for key, value in pairs(defaults) do
        if reset or DB[key] == nil then
            DB[key] = value
        end
    end

    if legacySpacing then
        if DB.spacingX == defaults.spacingX then
            DB.spacingX = legacySpacing
        end
        if DB.spacingY == defaults.spacingY then
            DB.spacingY = legacySpacing
        end
    end
    DB.spacing = nil
    DB.readyText = nil

    if reset or type(DB.assignments) ~= "table" then
        DB.assignments = {}
    end

    -- Older versions stored only spell assignments. Mark those explicitly and
    -- normalize item and companion assignments without discarding saved bars.
    local assignmentIndex, assignment
    for assignmentIndex, assignment in pairs(DB.assignments) do
        if type(assignment) ~= "table" then
            DB.assignments[assignmentIndex] = nil
        else
            local kind = string.lower(tostring(
                assignment.kind or
                (assignment.macroBody and "macro") or
                (assignment.companionType and "companion") or
                (assignment.itemId and "item") or
                "spell"
            ))
            if kind == "item" then
                assignment.kind = "item"
                assignment.itemId = tonumber(assignment.itemId or assignment.id)
                assignment.spellId = nil
                assignment.companionType = nil
                assignment.companionIndex = nil
                assignment.macroIndex = nil
                assignment.macroName = nil
                assignment.macroIcon = nil
                assignment.macroBody = nil
                if not assignment.itemId then
                    DB.assignments[assignmentIndex] = nil
                end
            elseif kind == "companion" then
                assignment.kind = "companion"
                assignment.companionType = string.upper(tostring(assignment.companionType or ""))
                assignment.companionIndex = tonumber(assignment.companionIndex or assignment.index)
                assignment.spellId = tonumber(assignment.spellId or assignment.id)
                assignment.itemId = nil
                assignment.macroIndex = nil
                assignment.macroName = nil
                assignment.macroIcon = nil
                assignment.macroBody = nil
                if (assignment.companionType ~= "MOUNT" and assignment.companionType ~= "CRITTER") or
                    (not assignment.companionIndex and not assignment.spellId)
                then
                    DB.assignments[assignmentIndex] = nil
                end
            elseif kind == "macro" then
                assignment.kind = "macro"
                assignment.macroIndex = tonumber(assignment.macroIndex or assignment.index)
                assignment.macroName = tostring(assignment.macroName or assignment.name or "Macro")
                assignment.macroIcon = assignment.macroIcon or assignment.icon
                assignment.macroBody = tostring(assignment.macroBody or assignment.macroText or "")
                assignment.itemId = nil
                assignment.spellId = nil
                assignment.companionType = nil
                assignment.companionIndex = nil
                if assignment.macroBody == "" and not assignment.macroIndex then
                    DB.assignments[assignmentIndex] = nil
                end
            else
                assignment.kind = "spell"
                assignment.spellId = tonumber(assignment.spellId or assignment.id)
                assignment.itemId = nil
                assignment.companionType = nil
                assignment.companionIndex = nil
                assignment.macroIndex = nil
                assignment.macroName = nil
                assignment.macroIcon = nil
                assignment.macroBody = nil
                if not assignment.spellId then
                    DB.assignments[assignmentIndex] = nil
                end
            end
            if DB.assignments[assignmentIndex] then
                assignment.fallback = math.max(0, tonumber(assignment.fallback) or 0)
            end
        end
    end
    if reset or type(DB.spellMetadata) ~= "table" then
        DB.spellMetadata = {}
    end
    if reset or type(DB.cooldowns) ~= "table" then
        DB.cooldowns = {}
    end
    if reset or type(DB.knownCooldownDurations) ~= "table" then
        DB.knownCooldownDurations = {}
    end
    if reset or type(DB.activeSpellIcons) ~= "table" then
        DB.activeSpellIcons = {}
    end
    if reset or type(DB.keybinds) ~= "table" then
        DB.keybinds = {}
    end
    if reset or type(DB.barPositions) ~= "table" then
        DB.barPositions = {}
    end
    if reset or type(DB.barSettings) ~= "table" then
        DB.barSettings = {}
    end
    if reset or type(DB.stanceBarAssignments) ~= "table" then
        DB.stanceBarAssignments = {}
    end
    if reset or type(DB.petBarPosition) ~= "table" then
        DB.petBarPosition = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -110
        }
    end
    if reset or type(DB.auraBarPosition) ~= "table" then
        DB.auraBarPosition = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -70
        }
    end

    -- Migrate the original single-bar position into bar 1.
    if not DB.barPositions[1] then
        DB.barPositions[1] = {
            point = DB.point or defaults.point,
            relativePoint = DB.relativePoint or defaults.relativePoint,
            x = tonumber(DB.x) or defaults.x,
            y = tonumber(DB.y) or defaults.y
        }
    end

    DB.version = 22
    DB.barCount = Clamp(DB.barCount, 1, MAX_BARS) or defaults.barCount
    DB.buttonCount = Clamp(DB.buttonCount, 1, MAX_BUTTONS) or defaults.buttonCount
    DB.columns = Clamp(DB.columns, 1, MAX_BUTTONS) or defaults.columns
    DB.rows = Clamp(DB.rows, 1, MAX_BUTTONS) or defaults.rows
    DB.buttonSize = Clamp(DB.buttonSize, 24, 64) or defaults.buttonSize
    DB.spacingX = Clamp(DB.spacingX, 0, 40) or defaults.spacingX
    DB.spacingY = Clamp(DB.spacingY, 0, 40) or defaults.spacingY
    DB.fallbackDelay = Clamp(DB.fallbackDelay, 0, 5) or defaults.fallbackDelay
    DB.minimapAngle = tonumber(DB.minimapAngle) or defaults.minimapAngle

    -- Existing characters used one shared geometry for every bar. Copy that
    -- layout into all five per-bar records during migration so nothing moves.
    local legacyBarSettings = {
        buttonCount = DB.buttonCount,
        rows = DB.rows,
        columns = DB.columns,
        buttonSize = DB.buttonSize,
        spacingX = DB.spacingX,
        spacingY = DB.spacingY
    }
    local settingsBarIndex
    for settingsBarIndex = 1, MAX_BARS do
        local existing = DB.barSettings[settingsBarIndex] or DB.barSettings[tostring(settingsBarIndex)]
        DB.barSettings[settingsBarIndex] = DMLCD.NormalizeBarSettings(existing, legacyBarSettings)
        DB.barSettings[tostring(settingsBarIndex)] = nil
    end
    DMLCD.SyncLegacyBarSettings()

    -- v1.3.0 generated saved positions even when a bar had never been moved.
    -- Migrate only those exact old defaults to the new center-screen cascade.
    -- Any genuinely moved/saved position remains untouched.
    if not reset and savedVersion > 0 and savedVersion < 6 then
        local oldHeight = (DB.rows * DB.buttonSize) +
            ((DB.rows - 1) * DB.spacingY) + 34
        local barIndex
        for barIndex = 1, MAX_BARS do
            local position = DB.barPositions[barIndex]
            if position then
                local point = position.point or "CENTER"
                local relativePoint = position.relativePoint or "CENTER"
                local x = tonumber(position.x) or 0
                local y = tonumber(position.y) or 0
                local oldY = -160 - ((barIndex - 1) * oldHeight)
                if point == "CENTER" and relativePoint == "CENTER" and
                    math.abs(x) < 0.01 and math.abs(y - oldY) < 0.01
                then
                    local newPoint, newRelativePoint, newX, newY =
                        GetDefaultBarPosition(barIndex)
                    position.point = newPoint
                    position.relativePoint = newRelativePoint
                    position.x = newX
                    position.y = newY
                end
            end
        end
    end

    DB.showMessages = DB.showMessages and true or false
    DB.bagnonCompatibility = DB.bagnonCompatibility ~= false
    DB.showReadyMessages = DB.showReadyMessages and true or false
    DB.debugMessages = DB.debugMessages and true or false
    DB.hideGryphons = DB.hideGryphons and true or false
    DB.useDMLAuraBar = DB.useDMLAuraBar and true or false
    DB.useDMLPetBar = DB.useDMLPetBar and true or false
    DB.useBar1AsStanceBar = DB.useBar1AsStanceBar and true or false
    DB.showAnchors = DB.showAnchors ~= false
    DB.showMinimapButton = DB.showMinimapButton ~= false

    local rangeFinder = string.upper(tostring(DB.rangeFinder or defaults.rangeFinder))
    -- The v1.9.1 Default dot mode did not match the Wrath action-bar visual
    -- reliably across clients. Retire that value cleanly by migrating it Off.
    if rangeFinder == "DEFAULT" then
        rangeFinder = "OFF"
    end
    if rangeFinder ~= "OFF" and rangeFinder ~= "BORDER" and
        rangeFinder ~= "FADE"
    then
        rangeFinder = defaults.rangeFinder
    end
    DB.rangeFinder = rangeFinder

    local blizzardMode = string.upper(tostring(DB.blizzardBarMode or defaults.blizzardBarMode))
    if blizzardMode ~= "SHOW" and blizzardMode ~= "ALL" and
        blizzardMode ~= "ACTION" and blizzardMode ~= "ACTION_BACKGROUND"
    then
        blizzardMode = defaults.blizzardBarMode
    end
    DB.blizzardBarMode = blizzardMode
    DB.showSlotNumbers = DB.showSlotNumbers ~= false

    local lockKey = string.upper(tostring(DB.barLockKey or defaults.barLockKey))
    if lockKey ~= "SHIFT" and lockKey ~= "CTRL" and lockKey ~= "ALT" and lockKey ~= "NONE" then
        lockKey = defaults.barLockKey
    end
    DB.barLockKey = lockKey

    for settingsBarIndex = 1, MAX_BARS do
        DB.barSettings[settingsBarIndex] = DMLCD.NormalizeBarSettings(
            DB.barSettings[settingsBarIndex],
            legacyBarSettings
        )
    end
    DMLCD.SyncLegacyBarSettings()
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function ConfigurationBlocked(debugOnly)
    if IsInCombat() then
        if debugOnly then
            DebugPrint("Configuration cannot be changed during combat.")
        else
            Print("Configuration cannot be changed during combat.")
        end
        return true
    end
    return false
end

local function GetBarLockKeyLabel()
    if DB.barLockKey == "CTRL" then
        return "Ctrl"
    elseif DB.barLockKey == "ALT" then
        return "Alt"
    elseif DB.barLockKey == "NONE" then
        return "no modifier"
    end
    return "Shift"
end

local function IsBarLockModifierDown()
    if DB.barLockKey == "NONE" then
        return false
    elseif DB.barLockKey == "CTRL" then
        return IsControlKeyDown and IsControlKeyDown()
    elseif DB.barLockKey == "ALT" then
        return IsAltKeyDown and IsAltKeyDown()
    end
    return IsShiftKeyDown and IsShiftKeyDown()
end

local function CanEditAssignments(showMessage)
    if not DB.locked or IsBarLockModifierDown() then
        return true
    end

    if showMessage then
        if DB.barLockKey == "NONE" then
            DebugPrint("The bar is locked. Unlock it before changing spell assignments.")
        else
            DebugPrint("The bar is locked. Hold " .. GetBarLockKeyLabel() .. " while dragging, or unlock the bar.")
        end
    end
    return false
end

local function SavePosition(barIndex)
    local frame = bars[barIndex]
    if not frame then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    DB.barPositions[barIndex] = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0
    }

    -- Keep the original single-bar fields updated for compatibility with
    -- older versions and manual SavedVariables edits.
    if barIndex == 1 then
        DB.point = DB.barPositions[barIndex].point
        DB.relativePoint = DB.barPositions[barIndex].relativePoint
        DB.x = DB.barPositions[barIndex].x
        DB.y = DB.barPositions[barIndex].y
    end
end

local function SaveAllPositions()
    local barIndex
    for barIndex = 1, DB.barCount do
        SavePosition(barIndex)
    end
    if DMLCD.SavePetBarPosition then
        DMLCD.SavePetBarPosition()
    end
    if DMLCD.SaveAuraBarPosition then
        DMLCD.SaveAuraBarPosition()
    end
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    local key, child
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

local function TrimText(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function InitializeGlobalDB()
    if type(DMLCooldownBarGlobalDB) ~= "table" then
        DMLCooldownBarGlobalDB = {}
    end

    globalDB = DMLCooldownBarGlobalDB
    if type(globalDB.profiles) ~= "table" then
        globalDB.profiles = {}
    end

    -- Legacy Character-Realm snapshots are migrated once into the normal
    -- profile list. Nothing is discarded: when a character-name profile
    -- already exists, the imported snapshot becomes Name-ac-2, Name-ac-3, etc.
    -- After migration the old parallel table is deleted permanently.
    if type(globalDB.characterLayouts) == "table" then
        local characterKey, record
        for characterKey, record in pairs(globalDB.characterLayouts) do
            if type(record) == "table" then
                local characterName = TrimText(record.character)
                if characterName == "" then
                    characterName = string.match(tostring(characterKey), "^(.-)%-[^%-]+$") or tostring(characterKey)
                end

                local targetName = characterName
                if globalDB.profiles[targetName] then
                    local suffix = 2
                    repeat
                        targetName = characterName .. "-ac-" .. tostring(suffix)
                        suffix = suffix + 1
                    until not globalDB.profiles[targetName]
                end

                globalDB.profiles[targetName] = {
                    sourceCharacter = tostring(characterKey),
                    savedAt = tonumber(record.savedAt) or 0,
                    automatic = nil,
                    data = DeepCopy(type(record.data) == "table" and record.data or record)
                }
            end
        end
    end

    globalDB.characterLayouts = nil
    globalDB.version = 3
end

local function GetCurrentCharacterIdentity()
    local characterName = UnitName and UnitName("player") or nil
    local realmName = GetRealmName and GetRealmName() or nil
    characterName = characterName and tostring(characterName) or "Unknown"
    realmName = realmName and tostring(realmName) or "Unknown Realm"
    return characterName .. "-" .. realmName, characterName, realmName
end

local function BuildLayoutSnapshot()
    SaveAllPositions()

    local snapshot = {}
    local key
    for key in pairs(defaults) do
        if key ~= "version" then
            snapshot[key] = DeepCopy(DB[key])
        end
    end

    snapshot.assignments = DeepCopy(DB.assignments or {})
    snapshot.stanceBarAssignments = DeepCopy(DB.stanceBarAssignments or {})
    snapshot.spellMetadata = DeepCopy(DB.spellMetadata or {})
    snapshot.keybinds = DeepCopy(DB.keybinds or {})
    snapshot.barPositions = DeepCopy(DB.barPositions or {})
    snapshot.petBarPosition = DeepCopy(DB.petBarPosition or {})
    snapshot.auraBarPosition = DeepCopy(DB.auraBarPosition or {})
    snapshot.barSettings = DeepCopy(DB.barSettings or {})
    snapshot.point = DB.point
    snapshot.relativePoint = DB.relativePoint
    snapshot.x = DB.x
    snapshot.y = DB.y
    return snapshot
end

local function GetSortedProfileNames()
    local names = {}
    if globalDB and globalDB.profiles then
        local name
        for name in pairs(globalDB.profiles) do
            table.insert(names, tostring(name))
        end
    end
    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)
    return names
end

local function FindNamedProfile(profileName)
    profileName = TrimText(profileName)
    if profileName == "" or not globalDB then
        return nil, nil
    end

    if globalDB.profiles[profileName] then
        return profileName, globalDB.profiles[profileName]
    end

    local lowerName = string.lower(profileName)
    local savedName, record
    for savedName, record in pairs(globalDB.profiles) do
        if string.lower(tostring(savedName)) == lowerName then
            return savedName, record
        end
    end
    return nil, nil
end

local function GetDefaultProfileName()
    local characterKey, characterName = GetCurrentCharacterIdentity()

    -- Reuse the automatic profile already associated with this exact character.
    -- This keeps a collision-resolved Name-ac-N profile stable across sessions.
    if globalDB and globalDB.profiles then
        local savedName, record
        for savedName, record in pairs(globalDB.profiles) do
            if type(record) == "table" and record.automatic and
                tostring(record.sourceCharacter or "") == tostring(characterKey)
            then
                return tostring(savedName)
            end
        end
    end

    local profileName = characterName
    local existing = globalDB and globalDB.profiles and globalDB.profiles[profileName]
    if existing and existing.sourceCharacter and
        tostring(existing.sourceCharacter) ~= tostring(characterKey)
    then
        local suffix = 2
        repeat
            profileName = characterName .. "-ac-" .. tostring(suffix)
            suffix = suffix + 1
        until not globalDB.profiles[profileName]
    end

    return profileName
end

-- Current character settings already live in DMLCooldownBarDB, which WoW saves
-- per character. Named profiles are snapshots and must never be rewritten just
-- because the live layout changed or another profile was loaded. Keep this
-- compatibility function as a no-op because older code paths still call it.
SaveCharacterLayoutSnapshot = function()
    return
end

local function EnsureDefaultCharacterProfile()
    if not globalDB or not DB then
        return nil
    end

    local profileName = GetDefaultProfileName()
    if not globalDB.profiles[profileName] then
        local characterKey = GetCurrentCharacterIdentity()
        globalDB.profiles[profileName] = {
            sourceCharacter = characterKey,
            savedAt = time and time() or 0,
            automatic = true,
            data = BuildLayoutSnapshot()
        }
    end
    return profileName
end

local function SaveNamedProfile(profileName)
    profileName = TrimText(profileName)
    if profileName == "" then
        Print("Enter a profile name first.")
        return false
    end
    if string.len(profileName) > 40 then
        Print("Profile names may contain no more than 40 characters.")
        return false
    end

    local characterKey = GetCurrentCharacterIdentity()
    local automatic = profileName == GetDefaultProfileName() and true or nil
    globalDB.profiles[profileName] = {
        sourceCharacter = characterKey,
        savedAt = time and time() or 0,
        automatic = automatic,
        data = BuildLayoutSnapshot()
    }
    Print("Profile '" .. profileName .. "' saved.")
    if RefreshProfileControls then
        RefreshProfileControls(profileName, nil)
    end
    return true
end

local function DeleteNamedProfile(profileName)
    local savedName = FindNamedProfile(profileName)
    if not savedName then
        Print("Profile not found: " .. tostring(profileName or ""))
        return false
    end

    globalDB.profiles[savedName] = nil
    if configControls.profileName then
        local currentText = TrimText(configControls.profileName:GetText())
        if string.lower(currentText) == string.lower(tostring(savedName)) then
            configControls.profileName:SetText(GetDefaultProfileName() or "")
        end
    end
    Print("Profile '" .. savedName .. "' deleted.")
    if RefreshProfileControls then
        RefreshProfileControls(nil, nil)
    end
    return true
end

local function GetRecordSnapshot(record)
    if type(record) ~= "table" then
        return nil
    end
    if type(record.data) == "table" then
        return record.data
    end
    return record
end

-- Keep a bar recoverable while still allowing its decorative border/padding
-- to sit slightly outside the screen. The bottom and side borders may overhang
-- by BAR_EDGE_OVERHANG pixels, but the complete drag handle is kept below the
-- top edge so an unlocked bar can always be grabbed again.
local function ConstrainBarToScreen(barIndex)
    local frame = bars[barIndex]
    if not frame or not UIParent then
        return false
    end

    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()

    if not left or not bottom or not width or not height or
        not screenWidth or not screenHeight then
        return false
    end

    local right = left + width
    local top = bottom + height
    local minimumLeft = -BAR_EDGE_OVERHANG
    local maximumRight = screenWidth + BAR_EDGE_OVERHANG
    local minimumBottom = -BAR_EDGE_OVERHANG
    local maximumTop = screenHeight - BAR_DRAG_HANDLE_HEIGHT - BAR_DRAG_HANDLE_GAP
    local deltaX = 0
    local deltaY = 0

    -- Normal bars fit within the adjusted screen rectangle. Extremely wide or
    -- tall development layouts cannot satisfy both edges at once, so keep the
    -- frame center/drag anchor in a recoverable part of the screen instead.
    if width <= (screenWidth + (BAR_EDGE_OVERHANG * 2)) then
        if left < minimumLeft then
            deltaX = minimumLeft - left
        elseif right > maximumRight then
            deltaX = maximumRight - right
        end
    else
        local centerX = left + (width / 2)
        if centerX < 0 then
            deltaX = -centerX
        elseif centerX > screenWidth then
            deltaX = screenWidth - centerX
        end
    end

    local availableHeight = maximumTop - minimumBottom
    if height <= availableHeight then
        if bottom < minimumBottom then
            deltaY = minimumBottom - bottom
        elseif top > maximumTop then
            deltaY = maximumTop - top
        end
    else
        -- Prefer keeping the drag handle visible for an unusually tall bar.
        if top > maximumTop then
            deltaY = maximumTop - top
        elseif top < 0 then
            deltaY = -top
        end
    end

    if deltaX == 0 and deltaY == 0 then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint(
        "BOTTOMLEFT",
        UIParent,
        "BOTTOMLEFT",
        left + deltaX,
        bottom + deltaY
    )
    return true
end

local function RestorePosition(barIndex)
    local frame = bars[barIndex]
    if not frame then
        return
    end

    local saved = DB.barPositions and DB.barPositions[barIndex]
    local point, relativePoint, x, y
    if saved then
        point = saved.point or "CENTER"
        relativePoint = saved.relativePoint or "CENTER"
        x = tonumber(saved.x) or 0
        y = tonumber(saved.y) or 0
    else
        point, relativePoint, x, y = GetDefaultBarPosition(barIndex)
        DB.barPositions[barIndex] = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
    end

    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint, x, y)
end

local function RestoreAllPositions()
    local barIndex
    local count = math.max(DB.barCount, #bars)
    for barIndex = 1, count do
        if bars[barIndex] then
            RestorePosition(barIndex)
        end
    end
    if DMLCD.RestorePetBarPosition then
        DMLCD.RestorePetBarPosition()
    end
end

function DMLCD.NormalizeSpellMetadataRank(value)
    if value == nil or value == "" then
        return nil, nil
    end

    local numeric = tonumber(value)
    if numeric then
        numeric = math.floor(numeric)
        if numeric > 0 then
            return numeric, "Rank " .. tostring(numeric)
        end
    end

    local text = tostring(value)
    local parsed = tonumber(string.match(text, "(%d+)"))
    return parsed, text
end

function DMLCD.CopyNonEmptySpellMetadata(target, source)
    if type(source) ~= "table" then
        return
    end

    local key, value
    for key, value in pairs(source) do
        if value ~= nil and value ~= "" then
            target[key] = value
        end
    end
end

function DMLCD.GetSpellMetadata(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end

    local metadata = {}
    DMLCD.CopyNonEmptySpellMetadata(metadata, DMLCD.GetCustomSpellDefinitions()[spellId])

    if DB and type(DB.spellMetadata) == "table" then
        DMLCD.CopyNonEmptySpellMetadata(metadata, DB.spellMetadata[tostring(spellId)] or DB.spellMetadata[spellId])
    end

    if next(metadata) then
        return metadata
    end
    return nil
end

function DMLCD.IsServerConfirmedCooldownOnly(spellId)
    local metadata = DMLCD.GetSpellMetadata(spellId)

    if type(metadata) == "table" and metadata.server_confirmed_cooldown then
        return true
    end

    return false
end

function DMLCD.NormalizeSpellIcon(icon)
    if not icon or icon == "" then
        return nil
    end
    icon = tostring(icon)
    if string.find(icon, "\\") or string.find(icon, "/") then
        return icon
    end
    return "Interface\\Icons\\" .. icon
end

local function ResolveSpell(spellId, suppliedName)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end

    local metadata = DMLCD.GetSpellMetadata(spellId) or {}
    local clientName, clientRank, clientIcon = GetSpellInfo(spellId)
    local displayName = metadata.name or clientName or suppliedName
    local rankNumber, rankText = DMLCD.NormalizeSpellMetadataRank(metadata.rank)

    if not rankText and clientRank and clientRank ~= "" then
        rankNumber, rankText = DMLCD.NormalizeSpellMetadataRank(clientRank)
    end

    local family = metadata.family
    if not family and displayName then
        family = string.lower(tostring(displayName))
    end

    local customText = metadata.custom_text or metadata.customText
    local icon = DMLCD.NormalizeSpellIcon(metadata.icon) or clientIcon or QUESTION_ICON
    local activeIcon = DMLCD.NormalizeSpellIcon(metadata.active_icon or metadata.activeIcon)

    if clientName then
        local castName = clientName
        if clientRank and clientRank ~= "" then
            castName = clientName .. "(" .. clientRank .. ")"
        end
        return {
            spellId = spellId,
            name = displayName or clientName,
            rank = rankText or clientRank or "",
            rankNumber = rankNumber,
            rankText = rankText,
            family = family,
            customText = customText,
            castName = castName,
            icon = icon,
            activeIcon = activeIcon,
            clientKnown = true
        }
    end

    if displayName and displayName ~= "" then
        return {
            spellId = spellId,
            name = displayName,
            rank = rankText or "",
            rankNumber = rankNumber,
            rankText = rankText,
            family = family,
            customText = customText,
            castName = nil,
            icon = icon,
            activeIcon = activeIcon,
            clientKnown = false
        }
    end

    return nil
end

function DMLCD.ShouldSecureCastById(spellId, resolved)
    spellId = tonumber(spellId)
    if not spellId or not resolved then
        return false
    end

    local family = resolved.family
    if not family or family == "" then
        return false
    end

    local definitions = DMLCD.GetCustomSpellDefinitions()
    local definition = definitions[spellId]

    -- Optional explicit override for unusual custom spells.
    if type(definition) == "table" and definition.secure_cast_by_id ~= nil then
        return definition.secure_cast_by_id and true or false
    end

    local otherId, otherDefinition
    for otherId, otherDefinition in pairs(definitions) do
        if tonumber(otherId) ~= spellId
            and type(otherDefinition) == "table"
            and otherDefinition.family == family
        then
            return true
        end
    end

    -- Metadata received from ALE may define an additional rank even when it is
    -- not present in DMLCustomSpells.lua.
    if DB and type(DB.spellMetadata) == "table" then
        for otherId, otherDefinition in pairs(DB.spellMetadata) do
            if tonumber(otherId) ~= spellId
                and type(otherDefinition) == "table"
                and otherDefinition.family == family
            then
                return true
            end
        end
    end

    return false
end

-- Return the exact spell ID occupying a Blizzard action slot. GetActionInfo
-- normally exposes the ID directly, while GetActionLink is used as a fallback
-- for clients that expose a spellbook index instead.
function DMLCD.GetActionSlotSpellId(slot)
    if not GetActionInfo then
        return nil
    end

    local actionType, actionId = GetActionInfo(slot)
    if actionType ~= "spell" then
        return nil
    end

    local spellId = tonumber(actionId)
    if GetActionLink then
        local link = GetActionLink(slot)
        local linkedId = link and tonumber(string.match(link, "spell:(%d+)"))
        if linkedId then
            spellId = linkedId
        end
    end
    return spellId
end

-- Blizzard may render Spell.dbc's activeIconID directly on an action-button
-- texture even when GetActionTexture still returns the normal icon. Read the
-- texture region the player actually sees so toggle icons such as Holyform
-- can be mirrored exactly on DML bars.
DMLCD.BlizzardActionButtonPrefixes = DMLCD.BlizzardActionButtonPrefixes or {
    "ActionButton",
    "BonusActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton"
}

function DMLCD.GetRenderedBlizzardActionTexture(actionSlot)
    actionSlot = tonumber(actionSlot)
    if not actionSlot then
        return nil
    end

    local prefixIndex, buttonIndex
    for prefixIndex = 1, #DMLCD.BlizzardActionButtonPrefixes do
        local prefix = DMLCD.BlizzardActionButtonPrefixes[prefixIndex]
        for buttonIndex = 1, 12 do
            local button = _G[prefix .. tostring(buttonIndex)]
            if button then
                local renderedSlot = tonumber(button.action)
                if not renderedSlot and button.GetAttribute then
                    renderedSlot = tonumber(button:GetAttribute("action"))
                end
                if not renderedSlot and ActionButton_GetPagedID then
                    local ok, pagedSlot = pcall(ActionButton_GetPagedID, button)
                    if ok and tonumber(pagedSlot) then
                        renderedSlot = tonumber(pagedSlot)
                    end
                end

                if renderedSlot == actionSlot then
                    local buttonName = button.GetName and button:GetName() or nil
                    local icon = button.icon or
                        (buttonName and _G[buttonName .. "Icon"]) or
                        (buttonName and _G[buttonName .. "IconTexture"])
                    if icon and icon.GetTexture then
                        local texture = icon:GetTexture()
                        if texture then
                            return texture
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Find a Blizzard action slot containing this exact rank. The slot is cached so
-- normal 0.1-second DML visual updates do not repeatedly scan all action pages.
function DMLCD.GetMatchingBlizzardActionState(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil, false
    end

    DMLCD.ActionSlotCache = DMLCD.ActionSlotCache or {}
    DMLCD.ActionSlotScanTimes = DMLCD.ActionSlotScanTimes or {}

    local key = tostring(spellId)
    local cachedSlot = tonumber(DMLCD.ActionSlotCache[key])
    if cachedSlot and DMLCD.GetActionSlotSpellId(cachedSlot) == spellId then
        local texture = DMLCD.GetRenderedBlizzardActionTexture(cachedSlot) or
            (GetActionTexture and GetActionTexture(cachedSlot) or nil)
        local current = IsCurrentAction and IsCurrentAction(cachedSlot) or false
        return texture, current and true or false
    end
    DMLCD.ActionSlotCache[key] = nil

    local now = GetTime and GetTime() or 0
    local lastScan = tonumber(DMLCD.ActionSlotScanTimes[key]) or -10
    if (now - lastScan) < 2 then
        return nil, false
    end
    DMLCD.ActionSlotScanTimes[key] = now

    local slot
    for slot = 1, 120 do
        if DMLCD.GetActionSlotSpellId(slot) == spellId then
            DMLCD.ActionSlotCache[key] = slot
            local texture = DMLCD.GetRenderedBlizzardActionTexture(slot) or
                (GetActionTexture and GetActionTexture(slot) or nil)
            local current = IsCurrentAction and IsCurrentAction(slot) or false
            return texture, current and true or false
        end
    end

    return nil, false
end

function DMLCD.PlayerHasAuraSpell(spellId, spellName)
    if not UnitBuff then
        return false
    end

    spellId = tonumber(spellId)
    spellName = spellName and tostring(spellName) or nil

    local auraIndex
    for auraIndex = 1, 40 do
        local auraName, _, _, _, _, _, _, _, _, _, auraSpellId =
            UnitBuff("player", auraIndex)
        if not auraName then
            break
        end

        if (spellId and tonumber(auraSpellId) == spellId) or
            (spellName and tostring(auraName) == spellName)
        then
            return true
        end
    end
    return false
end

DMLCD.SHARED_ACTIVE_STANCE_ICON =
    "Interface\\Icons\\Spell_Nature_WispSplode"

function DMLCD.SpellNamesMatch(firstName, secondName)
    if not firstName or not secondName then
        return false
    end

    return string.lower(tostring(firstName)) ==
        string.lower(tostring(secondName))
end

-- Returns whether the assigned spell belongs to the client's stance/form/aura
-- bar and, when it does, whether that exact entry is active. This naturally
-- covers Shadowform, warrior stances, druid shapeshifts, and paladin auras
-- without treating ordinary timed buffs as toggle states.
function DMLCD.GetShapeshiftSpellState(spellId, resolved)
    if not GetNumShapeshiftForms or not GetShapeshiftFormInfo then
        return false, false
    end

    spellId = tonumber(spellId)
    local spellName = resolved and (resolved.name or resolved.castName) or nil
    local formCount = tonumber(GetNumShapeshiftForms()) or 0
    local formIndex

    for formIndex = 1, formCount do
        local _, formName, isActive, _, formSpellId =
            GetShapeshiftFormInfo(formIndex)
        formSpellId = tonumber(formSpellId)
        if formSpellId and formSpellId <= 0 then
            formSpellId = nil
        end

        local matches = false
        if spellId and formSpellId then
            matches = spellId == formSpellId
        elseif spellName and formName then
            matches = DMLCD.SpellNamesMatch(spellName, formName)
        end

        if matches then
            return true, isActive and true or false
        end
    end

    return false, false
end

-- Blizzard uses its current-spell state for toggles and for on-next-melee
-- attacks such as Heroic Strike. Numeric IDs preserve exact custom ranks.
-- The third return value is deliberately narrow: only stance/form/aura-bar
-- spells and the custom Holyform fallback may receive the shared active icon.
function DMLCD.GetSpellActionState(spellId, resolved)
    spellId = tonumber(spellId)
    if not spellId or not resolved then
        return false, nil, false
    end

    local current = false
    if IsCurrentSpell then
        local ok, value = pcall(IsCurrentSpell, spellId)
        if ok and value then
            current = true
        end
    end

    local actionTexture, actionCurrent = DMLCD.GetMatchingBlizzardActionState(spellId)
    if actionCurrent then
        current = true
    end

    -- Name fallback is safe for ordinary/toggle spells. Do not use it for a
    -- configured multi-rank family because duplicate client rank text could
    -- make both ranks appear queued at once.
    if not current and IsCurrentSpell and not DMLCD.ShouldSecureCastById(spellId, resolved) then
        local spellName = resolved.castName or resolved.name
        if spellName and spellName ~= "" then
            local ok, value = pcall(IsCurrentSpell, spellName)
            if ok and value then
                current = true
            end
        end
    end

    local isStanceSpell, stanceActive =
        DMLCD.GetShapeshiftSpellState(spellId, resolved)
    local sharedActive = isStanceSpell and stanceActive or false

    -- Holyform is custom and Shadowform can vary across 3.3.5 clients.
    -- Only these exact spells receive the aura-based fallback.
    if (spellId == 46565 or spellId == 15473) and not sharedActive then
        sharedActive = DMLCD.PlayerHasAuraSpell(
            spellId,
            resolved.name or resolved.castName
        )
    end

    if sharedActive then
        current = true
    end

    return current and true or false, actionTexture, sharedActive and true or false
end

function DMLCD.GetCurrentSpellIcon(spellId, resolved, current, actionTexture, sharedActive)
    if not resolved then
        return QUESTION_ICON
    end

    if sharedActive then
        return resolved.activeIcon or DMLCD.SHARED_ACTIVE_STANCE_ICON
    end

    -- Inactive forms, stances, and auras always return to their own spell-ID
    -- texture. Queued attacks retain their own icon and use only the highlight.
    return resolved.icon or QUESTION_ICON
end

function DMLCD.UpdateButtonActionStateVisual(button, assignment, resolved)
    if not button then
        return
    end

    if assignment and resolved and
        (assignment.kind == "companion" or assignment.companionType)
    then
        button.dmlActionCurrent = resolved.active and true or false
        button.dmlSharedActive = false
        if button.stateHighlight then
            if button.dmlActionCurrent then
                button.stateHighlight:Show()
            else
                button.stateHighlight:Hide()
            end
        end
        return
    end

    if not assignment or not resolved or assignment.kind ~= "spell" then
        button.dmlActionCurrent = false
        button.dmlSharedActive = false
        if button.stateHighlight then
            button.stateHighlight:Hide()
        end
        return
    end

    local spellId = tonumber(assignment.spellId or resolved.spellId)
    local current, actionTexture, sharedActive =
        DMLCD.GetSpellActionState(spellId, resolved)
    button.dmlActionCurrent = current
    button.dmlSharedActive = sharedActive

    if button.stateHighlight then
        if current then
            button.stateHighlight:Show()
        else
            button.stateHighlight:Hide()
        end
    end

    if button.icon then
        button.icon:SetTexture(
            DMLCD.GetCurrentSpellIcon(
                spellId,
                resolved,
                current,
                actionTexture,
                sharedActive
            )
        )
    end
end

local function NormalizeIconPath(icon)
    if not icon or icon == "" then
        return nil
    end
    icon = tostring(icon)
    if string.find(icon, "\\") or string.find(icon, "/") then
        return icon
    end
    return "Interface\\Icons\\" .. icon
end

function DMLCD.InvalidateItemInfoCache(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end

    DMLCD.itemInfoCache[itemId] = nil
    DMLCD.itemInfoRetryAt[itemId] = nil
    DMLCD.itemIconFallbackCache[itemId] = nil
end

function DMLCD.ResolveItem(itemId, suppliedName)
    itemId = tonumber(itemId)
    if not itemId then
        return nil
    end

    local definitions = GetCustomItemDefinitions()
    local custom = definitions[itemId]
    local cached = DMLCD.itemInfoCache[itemId]
    local now = GetTime and GetTime() or 0
    local retryAt = tonumber(DMLCD.itemInfoRetryAt[itemId]) or 0

    if not cached and GetItemInfo and now >= retryAt then
        -- One GetItemInfo call supplies every value we need. Calling it twice
        -- can duplicate server item-query traffic on the Wrath client.
        local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemId)
        if itemName or itemLink or itemIcon then
            cached = {
                name = itemName,
                link = itemLink,
                icon = itemIcon
            }
            DMLCD.itemInfoCache[itemId] = cached
            DMLCD.itemInfoRetryAt[itemId] = nil
        else
            DMLCD.itemInfoRetryAt[itemId] = now + DMLCD.ITEM_INFO_RETRY_DELAY
        end
    end

    local fallbackIcon = DMLCD.itemIconFallbackCache[itemId]
    if fallbackIcon == nil and GetItemIcon then
        local ok, icon = pcall(GetItemIcon, itemId)
        fallbackIcon = ok and icon or false
        DMLCD.itemIconFallbackCache[itemId] = fallbackIcon
    end

    local customName = custom and custom.name
    local customIcon = custom and NormalizeIconPath(custom.icon)
    local itemName = cached and cached.name or nil
    local itemLink = cached and cached.link or nil
    local itemIcon = cached and cached.icon or nil

    return {
        kind = "item",
        itemId = itemId,
        name = itemName or customName or suppliedName or ("Item " .. tostring(itemId)),
        link = itemLink,
        icon = customIcon or itemIcon or (fallbackIcon or nil) or QUESTION_ICON,
        secureItem = "item:" .. tostring(itemId),
        clientKnown = (itemName or itemLink) and true or false,
        customDefined = custom and true or false
    }
end

-- Macros are copied into the assignment itself so profiles remain usable on a
-- second computer even when its global/character macro indices differ. When a
-- matching live macro exists, its current name, icon, and body are preferred.
function DMLCD.ResolveMacro(macroIndex, suppliedName, suppliedIcon, suppliedBody)
    macroIndex = tonumber(macroIndex)
    suppliedName = suppliedName and tostring(suppliedName) or nil
    suppliedBody = suppliedBody and tostring(suppliedBody) or ""

    local resolvedIndex = macroIndex
    local liveName, liveIcon, liveBody

    if resolvedIndex and GetMacroInfo then
        local ok
        ok, liveName, liveIcon, liveBody = pcall(GetMacroInfo, resolvedIndex)
        if not ok or not liveName then
            liveName, liveIcon, liveBody = nil, nil, nil
        end
    end

    if liveName and suppliedName and liveName ~= suppliedName then
        liveName, liveIcon, liveBody = nil, nil, nil
        resolvedIndex = nil
    end

    if not liveName and suppliedName and GetMacroIndexByName and GetMacroInfo then
        local ok, foundIndex = pcall(GetMacroIndexByName, suppliedName)
        foundIndex = ok and tonumber(foundIndex) or nil
        if foundIndex and foundIndex > 0 then
            local infoOk
            infoOk, liveName, liveIcon, liveBody = pcall(GetMacroInfo, foundIndex)
            if infoOk and liveName then
                resolvedIndex = foundIndex
            else
                liveName, liveIcon, liveBody = nil, nil, nil
            end
        end
    end

    local macroName = liveName or suppliedName or "Macro"
    local macroBody = liveBody or suppliedBody
    local macroIcon = liveIcon or suppliedIcon or QUESTION_ICON

    if not macroBody or macroBody == "" then
        return nil
    end

    return {
        kind = "macro",
        macroIndex = resolvedIndex,
        name = macroName,
        macroName = macroName,
        macroText = macroBody,
        icon = macroIcon,
        clientKnown = liveName and true or false
    }
end

-- Mounts and non-combat companion pets use Wrath's companion collection API.
-- Store both the collection position and summon-spell ID: companion positions can
-- be reordered by the client, while the spell ID remains the most stable identity.
function DMLCD.NormalizeCompanionType(value)
    local companionType = string.upper(tostring(value or ""))
    if companionType == "MOUNT" or companionType == "CRITTER" then
        return companionType
    end
    return nil
end

function DMLCD.GetCompanionTypeLabel(companionType)
    if DMLCD.NormalizeCompanionType(companionType) == "MOUNT" then
        return "mount"
    end
    return "companion pet"
end

function DMLCD.ResolveCompanion(companionType, companionIndex, spellId, suppliedName, suppliedIcon)
    companionType = DMLCD.NormalizeCompanionType(companionType)
    companionIndex = tonumber(companionIndex)
    spellId = tonumber(spellId)
    if not companionType then
        return nil
    end

    local count = GetNumCompanions and tonumber(GetNumCompanions(companionType)) or 0
    local resolvedIndex
    local creatureId
    local creatureName
    local creatureSpellId
    local icon
    local active

    if companionIndex and companionIndex >= 1 and companionIndex <= count and GetCompanionInfo then
        creatureId, creatureName, creatureSpellId, icon, active =
            GetCompanionInfo(companionType, companionIndex)
        creatureSpellId = tonumber(creatureSpellId)
        if creatureName and
            ((spellId and creatureSpellId == spellId) or
             (not spellId and (not suppliedName or suppliedName == creatureName)))
        then
            resolvedIndex = companionIndex
        else
            creatureId = nil
            creatureName = nil
            creatureSpellId = nil
            icon = nil
            active = nil
        end
    end

    if not resolvedIndex and GetCompanionInfo then
        local index
        for index = 1, count do
            local candidateCreatureId, candidateName, candidateSpellId, candidateIcon, candidateActive =
                GetCompanionInfo(companionType, index)
            candidateSpellId = tonumber(candidateSpellId)
            if (spellId and candidateSpellId == spellId) or
                (not spellId and suppliedName and candidateName == suppliedName)
            then
                resolvedIndex = index
                creatureId = candidateCreatureId
                creatureName = candidateName
                creatureSpellId = candidateSpellId
                icon = candidateIcon
                active = candidateActive
                break
            end
        end
    end

    spellId = creatureSpellId or spellId
    local spellName, _, spellIcon
    if spellId and GetSpellInfo then
        spellName, _, spellIcon = GetSpellInfo(spellId)
    end

    local displayName = creatureName or suppliedName or spellName
    if not displayName then
        displayName = (companionType == "MOUNT" and "Mount " or "Companion pet ") ..
            tostring(spellId or companionIndex or "?")
    end

    return {
        kind = "companion",
        companionType = companionType,
        companionIndex = resolvedIndex or companionIndex,
        creatureId = tonumber(creatureId),
        spellId = spellId,
        name = displayName,
        castName = spellName or creatureName or suppliedName,
        icon = icon or suppliedIcon or spellIcon or QUESTION_ICON,
        active = active and true or false,
        clientKnown = (spellName or creatureName) and true or false,
        available = resolvedIndex and true or false
    }
end

function DMLCD.BuildCompanionAssignment(companionType, companionIndex)
    local resolved = DMLCD.ResolveCompanion(companionType, companionIndex, nil, nil, nil)
    if not resolved then
        return nil
    end
    return {
        kind = "companion",
        companionType = resolved.companionType,
        companionIndex = resolved.companionIndex,
        spellId = resolved.spellId,
        name = resolved.name,
        icon = resolved.icon,
        fallback = 0
    }
end

function DMLCD.RememberPickedCompanion(companionType, companionIndex)
    companionType = DMLCD.NormalizeCompanionType(companionType)
    companionIndex = tonumber(companionIndex)
    if not companionType or not companionIndex then
        return
    end
    DMLCD.lastPickedCompanion = {
        companionType = companionType,
        companionIndex = companionIndex,
        pickedAt = GetTime and GetTime() or 0
    }
end

function DMLCD.InstallCompanionPickupHook()
    if DMLCD.companionPickupHookInstalled or not PickupCompanion or not hooksecurefunc then
        return
    end
    hooksecurefunc("PickupCompanion", function(companionType, companionIndex)
        DMLCD.RememberPickedCompanion(companionType, companionIndex)
    end)
    DMLCD.companionPickupHookInstalled = true
end

function DMLCD.ExtractCompanionCursorAssignment(cursorType, info1, info2)
    local companionType
    local companionIndex

    if cursorType == "companion" then
        companionType = DMLCD.NormalizeCompanionType(info2)
        companionIndex = tonumber(info1)
        if not companionType then
            companionType = DMLCD.NormalizeCompanionType(info1)
            companionIndex = tonumber(info2)
        end
    elseif cursorType == "spell" and tonumber(info1) == 0 then
        -- Early Wrath clients can report a dragged mount/pet as "spell", 0,
        -- "spell". PickupCompanion's secure post-hook preserves the real entry.
        local remembered = DMLCD.lastPickedCompanion
        if remembered then
            companionType = remembered.companionType
            companionIndex = remembered.companionIndex
        end
    end

    if not companionType or not companionIndex then
        return nil
    end
    return DMLCD.BuildCompanionAssignment(companionType, companionIndex)
end

local function GetAssignmentKind(assignment)
    if not assignment then
        return nil
    end
    if assignment.kind == "macro" or assignment.macroBody then
        return "macro"
    end
    if assignment.kind == "companion" or assignment.companionType then
        return "companion"
    end
    if assignment.kind == "item" or assignment.itemId then
        return "item"
    end
    return "spell"
end

local function GetAssignmentId(assignment)
    local kind = GetAssignmentKind(assignment)
    if kind == "item" then
        return tonumber(assignment.itemId)
    end
    if kind == "companion" then
        return tonumber(assignment.spellId) or tonumber(assignment.companionIndex)
    end
    if kind == "macro" then
        return tonumber(assignment.macroIndex) or assignment.macroName or assignment.name
    end
    return tonumber(assignment.spellId)
end

local function ResolveAssignment(assignment)
    if not assignment then
        return nil
    end
    local kind = GetAssignmentKind(assignment)
    if kind == "item" then
        return DMLCD.ResolveItem(assignment.itemId, assignment.name)
    end
    if kind == "companion" then
        return DMLCD.ResolveCompanion(
            assignment.companionType,
            assignment.companionIndex,
            assignment.spellId,
            assignment.name,
            assignment.icon
        )
    end
    if kind == "macro" then
        return DMLCD.ResolveMacro(
            assignment.macroIndex,
            assignment.macroName or assignment.name,
            assignment.macroIcon or assignment.icon,
            assignment.macroBody or assignment.macroText
        )
    end
    return ResolveSpell(assignment.spellId, assignment.name)
end

local function AssignmentMatches(left, right)
    if not left or not right then
        return false
    end
    local leftKind = GetAssignmentKind(left)
    local rightKind = GetAssignmentKind(right)
    if leftKind ~= rightKind then
        return false
    end
    if leftKind == "companion" then
        if DMLCD.NormalizeCompanionType(left.companionType) ~= DMLCD.NormalizeCompanionType(right.companionType) then
            return false
        end
        local leftSpellId = tonumber(left.spellId)
        local rightSpellId = tonumber(right.spellId)
        if leftSpellId and rightSpellId then
            return leftSpellId == rightSpellId
        end
        return tonumber(left.companionIndex) == tonumber(right.companionIndex)
    end
    if leftKind == "macro" then
        local leftIndex = tonumber(left.macroIndex)
        local rightIndex = tonumber(right.macroIndex)
        if leftIndex and rightIndex and leftIndex == rightIndex then
            return true
        end
        return tostring(left.macroName or left.name or "") == tostring(right.macroName or right.name or "") and
            tostring(left.macroBody or left.macroText or "") == tostring(right.macroBody or right.macroText or "")
    end
    return tonumber(GetAssignmentId(left)) == tonumber(GetAssignmentId(right))
end

local function GetAssignmentDisplayName(assignment)
    local resolved = ResolveAssignment(assignment)
    if resolved and resolved.name then
        return resolved.name
    end
    local kind = GetAssignmentKind(assignment)
    local id = GetAssignmentId(assignment)
    if kind == "companion" then
        return (DMLCD.NormalizeCompanionType(assignment.companionType) == "MOUNT" and "Mount " or "Companion pet ") .. tostring(id or "?")
    end
    if kind == "macro" then
        return tostring(assignment.macroName or assignment.name or "Macro")
    end
    return (kind == "item" and "Item " or "Spell ") .. tostring(id or "?")
end

local function GetCooldownKey(spellId)
    return tostring(tonumber(spellId) or spellId)
end

local function GetCooldownState(spellId)
    if not DB or type(DB.cooldowns) ~= "table" then
        return nil
    end
    return DB.cooldowns[GetCooldownKey(spellId)]
end

local function GetRemaining(state)
    if not state then
        return 0
    end

    if state.sessionExpires then
        return state.sessionExpires - GetTime()
    end

    if state.expiresAt then
        return state.expiresAt - time()
    end

    return 0
end

local function FormatRemaining(seconds)
    if seconds <= 0 then
        return ""
    end

    if seconds >= 3600 then
        return tostring(math.ceil(seconds / 3600)) .. "h"
    elseif seconds >= 60 then
        return tostring(math.ceil(seconds / 60)) .. "m"
    elseif seconds >= 10 then
        return tostring(math.ceil(seconds))
    end

    return string.format("%.1f", seconds)
end

function DMLCD.FormatCooldownDuration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        return nil
    end

    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds - (hours * 3600)) / 60)
        if minutes > 0 then
            return tostring(hours) .. "h " .. tostring(minutes) .. "m"
        end
        return tostring(hours) .. (hours == 1 and " hour" or " hours")
    elseif seconds >= 60 then
        local minutes = math.floor(seconds / 60)
        local remainder = math.floor((seconds - (minutes * 60)) + 0.5)
        if remainder > 0 then
            return tostring(minutes) .. "m " .. tostring(remainder) .. "s"
        end
        return tostring(minutes) .. (minutes == 1 and " minute" or " minutes")
    elseif seconds == math.floor(seconds) then
        return tostring(math.floor(seconds)) .. (seconds == 1 and " second" or " seconds")
    end

    return string.format("%.1f seconds", seconds)
end

function DMLCD.RememberCooldownDuration(spellId, duration)
    spellId = tonumber(spellId)
    duration = tonumber(duration)
    if not DB or not spellId or not duration or duration <= 0 then
        return
    end

    DB.knownCooldownDurations = DB.knownCooldownDurations or {}
    DB.knownCooldownDurations[GetCooldownKey(spellId)] = duration
end

function DMLCD.GetKnownCooldownDuration(assignment, state)
    if not assignment or GetAssignmentKind(assignment) ~= "spell" then
        return nil
    end

    if state and tonumber(state.duration) and tonumber(state.duration) > 0 then
        DMLCD.RememberCooldownDuration(assignment.spellId, state.duration)
    end

    if not DB or type(DB.knownCooldownDurations) ~= "table" then
        return nil
    end

    return tonumber(DB.knownCooldownDurations[GetCooldownKey(assignment.spellId)])
end

function DMLCD.GetRangeFinderMode()
    local mode = DB and DB.rangeFinder or defaults.rangeFinder
    mode = string.upper(tostring(mode or "OFF"))
    if mode == "DEFAULT" then
        mode = "OFF"
    end
    if mode ~= "BORDER" and mode ~= "FADE" then
        mode = "OFF"
    end
    return mode
end

function DMLCD.ApplyButtonIconAppearance(button)
    if not button or not button.icon then
        return
    end

    if button.dmlCooldownActive then
        if button.icon.SetDesaturated then
            button.icon:SetDesaturated(true)
            button.icon:SetVertexColor(0.65, 0.65, 0.65)
        else
            button.icon:SetVertexColor(0.45, 0.45, 0.45)
        end
    else
        if button.icon.SetDesaturated then
            button.icon:SetDesaturated(false)
        end
        button.icon:SetVertexColor(1, 1, 1)
    end

    local iconAlpha = 1
    if DB and DB.resourceFade and button.dmlResourceLow then
        iconAlpha = 0.35
    end
    if DMLCD.GetRangeFinderMode() == "FADE" and button.dmlOutOfRange then
        iconAlpha = math.min(iconAlpha, 0.35)
    end
    button.icon:SetAlpha(iconAlpha)
end

local function SetIconCooldownAppearance(button, active)
    button.dmlCooldownActive = active and true or false
    DMLCD.ApplyButtonIconAppearance(button)
end

function DMLCD.GetSpellResourceLow(assignment)
    if not DB or not DB.resourceFade or not assignment or GetAssignmentKind(assignment) ~= "spell" then
        return false
    end
    if not IsUsableSpell then
        return false
    end

    local spell = ResolveSpell(assignment.spellId, assignment.name)
    if not spell or not spell.clientKnown then
        return false
    end

    local query = spell.castName or spell.name or tonumber(assignment.spellId)
    local ok, _, noResource = pcall(IsUsableSpell, query)
    if not ok then
        return false
    end
    return noResource and true or false
end

function DMLCD.UpdateButtonResourceVisual(button, cache)
    if not button then
        return
    end

    local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex)
    local low = false
    if assignment and GetAssignmentKind(assignment) == "spell" and DB.resourceFade then
        local key = tostring(tonumber(assignment.spellId) or assignment.spellId)
        if cache and cache[key] ~= nil then
            low = cache[key]
        else
            low = DMLCD.GetSpellResourceLow(assignment)
            if cache then
                cache[key] = low
            end
        end
    end

    button.dmlResourceLow = low
    DMLCD.ApplyButtonIconAppearance(button)
end

function DMLCD.RefreshResourceButtonVisual(_, button)
    if button then
        DMLCD.UpdateButtonResourceVisual(button, DMLCD.updateResourceCache)
    end
end

function DMLCD.RefreshResourceVisuals()
    DMLCD.ClearScratchTable(DMLCD.updateResourceCache)
    ForEachActiveButton(DMLCD.RefreshResourceButtonVisual)
end

function DMLCD.GetAssignmentRangeState(assignment, resolved)
    if DMLCD.GetRangeFinderMode() == "OFF" or not assignment or not resolved then
        return nil
    end
    if not UnitExists or not UnitExists("target") then
        return nil
    end

    local kind = GetAssignmentKind(assignment)
    local result
    if kind == "spell" and IsSpellInRange then
        local query = resolved.castName or resolved.name
        if query and query ~= "" then
            local ok, value = pcall(IsSpellInRange, query, "target")
            if ok then
                result = value
            end
        end
        if result == nil and resolved.name and resolved.name ~= query then
            local ok, value = pcall(IsSpellInRange, resolved.name, "target")
            if ok then
                result = value
            end
        end
    elseif kind == "item" and IsItemInRange then
        local itemQuery = tonumber(assignment.itemId) or resolved.link or resolved.name
        if itemQuery then
            local ok, value = pcall(IsItemInRange, itemQuery, "target")
            if ok then
                result = value
            end
        end
    end

    if result == false or tonumber(result) == 0 then
        return false
    end

    -- A target exists but this action exposes no distance check. Blizzard
    -- treats those actions as having no out-of-range warning, so the default
    -- indicator remains neutral gray and border/fade modes remain normal.
    return true
end

function DMLCD.UpdateButtonRangeVisual(button, assignment, resolved, cache)
    if not button then
        return
    end

    local mode = DMLCD.GetRangeFinderMode()
    local rangeState
    if mode ~= "OFF" and assignment and resolved then
        local cacheKey = tostring(GetAssignmentKind(assignment)) .. ":" ..
            tostring(GetAssignmentId(assignment) or "?")
        if cache and cache[cacheKey] ~= nil then
            rangeState = cache[cacheKey]
        else
            rangeState = DMLCD.GetAssignmentRangeState(assignment, resolved)
            if cache and rangeState ~= nil then
                cache[cacheKey] = rangeState
            end
        end
    end

    button.dmlRangeState = rangeState
    button.dmlOutOfRange = rangeState == false


    if button.rangeBorder then
        if mode == "BORDER" and button.dmlOutOfRange then
            button.rangeBorder:Show()
        else
            button.rangeBorder:Hide()
        end
    end

    DMLCD.ApplyButtonIconAppearance(button)
end

local function ClearCooldownVisual(button)
    button.cooldown:Hide()
    button.cooldownText:SetText("")
    button.dmlCooldownKey = nil
    SetIconCooldownAppearance(button, false)
end

local function ApplyCooldownVisual(button, state, forceTimer)
    local remaining = GetRemaining(state)
    if remaining <= 0 then
        ClearCooldownVisual(button)
        return
    end

    local duration = tonumber(state.duration) or remaining
    if duration < remaining then
        duration = remaining
    end

    local startTime = tonumber(state.startMono) or (GetTime() - math.max(0, duration - remaining))
    local enable = state.enable
    if enable == nil then
        enable = 1
    end

    local cooldownKey = tostring(state.source or "unknown") .. ":" ..
        tostring(startTime) .. ":" .. tostring(duration) .. ":" .. tostring(enable)

    if forceTimer or button.dmlCooldownKey ~= cooldownKey then
        CooldownFrame_SetTimer(button.cooldown, startTime, duration, enable)
        button.dmlCooldownKey = cooldownKey
    end

    button.cooldown:Show()
    button.cooldownText:SetText(FormatRemaining(remaining))
    SetIconCooldownAppearance(button, true)
end

local function GetNativeCooldownState(assignment)
    if not DB.nativeCooldowns or not assignment then
        return nil
    end

local kind = GetAssignmentKind(assignment)

if kind == "spell" and DMLCD.IsServerConfirmedCooldownOnly(assignment.spellId) then
    return nil
end

local startTime, duration, enable

if kind == "item" then
        if not GetItemCooldown then
            return nil
        end
        local ok
        ok, startTime, duration, enable = pcall(GetItemCooldown, tonumber(assignment.itemId))
        if not ok then
            return nil
        end
    elseif kind == "companion" then
        local companion = DMLCD.ResolveCompanion(
            assignment.companionType,
            assignment.companionIndex,
            assignment.spellId,
            assignment.name,
            assignment.icon
        )
        if companion and companion.companionIndex and GetCompanionCooldown then
            local ok
            ok, startTime, duration, enable = pcall(
                GetCompanionCooldown,
                companion.companionType,
                companion.companionIndex
            )
            if not ok then
                startTime, duration, enable = nil, nil, nil
            end
        end
        if (not startTime or not duration) and assignment.spellId and GetSpellCooldown then
            local ok
            ok, startTime, duration, enable = pcall(GetSpellCooldown, tonumber(assignment.spellId))
            if not ok then
                startTime, duration, enable = nil, nil, nil
            end
        end
    elseif kind == "macro" then
        return nil
    else
        if not assignment.spellId or not GetSpellCooldown then
            return nil
        end

        local spell = ResolveSpell(assignment.spellId, assignment.name)
        if spell and spell.castName then
            local ok
            ok, startTime, duration, enable = pcall(GetSpellCooldown, spell.castName)
            if not ok then
                startTime, duration, enable = nil, nil, nil
            end
        end

        if not startTime or not duration then
            local ok
            ok, startTime, duration, enable = pcall(GetSpellCooldown, tonumber(assignment.spellId))
            if not ok then
                startTime, duration, enable = nil, nil, nil
            end
        end
    end

    startTime = tonumber(startTime)
    duration = tonumber(duration)
    if not startTime or not duration or duration <= 0 then
        return nil
    end

    if kind == "spell" then
        DMLCD.RememberCooldownDuration(assignment.spellId, duration)
    end

    local remaining = (startTime + duration) - GetTime()
    if remaining <= 0 then
        return nil
    end

    return {
        actionKind = kind,
        actionId = GetAssignmentId(assignment),
        actionName = assignment.name,
        duration = duration,
        startMono = startTime,
        sessionExpires = startTime + duration,
        source = kind == "item" and "Blizzard item" or
            (kind == "companion" and "Blizzard companion" or "Blizzard spell"),
        enable = enable
    }
end

local function GetDisplayedCooldownState(assignment)
    if not assignment then
        return nil
    end

    if GetAssignmentKind(assignment) == "spell" then
        local customState = GetCooldownState(assignment.spellId)
        if customState and GetRemaining(customState) > 0 then
            return customState
        end
    end

    return GetNativeCooldownState(assignment)
end

local function UpdateButtonCooldownVisual(button, forceTimer)
    local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex)
    local state = GetDisplayedCooldownState(assignment)

    if state and GetRemaining(state) > 0 then
        ApplyCooldownVisual(button, state, forceTimer)
    else
        ClearCooldownVisual(button)
    end
end

function DMLCD.GetSecureAssignmentValues(assignment, resolved)
    if not assignment or not resolved then
        return nil, nil
    end

    local kind = GetAssignmentKind(assignment)
    if kind == "item" then
        return "item", resolved.secureItem or ("item:" .. tostring(assignment.itemId))
    end
    if kind == "companion" then
        local secureSpell = resolved.castName or resolved.name or
            tonumber(resolved.spellId) or tonumber(assignment.spellId)
        if secureSpell then
            return "spell", secureSpell
        end
        return nil, nil
    end
    if kind == "macro" then
        local macroText = resolved.macroText or assignment.macroBody or assignment.macroText
        if macroText and macroText ~= "" then
            return "macro", macroText
        end
        return nil, nil
    end

    if not resolved.clientKnown then
        return nil, nil
    end

    local secureSpell
    if DMLCD.ShouldSecureCastById(assignment.spellId, resolved) then
        secureSpell = tonumber(resolved.spellId) or tonumber(assignment.spellId)
    else
        secureSpell = resolved.castName or resolved.name or
            tonumber(resolved.spellId) or tonumber(assignment.spellId)
    end

    if secureSpell then
        return "spell", secureSpell
    end
    return nil, nil
end

function DMLCD.ClearBarOneSecurePaging(button)
    if not button or IsInCombat() then
        return
    end

    if UnregisterStateDriver then
        pcall(UnregisterStateDriver, button, "dmlpage")
    end
    button:SetAttribute("_onstate-dmlpage", nil)
    button:SetAttribute("state-dmlpage", nil)

    local page
    for page = 1, 10 do
        button:SetAttribute("dml-type-" .. tostring(page), nil)
        button:SetAttribute("dml-spell-" .. tostring(page), nil)
        button:SetAttribute("dml-item-" .. tostring(page), nil)
        button:SetAttribute("dml-macrotext-" .. tostring(page), nil)
    end
end

function DMLCD.ConfigureBarOneSecurePaging(button)
    if not button or button.barIndex ~= 1 or not DB.useBar1AsStanceBar then
        return false
    end
    if IsInCombat() then
        pendingSecureRefresh = true
        return true
    end

    DMLCD.ClearBarOneSecurePaging(button)

    local page
    for page = 1, 10 do
        local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex, page)
        local resolved = ResolveAssignment(assignment)
        local actionType, actionValue = DMLCD.GetSecureAssignmentValues(assignment, resolved)
        local suffix = tostring(page)
        button:SetAttribute("dml-type-" .. suffix, actionType)
        if actionType == "spell" then
            button:SetAttribute("dml-spell-" .. suffix, actionValue)
        elseif actionType == "item" then
            button:SetAttribute("dml-item-" .. suffix, actionValue)
        elseif actionType == "macro" then
            button:SetAttribute("dml-macrotext-" .. suffix, actionValue)
        end
    end

    button:SetAttribute("_onstate-dmlpage", [[
        local page = newstate or "1"
        self:SetAttribute("type1", self:GetAttribute("dml-type-" .. page))
        self:SetAttribute("spell1", self:GetAttribute("dml-spell-" .. page))
        self:SetAttribute("item1", self:GetAttribute("dml-item-" .. page))
        self:SetAttribute("macrotext1", self:GetAttribute("dml-macrotext-" .. page))
        self:SetAttribute("type2", self:GetAttribute("dml-type-" .. page))
        self:SetAttribute("spell2", self:GetAttribute("dml-spell-" .. page))
        self:SetAttribute("item2", self:GetAttribute("dml-item-" .. page))
        self:SetAttribute("macrotext2", self:GetAttribute("dml-macrotext-" .. page))
    ]])

    local currentPage = tostring(DMLCD.GetBarOneActionPage())
    button:SetAttribute("type1", button:GetAttribute("dml-type-" .. currentPage))
    button:SetAttribute("spell1", button:GetAttribute("dml-spell-" .. currentPage))
    button:SetAttribute("item1", button:GetAttribute("dml-item-" .. currentPage))
    button:SetAttribute("macrotext1", button:GetAttribute("dml-macrotext-" .. currentPage))
    button:SetAttribute("type2", button:GetAttribute("dml-type-" .. currentPage))
    button:SetAttribute("spell2", button:GetAttribute("dml-spell-" .. currentPage))
    button:SetAttribute("item2", button:GetAttribute("dml-item-" .. currentPage))
    button:SetAttribute("macrotext2", button:GetAttribute("dml-macrotext-" .. currentPage))

    if RegisterStateDriver then
        pcall(
            RegisterStateDriver,
            button,
            "dmlpage",
            "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; " ..
            "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1"
        )
    end
    return true
end

local function SetSecureAction(button, assignment, resolved)
    if IsInCombat() then
        pendingSecureRefresh = true
        return
    end

    if button.dmlSuppressSecure then
        DMLCD.ClearBarOneSecurePaging(button)
        button:SetAttribute("type1", nil)
        button:SetAttribute("spell1", nil)
        button:SetAttribute("item1", nil)
        button:SetAttribute("type2", nil)
        button:SetAttribute("spell2", nil)
        button:SetAttribute("item2", nil)
        button:SetAttribute("macrotext1", nil)
        button:SetAttribute("macrotext2", nil)
        return
    end

    if button.barIndex == 1 and DB.useBar1AsStanceBar then
        DMLCD.ConfigureBarOneSecurePaging(button)
        return
    end

    DMLCD.ClearBarOneSecurePaging(button)

    button:SetAttribute("type1", nil)
    button:SetAttribute("spell1", nil)
    button:SetAttribute("item1", nil)
    button:SetAttribute("type2", nil)
    button:SetAttribute("spell2", nil)
    button:SetAttribute("item2", nil)
    button:SetAttribute("macrotext1", nil)
    button:SetAttribute("macrotext2", nil)

    local actionType, actionValue = DMLCD.GetSecureAssignmentValues(assignment, resolved)
    if actionType == "item" then
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", actionValue)
        button:SetAttribute("type2", "item")
        button:SetAttribute("item2", actionValue)
    elseif actionType == "spell" then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", actionValue)
        button:SetAttribute("type2", "spell")
        button:SetAttribute("spell2", actionValue)
    elseif actionType == "macro" then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", actionValue)
        button:SetAttribute("type2", "macro")
        button:SetAttribute("macrotext2", actionValue)
    end
end

local function ShowButtonTooltip(button)
    local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex)
    local simple = DB.simpleTooltips and true or false

    if not assignment then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Empty DML action slot")
        if not simple then
            if not DB.locked then
                GameTooltip:AddLine("Drag a spell, item, macro, mount, or companion pet here, or use an assignment command.", 0.8, 0.8, 0.8, true)
            elseif DB.barLockKey ~= "NONE" then
                GameTooltip:AddLine("Hold " .. GetBarLockKeyLabel() .. " while dropping an action here.", 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:Show()
        return
    end

    local kind = GetAssignmentKind(assignment)
    local resolved = ResolveAssignment(assignment)
    local state = GetDisplayedCooldownState(assignment)
    local remaining = state and GetRemaining(state) or 0
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    if kind == "item" then
        local itemId = tonumber(assignment.itemId)
        if resolved and resolved.link and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(resolved.link)
        else
            GameTooltip:SetText((resolved and resolved.name) or assignment.name or ("Item " .. tostring(itemId)))
            if not simple then
                GameTooltip:AddLine("Item ID " .. tostring(itemId), 0.75, 0.75, 0.75)
                if resolved and resolved.customDefined and not resolved.clientKnown then
                    GameTooltip:AddLine("Using the DML custom item name/icon override.", 0.4, 1, 0.6, true)
                end
            end
        end

        if remaining > 0 then
            GameTooltip:AddLine("Remaining cooldown: " .. (DMLCD.FormatCooldownDuration(remaining) or FormatRemaining(remaining)), 1, 0.82, 0)
        end

        if not simple then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("DML item action", 0.4, 1, 0.6)
            if state and remaining > 0 then
                GameTooltip:AddLine("Source: " .. tostring(state.source or "unknown"), 0.8, 0.8, 0.8)
            end
        end
    elseif kind == "companion" then
        local companion = resolved
        local spellId = tonumber((companion and companion.spellId) or assignment.spellId)
        if spellId and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink("spell:" .. tostring(spellId))
        else
            GameTooltip:SetText((companion and companion.name) or assignment.name or "Companion")
        end

        local companionType = DMLCD.NormalizeCompanionType(
            (companion and companion.companionType) or assignment.companionType
        )
        if remaining > 0 then
            GameTooltip:AddLine("Remaining cooldown: " .. (DMLCD.FormatCooldownDuration(remaining) or FormatRemaining(remaining)), 1, 0.82, 0)
        end
        if not simple then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                companionType == "MOUNT" and "DML mount action" or "DML companion pet action",
                0.4, 1, 0.6
            )
            if companion and companion.active then
                GameTooltip:AddLine("Currently active", 1, 0.82, 0)
            end
            if companion and not companion.available then
                GameTooltip:AddLine("This companion is not currently available in the collection.", 1, 0.35, 0.35, true)
            end
        end
    elseif kind == "macro" then
        local macro = resolved
        GameTooltip:SetText((macro and macro.name) or assignment.macroName or assignment.name or "Macro")
        if not simple then
            local macroText = (macro and macro.macroText) or assignment.macroBody or assignment.macroText
            if macroText and macroText ~= "" then
                GameTooltip:AddLine(macroText, 0.82, 0.82, 0.82, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("DML macro action", 0.4, 1, 0.6)
            if macro and not macro.clientKnown then
                GameTooltip:AddLine("Using the macro body saved in this DML profile.", 0.8, 0.8, 0.8, true)
            end
        end
    else
        local spell = resolved
        if spell and spell.clientKnown then
            if GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("spell:" .. tostring(spell.spellId))
            else
                GameTooltip:SetText(spell.name)
            end
        else
            GameTooltip:SetText((spell and spell.name) or assignment.name or ("Spell " .. tostring(assignment.spellId)))
            if not simple then
                GameTooltip:AddLine("Spell ID " .. tostring(assignment.spellId), 0.75, 0.75, 0.75)
            end
            GameTooltip:AddLine("This spell is not present in the client Spell.dbc. The addon can show its server timer, but the button cannot securely cast it.", 1, 0.35, 0.35, true)
        end

        if spell and spell.customText and spell.customText ~= "" then
            GameTooltip:AddLine(spell.customText, 1, 0.82, 0.2, true)
        end

        local scalingSpellId = tonumber(
            (spell and spell.spellId) or assignment.spellId
        )
        local bonusDamage =
            scalingSpellId and
            DMLCD.scalingBonusDamage and
            DMLCD.scalingBonusDamage[scalingSpellId]
        local extraManaCost =
            scalingSpellId and
            DMLCD.scalingManaCost and
            DMLCD.scalingManaCost[scalingSpellId]
        local scalingParts = {}

        if bonusDamage and bonusDamage > 0 then
            table.insert(
                scalingParts,
                "+" .. tostring(bonusDamage) .. " bonus damage"
            )
        end

        if extraManaCost and extraManaCost > 0 then
            table.insert(
                scalingParts,
                "+" .. tostring(extraManaCost) .. " mana cost"
            )
        end

        if #scalingParts > 0 then
            GameTooltip:AddLine(
                "Level scaling: " .. table.concat(scalingParts, ", "),
                1,
                0.82,
                0.2,
                true
            )
        end

        if spell and spell.rankText and spell.rankText ~= "" then
            GameTooltip:AddLine(spell.rankText, 0.4, 1, 0.6)
        end

        local totalCooldown = DMLCD.GetKnownCooldownDuration(assignment, state)
        if totalCooldown then
            GameTooltip:AddLine("Spell cooldown: " .. (DMLCD.FormatCooldownDuration(totalCooldown) or tostring(totalCooldown)), 0.4, 1, 0.6)
        else
            GameTooltip:AddLine("Spell cooldown: Unknown until first use", 0.65, 0.65, 0.65)
        end

        if remaining > 0 then
            GameTooltip:AddLine("Remaining cooldown: " .. (DMLCD.FormatCooldownDuration(remaining) or FormatRemaining(remaining)), 0.4, 1, 0.6)
        end

        if not simple then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("DML cooldown tracking", 0.4, 1, 0.6)
            GameTooltip:AddLine("Fallback: " .. tostring(assignment.fallback or 0) .. " seconds", 0.8, 0.8, 0.8)
            if state and remaining > 0 then
                GameTooltip:AddLine("Source: " .. tostring(state.source or "unknown"), 0.8, 0.8, 0.8)
            end
        end
    end

    local key = DB.keybinds and DB.keybinds[button.dmlIndex]
    if key and not simple then
        GameTooltip:AddLine("Keybind: " .. tostring(key), 0.4, 1, 0.6)
    end

    if button.dmlResourceLow then
        GameTooltip:AddLine("Not enough mana or other spell resource.", 1, 0.35, 0.35, true)
    end

    if not simple then
        if not DB.locked then
            GameTooltip:AddLine("Drag this action off the bar to remove or move it.", 0.7, 0.7, 0.7, true)
        elseif DB.barLockKey ~= "NONE" then
            GameTooltip:AddLine("Hold " .. GetBarLockKeyLabel() .. " and drag to remove or move this action.", 0.7, 0.7, 0.7, true)
        end
    end

    GameTooltip:Show()
end

local function UpdateCombatDropOverlay(button)
    if button and button.combatDropOverlay then
        button.combatDropOverlay:Hide()
    end
end

local function UpdateButton(button)
    local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex)

    if not assignment then
        button.icon:SetTexture(nil)
        button.emptyText:SetText(tostring(button.slotIndex or button.dmlIndex))
        if DB.showSlotNumbers then
            button.emptyText:Show()
        else
            button.emptyText:Hide()
        end
        button.actionKind = nil
        button.actionId = nil
        button.actionName = nil
        button.spellId = nil
        button.spellName = nil
        button.dmlResolved = nil
        button.dmlActionCurrent = false
        if button.stateHighlight then
            button.stateHighlight:Hide()
        end
        if button.pendingText then
            button.pendingText:Hide()
        end
        button.dmlResourceLow = false
        button.dmlRangeState = nil
        button.dmlOutOfRange = false
        if button.rangeBorder then
            button.rangeBorder:Hide()
        end
        UpdateCombatDropOverlay(button)
        SetSecureAction(button, nil, nil)
        ClearCooldownVisual(button)
        if button.hotkeyText and DB.keybinds then
            button.hotkeyText:SetText(DMLCD.CompactBindingText(DB.keybinds[button.dmlIndex]))
        end
        return
    end

    local kind = GetAssignmentKind(assignment)
    local resolved = ResolveAssignment(assignment)
    if resolved then
        assignment.kind = kind
        assignment.name = resolved.name
        if kind == "companion" then
            assignment.companionType = resolved.companionType or assignment.companionType
            assignment.companionIndex = resolved.companionIndex or assignment.companionIndex
            assignment.spellId = resolved.spellId or assignment.spellId
            assignment.icon = resolved.icon or assignment.icon
        elseif kind == "macro" then
            assignment.macroIndex = resolved.macroIndex or assignment.macroIndex
            assignment.macroName = resolved.macroName or resolved.name or assignment.macroName
            assignment.macroIcon = resolved.icon or assignment.macroIcon
            assignment.macroBody = resolved.macroText or assignment.macroBody
        end
        button.dmlResolved = resolved
        button.icon:SetTexture(resolved.icon or QUESTION_ICON)
        button.actionKind = kind
        button.actionId = GetAssignmentId(assignment)
        button.actionName = resolved.name
        if kind == "spell" then
            button.spellId = resolved.spellId
            button.spellName = resolved.name
        else
            button.spellId = nil
            button.spellName = nil
        end
        button.emptyText:Hide()
        SetSecureAction(button, assignment, resolved)
    else
        button.dmlResolved = nil
        button.dmlActionCurrent = false
        if button.stateHighlight then
            button.stateHighlight:Hide()
        end
        button.icon:SetTexture(QUESTION_ICON)
        button.actionKind = kind
        button.actionId = GetAssignmentId(assignment)
        if kind == "companion" then
            button.actionName = assignment.name or
                (DMLCD.NormalizeCompanionType(assignment.companionType) == "MOUNT" and "Mount " or "Companion pet ") ..
                tostring(GetAssignmentId(assignment))
        elseif kind == "macro" then
            button.actionName = assignment.macroName or assignment.name or "Macro"
        else
            button.actionName = assignment.name or ((kind == "item" and "Item " or "Spell ") .. tostring(GetAssignmentId(assignment)))
        end
        button.spellId = kind == "spell" and assignment.spellId or nil
        button.spellName = kind == "spell" and button.actionName or nil
        button.emptyText:Hide()
        SetSecureAction(button, assignment, nil)
    end

    if button.pendingText then
        button.pendingText:Hide()
    end
    UpdateCombatDropOverlay(button)

    UpdateButtonCooldownVisual(button, true)
    DMLCD.UpdateButtonResourceVisual(button)
    DMLCD.UpdateButtonActionStateVisual(button, assignment, resolved)
    DMLCD.UpdateButtonRangeVisual(button, assignment, resolved)

    if button.hotkeyText and DB.keybinds then
        button.hotkeyText:SetText(DMLCD.CompactBindingText(DB.keybinds[button.dmlIndex]))
    end
end

function DMLCD.RefreshAllButtonEntry(_, button)
    if button then
        UpdateButton(button)
    end
end

local function RefreshAllButtons()
    ForEachActiveButton(DMLCD.RefreshAllButtonEntry)

    -- Keep the optional DML pet bar's empty-slot numbers synchronized with the
    -- same Show slot numbers setting used by the player bars.
    if DMLCD.RefreshPetBar then
        DMLCD.RefreshPetBar()
    end
end

function DMLCD.RefreshItemAssignmentEntry(index, button)
    local assignment = DMLCD.GetAssignmentForIndex(index)
    local itemId = DMLCD.refreshItemAssignmentId
    if button and assignment and GetAssignmentKind(assignment) == "item" and
        (not itemId or tonumber(assignment.itemId) == itemId)
    then
        UpdateButton(button)
    end
end

function DMLCD.RefreshItemAssignmentButtons(itemId)
    DMLCD.refreshItemAssignmentId = tonumber(itemId)
    ForEachActiveButton(DMLCD.RefreshItemAssignmentEntry)
    DMLCD.refreshItemAssignmentId = nil
end

function DMLCD.HandleItemInfoReceived(itemId, success)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end

    if success == false or success == 0 then
        local now = GetTime and GetTime() or 0
        DMLCD.itemInfoRetryAt[itemId] = now + DMLCD.ITEM_INFO_RETRY_DELAY
        return
    end

    -- The client says this exact item is ready. Clear only that cache entry and
    -- refresh only DML buttons assigned to that item.
    DMLCD.InvalidateItemInfoCache(itemId)
    DMLCD.RefreshItemAssignmentButtons(itemId)
end

function DMLCD.RefreshBarOneStancePage()
    if not DB or not DB.useBar1AsStanceBar then
        DMLCD.stancePageRefreshDue = nil
        return
    end

    DMLCD.stancePageRefreshDue = nil
    local settings = DMLCD.GetBarSettings(1)
    local slotIndex
    for slotIndex = 1, settings.buttonCount do
        local button = buttons[GlobalIndex(1, slotIndex)]
        if button then
            UpdateButton(button)
        end
    end
end

function DMLCD.ScheduleBarOneStanceRefresh(delay)
    if DB and DB.useBar1AsStanceBar then
        DMLCD.stancePageRefreshDue = GetTime() + (tonumber(delay) or 0.05)
    end
end

function DMLCD.RefreshCompanionAssignmentEntry(index, button)
    local assignment = DMLCD.GetAssignmentForIndex(index)
    local companionType = DMLCD.refreshCompanionType
    if button and assignment and GetAssignmentKind(assignment) == "companion" and
        (not companionType or DMLCD.NormalizeCompanionType(assignment.companionType) == companionType)
    then
        UpdateButton(button)
    end
end

function DMLCD.RefreshCompanionAssignments(companionType)
    DMLCD.refreshCompanionType = DMLCD.NormalizeCompanionType(companionType)
    ForEachActiveButton(DMLCD.RefreshCompanionAssignmentEntry)
    DMLCD.refreshCompanionType = nil
end

local function FindAssignedButton(spellId)
    spellId = tonumber(spellId)
    local found
    ForEachActiveButton(function(index)
        if not found then
            local assignment = DB.assignments[index]
            if assignment and GetAssignmentKind(assignment) == "spell" and tonumber(assignment.spellId) == spellId then
                found = index
            end
        end
    end)
    return found
end

function DMLCD.GetSpellFamilyKey(spell)
    if not spell then
        return nil
    end
    local family = spell.family or spell.name
    if not family or family == "" then
        return nil
    end
    return string.lower(tostring(family))
end

function DMLCD.FindAssignedButtonByFamily(spell)
    local familyKey = DMLCD.GetSpellFamilyKey(spell)
    if not familyKey then
        return nil, nil
    end

    local foundIndex, foundSpell
    ForEachActiveButton(function(index)
        if not foundIndex then
            local assignment = DB.assignments[index]
            if assignment and GetAssignmentKind(assignment) == "spell" then
                local resolved = ResolveSpell(assignment.spellId, assignment.name)
                if DMLCD.GetSpellFamilyKey(resolved) == familyKey then
                    foundIndex = index
                    foundSpell = resolved
                end
            end
        end
    end)
    return foundIndex, foundSpell
end

local function FindFirstEmptyButton()
    local found
    ForEachActiveButton(function(index)
        if not found and not DB.assignments[index] then
            found = index
        end
    end)
    return found
end

local function AssignButton(index, spellId, fallbackSeconds, suppliedName, allowUnresolved, feedbackMode, pageOverride)
    index = tonumber(index)
    spellId = tonumber(spellId)
    fallbackSeconds = tonumber(fallbackSeconds) or 0

    if not index or not IsActiveButtonIndex(index) then
        local message = "That DML button is not active."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    if not spellId or spellId < 1 then
        if feedbackMode == "debug" then DebugPrint("Invalid spell ID.") else Print("Invalid spell ID.") end
        return false
    end

    if IsInCombat() then
        local message = "DML spell assignments cannot be changed during combat."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    local spell = ResolveSpell(spellId, suppliedName)
    if not spell and not allowUnresolved then
        local message = "Spell ID " .. tostring(spellId) .. " is not present in this 3.3.5a client's Spell.dbc."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    if not spell then
        spell = {
            spellId = spellId,
            name = suppliedName or ("Spell " .. tostring(spellId)),
            clientKnown = false,
            icon = QUESTION_ICON
        }
    end

    DMLCD.SetAssignmentForIndex(index, {
        kind = "spell",
        spellId = spellId,
        name = spell.name,
        fallback = math.max(0, fallbackSeconds)
    }, pageOverride)

    pendingCombatAssignments[index] = nil
    UpdateButton(buttons[index])

    local feedback
    if spell.clientKnown then
        feedback = FormatButtonRef(index) .. " assigned to " .. spell.name .. " (" .. tostring(spellId) .. ")."
    else
        feedback = FormatButtonRef(index) .. " assigned for display-only tracking of " .. spell.name .. " (" .. tostring(spellId) .. ")."
    end

    if feedbackMode == "debug" then
        DebugPrint(feedback)
    elseif feedbackMode ~= "silent" and feedbackMode ~= false then
        Print(feedback)
    end

    if SaveCharacterLayoutSnapshot then
        SaveCharacterLayoutSnapshot()
    end
    return true
end

local function AssignItemButton(index, itemId, suppliedName, feedbackMode, pageOverride)
    index = tonumber(index)
    itemId = tonumber(itemId)

    if not index or not IsActiveButtonIndex(index) then
        local message = "That DML button is not active."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    if not itemId or itemId < 1 then
        if feedbackMode == "debug" then DebugPrint("Invalid item ID.") else Print("Invalid item ID.") end
        return false
    end

    if IsInCombat() then
        local message = "DML item assignments cannot be changed during combat."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    local item = DMLCD.ResolveItem(itemId, suppliedName)
    if not item then
        local message = "Item ID " .. tostring(itemId) .. " could not be resolved."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    DMLCD.SetAssignmentForIndex(index, {
        kind = "item",
        itemId = itemId,
        name = item.name,
        fallback = 0
    }, pageOverride)

    UpdateButton(buttons[index])

    local feedback = FormatButtonRef(index) .. " assigned to " .. item.name .. " (item " .. tostring(itemId) .. ")."
    if feedbackMode == "debug" then
        DebugPrint(feedback)
    elseif feedbackMode ~= "silent" and feedbackMode ~= false then
        Print(feedback)
    end
    if SaveCharacterLayoutSnapshot then
        SaveCharacterLayoutSnapshot()
    end
    return true
end

function DMLCD.AssignMacroButton(index, macroIndex, suppliedName, suppliedIcon, suppliedBody, feedbackMode, pageOverride)
    index = tonumber(index)
    macroIndex = tonumber(macroIndex)

    if not index or not IsActiveButtonIndex(index) then
        local message = "That DML button is not active."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end
    if IsInCombat() then
        local message = "DML macro assignments cannot be changed during combat."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    local macro = DMLCD.ResolveMacro(macroIndex, suppliedName, suppliedIcon, suppliedBody)
    if not macro then
        local message = "That macro could not be resolved or has an empty body."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    DMLCD.SetAssignmentForIndex(index, {
        kind = "macro",
        macroIndex = macro.macroIndex or macroIndex,
        macroName = macro.macroName or macro.name,
        macroIcon = macro.icon,
        macroBody = macro.macroText,
        name = macro.name,
        fallback = 0
    }, pageOverride)

    UpdateButton(buttons[index])
    local feedback = FormatButtonRef(index) .. " assigned to macro " .. tostring(macro.name) .. "."
    if feedbackMode == "debug" then
        DebugPrint(feedback)
    elseif feedbackMode ~= "silent" and feedbackMode ~= false then
        Print(feedback)
    end
    if SaveCharacterLayoutSnapshot then
        SaveCharacterLayoutSnapshot()
    end
    return true
end

local function AssignCompanionButton(index, companionType, companionIndex, spellId, suppliedName, suppliedIcon, feedbackMode, pageOverride)
    index = tonumber(index)
    companionType = DMLCD.NormalizeCompanionType(companionType)
    companionIndex = tonumber(companionIndex)
    spellId = tonumber(spellId)

    if not index or not IsActiveButtonIndex(index) then
        local message = "That DML button is not active."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end
    if not companionType or (not companionIndex and not spellId) then
        local message = "That mount or companion pet could not be identified."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end
    if IsInCombat() then
        local message = "DML companion assignments cannot be changed during combat."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    local companion = DMLCD.ResolveCompanion(
        companionType,
        companionIndex,
        spellId,
        suppliedName,
        suppliedIcon
    )
    if not companion then
        local message = "That mount or companion pet could not be resolved."
        if feedbackMode == "debug" then DebugPrint(message) else Print(message) end
        return false
    end

    DMLCD.SetAssignmentForIndex(index, {
        kind = "companion",
        companionType = companion.companionType,
        companionIndex = companion.companionIndex or companionIndex,
        spellId = companion.spellId or spellId,
        name = companion.name,
        icon = companion.icon,
        fallback = 0
    }, pageOverride)

    UpdateButton(buttons[index])
    local feedback = FormatButtonRef(index) .. " assigned to " .. companion.name ..
        " (" .. DMLCD.GetCompanionTypeLabel(companion.companionType) .. ")."
    if feedbackMode == "debug" then
        DebugPrint(feedback)
    elseif feedbackMode ~= "silent" and feedbackMode ~= false then
        Print(feedback)
    end
    if SaveCharacterLayoutSnapshot then
        SaveCharacterLayoutSnapshot()
    end
    return true
end

local function ClearAssignment(index, silent, pageOverride)
    index = tonumber(index)
    if IsInCombat() then
        if not silent then
            Print("DML assignments cannot be cleared during combat.")
        end
        return false
    end
    if not index or not IsActiveButtonIndex(index) then
        if not silent then
            Print("That DML button is not active.")
        end
        return false
    end

    DMLCD.ClearAssignmentForIndex(index, pageOverride)
    pendingFallbacks[index] = nil
    UpdateButton(buttons[index])

    if not silent then
        Print(FormatButtonRef(index) .. " cleared.")
    end
    if SaveCharacterLayoutSnapshot then
        SaveCharacterLayoutSnapshot()
    end
    return true
end

local function CopyAssignment(assignment)
    if not assignment then
        return nil
    end

    local copy = {
        kind = GetAssignmentKind(assignment),
        name = assignment.name,
        fallback = tonumber(assignment.fallback) or 0
    }
    if copy.kind == "item" then
        copy.itemId = tonumber(assignment.itemId) or assignment.itemId
    elseif copy.kind == "companion" then
        copy.companionType = DMLCD.NormalizeCompanionType(assignment.companionType)
        copy.companionIndex = tonumber(assignment.companionIndex) or assignment.companionIndex
        copy.spellId = tonumber(assignment.spellId) or assignment.spellId
        copy.icon = assignment.icon
    elseif copy.kind == "macro" then
        copy.macroIndex = tonumber(assignment.macroIndex) or assignment.macroIndex
        copy.macroName = assignment.macroName or assignment.name
        copy.macroIcon = assignment.macroIcon or assignment.icon
        copy.macroBody = assignment.macroBody or assignment.macroText
    else
        copy.spellId = tonumber(assignment.spellId) or assignment.spellId
    end
    return copy
end

local function ExtractDraggedSpellId()
    local cursorType, info1, info2 = GetCursorInfo()
    if cursorType ~= "spell" then
        return nil
    end

    local spellId
    local bookType = info2

    -- Wrath clients commonly provide a spellbook slot plus book type.
    if bookType == BOOKTYPE_SPELL or bookType == BOOKTYPE_PET or bookType == "spell" or bookType == "pet" then
        if GetSpellLink then
            local link = GetSpellLink(info1, bookType)
            if link then
                spellId = tonumber(string.match(link, "spell:(%d+)"))
            end
        end
    end

    -- Some clients/builds provide the spell ID directly.
    if not spellId and tonumber(info1) and GetSpellInfo(tonumber(info1)) then
        spellId = tonumber(info1)
    end

    return spellId
end

local function ExtractDraggedItemId()
    if not GetCursorInfo then
        return nil
    end
    local cursorType, info1, info2 = GetCursorInfo()
    if cursorType ~= "item" then
        return nil
    end

    local itemId = tonumber(info1)
    if not itemId and info2 then
        itemId = tonumber(string.match(tostring(info2), "item:(%d+)"))
    end
    return itemId
end

function DMLCD.ExtractDraggedMacroAssignment(cursorType, info1)
    if cursorType ~= "macro" then
        return nil
    end

    local macroIndex = tonumber(info1)
    if not macroIndex or not GetMacroInfo then
        return nil
    end

    local ok, macroName, macroIcon, macroBody = pcall(GetMacroInfo, macroIndex)
    if not ok or not macroName or not macroBody or macroBody == "" then
        return nil
    end

    return {
        kind = "macro",
        macroIndex = macroIndex,
        macroName = macroName,
        macroIcon = macroIcon,
        macroBody = macroBody,
        name = macroName
    }
end

local function ExtractCursorAssignment()
    if not GetCursorInfo then
        return nil
    end
    local cursorType, info1, info2 = GetCursorInfo()
    local companionAssignment = DMLCD.ExtractCompanionCursorAssignment(cursorType, info1, info2)
    if companionAssignment then
        return companionAssignment
    end
    if cursorType == "spell" then
        local spellId = ExtractDraggedSpellId()
        if spellId then
            return { kind = "spell", spellId = spellId }
        end
    elseif cursorType == "item" then
        local itemId = ExtractDraggedItemId()
        if itemId then
            return { kind = "item", itemId = itemId }
        end
    elseif cursorType == "macro" then
        return DMLCD.ExtractDraggedMacroAssignment(cursorType, info1)
    end
    return nil
end

local function CursorContainsAction()
    if not GetCursorInfo then
        return false
    end
    local cursorType = GetCursorInfo()
    return cursorType == "spell" or cursorType == "item" or cursorType == "companion" or cursorType == "macro"
end

local function FindSpellBookSlot(spellId)
    spellId = tonumber(spellId)
    if not spellId or not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellLink then
        return nil
    end

    local tabCount = GetNumSpellTabs()
    local tab
    for tab = 1, tabCount do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset = tonumber(offset) or 0
        numSpells = tonumber(numSpells) or 0

        local slot
        for slot = offset + 1, offset + numSpells do
            local link = GetSpellLink(slot, BOOKTYPE_SPELL)
            local linkedId = link and tonumber(string.match(link, "spell:(%d+)"))
            if linkedId == spellId then
                return slot
            end
        end
    end

    return nil
end

local function PickupAssignedAction(assignment)
    if not assignment then
        return false
    end

    local kind = GetAssignmentKind(assignment)
    if kind == "macro" then
        if not PickupMacro then
            return false
        end
        local macro = DMLCD.ResolveMacro(
            assignment.macroIndex,
            assignment.macroName or assignment.name,
            assignment.macroIcon or assignment.icon,
            assignment.macroBody or assignment.macroText
        )
        local macroIndex = macro and tonumber(macro.macroIndex) or tonumber(assignment.macroIndex)
        if (not macroIndex or macroIndex <= 0) and GetMacroIndexByName then
            local ok, foundIndex = pcall(GetMacroIndexByName, assignment.macroName or assignment.name)
            macroIndex = ok and tonumber(foundIndex) or nil
        end
        if not macroIndex or macroIndex <= 0 then
            return false
        end
        local ok = pcall(PickupMacro, macroIndex)
        if not ok then
            return false
        end
        local cursorAssignment = ExtractCursorAssignment()
        return cursorAssignment and AssignmentMatches(assignment, cursorAssignment) or false
    end
    if kind == "companion" then
        if not PickupCompanion then
            return false
        end
        local companion = DMLCD.ResolveCompanion(
            assignment.companionType,
            assignment.companionIndex,
            assignment.spellId,
            assignment.name,
            assignment.icon
        )
        if not companion or not companion.companionIndex then
            return false
        end
        local ok = pcall(PickupCompanion, companion.companionType, companion.companionIndex)
        if not ok then
            return false
        end
        local cursorAssignment = ExtractCursorAssignment()
        return cursorAssignment and AssignmentMatches(assignment, cursorAssignment) or false
    end

    if kind == "item" then
        local itemId = tonumber(assignment.itemId)
        if not itemId or not PickupItem then
            return false
        end

        -- Different 3.3.5a client builds accept an item link string, numeric ID,
        -- or item name here. Try all three without requiring the item cache.
        local attempts = {
            "item:" .. tostring(itemId),
            itemId,
            assignment.name
        }
        local attemptIndex
        for attemptIndex = 1, #attempts do
            local value = attempts[attemptIndex]
            if value then
                local ok = pcall(PickupItem, value)
                if ok then
                    local cursorAssignment = ExtractCursorAssignment()
                    if cursorAssignment and cursorAssignment.kind == "item" and tonumber(cursorAssignment.itemId) == itemId then
                        return true
                    end
                end
                if ClearCursor then
                    ClearCursor()
                end
            end
        end
        return false
    end

    local spellId = tonumber(assignment.spellId)
    if not spellId then
        return false
    end

    -- Prefer the spellbook pickup API because it mirrors Blizzard's own
    -- spellbook drag behavior on Wrath clients.
    local slot = FindSpellBookSlot(spellId)
    if slot and PickupSpellBookItem then
        local ok = pcall(PickupSpellBookItem, slot, BOOKTYPE_SPELL)
        if ok then
            local cursorAssignment = ExtractCursorAssignment()
            if cursorAssignment and cursorAssignment.kind == "spell" and tonumber(cursorAssignment.spellId) == spellId then
                return true
            end
        end
    end

    -- Some 3.3.5a clients expose PickupSpell by spell ID or name.
    if PickupSpell then
        local ok = pcall(PickupSpell, spellId)
        if ok then
            local cursorAssignment = ExtractCursorAssignment()
            if cursorAssignment and cursorAssignment.kind == "spell" and tonumber(cursorAssignment.spellId) == spellId then
                return true
            end
        end

        local spell = ResolveSpell(spellId, assignment.name)
        if spell and spell.castName then
            ok = pcall(PickupSpell, spell.castName)
            if ok then
                local cursorAssignment = ExtractCursorAssignment()
                if cursorAssignment and cursorAssignment.kind == "spell" and tonumber(cursorAssignment.spellId) == spellId then
                    return true
                end
            end
        end
    end

    return false
end

local function StartCooldown(spellId, durationSeconds, token, spellName, source)
    spellId = tonumber(spellId)
    durationSeconds = tonumber(durationSeconds)
    if not spellId or not durationSeconds or durationSeconds <= 0 then
        return false
    end

    local nowMono = GetTime()
    local key = GetCooldownKey(spellId)
    local state = {
        spellId = spellId,
        spellName = spellName,
        duration = durationSeconds,
        token = tostring(token or ""),
        source = source or "ALE",
        startedAt = time(),
        expiresAt = time() + math.ceil(durationSeconds),
        startMono = nowMono,
        sessionExpires = nowMono + durationSeconds
    }

    DB.cooldowns[key] = state
    DMLCD.RememberCooldownDuration(spellId, durationSeconds)

    ForEachActiveButton(function(index, button)
        local assignment = DMLCD.GetAssignmentForIndex(index)
        if button and assignment and GetAssignmentKind(assignment) == "spell" and tonumber(assignment.spellId) == spellId then
            ApplyCooldownVisual(button, state)
        end
    end)

    if DB.showMessages or DB.debugMessages then
        local spell = ResolveSpell(spellId, spellName)
        local name = spell and spell.name or spellName or ("Spell " .. tostring(spellId))
        Print(name .. " cooldown started: " .. FormatRemaining(durationSeconds) .. ".")
    end

    return true
end

local function ClearCooldown(spellId, announce, suppliedName)
    spellId = tonumber(spellId)
    if not spellId then
        return false
    end

    local key = GetCooldownKey(spellId)
    local oldState = DB.cooldowns[key]
    DB.cooldowns[key] = nil

    ForEachActiveButton(function(index, button)
        local assignment = DMLCD.GetAssignmentForIndex(index)
        if button and assignment and GetAssignmentKind(assignment) == "spell" and tonumber(assignment.spellId) == spellId then
            ClearCooldownVisual(button)
        end
    end)

    if announce and (DB.showReadyMessages or DB.debugMessages) then
        local spell = ResolveSpell(spellId, suppliedName or (oldState and oldState.spellName))
        local name = spell and spell.name or suppliedName or (oldState and oldState.spellName) or ("Spell " .. tostring(spellId))
        Print(name .. " is ready.")
    end

    return oldState ~= nil
end

local function BuildSpellbookSnapshot()
    local snapshot = {}
    if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellLink then
        return snapshot
    end

    local tabCount = tonumber(GetNumSpellTabs()) or 0
    local tab
    for tab = 1, tabCount do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset = tonumber(offset) or 0
        numSpells = tonumber(numSpells) or 0

        local slot
        for slot = offset + 1, offset + numSpells do
            local passive = IsPassiveSpell and IsPassiveSpell(slot, BOOKTYPE_SPELL)
            if not passive then
                local spellId
                if GetSpellBookItemInfo then
                    local _, bookSpellId = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
                    spellId = tonumber(bookSpellId)
                end
                if not spellId then
                    local link = GetSpellLink(slot, BOOKTYPE_SPELL)
                    spellId = link and tonumber(string.match(link, "spell:(%d+)"))
                end
                if spellId then
                    local name, rank
                    if GetSpellName then
                        name, rank = GetSpellName(slot, BOOKTYPE_SPELL)
                    end
                    local resolved = ResolveSpell(spellId, name)
                    snapshot[spellId] = {
                        spellId = spellId,
                        name = (resolved and resolved.name) or name or ("Spell " .. tostring(spellId)),
                        rank = (resolved and resolved.rank) or rank or "",
                        slot = slot
                    }
                end
            end
        end
    end
    return snapshot
end

local function QueueLearnedSpell(spellId, spellName)
    spellId = tonumber(spellId)
    if not spellId or spellId < 1 then
        return false
    end
    pendingLearnedSpells[spellId] = {
        spellId = spellId,
        name = spellName
    }
    return true
end

local function AutoAssignLearnedSpell(spellId, suppliedName)
    spellId = tonumber(spellId)
    if not DB.autoAssign or not spellId then
        return false
    end

    if FindAssignedButton(spellId) then
        return false
    end

    local spell = ResolveSpell(spellId, suppliedName)
    if not spell then
        DebugPrint("Learned spell " .. tostring(spellId) .. " could not be resolved by the client.")
        return false
    end

    if IsInCombat() then
        QueueLearnedSpell(spellId, spell.name)
        DebugPrint(spell.name .. " auto-assignment queued until combat ends.")
        return false
    end

    -- New ranks replace an existing lower rank in the same custom family.
    -- Explicit numeric ranks prevent custom spells that all claim "Rank 1" in
    -- the client data from replacing newer ranks with older spell IDs.
    local familyIndex, existingSpell = DMLCD.FindAssignedButtonByFamily(spell)
    if familyIndex then
        local newRank = tonumber(spell.rankNumber)
        local oldRank = existingSpell and tonumber(existingSpell.rankNumber)
        if newRank and oldRank and newRank <= oldRank then
            DebugPrint(spell.name .. " " .. (spell.rankText or "rank") .. " did not replace the currently assigned " .. (existingSpell.rankText or "rank") .. ".")
            return false
        end

        local old = DB.assignments[familyIndex]
        local fallback = old and tonumber(old.fallback) or 0
        local assigned = AssignButton(familyIndex, spellId, fallback, spell.name, false, "silent", 1)
        if assigned then
            DebugPrint(spell.name .. " " .. (spell.rankText or "rank") .. " updated on " .. string.lower(FormatButtonRef(familyIndex)) .. ".")
        end
        return assigned
    end

    local emptyIndex = FindFirstEmptyButton()
    if not emptyIndex then
        DebugPrint("No empty DML slot was available for newly learned " .. spell.name .. ".")
        return false
    end

    local assigned = AssignButton(emptyIndex, spellId, 0, spell.name, false, "silent", 1)
    if assigned then
        DebugPrint(spell.name .. " auto-assigned to " .. string.lower(FormatButtonRef(emptyIndex)) .. ".")
    end
    return assigned
end

local function PrimeSpellbookSnapshot()
    knownSpellbookSpells = BuildSpellbookSnapshot()
    spellbookSnapshotReady = true
end

local function HandleSpellbookChanged()
    local current = BuildSpellbookSnapshot()
    if not spellbookSnapshotReady then
        knownSpellbookSpells = current
        spellbookSnapshotReady = true
        return
    end

    local learned = {}
    local spellId, data
    for spellId, data in pairs(current) do
        if not knownSpellbookSpells[spellId] then
            table.insert(learned, data)
        end
    end

    table.sort(learned, function(left, right)
        return (tonumber(left.slot) or 0) < (tonumber(right.slot) or 0)
    end)

    local _, learnedSpell
    for _, learnedSpell in ipairs(learned) do
        AutoAssignLearnedSpell(learnedSpell.spellId, learnedSpell.name)
    end

    knownSpellbookSpells = current
end

local function ProcessPendingLearnedSpells()
    local queued = pendingLearnedSpells
    pendingLearnedSpells = {}

    local spellId, data
    for spellId, data in pairs(queued) do
        AutoAssignLearnedSpell(spellId, data and data.name)
    end
end

local function HandleStart(spellId, cooldownMs, token, spellName)
    spellId = tonumber(spellId)
    cooldownMs = tonumber(cooldownMs)

    if not spellId or not cooldownMs or cooldownMs <= 0 then
        return
    end

    local durationSeconds = cooldownMs / 1000

    -- Cooldown START messages no longer create bar assignments. Auto-assign
    -- happens when the client reports that the player learned the spell.
    StartCooldown(spellId, durationSeconds, token, spellName, "ALE")

    -- Cancel any click fallback waiting for this spell.
    ForEachActiveButton(function(index)
        local assignment = DMLCD.GetAssignmentForIndex(index)
        if assignment and GetAssignmentKind(assignment) == "spell" and tonumber(assignment.spellId) == spellId then
            pendingFallbacks[index] = nil
        end
    end)
end

local function HandleReady(spellId, token, spellName)
    spellId = tonumber(spellId)
    if not spellId then
        return
    end

    local state = GetCooldownState(spellId)
    if not state then
        return
    end

    if tostring(state.token or "") ~= tostring(token or "") then
        -- Stale READY message from an older cast; ignore it.
        return
    end

    ClearCooldown(spellId, true, spellName)
end

local function HandleCooldownUpdate(spellId, cooldownMs, spellName)
    spellId = tonumber(spellId)
    cooldownMs = tonumber(cooldownMs)

    if not spellId or not cooldownMs then
        return
    end

    if cooldownMs <= 0 then
        ClearCooldown(spellId, false, spellName)
        DMLCD.RefreshSpellAssignment(spellId)
        return
    end

    local durationSeconds = cooldownMs / 1000

    -- Lua-managed cooldowns send the *remaining* cooldown after every update.
    -- Restart the visual timer from now with that remaining duration.
    StartCooldown(
        spellId,
        durationSeconds,
        "lua-managed",
        spellName,
        "ALE Lua"
    )

    DMLCD.RefreshSpellAssignment(spellId)
end

function DMLCD.SplitProtocolFields(message)
    local fields = {}
    local startAt = 1
    while true do
        local separator = string.find(message, "|", startAt, true)
        if not separator then
            table.insert(fields, string.sub(message, startAt))
            break
        end
        table.insert(fields, string.sub(message, startAt, separator - 1))
        startAt = separator + 1
    end
    return fields
end

function DMLCD.StoreSpellBonusDamage(spellId, bonusDamage)
    spellId = tonumber(spellId)
    bonusDamage = tonumber(bonusDamage)

    if not spellId or not bonusDamage then
        return false
    end

    DMLCD.scalingBonusDamage = DMLCD.scalingBonusDamage or {}
    if bonusDamage > 0 then
        DMLCD.scalingBonusDamage[spellId] = math.floor(bonusDamage + 0.5)
    else
        DMLCD.scalingBonusDamage[spellId] = nil
    end
    return true
end

function DMLCD.GetSpellBonusDamage(spellId)
    spellId = tonumber(spellId)
    if not spellId or type(DMLCD.scalingBonusDamage) ~= "table" then
        return 0
    end

    return tonumber(DMLCD.scalingBonusDamage[spellId]) or 0
end

function DMLCD.StoreSpellScalingManaCost(spellId, extraManaCost)
    spellId = tonumber(spellId)
    extraManaCost = tonumber(extraManaCost)

    if not spellId or not extraManaCost then
        return false
    end

    DMLCD.scalingManaCost = DMLCD.scalingManaCost or {}
    if extraManaCost > 0 then
        DMLCD.scalingManaCost[spellId] = math.floor(extraManaCost + 0.5)
    else
        DMLCD.scalingManaCost[spellId] = nil
    end
    return true
end

function DMLCD.GetSpellScalingManaCost(spellId)
    spellId = tonumber(spellId)
    if not spellId or type(DMLCD.scalingManaCost) ~= "table" then
        return 0
    end

    return tonumber(DMLCD.scalingManaCost[spellId]) or 0
end

function DMLCD.StoreSpellMetadata(spellId, spellName, rank, customText, family)
    spellId = tonumber(spellId)
    if not spellId or not DB then
        return false
    end

    DB.spellMetadata = DB.spellMetadata or {}
    local key = tostring(spellId)
    local metadata = DB.spellMetadata[key] or {}

    if spellName and spellName ~= "" then
        metadata.name = spellName
    end
    if rank and rank ~= "" then
        metadata.rank = tonumber(rank) or rank
    end
    if customText and customText ~= "" then
        metadata.custom_text = customText
    end
    if family and family ~= "" then
        metadata.family = family
    end

    DB.spellMetadata[key] = metadata
    return true
end

function DMLCD.RefreshSpellAssignment(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return
    end

    ForEachActiveButton(function(index, button)
        local assignment = DMLCD.GetAssignmentForIndex(index)
        if button and assignment and GetAssignmentKind(assignment) == "spell" and
            tonumber(assignment.spellId) == spellId
        then
            UpdateButton(button)

            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(button) then
                ShowButtonTooltip(button)
            end
        end
    end)
end

function DMLCD:ParseProtocolMessage(message)
    if type(message) ~= "string" or string.sub(message, 1, string.len(CHAT_PREFIX)) ~= CHAT_PREFIX then
        return false
    end

    local fields = DMLCD.SplitProtocolFields(message)
    local action = fields[2]
    local spellId = fields[3]
    local cooldownMs = fields[4]
    local token = fields[5]
    local spellName = fields[6] or ""
    local rank = fields[7]
    local customText = fields[8]
    local family = fields[9]

    if not action then
        return true
    end

if action == "START" then
    DMLCD.StoreSpellMetadata(spellId, spellName, rank, customText, family)
    DMLCD.RefreshSpellAssignment(spellId)
    HandleStart(spellId, cooldownMs, token, spellName)
elseif action == "READY" then
    DMLCD.StoreSpellMetadata(spellId, spellName, rank, customText, family)
    DMLCD.RefreshSpellAssignment(spellId)
    HandleReady(spellId, token, spellName)
elseif action == "COOLDOWN" then
    HandleCooldownUpdate(spellId, cooldownMs, spellName)
elseif action == "RESET" then
    ClearCooldown(spellId, false, spellName)
    DMLCD.RefreshSpellAssignment(spellId)
elseif action == "LEARN" then
        DMLCD.StoreSpellMetadata(spellId, spellName, rank, customText, family)
        AutoAssignLearnedSpell(spellId, spellName)
    elseif action == "META" then
        DMLCD.StoreSpellMetadata(spellId, spellName, rank, customText, family)
        DMLCD.RefreshSpellAssignment(spellId)
    elseif action == "BONUS" then
        if DMLCD.StoreSpellBonusDamage(spellId, cooldownMs) then
            DMLCD.RefreshSpellAssignment(spellId)
        end
    elseif action == "MANA" then
        if DMLCD.StoreSpellScalingManaCost(spellId, cooldownMs) then
            DMLCD.RefreshSpellAssignment(spellId)
        end
    end

    return true
end

local function ChatMessageFilter(_, _, message)
    if type(message) == "string" and string.sub(message, 1, string.len(CHAT_PREFIX)) == CHAT_PREFIX then
        return true
    end
    return false
end

local function InstallChatFilter()
    if chatFilterInstalled then
        return
    end

    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatMessageFilter)
        chatFilterInstalled = true
    end
end

local function QueueClickFallback(button)
    if not DB.clickFallback or not button or not button.dmlIndex then
        return
    end

    local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex)
if not assignment or GetAssignmentKind(assignment) ~= "spell" then
    return
end

if DMLCD.IsServerConfirmedCooldownOnly(assignment.spellId) then
    return
end

if GetCooldownState(assignment.spellId) then
    return
end

    local fallback = tonumber(assignment.fallback) or 0
    if fallback <= 0 then
        return
    end

    pendingFallbacks[button.dmlIndex] = {
        spellId = tonumber(assignment.spellId),
        due = GetTime() + DB.fallbackDelay,
        duration = fallback
    }
end

local function HandleActionDrop(button)
    if keybindMode then
        return false
    end
    if not CanEditAssignments(true) then
        return false
    end
    if IsInCombat() then
        DebugPrint("DML assignments cannot be changed during combat.")
        return false
    end

    local cursorAssignment = ExtractCursorAssignment()
    if not cursorAssignment then
        DebugPrint("That cursor does not contain a usable spell, item, macro, mount, or companion pet.")
        return false
    end

    button.dmlLastDropTime = GetTime()

    local targetIndex = button.dmlIndex
    local targetPage = DMLCD.GetAssignmentPageForIndex(targetIndex)
    local previousTarget = CopyAssignment(DMLCD.GetAssignmentForIndex(targetIndex, targetPage))

    -- An action dragged from another DML slot swaps assignments instead of
    -- overwriting the destination. Dropping on an empty slot remains a move.
    if activeAssignmentDrag and activeAssignmentDrag.assignment and
        AssignmentMatches(activeAssignmentDrag.assignment, cursorAssignment)
    then
        local sourceIndex = tonumber(activeAssignmentDrag.sourceIndex)
        local draggedAssignment = CopyAssignment(activeAssignmentDrag.assignment)

        if sourceIndex and IsActiveButtonIndex(sourceIndex) then
            if sourceIndex == targetIndex and
                tonumber(activeAssignmentDrag.sourcePage) == tonumber(targetPage)
            then
                DMLCD.SetAssignmentForIndex(sourceIndex, draggedAssignment, activeAssignmentDrag.sourcePage)
                pendingFallbacks[sourceIndex] = nil
                UpdateButton(buttons[sourceIndex])
                DebugPrint(FormatButtonRef(sourceIndex) .. " restored.")
            else
                DMLCD.SetAssignmentForIndex(targetIndex, draggedAssignment, targetPage)
                DMLCD.SetAssignmentForIndex(sourceIndex, previousTarget, activeAssignmentDrag.sourcePage)
                pendingFallbacks[targetIndex] = nil
                pendingFallbacks[sourceIndex] = nil
                UpdateButton(buttons[targetIndex])
                UpdateButton(buttons[sourceIndex])

                if previousTarget then
                    DebugPrint(FormatButtonRef(sourceIndex) .. " and " .. string.lower(FormatButtonRef(targetIndex)) .. " swapped.")
                else
                    DebugPrint("Action moved from " .. string.lower(FormatButtonRef(sourceIndex)) .. " to " .. string.lower(FormatButtonRef(targetIndex)) .. ".")
                end
            end

            activeAssignmentDrag = nil
            ClearCursor()
            DMLCD.lastPickedCompanion = nil
            if SaveCharacterLayoutSnapshot then
                SaveCharacterLayoutSnapshot()
            end
            return true
        end
    end

    local fallback = previousTarget and tonumber(previousTarget.fallback) or 0

    -- For a bag/spellbook drag onto an occupied DML slot, place the displaced
    -- action on the cursor when the client can pick it up.
    if previousTarget then
        DMLCD.lastPickedCompanion = nil
        ClearCursor()
        if not PickupAssignedAction(previousTarget) then
            DebugPrint("The existing action could not be placed on the cursor, so " .. string.lower(FormatButtonRef(targetIndex)) .. " was left unchanged.")
            return false
        end
    end

    local assigned
    if cursorAssignment.kind == "item" then
        assigned = AssignItemButton(targetIndex, cursorAssignment.itemId, nil, "debug", targetPage)
    elseif cursorAssignment.kind == "macro" then
        assigned = DMLCD.AssignMacroButton(
            targetIndex,
            cursorAssignment.macroIndex,
            cursorAssignment.macroName or cursorAssignment.name,
            cursorAssignment.macroIcon or cursorAssignment.icon,
            cursorAssignment.macroBody or cursorAssignment.macroText,
            "debug",
            targetPage
        )
    elseif cursorAssignment.kind == "companion" then
        assigned = AssignCompanionButton(
            targetIndex,
            cursorAssignment.companionType,
            cursorAssignment.companionIndex,
            cursorAssignment.spellId,
            cursorAssignment.name,
            cursorAssignment.icon,
            "debug",
            targetPage
        )
    else
        assigned = AssignButton(targetIndex, cursorAssignment.spellId, fallback, nil, false, "debug", targetPage)
    end

    if not assigned then
        if previousTarget then
            ClearCursor()
        end
        return false
    end

    activeAssignmentDrag = nil
    if not previousTarget then
        ClearCursor()
        DMLCD.lastPickedCompanion = nil
    else
        DebugPrint(FormatButtonRef(targetIndex) .. " replaced; the previous action is now on the cursor.")
    end
    return true
end

-- Blizzard's Wrath action buttons use a 64px quick-slot texture around a
-- 36px button. Scaling that ratio preserves the familiar visible border while
-- the spell icon sits slightly inset inside it.
local function UpdateButtonGeometry(button)
    if not button then
        return
    end

    local settings = DMLCD.GetBarSettings(button.barIndex)
    local size = settings.buttonSize
    local normalTextureSize = size * (64 / 36)
    local iconInset = math.max(2, math.floor((size * 2 / 36) + 0.5))

    button:SetWidth(size)
    button:SetHeight(size)

    if button.slot then
        button.slot:ClearAllPoints()
        button.slot:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.slot:SetWidth(normalTextureSize)
        button.slot:SetHeight(normalTextureSize)
    end

    if button.icon then
        button.icon:ClearAllPoints()
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", iconInset, -iconInset)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -iconInset, iconInset)
    end

    if button.stateHighlight and button.icon then
        button.stateHighlight:ClearAllPoints()
        -- Preserve the top and right edges while giving the lower-left corner
        -- a tiny extra pixel of breathing room around the icon.
        button.stateHighlight:SetPoint("TOPLEFT", button.icon, "TOPLEFT", -1, 0)
        button.stateHighlight:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 0, -2)
    end

    if button.rangeBorder and button.icon then
        button.rangeBorder:ClearAllPoints()
        -- Match the queued-spell indicator exactly: top/right stay fixed while
        -- the left edge expands one pixel and the bottom edge expands two.
        button.rangeBorder:SetPoint("TOPLEFT", button.icon, "TOPLEFT", -1, 0)
        button.rangeBorder:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 0, -2)
    end
end

local function CreateButton(index, parentBar, barIndex, slotIndex)
    local button = CreateFrame("Button", "DMLCooldownBarButton" .. tostring(index), parentBar, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    button:SetFrameLevel(parentBar:GetFrameLevel() + 5)
    button.dmlIndex = index
    button.barIndex = barIndex
    button.slotIndex = slotIndex
    button:EnableMouse(true)
    local initialSettings = DMLCD.GetBarSettings(barIndex)
    button:SetWidth(initialSettings.buttonSize)
    button:SetHeight(initialSettings.buttonSize)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Keep the Blizzard quick-slot frame visible around both empty and
    -- occupied buttons. The 64:36 scale makes the empty placeholder appear at
    -- the same visual size as a normal Blizzard action button, while the icon
    -- is inset so the frame hugs it instead of being covered by it.
    button.slot = button:CreateTexture(nil, "OVERLAY")
    button.slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Thin inner border used by toggles and on-next-melee abilities.
    -- It sits on the icon's inner edge and uses a pale white-yellow tint.
    button.stateHighlight = CreateFrame("Frame", nil, button)
    button.stateHighlight:SetFrameLevel(button:GetFrameLevel() + 4)
    button.stateHighlight:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    button.stateHighlight:SetBackdropBorderColor(1, 0.92, 0.42, 0.76)
    button.stateHighlight:Hide()

    button.rangeBorder = CreateFrame("Frame", nil, button)
    button.rangeBorder:SetFrameLevel(button:GetFrameLevel() + 3)
    button.rangeBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    button.rangeBorder:SetBackdropBorderColor(1, 0.08, 0.08, 0.76)
    button.rangeBorder:Hide()


    UpdateButtonGeometry(button)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
    button.cooldown:Hide()

    button.cooldownText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.cooldownText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.cooldownText:SetJustifyH("CENTER")
    button.cooldownText:SetTextColor(1, 0.82, 0)

    button.emptyText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.emptyText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.emptyText:SetTextColor(0.65, 0.65, 0.65)
    button.emptyText:SetText(tostring(slotIndex))

    button.hotkeyText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    button.hotkeyText:SetJustifyH("RIGHT")
    button.hotkeyText:SetTextColor(1, 1, 1)
    button.hotkeyText:SetText("")

    button.pendingText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.pendingText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 3, 3)
    button.pendingText:SetTextColor(1, 0.45, 0.1)
    button.pendingText:SetText("!")
    button.pendingText:Hide()

    -- Empty-slot combat drop target. It is deliberately non-secure and sits
    -- above only empty buttons, allowing a spell to be recorded without
    -- changing protected click attributes until combat ends.
    button.combatDropOverlay = CreateFrame("Button", nil, parentBar)
    button.combatDropOverlay:SetAllPoints(button)
    button.combatDropOverlay:SetFrameLevel(button:GetFrameLevel() + 7)
    button.combatDropOverlay:EnableMouse(true)
    button.combatDropOverlay:RegisterForClicks("LeftButtonUp")
    button.combatDropOverlay:RegisterForDrag("LeftButton")
    button.combatDropOverlay:SetScript("OnReceiveDrag", function()
        HandleActionDrop(button)
    end)
    button.combatDropOverlay:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and CursorContainsAction() then
            HandleActionDrop(button)
        end
    end)
    button.combatDropOverlay:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button.combatDropOverlay, "ANCHOR_RIGHT")
        GameTooltip:SetText("Empty DML slot")
        GameTooltip:AddLine("DML assignments are locked during combat.", 1, 0.55, 0.15, true)
        GameTooltip:Show()
    end)
    button.combatDropOverlay:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button.combatDropOverlay:Hide()

    button.bindOverlay = CreateFrame("Button", nil, button)
    button.bindOverlay:SetAllPoints(button)
    button.bindOverlay:SetFrameLevel(button:GetFrameLevel() + 8)
    button.bindOverlay:EnableMouse(true)
    button.bindOverlay:RegisterForClicks("RightButtonUp")
    button.bindOverlay:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    button.bindOverlay:SetBackdropColor(0.05, 0.15, 0.08, 0.55)
    button.bindOverlay:SetBackdropBorderColor(0.25, 1, 0.45, 1)

    button.bindOverlayText = button.bindOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.bindOverlayText:SetPoint("CENTER", button.bindOverlay, "CENTER", 0, 0)
    button.bindOverlayText:SetJustifyH("CENTER")
    button.bindOverlayText:SetTextColor(1, 1, 1)
    button.bindOverlay:Hide()

    button.bindOverlay:SetScript("OnEnter", function()
        if keybindMode then
            keybindHoverIndex = index
            button.bindOverlay:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
    end)

    button.bindOverlay:SetScript("OnLeave", function()
        if keybindHoverIndex == index then
            keybindHoverIndex = nil
        end
        button.bindOverlay:SetBackdropBorderColor(0.25, 1, 0.45, 1)
    end)

    button.bindOverlay:SetScript("OnClick", function(_, mouseButton)
        if keybindMode and mouseButton == "RightButton" then
            keybindWorking[index] = nil
            if RefreshKeybindOverlays then
                RefreshKeybindOverlays()
            end
        end
    end)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    button:SetScript("OnEnter", function(self)
        ShowButtonTooltip(self)
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnReceiveDrag", function(self)
        HandleActionDrop(self)
    end)

    -- On 3.3.5a, a spell already sitting on the cursor may be delivered as a
    -- click rather than OnReceiveDrag. Re-check the lock modifier at click
    -- time so Shift/Ctrl/Alt can be pressed after the spell was picked up.
    button:SetScript("PreClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or keybindMode or not CursorContainsAction() then
            return
        end
        -- Some clients call both OnReceiveDrag and PreClick for one drop.
        -- Suppress the secure cast without processing the displaced cursor
        -- spell a second time.
        if self.dmlLastDropTime and (GetTime() - self.dmlLastDropTime) < 0.15 then
            self.dmlSuppressSecure = true
            if not IsInCombat() then
                self:SetAttribute("type1", nil)
                self:SetAttribute("spell1", nil)
                self:SetAttribute("item1", nil)
            end
            return
        end

        if not CanEditAssignments(true) then
            return
        end

        self.dmlSuppressSecure = true
        if not IsInCombat() then
            self:SetAttribute("type1", nil)
            self:SetAttribute("spell1", nil)
            self:SetAttribute("item1", nil)
        end
        HandleActionDrop(self)
    end)

    button:SetScript("OnDragStart", function(self)
        if keybindMode then
            return
        end
        if ConfigurationBlocked(true) then
            return
        end
        if not CanEditAssignments(true) then
            return
        end

        local sourcePage = DMLCD.GetAssignmentPageForIndex(self.dmlIndex)
        local assignment = DMLCD.GetAssignmentForIndex(self.dmlIndex, sourcePage)
        if not assignment then
            return
        end

        local name = GetAssignmentDisplayName(assignment)
        local copiedAssignment = CopyAssignment(assignment)
        local pickedUp = PickupAssignedAction(assignment)
        ClearAssignment(self.dmlIndex, true, sourcePage)

        if pickedUp then
            activeAssignmentDrag = {
                sourceIndex = self.dmlIndex,
                sourcePage = sourcePage,
                assignment = copiedAssignment
            }
            DebugPrint(name .. " picked up from " .. string.lower(FormatButtonRef(self.dmlIndex)) .. ". Drop it on another slot or off the bar.")
        else
            activeAssignmentDrag = nil
            DebugPrint(name .. " removed from " .. string.lower(FormatButtonRef(self.dmlIndex)) .. ".")
        end
    end)

    button:SetScript("PostClick", function(self, mouseButton)
        if self.dmlSuppressSecure then
            self.dmlSuppressSecure = nil
            UpdateButton(self)
            return
        end

        if mouseButton == "LeftButton" or mouseButton == "RightButton" then
            QueueClickFallback(self)
        end
    end)

    buttons[index] = button
    return button
end

local function EnsureButtons()
    local barIndex, slotIndex
    for barIndex = 1, DB.barCount do
        local parentBar = bars[barIndex]
        for slotIndex = 1, MAX_BUTTONS do
            local index = GlobalIndex(barIndex, slotIndex)
            if not buttons[index] then
                CreateButton(index, parentBar, barIndex, slotIndex)
            end
        end
    end
end

local function ApplyBackground()
    local barIndex
    for barIndex = 1, #bars do
        local frame = bars[barIndex]
        if frame then
            if DB.background then
                frame:SetBackdropColor(0.04, 0.04, 0.04, 0.78)
                frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
            else
                frame:SetBackdropColor(0, 0, 0, 0)
                frame:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end
    end

    if DMLCD.petBar then
        if DB.background then
            DMLCD.petBar:SetBackdropColor(0.04, 0.04, 0.04, 0.78)
            DMLCD.petBar:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
        else
            DMLCD.petBar:SetBackdropColor(0, 0, 0, 0)
            DMLCD.petBar:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end

    if DMLCD.auraBar then
        if DB.background then
            DMLCD.auraBar:SetBackdropColor(0.04, 0.04, 0.04, 0.78)
            DMLCD.auraBar:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
        else
            DMLCD.auraBar:SetBackdropColor(0, 0, 0, 0)
            DMLCD.auraBar:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end
end

local function ApplyLockState()
    local barIndex
    for barIndex = 1, #dragHandles do
        local handle = dragHandles[barIndex]
        if handle then
            if DB.locked or not DB.showAnchors or barIndex > DB.barCount then
                handle:Hide()
            else
                handle:Show()
            end
        end
    end

    if DMLCD.petBarHandle then
        if DB.locked or not DB.showAnchors or not DB.useDMLPetBar then
            DMLCD.petBarHandle:Hide()
        else
            DMLCD.petBarHandle:Show()
        end
    end

    if DMLCD.auraBarHandle then
        local auraCount = GetNumShapeshiftForms and tonumber(GetNumShapeshiftForms()) or 0
        if DB.locked or not DB.showAnchors or not DB.useDMLAuraBar or auraCount < 1 then
            DMLCD.auraBarHandle:Hide()
        else
            DMLCD.auraBarHandle:Show()
        end
    end
end

local blizzardBarModeOptions = {
    { value = "SHOW", text = "Show blizz bar" },
    { value = "ALL", text = "Hide all" },
    { value = "ACTION", text = "Hide action bar" },
    { value = "ACTION_BACKGROUND", text = "Hide action bar and background" }
}

local function GetBlizzardBarModeText(value)
    local i
    for i = 1, #blizzardBarModeOptions do
        if blizzardBarModeOptions[i].value == value then
            return blizzardBarModeOptions[i].text
        end
    end
    return blizzardBarModeOptions[1].text
end

local function NormalizeBlizzardBarMode(value)
    value = string.upper(tostring(value or ""))
    value = string.gsub(value, "[%s_-]", "")

    if value == "SHOW" or value == "SHOWBLIZZBAR" or value == "DEFAULT" then
        return "SHOW"
    elseif value == "ALL" or value == "HIDEALL" then
        return "ALL"
    elseif value == "ACTION" or value == "HIDEACTION" or value == "HIDEACTIONBAR" then
        return "ACTION"
    elseif value == "BACKGROUND" or value == "ACTIONBACKGROUND" or
        value == "HIDEBACKGROUND" or value == "HIDEACTIONBARANDBACKGROUND"
    then
        return "ACTION_BACKGROUND"
    end

    return nil
end

local function PrintBlizzardBarWarning()
    Print("Warning: Blizzard action-bar keybinds remain active while its buttons are hidden. Clearing the Blizzard action bar first is recommended; otherwise remove its keybinds to prevent invisible abilities from casting.")
end

-- The Blizzard action bar is hidden with alpha instead of hiding its parent.
-- This leaves the XP bar, bag buttons, micro menu, vehicle controls, and their
-- positions untouched. Mouse input is disabled on invisible action/page buttons
-- so clicks pass through to the DML bars placed over them.
local function SetBlizzardElementHidden(name, hidden, disableMouse)
    local element = _G[name]
    if not element then
        return
    end

    -- Key the saved state by the actual frame object, not its global name.
    -- Some 3.3.5 UI builds expose aliases (for example StanceButton and
    -- ShapeshiftButton) that can reference the same frame. Name-keyed state can
    -- otherwise save alpha 1 through one alias, alpha 0 through the second, and
    -- later restore the shared button to invisible.
    local state = blizzardElementStates[element]
    if hidden then
        if not state then
            state = {}
            if element.GetAlpha then
                state.alpha = element:GetAlpha()
            else
                state.alpha = 1
            end
            blizzardElementStates[element] = state
        end
        if disableMouse and state.mouseEnabled == nil and element.IsMouseEnabled then
            state.mouseEnabled = element:IsMouseEnabled() and true or false
        end

        if element.SetAlpha then
            element:SetAlpha(0)
        end
        if disableMouse and element.EnableMouse then
            element:EnableMouse(false)
        end
    elseif state then
        if element.SetAlpha then
            element:SetAlpha(state.alpha or 1)
        end
        if state.mouseEnabled ~= nil and element.EnableMouse then
            element:EnableMouse(state.mouseEnabled)
        end
        blizzardElementStates[element] = nil
    end
end

ApplyBlizzardBarSettings = function()
    if not DB then
        return
    end

    if IsInCombat() then
        pendingBlizzardBarRefresh = true
        return
    end

    pendingBlizzardBarRefresh = false
    blizzardBarRefreshDue = nil

    local mode = DB.blizzardBarMode or "SHOW"
    local hideActions = mode ~= "SHOW"
    local hideBackground = mode == "ALL" or mode == "ACTION_BACKGROUND"
    local hideGryphons = mode == "ALL" or DB.hideGryphons
    -- Stances/forms/paladin auras are a separate Blizzard bar. Hide Action Bar
    -- must not hide it. It is hidden only by Hide All or the DML aura replacement.
    local hideAuraBar = mode == "ALL" or DB.useDMLAuraBar

    local i
    for i = 1, 12 do
        SetBlizzardElementHidden("ActionButton" .. tostring(i), hideActions, true)
        SetBlizzardElementHidden("BonusActionButton" .. tostring(i), hideActions, true)
    end

    -- ShapeshiftButton is the stock 3.3.5 stance/form/aura button name. Some
    -- UI variants also expose StanceButton aliases, so support both without
    -- changing their frame strata or levels.
    for i = 1, 10 do
        SetBlizzardElementHidden("ShapeshiftButton" .. tostring(i), hideAuraBar, true)
        SetBlizzardElementHidden("StanceButton" .. tostring(i), hideAuraBar, true)
    end

    local auraFrames = {
        "ShapeshiftBarFrame",
        "StanceBarFrame"
    }
    for i = 1, #auraFrames do
        SetBlizzardElementHidden(auraFrames[i], hideAuraBar, true)
    end

    local auraArt = {
        "ShapeshiftBarLeft",
        "ShapeshiftBarMiddle",
        "ShapeshiftBarRight",
        "StanceBarLeft",
        "StanceBarMiddle",
        "StanceBarRight"
    }
    for i = 1, #auraArt do
        SetBlizzardElementHidden(auraArt[i], hideAuraBar, false)
    end

    -- Bonus action buttons/page artwork belong to the main action bar, not the
    -- stance/aura bar. Possess/vehicle controls are deliberately not touched.
    SetBlizzardElementHidden("BonusActionBarFrame", hideActions, true)
    for i = 0, 3 do
        SetBlizzardElementHidden("BonusActionBarTexture" .. tostring(i), hideActions, false)
    end

    local pageControls = {
        "MainMenuBarPageNumber",
        "MainMenuBarPageUpButton",
        "MainMenuBarPageDownButton",
        "ActionBarUpButton",
        "ActionBarDownButton"
    }
    for i = 1, #pageControls do
        SetBlizzardElementHidden(pageControls[i], hideActions, true)
    end

    -- These are only the main action-bar background textures. In SHOW mode DML
    -- leaves Blizzard layering untouched so the UI renders exactly as stock WoW.
    for i = 0, 3 do
        SetBlizzardElementHidden("MainMenuBarTexture" .. tostring(i), hideBackground, false)
    end

    SetBlizzardElementHidden("MainMenuBarLeftEndCap", hideGryphons, false)
    SetBlizzardElementHidden("MainMenuBarRightEndCap", hideGryphons, false)

    local hidePetBar = DB.useDMLPetBar and true or false
    for i = 1, 10 do
        SetBlizzardElementHidden("PetActionButton" .. tostring(i), hidePetBar, true)
    end
    SetBlizzardElementHidden("PetActionBarFrame", hidePetBar, true)

    if DMLCD.ApplyAuraBarSettings then
        DMLCD.ApplyAuraBarSettings()
    end
    if DMLCD.ApplyPetBarSettings then
        DMLCD.ApplyPetBarSettings()
    end
end

local function ScheduleBlizzardBarRefresh(delay)
    if not DB then
        return
    end
    blizzardBarRefreshDue = GetTime() + (tonumber(delay) or 0.05)
end



DMLCD.AURA_ACTION_SLOTS = NUM_SHAPESHIFT_SLOTS or 10
DMLCD.AURA_BUTTON_SIZE = 30
DMLCD.AURA_BUTTON_SPACING = 3
DMLCD.AURA_BAR_PADDING = 5

function DMLCD.GetDefaultAuraBarPosition()
    return "CENTER", "CENTER", 0, -70
end

function DMLCD.SaveAuraBarPosition()
    if not DB or not DMLCD.auraBar then
        return
    end

    local point, _, relativePoint, x, y = DMLCD.auraBar:GetPoint(1)
    DB.auraBarPosition = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or -70
    }
end

function DMLCD.RestoreAuraBarPosition()
    if not DB or not DMLCD.auraBar then
        return
    end

    local saved = DB.auraBarPosition
    local point, relativePoint, x, y
    if type(saved) == "table" then
        point = saved.point or "CENTER"
        relativePoint = saved.relativePoint or "CENTER"
        x = tonumber(saved.x) or 0
        y = tonumber(saved.y) or -70
    else
        point, relativePoint, x, y = DMLCD.GetDefaultAuraBarPosition()
        DB.auraBarPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
    end

    DMLCD.auraBar:ClearAllPoints()
    DMLCD.auraBar:SetPoint(point, UIParent, relativePoint, x, y)
end

function DMLCD.ConstrainAuraBarToScreen()
    local frame = DMLCD.auraBar
    if not frame or not UIParent then
        return false
    end

    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    if not left or not bottom or not width or not height or
        not screenWidth or not screenHeight
    then
        return false
    end

    local right = left + width
    local top = bottom + height
    local minimumLeft = -BAR_EDGE_OVERHANG
    local maximumRight = screenWidth + BAR_EDGE_OVERHANG
    local minimumBottom = -BAR_EDGE_OVERHANG
    local maximumTop = screenHeight - BAR_DRAG_HANDLE_HEIGHT - BAR_DRAG_HANDLE_GAP
    local deltaX = 0
    local deltaY = 0

    if left < minimumLeft then
        deltaX = minimumLeft - left
    elseif right > maximumRight then
        deltaX = maximumRight - right
    end

    if bottom < minimumBottom then
        deltaY = minimumBottom - bottom
    elseif top > maximumTop then
        deltaY = maximumTop - top
    end

    if deltaX == 0 and deltaY == 0 then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + deltaX, bottom + deltaY)
    return true
end

function DMLCD.GetAuraBindingText(slot)
    if not GetBindingKey then
        return ""
    end

    local key = GetBindingKey("SHAPESHIFTBUTTON" .. tostring(slot)) or
        GetBindingKey("STANCEBUTTON" .. tostring(slot))
    if DMLCD.CompactBindingText then
        return DMLCD.CompactBindingText(key)
    end
    return key or ""
end

function DMLCD.UpdateAuraButton(button)
    if not button or not button.dmlAuraSlot or not GetShapeshiftFormInfo then
        return
    end

    local slot = button.dmlAuraSlot
    local texture, name, isActive, isCastable = GetShapeshiftFormInfo(slot)
    button.dmlAuraName = name

    if texture then
        button.icon:SetTexture(texture)
        button.icon:Show()
        if isCastable == false then
            button.icon:SetVertexColor(0.45, 0.45, 0.45)
        else
            button.icon:SetVertexColor(1, 1, 1)
        end
    else
        button.icon:SetTexture(nil)
        button.icon:Hide()
    end

    if isActive then
        button.activeBorder:Show()
    else
        button.activeBorder:Hide()
    end

    if button.cooldown and GetShapeshiftFormCooldown and CooldownFrame_SetTimer then
        local start, duration, enable = GetShapeshiftFormCooldown(slot)
        if start and duration and enable and start > 0 and duration > 0 and enable > 0 then
            CooldownFrame_SetTimer(button.cooldown, start, duration, enable)
            button.cooldown:Show()
        else
            button.cooldown:Hide()
        end
    elseif button.cooldown then
        button.cooldown:Hide()
    end

    button.hotkeyText:SetText(DMLCD.GetAuraBindingText(slot))
end

function DMLCD.RefreshAuraBar(allowVisibilityChanges)
    if not DMLCD.auraButtons then
        return
    end

    local count = GetNumShapeshiftForms and tonumber(GetNumShapeshiftForms()) or 0
    count = math.max(0, math.min(DMLCD.AURA_ACTION_SLOTS, count))

    if allowVisibilityChanges and DMLCD.auraBar then
        local visibleSlots = math.max(1, count)
        local width = (visibleSlots * DMLCD.AURA_BUTTON_SIZE) +
            ((visibleSlots - 1) * DMLCD.AURA_BUTTON_SPACING) +
            (DMLCD.AURA_BAR_PADDING * 2)
        DMLCD.auraBar:SetWidth(width)
        DMLCD.auraBar:SetHeight(DMLCD.AURA_BUTTON_SIZE + (DMLCD.AURA_BAR_PADDING * 2))
    end

    local slot
    for slot = 1, DMLCD.AURA_ACTION_SLOTS do
        local button = DMLCD.auraButtons[slot]
        if button then
            DMLCD.UpdateAuraButton(button)
            if allowVisibilityChanges then
                if slot <= count then
                    button:Show()
                else
                    button:Hide()
                end
            end
        end
    end
end

function DMLCD.ShowAuraButtonTooltip(button)
    if not button then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.dmlAuraName or ("Stance / aura " .. tostring(button.dmlAuraSlot)))
    GameTooltip:Show()
end

function DMLCD.CreateAuraButton(slot, parent)
    local button = CreateFrame(
        "Button",
        "DMLCooldownBarAuraButton" .. tostring(slot),
        parent,
        "SecureActionButtonTemplate"
    )
    button.dmlAuraSlot = slot
    button:SetID(slot)
    button:SetWidth(DMLCD.AURA_BUTTON_SIZE)
    button:SetHeight(DMLCD.AURA_BUTTON_SIZE)
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")

    local originalButton = _G["ShapeshiftButton" .. tostring(slot)] or
        _G["StanceButton" .. tostring(slot)]
    if originalButton then
        button:SetAttribute("type", "click")
        button:SetAttribute("clickbutton", originalButton)
    end

    button.slot = button:CreateTexture(nil, "OVERLAY")
    button.slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    button.slot:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.slot:SetWidth(DMLCD.AURA_BUTTON_SIZE * (64 / 36))
    button.slot:SetHeight(DMLCD.AURA_BUTTON_SIZE * (64 / 36))

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button.activeBorder = CreateFrame("Frame", nil, button)
    button.activeBorder:SetAllPoints(button.icon)
    button.activeBorder:SetFrameLevel(button:GetFrameLevel() + 3)
    button.activeBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    button.activeBorder:SetBackdropBorderColor(1, 0.92, 0.42, 0.9)
    button.activeBorder:Hide()

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
    button.cooldown:Hide()

    button.hotkeyText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    button.hotkeyText:SetJustifyH("RIGHT")
    button.hotkeyText:SetTextColor(1, 1, 1)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button:SetScript("OnEnter", function(self)
        DMLCD.ShowAuraButtonTooltip(self)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("PostClick", function()
        DMLCD.RefreshAuraBar(false)
    end)

    DMLCD.auraButtons[slot] = button
    DMLCD.UpdateAuraButton(button)
    return button
end

function DMLCD.CreateAuraBar()
    if DMLCD.auraBar then
        return DMLCD.auraBar
    end

    DMLCD.auraButtons = DMLCD.auraButtons or {}

    local frame = CreateFrame("Frame", "DMLCooldownBarAuraFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(20)
    frame:SetMovable(true)
    frame:SetClampedToScreen(false)
    frame:EnableMouse(false)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

    local handle = CreateFrame("Frame", "DMLCooldownBarAuraDragHandle", frame)
    handle:SetHeight(BAR_DRAG_HANDLE_HEIGHT)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, BAR_DRAG_HANDLE_GAP)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, BAR_DRAG_HANDLE_GAP)
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
    handle:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)

    local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("CENTER", handle, "CENTER", 0, 0)
    title:SetText("DML Aura Bar - drag to move")

    handle:SetScript("OnDragStart", function()
        if DB.locked or IsInCombat() then
            return
        end
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        DMLCD.ConstrainAuraBarToScreen()
        DMLCD.SaveAuraBarPosition()
        SaveCharacterLayoutSnapshot()
    end)

    DMLCD.auraBar = frame
    DMLCD.auraBarHandle = handle

    local slot
    for slot = 1, DMLCD.AURA_ACTION_SLOTS do
        local button = DMLCD.CreateAuraButton(slot, frame)
        button:SetPoint(
            "LEFT",
            frame,
            "LEFT",
            DMLCD.AURA_BAR_PADDING + ((slot - 1) *
                (DMLCD.AURA_BUTTON_SIZE + DMLCD.AURA_BUTTON_SPACING)),
            0
        )
    end

    DMLCD.RestoreAuraBarPosition()
    DMLCD.RefreshAuraBar(true)
    frame:Hide()
    return frame
end

function DMLCD.EnsureAuraBar()
    if not DMLCD.auraBar then
        DMLCD.CreateAuraBar()
    end
    return DMLCD.auraBar
end

function DMLCD.ApplyAuraBarSettings()
    if not DB then
        return
    end

    local frame = DMLCD.EnsureAuraBar()
    if not frame then
        return
    end

    local count = GetNumShapeshiftForms and tonumber(GetNumShapeshiftForms()) or 0
    if IsInCombat() then
        DMLCD.pendingAuraBarRefresh = true
        DMLCD.RefreshAuraBar(false)
        return
    end

    DMLCD.pendingAuraBarRefresh = false
    DMLCD.RefreshAuraBar(true)
    if DB.useDMLAuraBar and count > 0 then
        frame:Show()
    else
        frame:Hide()
    end

    ApplyBackground()
    ApplyLockState()
end

DMLCD.PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
DMLCD.PET_BUTTON_SIZE = 30
DMLCD.PET_BUTTON_SPACING = 3
DMLCD.PET_BAR_PADDING = 5

function DMLCD.GetDefaultPetBarPosition()
    return "CENTER", "CENTER", 0, -110
end

function DMLCD.SavePetBarPosition()
    if not DB or not DMLCD.petBar then
        return
    end

    local point, _, relativePoint, x, y = DMLCD.petBar:GetPoint(1)
    DB.petBarPosition = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or -110
    }
end

function DMLCD.RestorePetBarPosition()
    if not DB or not DMLCD.petBar then
        return
    end

    local saved = DB.petBarPosition
    local point, relativePoint, x, y
    if type(saved) == "table" then
        point = saved.point or "CENTER"
        relativePoint = saved.relativePoint or "CENTER"
        x = tonumber(saved.x) or 0
        y = tonumber(saved.y) or -110
    else
        point, relativePoint, x, y = DMLCD.GetDefaultPetBarPosition()
        DB.petBarPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
    end

    DMLCD.petBar:ClearAllPoints()
    DMLCD.petBar:SetPoint(point, UIParent, relativePoint, x, y)
end

function DMLCD.ConstrainPetBarToScreen()
    local frame = DMLCD.petBar
    if not frame or not UIParent then
        return false
    end

    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    if not left or not bottom or not width or not height or
        not screenWidth or not screenHeight
    then
        return false
    end

    local right = left + width
    local top = bottom + height
    local minimumLeft = -BAR_EDGE_OVERHANG
    local maximumRight = screenWidth + BAR_EDGE_OVERHANG
    local minimumBottom = -BAR_EDGE_OVERHANG
    local maximumTop = screenHeight - BAR_DRAG_HANDLE_HEIGHT - BAR_DRAG_HANDLE_GAP
    local deltaX = 0
    local deltaY = 0

    if left < minimumLeft then
        deltaX = minimumLeft - left
    elseif right > maximumRight then
        deltaX = maximumRight - right
    end

    if bottom < minimumBottom then
        deltaY = minimumBottom - bottom
    elseif top > maximumTop then
        deltaY = maximumTop - top
    end

    if deltaX == 0 and deltaY == 0 then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + deltaX, bottom + deltaY)
    return true
end

function DMLCD.GetPetBindingText(slot)
    if not GetBindingKey then
        return ""
    end

    local key = GetBindingKey("BONUSACTIONBUTTON" .. tostring(slot)) or
        GetBindingKey("PETACTIONBUTTON" .. tostring(slot))
    if DMLCD.CompactBindingText then
        return DMLCD.CompactBindingText(key)
    end
    return key or ""
end

function DMLCD.UpdatePetButton(button)
    if not button or not button.dmlPetSlot or not GetPetActionInfo then
        return
    end

    local slot = button.dmlPetSlot
    local name, subtext, texture, isToken, isActive, autoCastAllowed, autoCastEnabled =
        GetPetActionInfo(slot)

    if isToken then
        if texture and _G[texture] then
            texture = _G[texture]
        end
        if name and _G[name] then
            name = _G[name]
        end
    end

    button.dmlPetName = name
    button.dmlPetSubtext = subtext

    if texture then
        button.icon:SetTexture(texture)
        button.icon:Show()
        button.emptyText:Hide()
        button:SetAlpha(1)
    else
        button.icon:SetTexture(nil)
        button.icon:Hide()
        if DB.showSlotNumbers then
            button.emptyText:Show()
        else
            button.emptyText:Hide()
        end
        button:SetAlpha(0.42)
    end

    local usable = true
    if texture and GetPetActionSlotUsable then
        usable = GetPetActionSlotUsable(slot) and true or false
    elseif texture and GetPetActionsUsable then
        usable = GetPetActionsUsable() and true or false
    end

    if texture and usable then
        button.icon:SetVertexColor(1, 1, 1)
    elseif texture then
        button.icon:SetVertexColor(0.4, 0.4, 0.4)
    end

    if isActive then
        button.activeBorder:Show()
    else
        button.activeBorder:Hide()
    end

    if autoCastEnabled then
        button.autoCastBorder:SetBackdropBorderColor(0.2, 1, 0.35, 0.95)
        button.autoCastBorder:Show()
        button.autoCastText:SetText("A")
        button.autoCastText:SetTextColor(0.25, 1, 0.4)
        button.autoCastText:Show()
    elseif autoCastAllowed then
        button.autoCastBorder:SetBackdropBorderColor(0.25, 0.75, 1, 0.72)
        button.autoCastBorder:Show()
        button.autoCastText:SetText("A")
        button.autoCastText:SetTextColor(0.45, 0.8, 1)
        button.autoCastText:Show()
    else
        button.autoCastBorder:Hide()
        button.autoCastText:Hide()
    end

    if GetPetActionCooldown then
        local start, duration, enable = GetPetActionCooldown(slot)
        start = tonumber(start) or 0
        duration = tonumber(duration) or 0
        enable = tonumber(enable) or 0
        if start > 0 and duration > 0 and enable > 0 then
            CooldownFrame_SetTimer(button.cooldown, start, duration, enable)
            button.cooldown:Show()
        else
            button.cooldown:Hide()
        end
    else
        button.cooldown:Hide()
    end

    button.hotkeyText:SetText(DMLCD.GetPetBindingText(slot))
end

function DMLCD.RefreshPetBar()
    if not DMLCD.petButtons then
        return
    end

    local slot
    for slot = 1, DMLCD.PET_ACTION_SLOTS do
        DMLCD.UpdatePetButton(DMLCD.petButtons[slot])
    end
end

function DMLCD.ShowPetButtonTooltip(button)
    if not button then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if GameTooltip.SetPetAction then
        GameTooltip:SetPetAction(button.dmlPetSlot)
    else
        GameTooltip:SetText(button.dmlPetName or ("Pet action " .. tostring(button.dmlPetSlot)))
        if button.dmlPetSubtext and button.dmlPetSubtext ~= "" then
            GameTooltip:AddLine(button.dmlPetSubtext, 0.75, 0.75, 0.75, true)
        end
    end
    GameTooltip:Show()
end

function DMLCD.CreatePetButton(slot, parent)
    local button = CreateFrame(
        "Button",
        "DMLCooldownBarPetButton" .. tostring(slot),
        parent,
        "SecureActionButtonTemplate"
    )
    button.dmlPetSlot = slot
    button:SetID(slot)
    button:SetWidth(DMLCD.PET_BUTTON_SIZE)
    button:SetHeight(DMLCD.PET_BUTTON_SIZE)
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type1", "pet")
    button:SetAttribute("action", slot)

    local originalButton = _G["PetActionButton" .. tostring(slot)]
    if originalButton then
        button:SetAttribute("type2", "click")
        button:SetAttribute("clickbutton2", originalButton)
    end

    button.slot = button:CreateTexture(nil, "OVERLAY")
    button.slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    button.slot:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.slot:SetWidth(DMLCD.PET_BUTTON_SIZE * (64 / 36))
    button.slot:SetHeight(DMLCD.PET_BUTTON_SIZE * (64 / 36))

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button.activeBorder = CreateFrame("Frame", nil, button)
    button.activeBorder:SetAllPoints(button.icon)
    button.activeBorder:SetFrameLevel(button:GetFrameLevel() + 3)
    button.activeBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    button.activeBorder:SetBackdropBorderColor(1, 0.92, 0.42, 0.8)
    button.activeBorder:Hide()

    button.autoCastBorder = CreateFrame("Frame", nil, button)
    button.autoCastBorder:SetPoint("TOPLEFT", button.icon, "TOPLEFT", 1, -1)
    button.autoCastBorder:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -1, 1)
    button.autoCastBorder:SetFrameLevel(button:GetFrameLevel() + 2)
    button.autoCastBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    button.autoCastBorder:Hide()

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
    button.cooldown:Hide()

    button.emptyText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.emptyText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.emptyText:SetTextColor(0.6, 0.6, 0.6)
    button.emptyText:SetText(tostring(slot))

    button.hotkeyText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    button.hotkeyText:SetJustifyH("RIGHT")
    button.hotkeyText:SetTextColor(1, 1, 1)

    button.autoCastText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.autoCastText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 3, 2)
    button.autoCastText:SetText("A")
    button.autoCastText:Hide()

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    button:SetScript("OnEnter", function(self)
        DMLCD.ShowPetButtonTooltip(self)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        if IsInCombat() or (DB.locked and not IsBarLockModifierDown()) then
            return
        end
        if PickupPetAction then
            PickupPetAction(self.dmlPetSlot)
            DMLCD.RefreshPetBar()
        end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        if IsInCombat() or (DB.locked and not IsBarLockModifierDown()) then
            return
        end
        if PickupPetAction then
            PickupPetAction(self.dmlPetSlot)
            DMLCD.RefreshPetBar()
        end
    end)
    button:SetScript("PostClick", function()
        DMLCD.RefreshPetBar()
    end)

    DMLCD.petButtons[slot] = button
    DMLCD.UpdatePetButton(button)
    return button
end

function DMLCD.CreatePetBar()
    if DMLCD.petBar then
        return DMLCD.petBar
    end

    DMLCD.petButtons = DMLCD.petButtons or {}

    local frame = CreateFrame(
        "Frame",
        "DMLCooldownBarPetFrame",
        UIParent,
        "SecureHandlerStateTemplate"
    )
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(20)
    frame:SetMovable(true)
    frame:SetClampedToScreen(false)
    frame:EnableMouse(false)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

    local width = (DMLCD.PET_ACTION_SLOTS * DMLCD.PET_BUTTON_SIZE) +
        ((DMLCD.PET_ACTION_SLOTS - 1) * DMLCD.PET_BUTTON_SPACING) +
        (DMLCD.PET_BAR_PADDING * 2)
    frame:SetWidth(width)
    frame:SetHeight(DMLCD.PET_BUTTON_SIZE + (DMLCD.PET_BAR_PADDING * 2))

    local handle = CreateFrame("Frame", "DMLCooldownBarPetDragHandle", frame)
    handle:SetHeight(BAR_DRAG_HANDLE_HEIGHT)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, BAR_DRAG_HANDLE_GAP)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, BAR_DRAG_HANDLE_GAP)
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
    handle:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)

    local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("CENTER", handle, "CENTER", 0, 0)
    title:SetText("DML Pet Bar - drag to move")

    handle:SetScript("OnDragStart", function()
        if DB.locked or IsInCombat() then
            return
        end
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        DMLCD.ConstrainPetBarToScreen()
        DMLCD.SavePetBarPosition()
        SaveCharacterLayoutSnapshot()
    end)

    DMLCD.petBar = frame
    DMLCD.petBarHandle = handle

    local slot
    for slot = 1, DMLCD.PET_ACTION_SLOTS do
        local button = DMLCD.CreatePetButton(slot, frame)
        button:SetPoint(
            "LEFT",
            frame,
            "LEFT",
            DMLCD.PET_BAR_PADDING + ((slot - 1) *
                (DMLCD.PET_BUTTON_SIZE + DMLCD.PET_BUTTON_SPACING)),
            0
        )
    end

    DMLCD.RestorePetBarPosition()
    frame:Hide()
    return frame
end

function DMLCD.EnsurePetBar()
    if not DMLCD.petBar then
        DMLCD.CreatePetBar()
    end
    return DMLCD.petBar
end

function DMLCD.ApplyPetBarSettings()
    if not DB then
        return
    end

    local frame = DMLCD.EnsurePetBar()
    if not frame then
        return
    end

    if IsInCombat() then
        DMLCD.pendingPetBarRefresh = true
        return
    end

    DMLCD.pendingPetBarRefresh = false
    if DB.useDMLPetBar then
        if RegisterStateDriver then
            if not DMLCD.petVisibilityDriverActive then
                RegisterStateDriver(frame, "visibility", "[target=pet,exists] show; hide")
                DMLCD.petVisibilityDriverActive = true
            end
        elseif UnitExists and UnitExists("pet") then
            frame:Show()
        else
            frame:Hide()
        end
    else
        if DMLCD.petVisibilityDriverActive and UnregisterStateDriver then
            UnregisterStateDriver(frame, "visibility")
            DMLCD.petVisibilityDriverActive = false
        end
        frame:Hide()
    end

    ApplyBackground()
    ApplyLockState()
    DMLCD.RefreshPetBar()
end

local function CreateBarFrame(barIndex)
    local frameName = barIndex == 1 and "DMLCooldownBarFrame" or ("DMLCooldownBarFrame" .. tostring(barIndex))
    local handleName = barIndex == 1 and "DMLCooldownBarDragHandle" or ("DMLCooldownBarDragHandle" .. tostring(barIndex))

    local frame = CreateFrame("Frame", frameName, UIParent)
    frame.dmlBarIndex = barIndex
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(20)
    frame:SetMovable(true)
    -- Blizzard's normal clamping keeps every pixel of the frame on-screen,
    -- which leaves a visible gap at the bottom. We use a small custom clamp
    -- after movement/layout instead so only the decorative border may overhang.
    frame:SetClampedToScreen(false)
    frame:EnableMouse(false)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

    local handle = CreateFrame("Frame", handleName, frame)
    handle:SetHeight(BAR_DRAG_HANDLE_HEIGHT)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, BAR_DRAG_HANDLE_GAP)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, BAR_DRAG_HANDLE_GAP)
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
    handle:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.55, 0.9)

    local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("CENTER", handle, "CENTER", 0, 0)
    if barIndex == 1 then
        title:SetText("DML Cooldown Bar 1 - drag to move")
    else
        title:SetText("DML Cooldown Bar " .. tostring(barIndex) .. " - drag to move")
    end

    handle:SetScript("OnDragStart", function()
        if DB.locked or IsInCombat() then
            return
        end
        frame:StartMoving()
    end)

    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        ConstrainBarToScreen(barIndex)
        SavePosition(barIndex)
        if SaveCharacterLayoutSnapshot then
            SaveCharacterLayoutSnapshot()
        end
    end)

    bars[barIndex] = frame
    dragHandles[barIndex] = handle
    if barIndex == 1 then
        bar = frame
        dragHandle = handle
    end
    RestorePosition(barIndex)
    return frame
end

local function EnsureBars()
    if not keybindOwner then
        keybindOwner = CreateFrame("Frame", "DMLCooldownBarBindingOwner", UIParent)
    end

    local barIndex
    for barIndex = 1, DB.barCount do
        if not bars[barIndex] then
            CreateBarFrame(barIndex)
        end
    end
end

local function LayoutButtons()
    DMLCD.EnsurePetBar()

    -- Slash commands from older versions still edit the original scalar
    -- fields. Mirror those values into Bar 1 before laying out the bars.
    DMLCD.SyncBarOneFromLegacySettings()
    EnsureBars()
    EnsureButtons()

    local padding = BAR_PADDING
    local barIndex, slotIndex
    for barIndex = 1, #bars do
        local frame = bars[barIndex]
        if barIndex <= DB.barCount then
            local settings = DMLCD.GetBarSettings(barIndex)
            local width = (settings.columns * settings.buttonSize) +
                ((settings.columns - 1) * settings.spacingX) + (padding * 2)
            local height = (settings.rows * settings.buttonSize) +
                ((settings.rows - 1) * settings.spacingY) + (padding * 2)

            frame:SetWidth(width)
            frame:SetHeight(height)

            for slotIndex = 1, MAX_BUTTONS do
                local index = GlobalIndex(barIndex, slotIndex)
                local button = buttons[index]
                if button then
                    if slotIndex <= settings.buttonCount then
                        local zeroIndex = slotIndex - 1
                        local column = zeroIndex % settings.columns
                        local row = math.floor(zeroIndex / settings.columns)

                        button:ClearAllPoints()
                        button:SetPoint(
                            "TOPLEFT",
                            frame,
                            "TOPLEFT",
                            padding + (column * (settings.buttonSize + settings.spacingX)),
                            -padding - (row * (settings.buttonSize + settings.spacingY))
                        )
                        UpdateButtonGeometry(button)
                        button:Show()
                        UpdateButton(button)
                    else
                        button:Hide()
                    end
                end
            end

            if ConstrainBarToScreen(barIndex) then
                SavePosition(barIndex)
            end

            if DB.shown then
                frame:Show()
            else
                frame:Hide()
            end
        else
            frame:Hide()
        end
    end

    DMLCD.SyncLegacyBarSettings()
    ApplyBackground()
    ApplyLockState()
    DMLCD.ApplyPetBarSettings()
    if RefreshKeybindLabels then
        RefreshKeybindLabels()
    end
    if ApplySavedKeybinds then
        ApplySavedKeybinds()
    end
end

function DMLCD.UpdateIdleButtonVisuals(_, button)
    if not button then
        return
    end

    local assignment = DMLCD.GetAssignmentForIndex(button.dmlIndex)
    UpdateButtonCooldownVisual(button, false)
    DMLCD.UpdateButtonResourceVisual(button, DMLCD.updateResourceCache)
    DMLCD.UpdateButtonActionStateVisual(
        button,
        assignment,
        button.dmlResolved
    )
    DMLCD.UpdateButtonRangeVisual(
        button,
        assignment,
        button.dmlResolved,
        DMLCD.updateRangeCache
    )
end

local function CreateUpdateFrame()
    if updateFrame then
        return
    end

    updateFrame = CreateFrame("Frame", "DMLCooldownBarUpdateFrame", UIParent)
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        if not CursorContainsAction() then
            if activeAssignmentDrag then
                activeAssignmentDrag = nil
            end
            DMLCD.lastPickedCompanion = nil
        end

        updateElapsed = updateElapsed + elapsed
        if updateElapsed < 0.1 then
            return
        end
        updateElapsed = 0

        local now = GetTime()

        if blizzardBarRefreshDue and now >= blizzardBarRefreshDue then
            if IsInCombat() then
                pendingBlizzardBarRefresh = true
                blizzardBarRefreshDue = nil
            else
                ApplyBlizzardBarSettings()
            end
        end

        if DMLCD.stancePageRefreshDue and now >= DMLCD.stancePageRefreshDue then
            DMLCD.RefreshBarOneStancePage()
        end

        local index, pending
        for index, pending in pairs(pendingFallbacks) do
            if now >= pending.due then
                pendingFallbacks[index] = nil
                local assignment = DMLCD.GetAssignmentForIndex(index)
                if assignment
                    and tonumber(assignment.spellId) == tonumber(pending.spellId)
                    and not GetCooldownState(pending.spellId)
                then
                    StartCooldown(
                        pending.spellId,
                        pending.duration,
                        "M" .. tostring(math.floor(now * 1000)),
                        assignment.name,
                        "manual fallback"
                    )
                end
            end
        end

        local expired = DMLCD.ClearScratchTable(DMLCD.updateExpiredCooldowns)
        local key, state
        for key, state in pairs(DB.cooldowns) do
            local remaining = GetRemaining(state)
            if remaining <= 0 then
                expired[#expired + 1] = tonumber(state.spellId) or tonumber(key)
            end
        end

        local i
        for i = 1, #expired do
            ClearCooldown(expired[i], true, nil)
        end

        DMLCD.ClearScratchTable(DMLCD.updateResourceCache)
        DMLCD.ClearScratchTable(DMLCD.updateRangeCache)
        ForEachActiveButton(DMLCD.UpdateIdleButtonVisuals)
    end)
end

local function CopyTable(source)
    local result = {}
    local key, value
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

function DMLCD.CompactBindingText(key)
    if not key or key == "" then
        return ""
    end

    local text = tostring(key)
    text = string.gsub(text, "ALT%-", "A-")
    text = string.gsub(text, "CTRL%-", "C-")
    text = string.gsub(text, "SHIFT%-", "S-")
    text = string.gsub(text, "NUMPAD", "N")
    text = string.gsub(text, "MOUSEWHEELUP", "MWU")
    text = string.gsub(text, "MOUSEWHEELDOWN", "MWD")
    text = string.gsub(text, "BUTTON", "M")
    return text
end

RefreshKeybindLabels = function()
    local i
    for i = 1, #buttons do
        if buttons[i] and buttons[i].hotkeyText then
            buttons[i].hotkeyText:SetText(DMLCD.CompactBindingText(DB.keybinds and DB.keybinds[i]))
        end
    end
end

ApplySavedKeybinds = function()
    if not keybindOwner then
        return
    end

    if IsInCombat() then
        pendingBindingRefresh = true
        return
    end

    if not ClearOverrideBindings or not SetOverrideBindingClick then
        Print("This client does not expose the Wrath override-binding API needed for DML keybinds.")
        return
    end

    ClearOverrideBindings(keybindOwner)

    ForEachActiveButton(function(index, button)
        local key = DB.keybinds and DB.keybinds[index]
        if key and key ~= "" and button then
            SetOverrideBindingClick(keybindOwner, true, key, button:GetName(), "LeftButton")
        end
    end)

    pendingBindingRefresh = false
    RefreshKeybindLabels()
end

RefreshKeybindOverlays = function()
    local i
    for i = 1, #buttons do
        local button = buttons[i]
        if button and button.bindOverlay then
            if keybindMode and IsActiveButtonIndex(i) then
                local key = keybindWorking[i]
                button.bindOverlayText:SetText(key and DMLCD.CompactBindingText(key) or "No bind")
                button.bindOverlay:Show()
            else
                button.bindOverlay:Hide()
            end
        end
    end
end

local function IsModifierKey(key)
    key = string.upper(tostring(key or ""))
    return key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT" or
        key == "LCTRL" or key == "RCTRL" or key == "CTRL" or
        key == "LALT" or key == "RALT" or key == "ALT"
end

local function BuildBindingKey(key)
    key = string.upper(tostring(key or ""))
    if key == "" or IsModifierKey(key) then
        return nil
    end

    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end

    return prefix .. key
end

local function AssignWorkingKey(index, key)
    if not index or not key then
        return
    end

    local otherIndex, otherKey
    for otherIndex, otherKey in pairs(keybindWorking) do
        if otherIndex ~= index and otherKey == key then
            keybindWorking[otherIndex] = nil
        end
    end

    keybindWorking[index] = key
    RefreshKeybindOverlays()
end

local function RestoreAfterKeybindMode()
    if keybindCapture then
        keybindCapture:Hide()
    end
    if keybindPrompt then
        keybindPrompt:Hide()
    end

    RefreshKeybindOverlays()
    RefreshKeybindLabels()

    if not keybindRestoreBarShown then
        local barIndex
        for barIndex = 1, DB.barCount do
            if bars[barIndex] then
                bars[barIndex]:Hide()
            end
        end
    end

    if keybindRestoreConfig and configFrame then
        configFrame:Show()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
    end
end

FinishKeybindMode = function(saveChanges, reason)
    if not keybindMode then
        return
    end

    if saveChanges then
        if IsInCombat() then
            Print("Keybinds cannot be saved during combat.")
            return
        end
        DB.keybinds = CopyTable(keybindWorking)
        ApplySavedKeybinds()
        SaveCharacterLayoutSnapshot()
        Print("DML keybinds saved.")
    else
        Print(reason or "DML keybind changes canceled.")
    end

    keybindMode = false
    keybindHoverIndex = nil
    keybindWorking = {}
    RestoreAfterKeybindMode()
end

StartKeybindMode = function()
    if keybindMode then
        FinishKeybindMode(false, "DML keybind changes canceled.")
        return
    end

    if ConfigurationBlocked() then
        return
    end

    if not SetOverrideBindingClick or not ClearOverrideBindings then
        Print("This client does not expose the Wrath override-binding API needed for DML keybinds.")
        return
    end

    keybindWorking = CopyTable(DB.keybinds)
    keybindMode = true
    keybindHoverIndex = nil
    keybindRestoreConfig = configFrame and configFrame:IsShown() or false
    keybindRestoreBarShown = DB.shown

    if configFrame then
        configFrame:Hide()
    end
    local barIndex
    for barIndex = 1, DB.barCount do
        if bars[barIndex] then
            bars[barIndex]:Show()
        end
    end
    if keybindCapture then
        keybindCapture:Show()
    end
    if keybindPrompt then
        keybindPrompt:Show()
    end

    RefreshKeybindOverlays()
    Print("Keybind mode: hover a DML button and press a key. Right-click clears. Escape cancels.")
end

local function CreateKeybindFrames()
    keybindCapture = CreateFrame("Frame", "DMLCooldownBarKeybindCapture", UIParent)
    keybindCapture:SetAllPoints(UIParent)
    keybindCapture:SetFrameStrata("DIALOG")
    keybindCapture:EnableKeyboard(true)
    keybindCapture:EnableMouse(false)
    keybindCapture:Hide()

    keybindCapture:SetScript("OnKeyDown", function(_, key)
        if not keybindMode then
            return
        end

        key = string.upper(tostring(key or ""))
        if key == "ESCAPE" then
            FinishKeybindMode(false, "DML keybind changes canceled.")
            return
        end

        if not keybindHoverIndex then
            return
        end

        local bindingKey = BuildBindingKey(key)
        if bindingKey then
            AssignWorkingKey(keybindHoverIndex, bindingKey)
        end
    end)

    keybindPrompt = CreateFrame("Frame", "DMLCooldownBarKeybindPrompt", UIParent)
    keybindPrompt:SetWidth(430)
    keybindPrompt:SetHeight(135)
    keybindPrompt:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
    keybindPrompt:SetFrameStrata("FULLSCREEN_DIALOG")
    keybindPrompt:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    local title = keybindPrompt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", keybindPrompt, "TOP", 0, -18)
    title:SetText("DML Key Bind Mode")

    local question = keybindPrompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    question:SetPoint("TOP", title, "BOTTOM", 0, -8)
    question:SetText("Save keybinds?")

    local instruction = keybindPrompt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instruction:SetPoint("TOP", question, "BOTTOM", 0, -6)
    instruction:SetText("Hover a button and press a key. Right-click clears. Escape cancels.")

    local saveButton = CreateFrame("Button", nil, keybindPrompt, "UIPanelButtonTemplate")
    saveButton:SetWidth(95)
    saveButton:SetHeight(22)
    saveButton:SetPoint("BOTTOMRIGHT", keybindPrompt, "BOTTOM", -6, 18)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function()
        FinishKeybindMode(true)
    end)

    local cancelButton = CreateFrame("Button", nil, keybindPrompt, "UIPanelButtonTemplate")
    cancelButton:SetWidth(95)
    cancelButton:SetHeight(22)
    cancelButton:SetPoint("BOTTOMLEFT", keybindPrompt, "BOTTOM", 6, 18)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        FinishKeybindMode(false, "DML keybind changes canceled.")
    end)

    keybindPrompt:Hide()
end

local function CreateLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function CreateEditField(parent, key, labelText, x, y, width)
    CreateLabel(parent, labelText, x, y)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetWidth(width or 70)
    edit:SetHeight(20)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 150, y + 5)
    edit:SetFrameLevel(parent:GetFrameLevel() + 20)
    edit:SetTextColor(1, 1, 1)
    edit:SetTextInsets(8, 8, 0, 0)

    -- 3.3.5's InputBoxTemplate center texture can fall behind Dialog backdrops.
    -- Give every numeric field the same reliable fill/layering as Profile name.
    local fill = edit:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", edit, "TOPLEFT", 5, -3)
    fill:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -5, 3)
    fill:SetTexture(0.04, 0.04, 0.04, 0.95)
    edit.dmlBackgroundFill = fill

    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    configControls[key] = edit
    return edit
end

-- Preserve the current edit fields as a draft before switching the Bar
-- settings selector. This lets each bar be edited independently before Apply.
function DMLCD.CaptureConfigBarFields(silent)
    if not configControls.buttonCount or not configControls.rows or
        not configControls.columns or not configControls.buttonSize or
        not configControls.spacingX or not configControls.spacingY
    then
        return true
    end

    local barIndex = math.floor(Clamp(DMLCD.ConfigSelectedBar, 1, MAX_BARS) or 1)
    local buttonCount = Clamp(configControls.buttonCount:GetText(), 1, MAX_BUTTONS)
    local rows = Clamp(configControls.rows:GetText(), 1, MAX_BUTTONS)
    local columns = Clamp(configControls.columns:GetText(), 1, MAX_BUTTONS)
    local buttonSize = Clamp(configControls.buttonSize:GetText(), 24, 64)
    local spacingX = Clamp(configControls.spacingX:GetText(), 0, 40)
    local spacingY = Clamp(configControls.spacingY:GetText(), 0, 40)

    if not buttonCount or not rows or not columns or not buttonSize or
        not spacingX or not spacingY
    then
        if not silent then
            Print("Bar " .. tostring(barIndex) .. " contains an invalid number.")
        end
        return false
    end

    buttonCount = math.floor(buttonCount)
    rows = math.floor(rows)
    columns = math.floor(columns)
    buttonSize = math.floor(buttonSize)
    spacingX = math.floor(spacingX)
    spacingY = math.floor(spacingY)

    local cells = rows * columns
    if cells < buttonCount then
        if not silent then
            Print("Bar " .. tostring(barIndex) .. " only has " .. tostring(cells) ..
                " grid cells for " .. tostring(buttonCount) .. " buttons.")
        end
        return false
    elseif cells > MAX_BUTTONS then
        if not silent then
            Print("Bar " .. tostring(barIndex) .. " may contain no more than " ..
                tostring(MAX_BUTTONS) .. " grid cells.")
        end
        return false
    end

    DMLCD.ConfigBarDrafts = DMLCD.ConfigBarDrafts or {}
    DMLCD.ConfigBarDrafts[barIndex] = {
        buttonCount = buttonCount,
        rows = rows,
        columns = columns,
        buttonSize = buttonSize,
        spacingX = spacingX,
        spacingY = spacingY
    }
    return true
end

function DMLCD.PopulateConfigBarFields(barIndex)
    barIndex = math.floor(Clamp(barIndex, 1, MAX_BARS) or 1)
    DMLCD.ConfigBarDrafts = DMLCD.ConfigBarDrafts or {}
    local settings = DMLCD.ConfigBarDrafts[barIndex] or DMLCD.GetBarSettings(barIndex)
    configControls.buttonCount:SetText(tostring(settings.buttonCount))
    configControls.rows:SetText(tostring(settings.rows))
    configControls.columns:SetText(tostring(settings.columns))
    configControls.buttonSize:SetText(tostring(settings.buttonSize))
    configControls.spacingX:SetText(tostring(settings.spacingX))
    configControls.spacingY:SetText(tostring(settings.spacingY))
end

function DMLCD.SetBarCountDropdownValue(dropdown, value, skipCapture)
    if not skipCapture and not DMLCD.CaptureConfigBarFields(false) then
        return false
    end

    value = math.floor(Clamp(value, 1, MAX_BARS) or 1)
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, tostring(value))
    end

    local selectedBar = math.floor(Clamp(DMLCD.ConfigSelectedBar, 1, value) or 1)
    if configControls.barSettings then
        DMLCD.SetBarSettingsDropdownValue(configControls.barSettings, selectedBar, true)
    end
    return true
end

function DMLCD.CreateBarCountDropdown(parent, x, y)
    CreateLabel(parent, "Number of bars", x, y)
    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarCountDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 132, y + 12)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 70)
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local i
            for i = 1, MAX_BARS do
                local selected = i
                local info = UIDropDownMenu_CreateInfo()
                info.text = tostring(selected)
                info.value = selected
                info.checked = dropdown.selectedValue == selected
                info.func = function()
                    DMLCD.SetBarCountDropdownValue(dropdown, selected, false)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    configControls.barCount = dropdown
    return dropdown
end

function DMLCD.SetBarSettingsDropdownValue(dropdown, value, skipCapture)
    if not skipCapture and not DMLCD.CaptureConfigBarFields(false) then
        return false
    end

    local barCount = configControls.barCount and
        tonumber(configControls.barCount.selectedValue) or DB.barCount
    value = math.floor(Clamp(value, 1, barCount or 1) or 1)
    DMLCD.ConfigSelectedBar = value
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, "Bar " .. tostring(value))
    end
    DMLCD.PopulateConfigBarFields(value)
    return true
end

function DMLCD.CreateBarSettingsDropdown(parent, x, y)
    CreateLabel(parent, "Bar settings", x, y)
    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarSettingsDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 132, y + 12)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 100)
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local barCount = configControls.barCount and
                tonumber(configControls.barCount.selectedValue) or DB.barCount
            local i
            for i = 1, math.floor(Clamp(barCount, 1, MAX_BARS) or 1) do
                local selected = i
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Bar " .. tostring(selected)
                info.value = selected
                info.checked = dropdown.selectedValue == selected
                info.func = function()
                    DMLCD.SetBarSettingsDropdownValue(dropdown, selected, false)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    configControls.barSettings = dropdown
    return dropdown
end

local function CreateCheckField(parent, key, labelText, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + 7)

    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(labelText)
    configControls[key] = check
    return check
end

DMLCD.RangeFinderOptions = {
    { value = "OFF", text = "Off" },
    { value = "BORDER", text = "Border" },
    { value = "FADE", text = "Fade" }
}

function DMLCD.NormalizeRangeFinderMode(value)
    value = string.upper(tostring(value or "OFF"))
    if value == "DEFAULT" then
        value = "OFF"
    end
    if value ~= "BORDER" and value ~= "FADE" then
        value = "OFF"
    end
    return value
end

function DMLCD.GetRangeFinderModeText(value)
    value = DMLCD.NormalizeRangeFinderMode(value)
    local optionIndex
    for optionIndex = 1, #DMLCD.RangeFinderOptions do
        if DMLCD.RangeFinderOptions[optionIndex].value == value then
            return DMLCD.RangeFinderOptions[optionIndex].text
        end
    end
    return "Off"
end

function DMLCD.SetRangeFinderDropdownValue(dropdown, value)
    value = DMLCD.NormalizeRangeFinderMode(value)
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, DMLCD.GetRangeFinderModeText(value))
    end
end

function DMLCD.CreateRangeFinderDropdown(parent, x, y)
    CreateLabel(parent, "Range finder", x, y)
    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarRangeFinderDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 132, y + 12)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 105)
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local optionIndex
            for optionIndex = 1, #DMLCD.RangeFinderOptions do
                local option = DMLCD.RangeFinderOptions[optionIndex]
                local selectedValue = option.value
                local selectedText = option.text
                local info = UIDropDownMenu_CreateInfo()
                info.text = selectedText
                info.value = selectedValue
                info.checked = dropdown.selectedValue == selectedValue
                info.func = function()
                    DMLCD.SetRangeFinderDropdownValue(dropdown, selectedValue)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    configControls.rangeFinder = dropdown
    return dropdown
end

local barLockKeyOptions = {
    { value = "SHIFT", text = "Shift" },
    { value = "CTRL", text = "Ctrl" },
    { value = "ALT", text = "Alt" },
    { value = "NONE", text = "None" }
}

local function SetBarLockDropdownValue(dropdown, value)
    value = string.upper(tostring(value or "SHIFT"))
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end

    local i
    for i = 1, #barLockKeyOptions do
        if barLockKeyOptions[i].value == value then
            if UIDropDownMenu_SetText then
                UIDropDownMenu_SetText(dropdown, barLockKeyOptions[i].text)
            end
            return
        end
    end
end

local function CreateBarLockKeyDropdown(parent, x, y)
    CreateLabel(parent, "Locked-bar drag modifier", x, y)

    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarLockKeyDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 132, y + 12)

    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 105)
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local i
            for i = 1, #barLockKeyOptions do
                local option = barLockKeyOptions[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.text
                info.value = option.value
                info.checked = dropdown.selectedValue == option.value
                info.func = function()
                    SetBarLockDropdownValue(dropdown, option.value)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end

    configControls.barLockKey = dropdown
    return dropdown
end

local function SetBlizzardBarDropdownValue(dropdown, value)
    value = NormalizeBlizzardBarMode(value) or "SHOW"
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, GetBlizzardBarModeText(value))
    end
end

local function CreateBlizzardBarDropdown(parent, x, y)
    CreateLabel(parent, "Blizzard bar", x, y)

    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarBlizzardBarDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 105, y + 12)

    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 190)
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local i
            for i = 1, #blizzardBarModeOptions do
                local option = blizzardBarModeOptions[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.text
                info.value = option.value
                info.checked = dropdown.selectedValue == option.value
                info.func = function()
                    SetBlizzardBarDropdownValue(dropdown, option.value)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end

    configControls.blizzardBarMode = dropdown
    return dropdown
end

local function SetNamedProfileDropdownValue(dropdown, value)
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, value or "Select profile")
    end
end

local function CreateNamedProfileDropdown(parent, x, y)
    CreateLabel(parent, "Saved profile", x, y)
    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarProfileDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 100, y + 12)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 190)
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local names = GetSortedProfileNames()
            local i
            for i = 1, #names do
                local profileName = names[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text = profileName
                info.value = profileName
                info.checked = dropdown.selectedValue == profileName
                info.func = function()
                    SetNamedProfileDropdownValue(dropdown, profileName)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    configControls.profileDropdown = dropdown
    return dropdown
end

local function SetCopyProfileDropdownValue(dropdown, value)
    dropdown.selectedValue = value
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropdown, value)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, value or "Select profile")
    end
end

local function CreateCopyProfileDropdown(parent, x, y)
    CreateLabel(parent, "Copy profile", x, y)
    local dropdown = CreateFrame(
        "Frame",
        "DMLCooldownBarCopyProfileDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 105, y + 12)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, 210)
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dropdown, function()
            local names = GetSortedProfileNames()
            local i
            for i = 1, #names do
                local profileName = names[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text = profileName
                info.value = profileName
                info.checked = dropdown.selectedValue == profileName
                info.func = function()
                    SetCopyProfileDropdownValue(dropdown, profileName)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    configControls.copyProfileDropdown = dropdown
    return dropdown
end

RefreshProfileControls = function(preferredProfile, preferredCopyProfile)
    if not configFrame or not globalDB then
        return
    end

    local defaultProfileName = GetDefaultProfileName()
    local profileDropdown = configControls.profileDropdown
    if profileDropdown then
        local selected = preferredProfile or profileDropdown.selectedValue
        local savedName = selected and FindNamedProfile(selected) or nil
        if not savedName and defaultProfileName then
            savedName = FindNamedProfile(defaultProfileName)
        end
        selected = savedName
        SetNamedProfileDropdownValue(profileDropdown, selected)

        if configControls.profileName and TrimText(configControls.profileName:GetText()) == "" then
            configControls.profileName:SetText(defaultProfileName or "")
        end
    elseif configControls.profileName and TrimText(configControls.profileName:GetText()) == "" then
        configControls.profileName:SetText(defaultProfileName or "")
    end

    local copyDropdown = configControls.copyProfileDropdown
    if copyDropdown then
        local names = GetSortedProfileNames()
        local selected = preferredCopyProfile or copyDropdown.selectedValue
        local savedName = selected and FindNamedProfile(selected) or nil
        selected = savedName or names[1]

        if selected then
            SetCopyProfileDropdownValue(copyDropdown, selected)
        else
            copyDropdown.selectedValue = nil
            if UIDropDownMenu_SetSelectedValue then
                UIDropDownMenu_SetSelectedValue(copyDropdown, nil)
            end
            if UIDropDownMenu_SetText then
                UIDropDownMenu_SetText(copyDropdown, "No saved profiles")
            end
        end

        if configControls.copyProfileButton then
            if selected then
                configControls.copyProfileButton:Enable()
            else
                configControls.copyProfileButton:Disable()
            end
        end
    end
end

RefreshConfigFields = function()
    if not configFrame then
        return
    end

    DMLCD.ConfigBarDrafts = {}
    DMLCD.ConfigSelectedBar = math.floor(Clamp(DMLCD.ConfigSelectedBar, 1, DB.barCount) or 1)
    DMLCD.SetBarCountDropdownValue(configControls.barCount, DB.barCount, true)
    DMLCD.SetBarSettingsDropdownValue(
        configControls.barSettings,
        DMLCD.ConfigSelectedBar,
        true
    )
    configControls.fallbackDelay:SetText(tostring(DB.fallbackDelay))

    configControls.locked:SetChecked(DB.locked and 1 or nil)
    configControls.shown:SetChecked(DB.shown and 1 or nil)
    configControls.background:SetChecked(DB.background and 1 or nil)
    configControls.showSlotNumbers:SetChecked(DB.showSlotNumbers and 1 or nil)
    configControls.autoAssign:SetChecked(DB.autoAssign and 1 or nil)
    configControls.clickFallback:SetChecked(DB.clickFallback and 1 or nil)
    configControls.nativeCooldowns:SetChecked(DB.nativeCooldowns and 1 or nil)
    configControls.resourceFade:SetChecked(DB.resourceFade and 1 or nil)
    DMLCD.SetRangeFinderDropdownValue(configControls.rangeFinder, DB.rangeFinder)
    configControls.simpleTooltips:SetChecked(DB.simpleTooltips and 1 or nil)
    configControls.bagnonCompatibility:SetChecked(DB.bagnonCompatibility and 1 or nil)
    configControls.showMessages:SetChecked(DB.showMessages and 1 or nil)
    configControls.showReadyMessages:SetChecked(DB.showReadyMessages and 1 or nil)
    configControls.debugMessages:SetChecked(DB.debugMessages and 1 or nil)
    configControls.showMinimapButton:SetChecked(DB.showMinimapButton and 1 or nil)
    configControls.hideGryphons:SetChecked(DB.hideGryphons and 1 or nil)
    configControls.useDMLAuraBar:SetChecked(DB.useDMLAuraBar and 1 or nil)
    configControls.useDMLPetBar:SetChecked(DB.useDMLPetBar and 1 or nil)
    configControls.useBar1AsStanceBar:SetChecked(DB.useBar1AsStanceBar and 1 or nil)
    configControls.showAnchors:SetChecked(DB.showAnchors and 1 or nil)
    SetBarLockDropdownValue(configControls.barLockKey, DB.barLockKey)
    SetBlizzardBarDropdownValue(configControls.blizzardBarMode, DB.blizzardBarMode)
    if RefreshProfileControls then
        RefreshProfileControls()
    end
end

local function ApplyConfigSettings()
    if ConfigurationBlocked() then
        return false
    end

    local previousBlizzardMode = DB.blizzardBarMode

    if not DMLCD.CaptureConfigBarFields(false) then
        return false
    end

    local barCount = math.floor(Clamp(configControls.barCount.selectedValue, 1, MAX_BARS) or 1)
    local fallbackDelay = Clamp(configControls.fallbackDelay:GetText(), 0, 5)
    if not fallbackDelay then
        Print("Config contains an invalid fallback delay.")
        return false
    end

    DB.barSettings = type(DB.barSettings) == "table" and DB.barSettings or {}
    local barIndex
    for barIndex = 1, MAX_BARS do
        local settings = DMLCD.ConfigBarDrafts and DMLCD.ConfigBarDrafts[barIndex]
        if settings then
            DB.barSettings[barIndex] = DMLCD.NormalizeBarSettings(
                settings,
                DB.barSettings[barIndex] or DB.barSettings[1] or defaults
            )
        elseif type(DB.barSettings[barIndex]) ~= "table" then
            DB.barSettings[barIndex] = DMLCD.NormalizeBarSettings(
                nil,
                DB.barSettings[1] or defaults
            )
        end
    end

    DB.barCount = barCount
    DMLCD.SyncLegacyBarSettings()
    DB.fallbackDelay = fallbackDelay

    DB.locked = configControls.locked:GetChecked() and true or false
    DB.shown = configControls.shown:GetChecked() and true or false
    DB.background = configControls.background:GetChecked() and true or false
    DB.showSlotNumbers = configControls.showSlotNumbers:GetChecked() and true or false
    DB.autoAssign = configControls.autoAssign:GetChecked() and true or false
    DB.clickFallback = configControls.clickFallback:GetChecked() and true or false
    DB.nativeCooldowns = configControls.nativeCooldowns:GetChecked() and true or false
    DB.resourceFade = configControls.resourceFade:GetChecked() and true or false
    DB.rangeFinder = DMLCD.NormalizeRangeFinderMode(
        configControls.rangeFinder.selectedValue or DB.rangeFinder
    )
    DB.simpleTooltips = configControls.simpleTooltips:GetChecked() and true or false
    DB.bagnonCompatibility = configControls.bagnonCompatibility:GetChecked() and true or false
    DB.showMessages = configControls.showMessages:GetChecked() and true or false
    DB.showReadyMessages = configControls.showReadyMessages:GetChecked() and true or false
    DB.debugMessages = configControls.debugMessages:GetChecked() and true or false
    DB.showMinimapButton = configControls.showMinimapButton:GetChecked() and true or false
    DB.hideGryphons = configControls.hideGryphons:GetChecked() and true or false
    DB.useDMLAuraBar = configControls.useDMLAuraBar:GetChecked() and true or false
    DB.useDMLPetBar = configControls.useDMLPetBar:GetChecked() and true or false
    DB.useBar1AsStanceBar = configControls.useBar1AsStanceBar:GetChecked() and true or false
    DB.showAnchors = configControls.showAnchors:GetChecked() and true or false
    DB.barLockKey = configControls.barLockKey.selectedValue or DB.barLockKey or "SHIFT"
    DB.blizzardBarMode = configControls.blizzardBarMode.selectedValue or DB.blizzardBarMode or "SHOW"

    LayoutButtons()
    SetShown(DB.shown)
    RefreshAllButtons()
    ApplySavedKeybinds()
    UpdateMinimapButtonVisibility()
    ApplyBlizzardBarSettings()
    if DMLCD.RefreshBagnonIcons then
        DMLCD.RefreshBagnonIcons()
    end
    RefreshConfigFields()
    SaveCharacterLayoutSnapshot()
    Print("Configuration applied: " .. tostring(DB.barCount) .. " bar(s) with individual bar layouts.")
    if DB.blizzardBarMode ~= "SHOW" and DB.blizzardBarMode ~= previousBlizzardMode then
        PrintBlizzardBarWarning()
    end
    return true
end

local function ResetFromConfig()
    if ConfigurationBlocked() then
        return
    end

    CopyDefaults(true)
    pendingFallbacks = {}
    RestoreAllPositions()
    if DMLCD.RestorePetBarPosition then
        DMLCD.RestorePetBarPosition()
    end
    if DMLCD.RestoreAuraBarPosition then
        DMLCD.RestoreAuraBarPosition()
    end
    LayoutButtons()
    SetShown(DB.shown)
    ApplySavedKeybinds()
    UpdateMinimapButtonVisibility()
    ApplyBlizzardBarSettings()
    if DMLCD.RefreshBagnonIcons then
        DMLCD.RefreshBagnonIcons()
    end
    RefreshConfigFields()
    SaveCharacterLayoutSnapshot()
    Print("Settings reset to defaults.")
end

function DMLCD.ResetBarPositionsFromConfig()
    if ConfigurationBlocked() then
        return
    end

    DB.barPositions = {}
    DB.petBarPosition = nil
    DB.auraBarPosition = nil
    DB.point = defaults.point
    DB.relativePoint = defaults.relativePoint
    DB.x = defaults.x
    DB.y = defaults.y

    RestoreAllPositions()
    if DMLCD.RestorePetBarPosition then
        DMLCD.RestorePetBarPosition()
    end
    if DMLCD.RestoreAuraBarPosition then
        DMLCD.RestoreAuraBarPosition()
    end
    SaveAllPositions()
    RefreshConfigFields()
    SaveCharacterLayoutSnapshot()

    Print("DML bar positions, including the aura and pet bars, reset to the center of the screen.")
end

local function CreateConfigFrame()
    DMLCD.ConfigBarDrafts = {}
    DMLCD.ConfigSelectedBar = 1
    configFrame = CreateFrame("Frame", "DMLCooldownBarConfigFrame", UIParent)
    configFrame:SetWidth(740)
    configFrame:SetHeight(790)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    configFrame:SetFrameStrata("DIALOG")
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

    configFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    configFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", configFrame, "TOP", 0, -18)
    title:SetText("DML Cooldown Bar Configuration")

    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    CreateLabel(configFrame, "Layout", 28, -55)
    DMLCD.CreateBarCountDropdown(configFrame, 40, -82)
    DMLCD.CreateBarSettingsDropdown(configFrame, 40, -112)
    CreateEditField(configFrame, "buttonCount", "Buttons per bar", 40, -142, 70)
    CreateEditField(configFrame, "rows", "Rows", 40, -172, 70)
    CreateEditField(configFrame, "columns", "Columns", 40, -202, 70)
    CreateEditField(configFrame, "buttonSize", "Button size", 40, -232, 70)
    CreateEditField(configFrame, "spacingX", "Horizontal gap", 40, -262, 70)
    CreateEditField(configFrame, "spacingY", "Vertical gap", 40, -292, 70)
    CreateEditField(configFrame, "fallbackDelay", "Fallback delay", 40, -322, 70)
    CreateCheckField(configFrame, "showSlotNumbers", "Show slot numbers", 40, -362)
    CreateBlizzardBarDropdown(configFrame, 28, -397)
    CreateCheckField(configFrame, "hideGryphons", "Hide gryphons", 40, -437)
    CreateCheckField(configFrame, "useDMLAuraBar", "Use DML aura bar", 185, -437)
    CreateCheckField(configFrame, "showAnchors", "Show anchors", 40, -467)
    CreateCheckField(configFrame, "useDMLPetBar", "Use DML pet bar", 185, -467)
    CreateCheckField(configFrame, "simpleTooltips", "Simple tooltips", 40, -497)
    CreateCheckField(configFrame, "useBar1AsStanceBar", "Use bar 1 as stance bar", 185, -497)

    CreateLabel(configFrame, "Behavior", 375, -55)
    CreateCheckField(configFrame, "shown", "Show bars", 385, -82)
    CreateCheckField(configFrame, "locked", "Lock bars", 385, -112)
    CreateCheckField(configFrame, "background", "Background", 385, -142)
    CreateCheckField(configFrame, "autoAssign", "Auto-assign learned spells", 385, -172)
    CreateCheckField(configFrame, "nativeCooldowns", "Normal spell/item cooldowns", 385, -202)
    CreateCheckField(configFrame, "bagnonCompatibility", "Bagnon compatibility", 385, -232)
    CreateCheckField(configFrame, "clickFallback", "Click fallback (ALE backup)", 385, -262)
    CreateCheckField(configFrame, "showMessages", "Show cooldown messages", 385, -292)
    CreateCheckField(configFrame, "showReadyMessages", "Show spell ready messages", 385, -322)
    CreateCheckField(configFrame, "showMinimapButton", "Show minimap button", 385, -352)
    CreateCheckField(configFrame, "debugMessages", "Addon debug messages", 385, -382)
    CreateCheckField(configFrame, "resourceFade", "Fade when resource is low", 385, -412)
    DMLCD.CreateRangeFinderDropdown(configFrame, 375, -447)
    CreateBarLockKeyDropdown(configFrame, 375, -487)

    CreateLabel(configFrame, "Profiles", 28, -520)
    CreateLabel(configFrame, "Profile name", 40, -550)
    local profileName = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    profileName:SetWidth(180)
    profileName:SetHeight(20)
    profileName:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 145, -545)
    profileName:SetFrameLevel(configFrame:GetFrameLevel() + 20)
    profileName:SetTextInsets(8, 8, 0, 0)
    profileName:SetAutoFocus(false)

    -- The 3.3.5 InputBoxTemplate middle texture can render behind a dialog
    -- backdrop on some clients. This child-frame fill keeps the entire input
    -- field visible while retaining Blizzard's left/right border artwork.
    local profileNameFill = profileName:CreateTexture(nil, "BACKGROUND")
    profileNameFill:SetPoint("TOPLEFT", profileName, "TOPLEFT", 5, -3)
    profileNameFill:SetPoint("BOTTOMRIGHT", profileName, "BOTTOMRIGHT", -5, 3)
    profileNameFill:SetTexture(0.04, 0.04, 0.04, 0.95)
    profileName.dmlBackgroundFill = profileNameFill

    profileName:SetText(GetDefaultProfileName() or "")
    profileName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    profileName:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    configControls.profileName = profileName

    CreateNamedProfileDropdown(configFrame, 375, -550)

    local saveProfile = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    saveProfile:SetWidth(115)
    saveProfile:SetHeight(23)
    saveProfile:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 40, -585)
    saveProfile:SetText("Save Current")
    saveProfile:SetScript("OnClick", function()
        local requestedName = TrimText(configControls.profileName:GetText())
        if ApplyConfigSettings() then
            SaveNamedProfile(requestedName)
        end
    end)

    local loadProfile = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    loadProfile:SetWidth(95)
    loadProfile:SetHeight(23)
    loadProfile:SetPoint("LEFT", saveProfile, "RIGHT", 8, 0)
    loadProfile:SetText("Load")
    loadProfile:SetScript("OnClick", function()
        local selected = configControls.profileDropdown.selectedValue
        local savedName, record = FindNamedProfile(selected or configControls.profileName:GetText())
        if not savedName then
            Print("Select a saved profile to load.")
            return
        end
        RequestProfileApply(
            GetRecordSnapshot(record),
            "Profile '" .. savedName .. "'",
            savedName
        )
    end)

    local deleteProfile = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    deleteProfile:SetWidth(95)
    deleteProfile:SetHeight(23)
    deleteProfile:SetPoint("LEFT", loadProfile, "RIGHT", 8, 0)
    deleteProfile:SetText("Delete")
    deleteProfile:SetScript("OnClick", function()
        local selected = configControls.profileDropdown.selectedValue
        DeleteNamedProfile(selected or configControls.profileName:GetText())
    end)

    CreateCopyProfileDropdown(configFrame, 375, -600)
    local copyProfile = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    copyProfile:SetWidth(155)
    copyProfile:SetHeight(23)
    copyProfile:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 475, -630)
    copyProfile:SetText("Copy To This Character")
    configControls.copyProfileButton = copyProfile
    copyProfile:SetScript("OnClick", function()
        local selected = configControls.copyProfileDropdown.selectedValue
        local savedName, record = FindNamedProfile(selected)
        if not savedName then
            Print("Select a saved profile to copy.")
            return
        end

        local snapshot = GetRecordSnapshot(record)
        if not snapshot then
            Print("The selected profile is empty or invalid.")
            return
        end
        RequestProfileApply(snapshot, "Profile '" .. savedName .. "'")
    end)

    local note = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetWidth(670)
    note:SetPoint("TOP", configFrame, "TOP", 0, -690)
    note:SetJustifyH("LEFT")
    note:SetText(
        "Profiles save settings, bar positions, assignments, and DML keybinds, but not active cooldown timers. Each character receives an initial profile using its character name. Loading or copying a profile changes only the live character layout; saved profiles change only when Save Current is pressed. Saved Profile and Copy Profile use the same account-wide list. Hidden Blizzard buttons keep their original keybinds, so clearing the Blizzard bar first is recommended."
    )

    local apply = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    apply:SetWidth(100)
    apply:SetHeight(24)
    apply:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 34, 30)
    apply:SetText("Apply")
    apply:SetScript("OnClick", ApplyConfigSettings)

    local keybind = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    keybind:SetWidth(120)
    keybind:SetHeight(24)
    keybind:SetPoint("LEFT", apply, "RIGHT", 10, 0)
    keybind:SetText("Set Key Binds")
    keybind:SetScript("OnClick", StartKeybindMode)

    local reset = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    reset:SetWidth(110)
    reset:SetHeight(24)
    reset:SetPoint("LEFT", keybind, "RIGHT", 10, 0)
    reset:SetText("Reset Defaults")
    reset:SetScript("OnClick", ResetFromConfig)

    local resetPositions = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    resetPositions:SetWidth(120)
    resetPositions:SetHeight(24)
    resetPositions:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    resetPositions:SetText("Reset Positions")
    resetPositions:SetScript("OnClick", DMLCD.ResetBarPositionsFromConfig)

    local closeBottom = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    closeBottom:SetWidth(80)
    closeBottom:SetHeight(24)
    closeBottom:SetPoint("LEFT", resetPositions, "RIGHT", 10, 0)
    closeBottom:SetText("Close")
    closeBottom:SetScript("OnClick", function()
        configFrame:Hide()
    end)

    table.insert(UISpecialFrames, "DMLCooldownBarConfigFrame")
    configFrame:Hide()
end

ShowConfigWindow = function()
    if not configFrame then
        return
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        SaveCharacterLayoutSnapshot()
        EnsureDefaultCharacterProfile()
        RefreshConfigFields()
        if RefreshProfileControls then
            RefreshProfileControls()
        end
        configFrame:Show()
    end
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
    if not minimapButton or not Minimap then
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

local function UpdateMinimapButtonFromCursor()
    if not minimapButton or not Minimap or not GetCursorPosition then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then
        return
    end

    DB.minimapAngle = math.deg(Atan2(cursorY - centerY, cursorX - centerX))
    PositionMinimapButton()
end

UpdateMinimapButtonVisibility = function()
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

local function ApplyProfileSnapshotNow(snapshot, label, profileNameAfterLoad)
    if type(snapshot) ~= "table" then
        Print("The selected profile does not contain a valid layout.")
        return false
    end

    if keybindMode then
        FinishKeybindMode(false, "DML keybind changes canceled before loading the layout.")
    end

    local key
    for key in pairs(DB) do
        DB[key] = nil
    end
    for key, value in pairs(snapshot) do
        DB[key] = DeepCopy(value)
    end

    DB.version = defaults.version
    DB.cooldowns = {}
    pendingFallbacks = {}
    activeAssignmentDrag = nil
    CopyDefaults(false)

    LayoutButtons()
    RestoreAllPositions()
    if DMLCD.RestorePetBarPosition then
        DMLCD.RestorePetBarPosition()
    end
    if DMLCD.RestoreAuraBarPosition then
        DMLCD.RestoreAuraBarPosition()
    end
    SetShown(DB.shown)
    RefreshAllButtons()
    ApplySavedKeybinds()
    UpdateMinimapButtonVisibility()
    ApplyBlizzardBarSettings()
    if DMLCD.RefreshBagnonIcons then
        DMLCD.RefreshBagnonIcons()
    end
    RefreshConfigFields()

    -- Loading a saved profile also makes that profile the current working name
    -- shown in the Profile name field. Copy Profile deliberately does not pass
    -- this value, so it can import another layout without changing the user's
    -- current save destination. Neither path writes a saved profile here.
    if profileNameAfterLoad and configControls.profileName then
        configControls.profileName:SetText(tostring(profileNameAfterLoad))
    end

    -- Loading/copying a profile changes only this character's live per-character
    -- layout. The source profile and the character's named profile remain
    -- untouched until Save Current is explicitly pressed.
    Print((label or "Layout") .. " loaded for this character. Use Save Current to overwrite a saved profile.")
    if DB.blizzardBarMode ~= "SHOW" then
        PrintBlizzardBarWarning()
    end
    return true
end

RequestProfileApply = function(snapshot, label, profileNameAfterLoad)
    if type(snapshot) ~= "table" then
        Print("The selected profile does not contain a valid layout.")
        return false
    end

    if IsInCombat() then
        pendingProfileApply = {
            data = DeepCopy(snapshot),
            label = label or "Layout",
            profileNameAfterLoad = profileNameAfterLoad
        }
        Print((label or "Layout") .. " will load when combat ends.")
        return true
    end

    return ApplyProfileSnapshotNow(snapshot, label, profileNameAfterLoad)
end

local function CreateMinimapButton()
    if not Minimap then
        return
    end

    minimapButton = CreateFrame("Button", "DMLCooldownBarMinimapButton", Minimap)
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)
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
        GameTooltip:SetText("DML Cooldown Bar")
        GameTooltip:AddLine("Left-click: open or close configuration", 1, 1, 1)
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
        ShowConfigWindow()
    end)

    minimapButton:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", UpdateMinimapButtonFromCursor)
    end)

    minimapButton:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self.dragStopTime = GetTime()
        self:SetScript("OnUpdate", nil)
        UpdateMinimapButtonFromCursor()
        if SaveCharacterLayoutSnapshot then
            SaveCharacterLayoutSnapshot()
        end
    end)

    UpdateMinimapButtonVisibility()
end

local function RestoreCooldowns()
    local expired = {}
    local key, state

    for key, state in pairs(DB.cooldowns) do
        if type(state) ~= "table" or not state.expiresAt or not state.spellId then
            table.insert(expired, key)
        else
            local remaining = state.expiresAt - time()
            if remaining <= 0 then
                table.insert(expired, key)
            else
                state.sessionExpires = GetTime() + remaining
                state.startMono = state.sessionExpires - (tonumber(state.duration) or remaining)
            end
        end
    end

    local i
    for i = 1, #expired do
        DB.cooldowns[expired[i]] = nil
    end
end

SetShown = function(shown)
    DB.shown = shown and true or false
    local barIndex
    for barIndex = 1, #bars do
        if bars[barIndex] then
            if DB.shown and barIndex <= DB.barCount then
                bars[barIndex]:Show()
            else
                bars[barIndex]:Hide()
            end
        end
    end
end

local function PrintLayoutStatus()
    Print(
        tostring(DB.barCount) .. " bar(s). Bar 1: " .. tostring(DB.buttonCount) ..
        " buttons, arranged as " .. tostring(DB.rows) ..
        " row(s) x " .. tostring(DB.columns) .. " column(s)."
    )
end

local function PrintHelp()
    Print("Version " .. ADDON_VERSION)
    Print("Commands use one chat line each.")
    Print("/dmlcd unlock | lock | show | hide | config")
    Print("/dmlcd bars <1-5> | buttons <1-48> | rows <n> | columns <n>")
    Print("/dmlcd layout <buttons> <rows> <columns> | grid <rows> <columns>")
    Print("/dmlcd size <24-64> | spacing <horizontal> [vertical]")
    Print("/dmlcd hspacing <0-40> | vspacing <0-40> | background on|off")
    Print("/dmlcd slotnumbers on|off | barlockkey shift|ctrl|alt|none | minimap on|off")
    Print("/dmlcd blizzardbar show|all|action|background | hidegryphons on|off")
    Print("/dmlcd anchors on|off  (DML aura/pet bar options are available in Config)")
    Print("/dmlcd assign <slot> <spellId> [fallbackSeconds]  (bar 1)")
    Print("/dmlcd assignbar <bar> <slot> <spellId> [fallbackSeconds]")
    Print("/dmlcd assignitem <slot> <itemId> | assignitembar <bar> <slot> <itemId>")
    Print("/dmlcd clear <slot> | clearbar <bar> <slot> | clearall | autoassign on|off")
    Print("Auto-assign watches newly learned active spells; cooldown START messages do not create slots.")
    Print("/dmlcd messages on|off | readymessages on|off | debug on|off")
    Print("/dmlcd clickfallback on|off | nativecooldowns on|off | resourcefade on|off | bagnon on|off")
    Print("/dmlcd fallbackdelay <0-5>")
    Print("/dmlcd kb | keybind | kb save | kb cancel")
    Print("/dmlcd profile save|load|delete <name> | profile list")
    Print("/dmlcd profile copy <name>")
    Print("/dmlcd testlearn <spellId> | testmeta <spellId> <rank> [custom text]")
    Print("/dmlcd teststart <spellId> <seconds> [token]")
    Print("/dmlcd testready <spellId> [token] | status | reset")
    Print("Unlocked: drag spells/items normally. Locked: the selected modifier can be pressed before or after pickup.")
end

local function ParseOnOff(value)
    value = string.lower(tostring(value or ""))
    if value == "on" or value == "1" or value == "true" then
        return true
    elseif value == "off" or value == "0" or value == "false" then
        return false
    end
    return nil
end

local function Tokenize(message)
    local result = {}
    local token
    for token in string.gmatch(message or "", "%S+") do
        table.insert(result, token)
    end
    return result
end

local function HandleSlash(message)
    local args = Tokenize(message)
    local command = string.lower(args[1] or "help")

    if command == "help" then
        PrintHelp()
        return
    elseif command == "show" then
        SetShown(true)
        return
    elseif command == "hide" then
        SetShown(false)
        return
    elseif command == "version" then
        Print("Version " .. ADDON_VERSION .. " for WoW 3.3.5a.")
        return
    elseif command == "status" then
        Print(
            tostring(DB.barCount) .. " bar(s). Bar 1: " .. tostring(DB.buttonCount) .. " buttons, " ..
            tostring(DB.columns) .. " columns, " .. tostring(DB.rows) .. " rows, size " ..
            tostring(DB.buttonSize) .. ", spacing " .. tostring(DB.spacingX) ..
            " horizontal / " .. tostring(DB.spacingY) .. " vertical."
        )
        Print(
            "Locked: " .. tostring(DB.locked) .. " (drag modifier: " .. GetBarLockKeyLabel() ..
            "), anchors: " .. tostring(DB.showAnchors) .. ", slot numbers: " .. tostring(DB.showSlotNumbers) .. ", autoassign: " ..
            tostring(DB.autoAssign) .. ", click fallback: " .. tostring(DB.clickFallback) ..
            ", normal spell/item cooldowns: " .. tostring(DB.nativeCooldowns) ..
            ", resource fade: " .. tostring(DB.resourceFade) ..
            ", Bagnon compatibility: " .. tostring(DB.bagnonCompatibility) .. "."
        )
        Print(
            "Cooldown messages: " .. tostring(DB.showMessages) .. ", ready messages: " ..
            tostring(DB.showReadyMessages) .. ", debug messages: " .. tostring(DB.debugMessages) ..
            ", minimap button: " .. tostring(DB.showMinimapButton) .. "."
        )
        Print(
            "Blizzard bar: " .. GetBlizzardBarModeText(DB.blizzardBarMode) ..
            ", hide gryphons: " .. tostring(DB.hideGryphons) .. "."
        )
        return
    elseif command == "config" or command == "options" then
        ShowConfigWindow()
        return
    elseif command == "profile" or command == "profiles" then
        local action = string.lower(args[2] or "")
        local value = ""
        if #args >= 3 then
            value = table.concat(args, " ", 3)
        end

        if action == "save" then
            SaveNamedProfile(value)
        elseif action == "load" then
            local savedName, record = FindNamedProfile(value)
            if not savedName then
                Print("Profile not found: " .. tostring(value))
            else
                RequestProfileApply(
                    GetRecordSnapshot(record),
                    "Profile '" .. savedName .. "'",
                    savedName
                )
            end
        elseif action == "delete" then
            DeleteNamedProfile(value)
        elseif action == "list" then
            local names = GetSortedProfileNames()
            if #names == 0 then
                Print("No named profiles have been saved.")
            else
                Print("Saved profiles: " .. table.concat(names, ", "))
            end
        elseif action == "characters" or action == "chars" then
            local names = GetSortedProfileNames()
            if #names == 0 then
                Print("No saved profiles are available yet.")
            else
                Print("Character layouts are unified with saved profiles: " .. table.concat(names, ", "))
            end
        elseif action == "copy" then
            local savedName, record = FindNamedProfile(value)
            if not savedName then
                Print("Profile not found: " .. tostring(value))
            else
                RequestProfileApply(GetRecordSnapshot(record), "Profile '" .. savedName .. "'")
            end
        else
            Print("Usage: /dmlcd profile save|load|delete|copy <name>")
            Print("       /dmlcd profile list")
        end
        return
    elseif command == "kb" or command == "keybind" then
        local action = string.lower(args[2] or "")
        if action == "save" then
            if keybindMode then
                FinishKeybindMode(true)
            else
                Print("Keybind mode is not active. Use /dmlcd kb first.")
            end
        elseif action == "cancel" or action == "close" then
            if keybindMode then
                FinishKeybindMode(false, "DML keybind changes canceled.")
            end
        elseif action == "" then
            StartKeybindMode()
        else
            Print("Usage: /dmlcd kb [save|cancel]")
        end
        return
    end

    if command == "lock" or command == "unlock" then
        if ConfigurationBlocked() then
            return
        end
        DB.locked = command == "lock"
        ApplyLockState()
        if DB.locked then
            Print("Bars locked.")
        elseif DB.showAnchors then
            Print("Bars unlocked. Drag each anchor to move its bar.")
        else
            Print("Bars unlocked. Anchors are hidden; enable Show anchors to move the bars.")
        end
        return
    end

    if command == "bars" or command == "barcount" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 1, MAX_BARS)
        if not value then
            Print("Usage: /dmlcd bars <1-5>")
            return
        end
        DB.barCount = math.floor(value)
        LayoutButtons()
        SetShown(DB.shown)
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Number of DML bars set to " .. tostring(DB.barCount) .. ".")
        return
    end

    if command == "layout" then
        if ConfigurationBlocked() then
            return
        end

        local buttonCount = Clamp(args[2], 1, MAX_BUTTONS)
        local rows = Clamp(args[3], 1, MAX_BUTTONS)
        local columns = Clamp(args[4], 1, MAX_BUTTONS)

        if not buttonCount or not rows or not columns then
            Print("Usage: /dmlcd layout <buttons> <rows> <columns>")
            Print("Example: /dmlcd layout 12 1 12")
            return
        end

        buttonCount = math.floor(buttonCount)
        rows = math.floor(rows)
        columns = math.floor(columns)

        local cells = rows * columns
        if cells < buttonCount then
            Print("That grid only has " .. tostring(cells) .. " slots for " .. tostring(buttonCount) .. " buttons.")
            return
        elseif cells > MAX_BUTTONS then
            Print("A layout may contain no more than " .. tostring(MAX_BUTTONS) .. " total grid slots.")
            return
        end

        DB.buttonCount = buttonCount
        DB.rows = rows
        DB.columns = columns
        LayoutButtons()
        PrintLayoutStatus()
        return
    elseif command == "grid" then
        if ConfigurationBlocked() then
            return
        end

        local rows = Clamp(args[2], 1, MAX_BUTTONS)
        local columns = Clamp(args[3], 1, MAX_BUTTONS)
        if not rows or not columns then
            Print("Usage: /dmlcd grid <rows> <columns>")
            Print("Example: /dmlcd grid 1 12")
            return
        end

        rows = math.floor(rows)
        columns = math.floor(columns)
        local cells = rows * columns
        if cells > MAX_BUTTONS then
            Print("A grid may contain no more than " .. tostring(MAX_BUTTONS) .. " buttons.")
            return
        end

        DB.buttonCount = cells
        DB.rows = rows
        DB.columns = columns
        LayoutButtons()
        PrintLayoutStatus()
        return
    end

    if command == "buttons" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 1, MAX_BUTTONS)
        if not value then
            Print("Usage: /dmlcd buttons <1-48>")
            return
        end
        DB.buttonCount = math.floor(value)
        DB.columns = math.min(DB.columns, DB.buttonCount)
        DB.rows = math.ceil(DB.buttonCount / DB.columns)
        LayoutButtons()
        PrintLayoutStatus()
        return
    elseif command == "columns" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 1, MAX_BUTTONS)
        if not value then
            Print("Usage: /dmlcd columns <number>")
            return
        end
        DB.columns = math.min(math.floor(value), DB.buttonCount)
        DB.rows = math.ceil(DB.buttonCount / DB.columns)
        LayoutButtons()
        PrintLayoutStatus()
        return
    elseif command == "rows" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 1, MAX_BUTTONS)
        if not value then
            Print("Usage: /dmlcd rows <number>")
            return
        end
        DB.rows = math.min(math.floor(value), DB.buttonCount)
        DB.columns = math.ceil(DB.buttonCount / DB.rows)
        LayoutButtons()
        PrintLayoutStatus()
        return
    elseif command == "size" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 24, 64)
        if not value then
            Print("Usage: /dmlcd size <24-64>")
            return
        end
        DB.buttonSize = math.floor(value)
        LayoutButtons()
        Print("Button size set to " .. tostring(DB.buttonSize) .. " pixels.")
        return
    elseif command == "spacing" then
        if ConfigurationBlocked() then
            return
        end
        local horizontal = Clamp(args[2], 0, 40)
        local vertical = args[3] and Clamp(args[3], 0, 40) or horizontal
        if not horizontal or not vertical then
            Print("Usage: /dmlcd spacing <horizontal 0-40> [vertical 0-40]")
            return
        end
        DB.spacingX = math.floor(horizontal)
        DB.spacingY = math.floor(vertical)
        LayoutButtons()
        Print("Button gaps set to " .. tostring(DB.spacingX) .. " horizontal / " .. tostring(DB.spacingY) .. " vertical pixels. Zero means borders touch.")
        return
    elseif command == "hspacing" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 0, 40)
        if not value then
            Print("Usage: /dmlcd hspacing <0-40>")
            return
        end
        DB.spacingX = math.floor(value)
        LayoutButtons()
        Print("Horizontal spacing set to " .. tostring(DB.spacingX) .. " pixels.")
        return
    elseif command == "vspacing" then
        if ConfigurationBlocked() then
            return
        end
        local value = Clamp(args[2], 0, 40)
        if not value then
            Print("Usage: /dmlcd vspacing <0-40>")
            return
        end
        DB.spacingY = math.floor(value)
        LayoutButtons()
        Print("Vertical spacing set to " .. tostring(DB.spacingY) .. " pixels.")
        return
    elseif command == "background" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd background on|off")
            return
        end
        DB.background = value
        ApplyBackground()
        Print("Bar backgrounds " .. (value and "enabled." or "disabled."))
        return
    elseif command == "slotnumbers" or command == "showslotnumbers" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd slotnumbers on|off")
            return
        end
        DB.showSlotNumbers = value
        RefreshAllButtons()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Slot numbers " .. (value and "shown." or "hidden."))
        return
    elseif command == "barlockkey" or command == "dragmodifier" then
        local value = string.upper(tostring(args[2] or ""))
        if value == "CONTROL" then
            value = "CTRL"
        end
        if value ~= "SHIFT" and value ~= "CTRL" and value ~= "ALT" and value ~= "NONE" then
            Print("Usage: /dmlcd barlockkey shift|ctrl|alt|none")
            return
        end
        DB.barLockKey = value
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Locked-bar drag modifier set to " .. GetBarLockKeyLabel() .. ".")
        return
    elseif command == "minimap" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd minimap on|off")
            return
        end
        DB.showMinimapButton = value
        UpdateMinimapButtonVisibility()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Minimap button " .. (value and "shown." or "hidden."))
        return
    elseif command == "blizzardbar" or command == "blizzbar" then
        if ConfigurationBlocked() then
            return
        end
        local value = NormalizeBlizzardBarMode(args[2])
        if not value then
            Print("Usage: /dmlcd blizzardbar show|all|action|background")
            return
        end
        local changed = DB.blizzardBarMode ~= value
        DB.blizzardBarMode = value
        ApplyBlizzardBarSettings()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Blizzard bar set to: " .. GetBlizzardBarModeText(value) .. ".")
        if changed and value ~= "SHOW" then
            PrintBlizzardBarWarning()
        end
        return
    elseif command == "hidegryphons" or command == "gryphons" then
        if ConfigurationBlocked() then
            return
        end
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd hidegryphons on|off")
            return
        end
        DB.hideGryphons = value
        ApplyBlizzardBarSettings()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Blizzard gryphons " .. (value and "hidden." or "shown when allowed by the selected Blizzard bar mode."))
        return
    elseif command == "anchors" or command == "showanchors" then
        if ConfigurationBlocked() then
            return
        end
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd anchors on|off")
            return
        end
        DB.showAnchors = value
        ApplyLockState()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        SaveCharacterLayoutSnapshot()
        Print("DML bar anchors " .. (value and "shown." or "hidden. Bars remain unlocked if Lock bars is disabled."))
        return
    elseif command == "assign" then
        local slotIndex = tonumber(args[2])
        if not slotIndex or not args[3] then
            Print("Usage: /dmlcd assign <slot> <spellId> [fallbackSeconds]")
            return
        end
        AssignButton(GlobalIndex(1, slotIndex), args[3], args[4] or 0, nil, false)
        return
    elseif command == "assignbar" then
        local barIndex = tonumber(args[2])
        local slotIndex = tonumber(args[3])
        if not barIndex or not slotIndex or not args[4] then
            Print("Usage: /dmlcd assignbar <bar 1-5> <slot> <spellId> [fallbackSeconds]")
            return
        end
        AssignButton(GlobalIndex(barIndex, slotIndex), args[4], args[5] or 0, nil, false)
        return
    elseif command == "assignitem" then
        if ConfigurationBlocked() then
            return
        end
        local slotIndex = tonumber(args[2])
        if not slotIndex or not args[3] then
            Print("Usage: /dmlcd assignitem <slot> <itemId>")
            return
        end
        AssignItemButton(GlobalIndex(1, slotIndex), args[3], nil, false)
        return
    elseif command == "assignitembar" then
        if ConfigurationBlocked() then
            return
        end
        local barIndex = tonumber(args[2])
        local slotIndex = tonumber(args[3])
        if not barIndex or not slotIndex or not args[4] then
            Print("Usage: /dmlcd assignitembar <bar 1-5> <slot> <itemId>")
            return
        end
        AssignItemButton(GlobalIndex(barIndex, slotIndex), args[4], nil, false)
        return
    elseif command == "clear" then
        if ConfigurationBlocked() then
            return
        end
        local slotIndex = tonumber(args[2])
        if not slotIndex then
            Print("Usage: /dmlcd clear <slot>")
            return
        end
        ClearAssignment(GlobalIndex(1, slotIndex), false)
        return
    elseif command == "clearbar" then
        if ConfigurationBlocked() then
            return
        end
        local barIndex = tonumber(args[2])
        local slotIndex = tonumber(args[3])
        if not barIndex or not slotIndex then
            Print("Usage: /dmlcd clearbar <bar 1-5> <slot>")
            return
        end
        ClearAssignment(GlobalIndex(barIndex, slotIndex), false)
        return
    elseif command == "clearall" then
        if ConfigurationBlocked() then
            return
        end
        DB.assignments = {}
        DB.stanceBarAssignments = {}
        pendingFallbacks = {}
        RefreshAllButtons()
        Print("All button assignments cleared.")
        return
    elseif command == "autoassign" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd autoassign on|off")
            return
        end
        DB.autoAssign = value
        Print("Auto-assign learned spells " .. (value and "enabled." or "disabled."))
        return
    elseif command == "messages" or command == "cooldownmessages" or command == "showmessages" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd messages on|off")
            return
        end
        DB.showMessages = value
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Cooldown messages " .. (value and "enabled." or "disabled."))
        return
    elseif command == "readymessages" or command == "showreadymessages" or command == "readytext" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd readymessages on|off")
            return
        end
        DB.showReadyMessages = value
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Spell ready messages " .. (value and "enabled." or "disabled."))
        return
    elseif command == "debug" or command == "debugmessages" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd debug on|off")
            return
        end
        DB.debugMessages = value
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Addon debug messages " .. (value and "enabled." or "disabled."))
        return
    elseif command == "resourcefade" or command == "powerfade" or command == "manafade" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd resourcefade on|off")
            return
        end
        DB.resourceFade = value
        DMLCD.RefreshResourceVisuals()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        SaveCharacterLayoutSnapshot()
        Print("Low-resource spell fading " .. (value and "enabled." or "disabled."))
        return
    elseif command == "bagnon" or command == "bagnoncompatibility" or command == "bagicons" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd bagnon on|off")
            return
        end
        DB.bagnonCompatibility = value
        if DMLCD.RefreshBagnonIcons then
            DMLCD.RefreshBagnonIcons()
        end
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        SaveCharacterLayoutSnapshot()
        Print("Bagnon custom-item icon compatibility " .. (value and "enabled." or "disabled."))
        return
    elseif command == "clickfallback" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd clickfallback on|off")
            return
        end
        DB.clickFallback = value
        Print("Click fallback " .. (value and "enabled." or "disabled."))
        return
    elseif command == "nativecooldowns" or command == "normalcooldowns" then
        local value = ParseOnOff(args[2])
        if value == nil then
            Print("Usage: /dmlcd nativecooldowns on|off")
            return
        end
        DB.nativeCooldowns = value
        ForEachActiveButton(function(_, button)
            if button then
                UpdateButtonCooldownVisual(button, true)
            end
        end)
        Print("Normal spell/item cooldown display " .. (value and "enabled." or "disabled."))
        return
    elseif command == "fallbackdelay" then
        local value = Clamp(args[2], 0, 5)
        if not value then
            Print("Usage: /dmlcd fallbackdelay <0-5>")
            return
        end
        DB.fallbackDelay = value
        Print("Fallback delay set to " .. tostring(value) .. " seconds.")
        return
    elseif command == "testlearn" then
        local spellId = tonumber(args[2])
        if not spellId then
            Print("Usage: /dmlcd testlearn <spellId>")
            return
        end
        local spell = ResolveSpell(spellId, nil)
        local name = spell and spell.name or ("Spell " .. tostring(spellId))
        AutoAssignLearnedSpell(spellId, name)
        return
    elseif command == "testmeta" then
        local spellId = tonumber(args[2])
        local rank = args[3]
        if not spellId or not rank then
            Print("Usage: /dmlcd testmeta <spellId> <rank> [custom text]")
            return
        end
        local text = #args >= 4 and table.concat(args, " ", 4) or ""
        local spell = ResolveSpell(spellId, nil)
        DMLCD.StoreSpellMetadata(spellId, spell and spell.name or ("Spell " .. tostring(spellId)), rank, text, spell and spell.family)
        DMLCD.RefreshSpellAssignment(spellId)
        Print("Stored test metadata for spell " .. tostring(spellId) .. ".")
        return
    elseif command == "teststart" then
        local spellId = tonumber(args[2])
        local seconds = tonumber(args[3])
        local token = args[4] or "TEST1"
        if not spellId or not seconds or seconds <= 0 then
            Print("Usage: /dmlcd teststart <spellId> <seconds> [token]")
            return
        end
        local spell = ResolveSpell(spellId, nil)
        local name = spell and spell.name or ("Spell " .. tostring(spellId))
        DMLCD:ParseProtocolMessage(
            "DMLCD|START|" .. tostring(spellId) .. "|" .. tostring(math.floor(seconds * 1000)) .. "|" .. tostring(token) .. "|" .. name
        )
        return
    elseif command == "testready" then
        local spellId = tonumber(args[2])
        if not spellId then
            Print("Usage: /dmlcd testready <spellId> [token]")
            return
        end
        local state = GetCooldownState(spellId)
        local token = args[3] or (state and state.token) or "TEST1"
        local spell = ResolveSpell(spellId, nil)
        local name = spell and spell.name or ("Spell " .. tostring(spellId))
        DMLCD:ParseProtocolMessage(
            "DMLCD|READY|" .. tostring(spellId) .. "|0|" .. tostring(token) .. "|" .. name
        )
        return
    elseif command == "reset" then
        if ConfigurationBlocked() then
            return
        end
        CopyDefaults(true)
        pendingFallbacks = {}
        RestoreAllPositions()
        if DMLCD.RestorePetBarPosition then
            DMLCD.RestorePetBarPosition()
        end
        if DMLCD.RestoreAuraBarPosition then
            DMLCD.RestoreAuraBarPosition()
        end
        LayoutButtons()
        SetShown(DB.shown)
        ApplySavedKeybinds()
        UpdateMinimapButtonVisibility()
        ApplyBlizzardBarSettings()
        if RefreshConfigFields then
            RefreshConfigFields()
        end
        Print("Settings reset to defaults.")
        return
    end

    Print("Unknown command. Use /dmlcd help.")
end

local function RegisterSlashCommands()
    SLASH_DMLCOOLDOWNBAR1 = "/dmlcd"
    SlashCmdList["DMLCOOLDOWNBAR"] = HandleSlash
end

local function FinishInitialize()
    InitializeGlobalDB()
    CopyDefaults(false)
    DMLCD.InstallCompanionPickupHook()
    RestoreCooldowns()
    EnsureBars()
    CreateUpdateFrame()
    CreateKeybindFrames()
    CreateConfigFrame()
    CreateMinimapButton()
    RestoreAllPositions()
    LayoutButtons()
    SetShown(DB.shown)
    ApplySavedKeybinds()
    ApplyBlizzardBarSettings()
    InstallChatFilter()
    SaveCharacterLayoutSnapshot()
    local defaultProfileName = EnsureDefaultCharacterProfile()
    if RefreshProfileControls then
        RefreshProfileControls(defaultProfileName, nil)
    end
end

local function Initialize()
    if initialized then
        return
    end

    -- Register this first. If a client-specific UI call fails later, /dmlcd
    -- still exists and the error is visible instead of leaving a dead frame.
    RegisterSlashCommands()

    local ok, errorMessage = pcall(FinishInitialize)
    if not ok then
        Print("Initialization error: " .. tostring(errorMessage))
        Print("Use /console scriptErrors 1, then /reload, if the full error window is hidden.")
        return
    end

    initialized = true
    DebugPrint("Version " .. ADDON_VERSION .. " loaded. Use /dmlcd help.")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("UPDATE_MACROS")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
eventFrame:RegisterEvent("UNIT_MANA")
eventFrame:RegisterEvent("UNIT_RAGE")
eventFrame:RegisterEvent("UNIT_ENERGY")
eventFrame:RegisterEvent("UNIT_RUNIC_POWER")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("COMPANION_UPDATE")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_SHOWGRID")
eventFrame:RegisterEvent("ACTIONBAR_HIDEGRID")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PET_BAR_UPDATE")
eventFrame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("PET_BAR_SHOWGRID")
eventFrame:RegisterEvent("PET_BAR_HIDEGRID")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
eventFrame:RegisterEvent("PLAYER_CONTROL_LOST")
eventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
eventFrame:RegisterEvent("PLAYER_FARSIGHT_FOCUS_CHANGED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            Initialize()
        end
        return
    end

    if not initialized then
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        local message = ...
        DMLCD:ParseProtocolMessage(message)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ForEachActiveButton(function(_, button)
            UpdateCombatDropOverlay(button)
        end)
        if pendingSecureRefresh then
            pendingSecureRefresh = false
            pendingCombatAssignments = {}
            RefreshAllButtons()
        end
        ProcessPendingLearnedSpells()
        if pendingBindingRefresh then
            ApplySavedKeybinds()
        end
        if pendingBlizzardBarRefresh then
            ApplyBlizzardBarSettings()
        end
        if DMLCD.pendingAuraBarRefresh then
            DMLCD.ApplyAuraBarSettings()
        end
        if DMLCD.pendingPetBarRefresh then
            DMLCD.ApplyPetBarSettings()
        end
        if pendingProfileApply then
            local queued = pendingProfileApply
            pendingProfileApply = nil
            ApplyProfileSnapshotNow(queued.data, queued.label, queued.profileNameAfterLoad)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if keybindMode then
            FinishKeybindMode(false, "DML keybind mode canceled because combat started.")
        end
        ForEachActiveButton(function(_, button)
            UpdateCombatDropOverlay(button)
        end)
    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "ACTIONBAR_SHOWGRID" or
        event == "ACTIONBAR_HIDEGRID" or event == "UPDATE_BONUS_ACTIONBAR" or
        event == "UPDATE_SHAPESHIFT_FORMS" or event == "UPDATE_SHAPESHIFT_FORM"
    then
        ScheduleBlizzardBarRefresh(0.05)
        DMLCD.ScheduleBarOneStanceRefresh(0.05)
        if DMLCD.RefreshAuraBar then
            DMLCD.RefreshAuraBar(not IsInCombat())
        end
    elseif event == "PET_BAR_UPDATE" or event == "PET_BAR_UPDATE_COOLDOWN" or
        event == "PET_BAR_SHOWGRID" or event == "PET_BAR_HIDEGRID" or
        event == "ACTIONBAR_UPDATE_STATE" or event == "PLAYER_CONTROL_LOST" or
        event == "PLAYER_CONTROL_GAINED" or event == "PLAYER_FARSIGHT_FOCUS_CHANGED" or
        event == "UPDATE_BINDINGS"
    then
        DMLCD.RefreshPetBar()
        if DMLCD.RefreshAuraBar then
            DMLCD.RefreshAuraBar(not IsInCombat())
        end
        ScheduleBlizzardBarRefresh(0.05)
        if not RegisterStateDriver then
            DMLCD.ApplyPetBarSettings()
        end
    elseif event == "UNIT_PET" or event == "UNIT_FLAGS" or event == "UNIT_AURA" then
        local unit = ...
        if not unit or unit == "player" or unit == "pet" then
            DMLCD.RefreshPetBar()
            ScheduleBlizzardBarRefresh(0.05)
            if not RegisterStateDriver then
                DMLCD.ApplyPetBarSettings()
            end
        end
    elseif event == "COMPANION_UPDATE" then
        local companionType = ...
        DMLCD.RefreshCompanionAssignments(companionType)
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        HandleSpellbookChanged()
        RefreshAllButtons()
    elseif event == "UPDATE_MACROS" then
        RefreshAllButtons()
    elseif event == "BAG_UPDATE" then
        -- Bag changes affect item assignments only. Successful item data remains
        -- cached; unresolved entries retry no more than once every five seconds.
        DMLCD.RefreshItemAssignmentButtons()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemId, success = ...
        DMLCD.HandleItemInfoReceived(itemId, success)
    elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "UNIT_MANA" or event == "UNIT_RAGE" or
        event == "UNIT_ENERGY" or event == "UNIT_RUNIC_POWER" or event == "UNIT_DISPLAYPOWER"
    then
        local unit = ...
        if not unit or unit == "player" then
            DMLCD.RefreshResourceVisuals()
        end
        DMLCD.RefreshPetBar()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        ForEachActiveButton(function(_, button)
            if button then
                UpdateButtonCooldownVisual(button, true)
            end
        end)
        DMLCD.RefreshPetBar()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not spellbookSnapshotReady then
            PrimeSpellbookSnapshot()
        end
        RefreshAllButtons()
        ApplySavedKeybinds()
        DMLCD.ApplyPetBarSettings()
        DMLCD.RefreshPetBar()
        ScheduleBlizzardBarRefresh(0.1)
        SaveCharacterLayoutSnapshot()
    elseif event == "PLAYER_LOGOUT" then
        SaveAllPositions()
        SaveCharacterLayoutSnapshot()
    end
end)
