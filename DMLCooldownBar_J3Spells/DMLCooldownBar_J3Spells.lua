-- DML Cooldown Bar - optional J3Spells/ALE integration
-- World of Warcraft 3.3.5a / Interface 30300
--
-- This addon is optional. DMLCooldownBar works normally without it.
-- When enabled from DML configuration, native Blizzard cooldowns remain the
-- baseline. J3/ALE timers override only spells for which the server sends a
-- DMLCD timer, while metadata marked server_confirmed_cooldown waits for J3.

if type(DMLCooldownBar) ~= "table" then
    return
end

local DMLCD = DMLCooldownBar
local J3 = {
    name = "J3Spells",
    enabled = false,
    cooldowns = {},
    spellMetadata = {},
    scalingBonusDamage = {},
    scalingManaCost = {},
    pendingFallbacks = {},
    chatFilterInstalled = false
}

local CHAT_PREFIX = "DMLCD|"
local PRINT_PREFIX = "|cff66ff99DML Cooldown Bar J3|r: "

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(PRINT_PREFIX .. tostring(message))
    end
end

local function GetDB()
    return DMLCD.GetDB and DMLCD.GetDB() or DMLCooldownBarDB
end

local function EnsureState()
    local db = GetDB()
    if not db then
        return nil
    end

    db.j3Cooldowns = type(db.j3Cooldowns) == "table" and db.j3Cooldowns or {}
    db.j3SpellMetadata = type(db.j3SpellMetadata) == "table" and db.j3SpellMetadata or {}
    db.j3Settings = type(db.j3Settings) == "table" and db.j3Settings or {}

    if db.j3Settings.clickFallback == nil then
        db.j3Settings.clickFallback = true
    end
    if db.j3Settings.fallbackDelay == nil then
        db.j3Settings.fallbackDelay = 0.75
    end
    if db.j3Settings.showMessages == nil then
        db.j3Settings.showMessages = false
    end
    if db.j3Settings.showReadyMessages == nil then
        db.j3Settings.showReadyMessages = false
    end

    J3.cooldowns = db.j3Cooldowns
    J3.spellMetadata = db.j3SpellMetadata
    return db
end

local function GetCooldownKey(spellId)
    return tostring(tonumber(spellId) or spellId)
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

local function GetSpellName(spellId, suppliedName)
    local metadata = J3:GetSpellMetadata(spellId)
    if metadata and metadata.name then
        return metadata.name
    end
    local clientName = GetSpellInfo and GetSpellInfo(tonumber(spellId))
    return clientName or suppliedName or ("Spell " .. tostring(spellId))
end

