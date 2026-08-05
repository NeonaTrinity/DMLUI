-- DML Cooldown Bar - Bagnon custom item icon compatibility
-- World of Warcraft 3.3.5a
--
-- This compatibility layer changes only the first texture return value for a
-- mapped custom item. Every other value returned by the installed Bagnon build
-- is preserved exactly, including nil values and any version-specific extras.
-- Hooks are reversible when compatibility is disabled and never stack on top
-- of an already-installed DML wrapper.

local ADDON_NAME = "DMLCooldownBar"
local DMLCD = _G.DMLCooldownBar or {}
local hookStates = setmetatable({}, { __mode = "k" })
local iconByItemId = {}
local linkIconCache = {}
local linkIconCacheSize = 0
local MAX_LINK_ICON_CACHE = 512

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

local function ClearTable(tbl)
    local key
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function RebuildIconCache()
    ClearTable(iconByItemId)
    ClearTable(linkIconCache)
    linkIconCacheSize = 0

    if type(DMLCooldownBarCustomItems) ~= "table" then
        return
    end

    local itemId, definition
    for itemId, definition in pairs(DMLCooldownBarCustomItems) do
        local numericItemId = tonumber(itemId)
        if numericItemId and type(definition) == "table" then
            local icon = NormalizeIconPath(definition.icon)
            if icon then
                iconByItemId[numericItemId] = icon
            end
        end
    end
end

local function CompatibilityEnabled()
    if DMLCD and type(DMLCD.IsBagnonCompatibilityEnabled) == "function" then
        return DMLCD:IsBagnonCompatibilityEnabled()
    end

    if type(DMLCooldownBarDB) == "table" then
        return DMLCooldownBarDB.bagnonCompatibility ~= false
    end
    return true
end

local function GetCustomIconFromLink(link)
    if not CompatibilityEnabled() or type(link) ~= "string" or link == "" then
        return nil
    end

    local cached = linkIconCache[link]
    if cached ~= nil then
        return cached or nil
    end

    -- Keep the useful negative cache, but cap it so Bagnon_Forever, random
    -- properties, enchants, and newly seen items cannot grow DML forever.
    if linkIconCacheSize >= MAX_LINK_ICON_CACHE then
        ClearTable(linkIconCache)
        linkIconCacheSize = 0
    end

    local itemId = tonumber(string.match(link, "item:(%-?%d+)"))
    local icon = itemId and iconByItemId[itemId] or nil
    linkIconCache[link] = icon or false
    linkIconCacheSize = linkIconCacheSize + 1
    return icon
end

-- Preserve the upstream function's exact vararg return count without creating
-- a temporary table for every visible Bagnon slot refresh.
local function ReplaceFirstReturnWithCustomIcon(linkIndex, ...)
    local customTexture = GetCustomIconFromLink(select(linkIndex, ...))
    if customTexture then
        return customTexture, select(2, ...)
    end
    return ...
end

local function InstallClassHook(slotClass, linkIndex)
    if type(slotClass) ~= "table" then
        return false
    end

    local current = slotClass.GetItemSlotInfo
    if type(current) ~= "function" then
        return false
    end

    local state = hookStates[slotClass]
    if state and current == state.wrapper then
        state.installed = true
        return true
    end

    -- Another addon may have wrapped DML after installation. In that case our
    -- wrapper is already inside the call chain; adding another would stack it.
    if state and state.installed and current ~= state.wrapper then
        return true
    end

    local upstream = current
    local wrapper = function(self)
        return ReplaceFirstReturnWithCustomIcon(linkIndex, upstream(self))
    end

    hookStates[slotClass] = {
        upstream = upstream,
        wrapper = wrapper,
        linkIndex = linkIndex,
        installed = true
    }
    slotClass.GetItemSlotInfo = wrapper
    return true
end

local function UninstallClassHook(slotClass)
    local state = type(slotClass) == "table" and hookStates[slotClass] or nil
    if not state or not state.installed then
        return false
    end

    -- Restore only when DML still owns the method directly. If another addon
    -- wrapped it afterward, CompatibilityEnabled() makes our inner wrapper a
    -- transparent pass-through and avoids breaking that addon's hook chain.
    if slotClass.GetItemSlotInfo == state.wrapper then
        slotClass.GetItemSlotInfo = state.upstream
        state.installed = false
        return true
    end

    return false
end

local function InstallBagnonHooks()
    local bagnon = _G.Bagnon
    if type(bagnon) ~= "table" then
        return
    end

    -- Inventory, bank, keyring, and Bagnon_Forever cached-character slots.
    InstallClassHook(bagnon.ItemSlot, 7)

    -- Bagnon_GuildBank is load-on-demand and may appear later.
    InstallClassHook(bagnon.GuildItemSlot, 4)
end

local function UninstallBagnonHooks()
    local bagnon = _G.Bagnon
    if type(bagnon) ~= "table" then
        return
    end

    UninstallClassHook(bagnon.ItemSlot)
    UninstallClassHook(bagnon.GuildItemSlot)
end

local function SyncBagnonHooks()
    if CompatibilityEnabled() then
        InstallBagnonHooks()
    else
        UninstallBagnonHooks()
    end
end

local function RefreshItemFrame(itemFrame)
    if not itemFrame or type(itemFrame.GetAllItemSlots) ~= "function" then
        return
    end

    local _, slot
    for _, slot in itemFrame:GetAllItemSlots() do
        if slot and type(slot.Update) == "function" then
            slot:Update()
        end
    end
end

local function RefreshVisibleBagnonSlots()
    local bagnon = _G.Bagnon
    if type(bagnon) ~= "table" then
        return
    end

    -- Standard inventory/bank/keyring frames.
    local _, frame
    for _, frame in pairs(bagnon.frames or {}) do
        if frame and type(frame.GetItemFrame) == "function" then
            RefreshItemFrame(frame:GetItemFrame())
        end
    end

    -- Guild bank is created outside Bagnon's regular frame list.
    local guildFrame = _G.BagnonFrameguildbank
    if guildFrame and type(guildFrame.GetItemFrame) == "function" then
        RefreshItemFrame(guildFrame:GetItemFrame())
    end
end

DMLCD.RefreshBagnonIcons = function()
    SyncBagnonHooks()
    RefreshVisibleBagnonSlots()
end

DMLCD.RebuildBagnonIconCache = function()
    RebuildIconCache()
    DMLCD.RefreshBagnonIcons()
end

RebuildIconCache()
SyncBagnonHooks()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "Bagnon" or addonName == "Bagnon_GuildBank" or addonName == ADDON_NAME then
        SyncBagnonHooks()
    end
end)