function J3:GetSpellMetadata(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end
    EnsureState()
    return self.spellMetadata[tostring(spellId)] or self.spellMetadata[spellId]
end

function J3:HasOtherSpellInFamily(spellId, family)
    if not family or family == "" then
        return false
    end
    EnsureState()
    local otherId, metadata
    for otherId, metadata in pairs(self.spellMetadata) do
        if tonumber(otherId) ~= tonumber(spellId) and type(metadata) == "table" and
            metadata.family == family
        then
            return true
        end
    end
    return false
end

function J3:StoreSpellMetadata(spellId, spellName, rank, customText, family)
    spellId = tonumber(spellId)
    if not spellId then
        return false
    end
    EnsureState()

    local key = tostring(spellId)
    local metadata = self.spellMetadata[key] or {}
    if spellName and spellName ~= "" then metadata.name = spellName end
    if rank and rank ~= "" then metadata.rank = tonumber(rank) or rank end
    if customText and customText ~= "" then metadata.custom_text = customText end
    if family and family ~= "" then metadata.family = family end
    self.spellMetadata[key] = metadata
    return true
end

function J3:GetSpellBonusDamage(spellId)
    return tonumber(self.scalingBonusDamage[tonumber(spellId)]) or 0
end

function J3:GetSpellScalingManaCost(spellId)
    return tonumber(self.scalingManaCost[tonumber(spellId)]) or 0
end

function J3:StoreSpellBonusDamage(spellId, value)
    spellId = tonumber(spellId)
    value = tonumber(value)
    if not spellId or not value then return false end
    if value > 0 then
        self.scalingBonusDamage[spellId] = math.floor(value + 0.5)
    else
        self.scalingBonusDamage[spellId] = nil
    end
    return true
end

function J3:StoreSpellScalingManaCost(spellId, value)
    spellId = tonumber(spellId)
    value = tonumber(value)
    if not spellId or not value then return false end
    if value > 0 then
        self.scalingManaCost[spellId] = math.floor(value + 0.5)
    else
        self.scalingManaCost[spellId] = nil
    end
    return true
end

function J3:StartCooldown(spellId, durationSeconds, token, spellName, source)
    spellId = tonumber(spellId)
    durationSeconds = tonumber(durationSeconds)
    if not spellId or not durationSeconds or durationSeconds <= 0 then
        return false
    end
    EnsureState()

    local nowMono = GetTime()
    local nowWall = time()
    local state = {
        spellId = spellId,
        spellName = spellName,
        duration = durationSeconds,
        token = tostring(token or ""),
        source = source or "J3Spells ALE",
        startedAt = nowWall,
        expiresAt = nowWall + math.ceil(durationSeconds),
        startMono = nowMono,
        sessionExpires = nowMono + durationSeconds,
        enable = 1
    }
    self.cooldowns[GetCooldownKey(spellId)] = state

    if DMLCD.RememberIntegrationCooldownDuration then
        DMLCD.RememberIntegrationCooldownDuration(spellId, durationSeconds)
    end
    if DMLCD.RefreshSpellAssignment then
        DMLCD.RefreshSpellAssignment(spellId)
    end

    local db = GetDB()
    if db and db.j3Settings and db.j3Settings.showMessages then
        Print(GetSpellName(spellId, spellName) .. " cooldown started.")
    end
    return true
end

function J3:ClearCooldown(spellId, announce, suppliedName)
    spellId = tonumber(spellId)
    if not spellId then return false end
    EnsureState()
    local key = GetCooldownKey(spellId)
    local oldState = self.cooldowns[key]
    self.cooldowns[key] = nil

    if DMLCD.RefreshSpellAssignment then
        DMLCD.RefreshSpellAssignment(spellId)
    end

    local db = GetDB()
    if announce and db and db.j3Settings and db.j3Settings.showReadyMessages then
        Print(GetSpellName(spellId, suppliedName or (oldState and oldState.spellName)) .. " is ready.")
    end
    return oldState ~= nil
end

function J3:GetCooldownState(assignment)
    if not self.enabled or type(assignment) ~= "table" then
        return nil
    end
    local kind = assignment.kind or (assignment.itemId and "item") or "spell"
    if kind ~= "spell" then
        return nil
    end
    EnsureState()
    local state = self.cooldowns[GetCooldownKey(assignment.spellId)]
    if state and GetRemaining(state) > 0 then
        return state
    end
    return nil
end

function J3.SplitProtocolFields(message)
    local fields = {}
    local startAt = 1
    while true do
        local separator = string.find(message, "|", startAt, true)
        if not separator then
            fields[#fields + 1] = string.sub(message, startAt)
            break
        end
        fields[#fields + 1] = string.sub(message, startAt, separator - 1)
        startAt = separator + 1
    end
    return fields
end

function J3:ParseProtocolMessage(message)
    if not self.enabled or type(message) ~= "string" or
        string.sub(message, 1, string.len(CHAT_PREFIX)) ~= CHAT_PREFIX
    then
        return false
    end

    local fields = J3.SplitProtocolFields(message)
    local action = fields[2]
    local spellId = tonumber(fields[3])
    local cooldownMs = tonumber(fields[4])
    local token = fields[5]
    local spellName = fields[6] or ""
    local rank = fields[7]
    local customText = fields[8]
    local family = fields[9]

    if not action then return true end

    if action == "START" then
        self:StoreSpellMetadata(spellId, spellName, rank, customText, family)
        if cooldownMs and cooldownMs > 0 then
            self:StartCooldown(spellId, cooldownMs / 1000, token, spellName, "J3Spells ALE")
        end
        self.pendingFallbacks[spellId] = nil
    elseif action == "READY" then
        self:StoreSpellMetadata(spellId, spellName, rank, customText, family)
        local state = self.cooldowns[GetCooldownKey(spellId)]
        if state and tostring(state.token or "") == tostring(token or "") then
            self:ClearCooldown(spellId, true, spellName)
        end
    elseif action == "COOLDOWN" then
        if cooldownMs and cooldownMs > 0 then
            self:StartCooldown(spellId, cooldownMs / 1000, "lua-managed", spellName, "J3Spells Lua")
        else
            self:ClearCooldown(spellId, false, spellName)
        end
    elseif action == "RESET" then
        self:ClearCooldown(spellId, false, spellName)
    elseif action == "LEARN" then
        self:StoreSpellMetadata(spellId, spellName, rank, customText, family)
        if DMLCD.RefreshSpellAssignment then DMLCD.RefreshSpellAssignment(spellId) end
        if DMLCD.AutoAssignLearnedSpell then
            DMLCD.AutoAssignLearnedSpell(spellId, spellName)
        end
    elseif action == "META" then
        self:StoreSpellMetadata(spellId, spellName, rank, customText, family)
        if DMLCD.RefreshSpellAssignment then DMLCD.RefreshSpellAssignment(spellId) end
    elseif action == "BONUS" then
        if self:StoreSpellBonusDamage(spellId, cooldownMs) and DMLCD.RefreshSpellAssignment then
            DMLCD.RefreshSpellAssignment(spellId)
        end
    elseif action == "MANA" then
        if self:StoreSpellScalingManaCost(spellId, cooldownMs) and DMLCD.RefreshSpellAssignment then
            DMLCD.RefreshSpellAssignment(spellId)
        end
    end

    return true
end

local function ChatMessageFilter(_, _, message)
    return J3.enabled and type(message) == "string" and
        string.sub(message, 1, string.len(CHAT_PREFIX)) == CHAT_PREFIX or false
end

J3.eventFrame = CreateFrame("Frame")
J3.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_SYSTEM" and J3.enabled then
        J3:ParseProtocolMessage(...)
    end
end)

function J3:InstallChatFilter()
    if self.chatFilterInstalled then return end
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatMessageFilter)
        self.chatFilterInstalled = true
    end
end

function J3:RemoveChatFilter()
    if not self.chatFilterInstalled then return end
    if ChatFrame_RemoveMessageEventFilter then
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", ChatMessageFilter)
    end
    self.chatFilterInstalled = false
end

function J3:RestoreCooldowns()
    EnsureState()
    local nowMono = GetTime()
    local nowWall = time()
    local key, state
    for key, state in pairs(self.cooldowns) do
        if type(state) ~= "table" or not state.spellId or not state.expiresAt then
            self.cooldowns[key] = nil
        else
            local remaining = tonumber(state.expiresAt) - nowWall
            if remaining <= 0 then
                self.cooldowns[key] = nil
            else
                state.sessionExpires = nowMono + remaining
                state.startMono = nowMono
                state.duration = math.max(remaining, tonumber(state.duration) or remaining)
                state.enable = 1
            end
        end
    end
end

function J3:Enable()
    if self.enabled then return end
    EnsureState()
    self.enabled = true
    self:RestoreCooldowns()
    self.eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    self:InstallChatFilter()
    if DMLCD.RefreshAllButtons then DMLCD.RefreshAllButtons() end
end

function J3:Disable()
    if not self.enabled then return end
    self.enabled = false
    self.eventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:RemoveChatFilter()
    self.pendingFallbacks = {}
    if DMLCD.RefreshAllButtons then DMLCD.RefreshAllButtons() end
end

function J3:OnButtonClick(button, assignment, mouseButton)
    if not self.enabled or not assignment then return end
    local kind = assignment.kind or (assignment.itemId and "item") or "spell"
    if kind ~= "spell" then return end

    local db = EnsureState()
    local settings = db and db.j3Settings
    if not settings or not settings.clickFallback then return end
    if DMLCD.IsServerConfirmedCooldownOnly and DMLCD.IsServerConfirmedCooldownOnly(assignment.spellId) then
        return
    end
    if self:GetCooldownState(assignment) then return end

    local fallback = tonumber(assignment.fallback) or 0
    if fallback <= 0 then return end
    self.pendingFallbacks[tonumber(assignment.spellId)] = {
        due = GetTime() + (tonumber(settings.fallbackDelay) or 0.75),
        duration = fallback,
        spellName = assignment.name
    }
end

function J3:OnUpdate(now)
    if not self.enabled then return end
    now = tonumber(now) or GetTime()

    local spellId, pending
    for spellId, pending in pairs(self.pendingFallbacks) do
        if now >= (tonumber(pending.due) or 0) then
            self.pendingFallbacks[spellId] = nil
            if not self.cooldowns[GetCooldownKey(spellId)] then
                self:StartCooldown(spellId, pending.duration, "fallback", pending.spellName, "J3 fallback")
            end
        end
    end

    local expired = {}
    local key, state
    for key, state in pairs(self.cooldowns) do
        if GetRemaining(state) <= 0 then
            expired[#expired + 1] = tonumber(state.spellId) or key
        end
    end
    local i
    for i = 1, #expired do
        self:ClearCooldown(expired[i], true, nil)
    end
end

-- Optional diagnostics/configuration for the integration itself. The main DML
-- checkbox controls whether this module is active.
SLASH_DMLCOOLDOWNBARJ3_1 = "/dmlj3"
SlashCmdList["DMLCOOLDOWNBARJ3"] = function(message)
    local command, value = string.match(tostring(message or ""), "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    local db = EnsureState()
    local settings = db and db.j3Settings

    if command == "messages" then
        settings.showMessages = value == "on" and true or false
        Print("Cooldown messages " .. (settings.showMessages and "enabled." or "disabled."))
    elseif command == "ready" then
        settings.showReadyMessages = value == "on" and true or false
        Print("Ready messages " .. (settings.showReadyMessages and "enabled." or "disabled."))
    elseif command == "fallback" then
        settings.clickFallback = value == "on" and true or false
        Print("Click fallback " .. (settings.clickFallback and "enabled." or "disabled."))
    elseif command == "delay" then
        local delay = tonumber(value)
        if delay and delay >= 0 and delay <= 5 then
            settings.fallbackDelay = delay
            Print("Fallback delay set to " .. tostring(delay) .. " seconds.")
        else
            Print("Usage: /dmlj3 delay <0-5>")
        end
    else
        Print("Status: " .. (J3.enabled and "enabled" or "disabled") ..
            ", fallback " .. (settings.clickFallback and "on" or "off") ..
            ", delay " .. tostring(settings.fallbackDelay) .. "s.")
        Print("Commands: /dmlj3 messages on|off, ready on|off, fallback on|off, delay <0-5>")
    end
end

DMLCooldownBar_J3Spells = J3
DMLCD.RegisterOptionalIntegration("J3Spells", J3)
