local _, SQOL = ...
local L = SQOL.L

------------------------------------------------------------
-- RepWatch: auto-switch watched reputation on rep gain
-- Uses C_Reputation APIs when available (TWW/11.0.2+), with legacy fallback.
------------------------------------------------------------
SQOL._repWatchPending = false
SQOL._repLastStanding = nil
SQOL._repApiWarned = false

local internalWatchChange = false
local memoryDB, observedID, observedName, observedValid
local returnTimer, returnPending, returnGeneration = nil, nil, 0
local pendingWatch
local queueReturn, cancelReturn
local standingFields = { "currentStanding", "earnedValue", "barValue", "currentValue", "currentReputation" }
local booleanFields = { "isHeader", "isCollapsed", "hasRep", "isWatched" }

local function usableNumber(value)
    return SQOL.CanUseValue(value) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

local function usableName(value)
    return SQOL.CanUseValue(value) and type(value) == "string" and value ~= ""
end

-- Never copy inaccessible fields into snapshots or use them as table keys.
local function safeFactionData(data)
    if not SQOL.CanUseValue(data) or type(data) ~= "table" then return nil end
    if type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, data)
        if not ok or not accessible then return nil end
    end
    local ok, result = pcall(function()
        local clean = {}
        if usableNumber(data.factionID) then clean.factionID = data.factionID end
        if usableName(data.name) then clean.name = data.name end
        for _, key in ipairs(standingFields) do
            if usableNumber(data[key]) then clean.currentStanding = data[key]; break end
        end
        for _, key in ipairs(booleanFields) do
            local value = data[key]
            if SQOL.CanUseValue(value) and type(value) == "boolean" then clean[key] = value end
        end
        return clean
    end)
    return ok and result or nil
end

local function SQOL_Rep_GetNumFactions()
    local query = C_Reputation and C_Reputation.GetNumFactions or rawget(_G, "GetNumFactions")
    if type(query) == "function" then
        local ok, count = pcall(query)
        if ok and usableNumber(count) and count >= 0 then return math.floor(count) end
    end
    return nil
end

local function SQOL_Rep_GetFactionDataByIndex(index)
    if C_Reputation and type(C_Reputation.GetFactionDataByIndex) == "function" then
        local ok, data = pcall(C_Reputation.GetFactionDataByIndex, index)
        if ok then return safeFactionData(data) end
        return nil
    end

    local legacy = rawget(_G, "GetFactionInfo")
    if type(legacy) == "function" then
        local ok, name, description, standingId, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar,
            isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = pcall(legacy, index)

        if not ok or not usableName(name) then
            return nil
        end

        return safeFactionData({
            factionID = factionID,
            name = name,
            description = description,
            reaction = standingId,
            currentReactionThreshold = bottomValue,
            nextReactionThreshold = topValue,
            -- For legacy APIs, "earnedValue" changes with rep gain and is stable for delta detection.
            currentStanding = earnedValue,
            atWarWith = atWarWith,
            canToggleAtWar = canToggleAtWar,
            isHeader = isHeader,
            isCollapsed = isCollapsed,
            hasRep = hasRep,
            isWatched = isWatched,
            isChild = isChild,
        })
    end

    return nil
end

local function SQOL_Rep_ExpandAllHeaders()
    if C_Reputation and type(C_Reputation.ExpandAllFactionHeaders) == "function" then
        SQOL.safe_pcall(C_Reputation.ExpandAllFactionHeaders)
        return true
    end

    local legacy = rawget(_G, "ExpandFactionHeader")
    if type(legacy) ~= "function" then
        return false
    end

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return false
    end

    local i = 1
    while i <= num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and data.isHeader and data.isCollapsed then
            SQOL.safe_pcall(legacy, i)
            local updated = SQOL_Rep_GetNumFactions()
            if type(updated) == "number" then
                num = updated
            end
        end
        i = i + 1
    end

    return true
end

local function SQOL_Rep_CollapseHeader(index)
    if C_Reputation and type(C_Reputation.CollapseFactionHeader) == "function" then
        return SQOL.safe_pcall(C_Reputation.CollapseFactionHeader, index)
    end

    local legacy = rawget(_G, "CollapseFactionHeader")
    if type(legacy) == "function" then
        return SQOL.safe_pcall(legacy, index)
    end

    return false
end

local function SQOL_Rep_SnapshotCollapsedHeaders()
    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return nil
    end

    local counts = {}
    local collapsed = {}
    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and data.isHeader and type(data.name) == "string" and data.name ~= "" then
            counts[data.name] = (counts[data.name] or 0) + 1
            if data.isCollapsed then
                local key = data.name .. "|" .. counts[data.name]
                collapsed[key] = true
            end
        end
    end

    return collapsed
end

local function SQOL_Rep_RestoreCollapsedHeaders(collapsed)
    if type(collapsed) ~= "table" then
        return
    end

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return
    end

    local counts = {}
    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and data.isHeader and type(data.name) == "string" and data.name ~= "" then
            counts[data.name] = (counts[data.name] or 0) + 1
            local key = data.name .. "|" .. counts[data.name]
            if collapsed[key] then
                SQOL_Rep_CollapseHeader(i)
            end
        end
    end
end

local function SQOL_Rep_WithExpandedHeaders(fn)
    if type(fn) ~= "function" then
        return nil
    end

    local collapsed = SQOL_Rep_SnapshotCollapsedHeaders()
    SQOL_Rep_ExpandAllHeaders()

    local ok, result = pcall(fn)

    if collapsed then
        SQOL_Rep_RestoreCollapsedHeaders(collapsed)
    end

    if not ok then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("RepWatch -> header expand error:", result)
        end
        return nil
    end

    return result
end

local function SQOL_Rep_WithLegacyShown(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local query = C_Reputation and (C_Reputation.AreLegacyReputationsShown or C_Reputation.AreLegacyFactionsShown)
    local setter = C_Reputation and (C_Reputation.SetLegacyReputationsShown or C_Reputation.SetLegacyFactionIsShown)
    if type(query) ~= "function" or type(setter) ~= "function" then
        return fn()
    end

    local readOK, wasShown = pcall(query)
    if not readOK or not SQOL.CanUseValue(wasShown) or type(wasShown) ~= "boolean" then return nil end
    if not wasShown then
        if not SQOL.safe_pcall(setter, true) then return nil end
    end

    local ok, result = pcall(fn)

    if not wasShown then
        SQOL.safe_pcall(setter, false)
    end

    if not ok then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("RepWatch -> legacy toggle error:", result)
        end
        return nil
    end

    return result
end

local function SQOL_Rep_GetWatchedFaction()
    if C_Reputation and type(C_Reputation.GetWatchedFactionData) == "function" then
        local ok, rawData = pcall(C_Reputation.GetWatchedFactionData)
        if not ok or not SQOL.CanUseValue(rawData) then return nil, nil, false end
        if rawData == nil then return nil, nil, true end
        local data = safeFactionData(rawData)
        if data and usableName(data.name) then return data.factionID, data.name, true end
        return nil, nil, false
    end

    local legacy = rawget(_G, "GetWatchedFactionInfo")
    if type(legacy) == "function" then
        local ok, name = pcall(legacy)
        if not ok or not SQOL.CanUseValue(name) then return nil, nil, false end
        if name == nil then return nil, nil, true end
        if usableName(name) then return nil, name, true end
    end

    return nil, nil, false
end

local function SQOL_Rep_WatchedMatches(factionID, factionName)
    local watchedID, watchedName = SQOL_Rep_GetWatchedFaction()
    if type(factionID) == "number" and type(watchedID) == "number" and watchedID == factionID then
        return true
    end
    if type(factionName) == "string" and factionName ~= "" and type(watchedName) == "string" then
        return watchedName == factionName
    end
    return false
end

local function SQOL_Rep_FindFactionIndexByID(factionID)
    if type(factionID) ~= "number" then
        return nil
    end

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return nil
    end

    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and data.factionID == factionID then
            return i, data.name
        end
    end

    return nil
end

local function SQOL_Rep_FindFactionIndexByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return nil
    end

    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and data.name == name then
            return i, data.factionID
        end
    end

    return nil
end

local function SQOL_Rep_SetWatchedFactionRaw(index, factionID, factionName)
    -- The direct ID API avoids expanding or relaying out Blizzard's panel.
    if C_Reputation and type(C_Reputation.SetWatchedFactionByID) == "function" and usableNumber(factionID) then
        if SQOL.safe_pcall(C_Reputation.SetWatchedFactionByID, factionID) then
            if pendingWatch then pendingWatch.accepted = true end
            if SQOL_Rep_WatchedMatches(factionID, factionName) then return true end
        end
    end
    if SQOL.RepWatch_ReputationFrameOpen() then return false end
    return SQOL_Rep_WithLegacyShown(function()
        local ok = false

        local legacy = C_Reputation and C_Reputation.SetWatchedFactionByIndex or rawget(_G, "SetWatchedFactionIndex")
        if type(legacy) == "function" then
            local legacyResult = SQOL_Rep_WithExpandedHeaders(function()
                local useIndex
                -- Expanding headers can move indices. Resolve the identity again.
                if usableNumber(factionID) then
                    useIndex = SQOL_Rep_FindFactionIndexByID(factionID)
                elseif usableName(factionName) then
                    useIndex = SQOL_Rep_FindFactionIndexByName(factionName)
                else
                    useIndex = index
                end
                if type(useIndex) == "number" then
                    local legacyOk = SQOL.safe_pcall(legacy, useIndex)
                    if legacyOk and pendingWatch then pendingWatch.accepted = true end
                    if legacyOk and SQOL_Rep_WatchedMatches(factionID, factionName) then
                        return true
                    end
                    return false
                end
                return false
            end)
            if legacyResult ~= nil then
                return legacyResult
            end
        end

        return ok
    end) or false
end

local function SQOL_Rep_SetWatchedFactionByIndexOrID(index, factionID, factionName, restoring)
    if not restoring and SQOL.RepMemory_OnFactionUpdate then SQOL.RepMemory_OnFactionUpdate() end
    -- Setters have no return value and some clients publish the watched faction
    -- later. Keep a bounded acknowledgement window instead of treating our own
    -- delayed UPDATE_FACTION as an external selection.
    if pendingWatch and SQOL_Rep_WatchedMatches(pendingWatch.factionID, pendingWatch.name) then
        SQOL.RepMemory_OnFactionUpdate()
    end
    if pendingWatch and pendingWatch.factionID == factionID and pendingWatch.name == factionName then return true end
    local request
    if memoryDB and type(memoryDB.preferredFaction) == "table"
        and SQOL.DB and SQOL.DB.RepMemory and SQOL.DB.RepWatch then
        request = { factionID = factionID, name = factionName, restoring = restoring,
            deadline = GetTime() + 2 }
    end
    pendingWatch = request
    internalWatchChange = true
    local ok, result = pcall(SQOL_Rep_SetWatchedFactionRaw, index, factionID, factionName)
    internalWatchChange = false
    observedID, observedName, observedValid = SQOL_Rep_GetWatchedFaction()
    if ok and result then
        pendingWatch = nil
        if not restoring and queueReturn then queueReturn() end
    elseif ok and request and request.accepted then
        local schedule = C_Timer and (C_Timer.After or C_Timer.NewTimer)
        if type(schedule) == "function" then
            schedule(2, function()
                if pendingWatch == request then SQOL.RepMemory_OnFactionUpdate() end
            end)
            return true
        end
        pendingWatch = nil
    else
        pendingWatch = nil
    end
    return ok and result or false
end

local function SQOL_Rep_BuildSnapshot()
    return SQOL_Rep_WithLegacyShown(function()
        return SQOL_Rep_WithExpandedHeaders(function()
            local num = SQOL_Rep_GetNumFactions()
            if not num then
                return nil
            end

            local snap = {}
            for i = 1, num do
                local data = SQOL_Rep_GetFactionDataByIndex(i)
                if data and type(data.factionID) == "number" and type(data.currentStanding) == "number" then
                    snap[data.factionID] = data.currentStanding
                end
            end
            return snap
        end)
    end)
end

------------------------------------------------------------
-- RepWatch helpers: map "faction name" -> factionID.
-- This is the most reliable way to switch watched reputation in modern Retail,
-- because the chat event already tells us which faction changed.
------------------------------------------------------------
SQOL._repNameToID = SQOL._repNameToID or {}

function SQOL.Rep_RebuildNameMap()
    SQOL.TableWipe(SQOL._repNameToID)

    local ok = SQOL_Rep_WithLegacyShown(function()
        return SQOL_Rep_WithExpandedHeaders(function()
            local num = SQOL_Rep_GetNumFactions()
            if not num then
                return false
            end

            for i = 1, num do
                local data = SQOL_Rep_GetFactionDataByIndex(i)
                if data and type(data.factionID) == "number" and type(data.name) == "string" and data.name ~= "" then
                    SQOL._repNameToID[data.name] = data.factionID
                end
            end
            return true
        end)
    end)

    return ok or false
end

local function SQOL_Rep_FindFactionIDByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local id = SQOL._repNameToID[name]
    if type(id) == "number" then
        return id
    end

    -- Refresh once (headers / list may have changed)
    if SQOL.Rep_RebuildNameMap() then
        id = SQOL._repNameToID[name]
        if type(id) == "number" then
            return id
        end
    end

    return nil
end

local function SQOL_Rep_StripChatCodes(msg)
    if type(msg) ~= "string" then
        return msg
    end
    -- Some chat event payloads are "secret strings"; avoid msg:method() on them.
    msg = string.gsub(msg, "|c%x%x%x%x%x%x%x%x", "")
    msg = string.gsub(msg, "|r", "")
    msg = string.gsub(msg, "|T.-|t", "")
    msg = string.gsub(msg, "|A.-|a", "")
    msg = string.gsub(msg, "|H.-|h(.-)|h", "%1")
    msg = string.gsub(msg, "|3%-%d+%((.-)%)", "%1")
    return msg
end

-- Blizzard's localized reputation chat templates, most specific first.
-- "INCREASED" in the name marks a gain.
local SQOL_REP_TEMPLATE_NAMES = {
    "FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE",
    "FACTION_STANDING_INCREASED_ACH_BONUS",
    "FACTION_STANDING_INCREASED_DOUBLE_BONUS",
    "FACTION_STANDING_INCREASED_BONUS",
    "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
    "FACTION_STANDING_INCREASED",
    "FACTION_STANDING_INCREASED_GENERIC_ACCOUNT_WIDE",
    "FACTION_STANDING_INCREASED_GENERIC",
    "FACTION_STANDING_DECREASED_ACCOUNT_WIDE",
    "FACTION_STANDING_DECREASED",
    "FACTION_STANDING_DECREASED_GENERIC_ACCOUNT_WIDE",
    "FACTION_STANDING_DECREASED_GENERIC",
}

-- enUS fallbacks for clients without the templates above.
-- Each capture is the faction name ("s") or the amount ("d").
local SQOL_REP_FALLBACK_PATTERNS = {
    { pattern = "^Reputation with (.-) increased by ([%d,%.]+)", kinds = { "s", "d" }, increased = true },
    { pattern = "^Your reputation with (.-) has increased by ([%d,%.]+)", kinds = { "s", "d" }, increased = true },
    -- Account-wide factions: "Your Warband's reputation with X increased by N."
    { pattern = "^Your [^']-'s reputation with (.-) increased by ([%d,%.]+)", kinds = { "s", "d" }, increased = true },
    { pattern = "^Reputation with (.-) increased", kinds = { "s" }, increased = true },
    { pattern = "^Your reputation with (.-) has increased", kinds = { "s" }, increased = true },
    { pattern = "^Your [^']-'s reputation with (.-) increased", kinds = { "s" }, increased = true },
    { pattern = "^Reputation with (.-) decreased", kinds = { "s" }, increased = false },
    { pattern = "^Your reputation with (.-) has decreased", kinds = { "s" }, increased = false },
    { pattern = "^Your [^']-'s reputation with (.-) decreased", kinds = { "s" }, increased = false },
}

local function SQOL_Rep_EscapePattern(text)
    return (string.gsub(text, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Turns a format string such as "Reputation with %s increased by %d." into a
-- Lua pattern. Handles %s, %d, %.1f and reordered arguments (%2$d), plus the
-- grammar codes of some locales: ruRU declines the name with "|3-7(%s)"
-- (unwrapped here and in SQOL_Rep_StripChatCodes), and frFR picks a plural
-- with "|4point:points;" (matched loosely, raw or already resolved).
local function SQOL_Rep_TemplateToPattern(template)
    template = string.gsub(template, "|3%-%d+%((.-)%)", "%1")
    template = string.gsub(template, "|4[^;]*;", "\001")
    local parts, kinds = {}, {}
    local pos = 1
    while pos <= #template do
        local s, e, conv = string.find(template, "%%%d*%$?[%-%d%.]*([sdf%%])", pos)
        if not s then
            parts[#parts + 1] = SQOL_Rep_EscapePattern(string.sub(template, pos))
            break
        end
        parts[#parts + 1] = SQOL_Rep_EscapePattern(string.sub(template, pos, s - 1))
        if conv == "%" then
            parts[#parts + 1] = "%%"
        else
            kinds[#kinds + 1] = conv == "s" and "s" or "d"
            parts[#parts + 1] = conv == "s" and "(.-)" or "([%d,%.]+)"
        end
        pos = e + 1
    end
    if #kinds == 0 then return nil end
    local pattern = "^" .. string.gsub(table.concat(parts), "\001", ".-")
    -- A lazy capture at the very end would match nothing.
    if string.sub(pattern, -4) == "(.-)" then
        pattern = pattern .. "$"
    end
    return pattern, kinds
end

local SQOL_RepPatterns
local function SQOL_Rep_GetPatterns()
    if SQOL_RepPatterns then return SQOL_RepPatterns end
    SQOL_RepPatterns = {}
    for _, globalName in ipairs(SQOL_REP_TEMPLATE_NAMES) do
        local template = rawget(_G, globalName)
        if type(template) == "string" and template ~= "" then
            local pattern, kinds = SQOL_Rep_TemplateToPattern(template)
            if pattern then
                SQOL_RepPatterns[#SQOL_RepPatterns + 1] = {
                    pattern = pattern,
                    kinds = kinds,
                    increased = string.find(globalName, "INCREASED", 1, true) ~= nil,
                }
            end
        end
    end
    for _, entry in ipairs(SQOL_REP_FALLBACK_PATTERNS) do
        SQOL_RepPatterns[#SQOL_RepPatterns + 1] = entry
    end
    return SQOL_RepPatterns
end

-- Returns faction name, amount (or nil) and whether it was a gain,
-- for a reputation chat message with the chat codes already stripped.
local function SQOL_Rep_ParseMessage(msg)
    for _, entry in ipairs(SQOL_Rep_GetPatterns()) do
        local captures = { string.match(msg, entry.pattern) }
        if captures[1] then
            local name, amount
            for i, kind in ipairs(entry.kinds) do
                if kind == "s" and not name then
                    name = captures[i]
                elseif kind == "d" and not amount then
                    amount = tonumber((string.gsub(captures[i], "[,%.]", "")))
                end
            end
            if name then
                return name, amount, entry.increased
            end
        end
    end
end

-- For tests: parse a raw chat message, and rebuild the patterns after the
-- templates change.
function SQOL.Rep_ParseMessage(msg)
    if not SQOL.CanUseValue(msg) or type(msg) ~= "string" then return nil end
    local ok, name, amount, increased = pcall(function()
        return SQOL_Rep_ParseMessage(SQOL_Rep_StripChatCodes(msg))
    end)
    if ok and SQOL.CanUseValue(name) and SQOL.CanUseValue(amount) and SQOL.CanUseValue(increased) then
        return name, amount, increased
    end
end

function SQOL.Rep_ResetPatterns()
    SQOL_RepPatterns = nil
end

local function SQOL_Rep_ParseFactionNameFromMessage(msg)
    if not SQOL.CanUseValue(msg) or type(msg) ~= "string" then
        return nil
    end

    msg = SQOL_Rep_StripChatCodes(msg)

    local name = SQOL.Rep_ParseMessage(msg)

    if type(name) ~= "string" then
        return nil
    end

    name = string.gsub(name, "%.$", "")
    name = string.match(name, "^%s*(.-)%s*$")

    if name == "" then
        return nil
    end

    return name
end

-- Small, bounded pool of floating labels. This uses chat gains rather than
-- faction snapshots, so login, watched-bar changes and standing transitions
-- cannot create synthetic reputation gains.
local repGainFrame
local repGainLines = {}
local repGainDuration = 2.5

function SQOL.RepGains_Hide()
    if not repGainFrame then return end
    for _, line in ipairs(repGainLines) do
        line.age = nil
        line:Hide()
    end
    repGainFrame:Hide()
end

function SQOL.RepGains_Show(name, amount)
    if not repGainFrame then
        repGainFrame = CreateFrame("Frame", nil, UIParent)
        repGainFrame:SetAllPoints(UIParent)
        repGainFrame:EnableMouse(false)
        repGainFrame:SetScript("OnUpdate", function(self, elapsed)
            local active = false
            for _, line in ipairs(repGainLines) do
                if line.age then
                    line.age = line.age + elapsed
                    if line.age >= repGainDuration then
                        line.age = nil
                        line:Hide()
                    else
                        active = true
                        line:SetPoint("CENTER", self, "CENTER", 0, 65 + line.offset + line.age * 22)
                        line:SetAlpha(math.min(1, (repGainDuration - line.age) / 0.8))
                    end
                end
            end
            if not active then self:Hide() end
        end)
    end

    local available, oldest
    for _, line in ipairs(repGainLines) do
        if not line.age then
            available = available or line
        else
            line.offset = line.offset + 28
            if not oldest or line.age > oldest.age then oldest = line end
        end
    end
    if not available and #repGainLines < 3 then
        available = repGainFrame:CreateFontString(nil, "OVERLAY")
        available:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
        available:SetTextColor(0.3, 1, 0.3)
        repGainLines[#repGainLines + 1] = available
    end
    local line = available or oldest
    line.age, line.offset = 0, 0
    line:SetText(string.format(L["+%d Rep — %s"], amount, name))
    line:SetPoint("CENTER", repGainFrame, "CENTER", 0, 65)
    line:SetAlpha(1)
    line:Show()
    repGainFrame:Show()
end

function SQOL.RepGains_HandleMessage(msg)
    if not SQOL.DB or not SQOL.DB.ShowRepGains then return end
    if not SQOL.CanUseValue(msg) or type(msg) ~= "string" then return end
    local _, amount, increased = SQOL.Rep_ParseMessage(msg)
    if not increased or not amount or amount <= 0 then return end
    local name = SQOL_Rep_ParseFactionNameFromMessage(msg)
    if name then SQOL.RepGains_Show(name, amount) end
end

local function SQOL_Rep_FindFactionIDFromMessage(msg)
    if not SQOL.CanUseValue(msg) or type(msg) ~= "string" then
        return nil, nil
    end

    msg = SQOL_Rep_StripChatCodes(msg)

    local name = SQOL_Rep_ParseFactionNameFromMessage(msg)
    if name then
        local id = SQOL_Rep_FindFactionIDByName(name)
        if type(id) == "number" then
            return id, name
        end
    end

    if not next(SQOL._repNameToID) then
        SQOL.Rep_RebuildNameMap()
    end

    local bestName, bestID
    for factionName, factionID in pairs(SQOL._repNameToID) do
        if string.find(msg, factionName, 1, true) then
            if not bestName or #factionName > #bestName then
                bestName = factionName
                bestID = factionID
            end
        end
    end

    return bestID, bestName
end

-- Avoid switching watched reputation while Collections/Transmog is open.
local function SQOL_Rep_FrameVisible(frame)
    if not frame then return false end
    -- IsShown only reports the child's own flag. Closing CharacterFrame or
    -- CollectionsJournal can leave that flag set on its now-invisible children.
    local query = frame.IsVisible or frame.IsShown
    if type(query) ~= "function" then return false end
    local ok, visible = pcall(query, frame)
    -- An unreadable panel state must not trigger a layout-changing scan.
    return not ok or not SQOL.CanUseValue(visible) or visible == true
end

local function SQOL_RepWatch_CollectionsOpen()
    local wardrobe = rawget(_G, "WardrobeFrame")
    if SQOL_Rep_FrameVisible(wardrobe) then
        return true
    end
    local collection = rawget(_G, "WardrobeCollectionFrame")
    if SQOL_Rep_FrameVisible(collection) then
        return true
    end
    local journal = rawget(_G, "CollectionsJournal")
    if SQOL_Rep_FrameVisible(journal) then
        return true
    end
    return false
end

-- Avoid the expand-all/re-collapse scan while the Reputation panel is open.
-- That scan re-lays out the reputation list, which makes the text visibly jump
-- when the user simply clicks an expansion header to collapse/expand it.
function SQOL.RepWatch_ReputationFrameOpen()
    local repFrame = rawget(_G, "ReputationFrame")
    return SQOL_Rep_FrameVisible(repFrame)
end

function SQOL.RepWatch_HandleFactionChangeMessage(msg)
    if not SQOL.DB or not SQOL.DB.RepWatch then
        return false
    end
    if not SQOL.CanUseValue(msg) or type(msg) ~= "string" then return true end
    local _, _, increased = SQOL.Rep_ParseMessage(msg)
    if increased == false then return true end
    if increased ~= true then return false end
    if returnPending and queueReturn then queueReturn() end
    if SQOL_RepWatch_CollectionsOpen() then
        SQOL._repWatchDeferred = true
        return false
    end

    local id, name = SQOL_Rep_FindFactionIDFromMessage(msg)
    if not id and not name then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("RepWatch -> Could not parse faction from message:", tostring(msg))
        end
        return false
    end

    if type(id) ~= "number" then
        local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(nil, nil, name)
        if ok then
            SQOL.dprint("RepWatch -> Now watching (name):", name)
            return true
        end

        SQOL._repPendingName = name
        SQOL._repPendingAt = (type(GetTime) == "function") and GetTime() or 0
        SQOL.dprint("RepWatch -> Deferring watch until faction appears:", name)
        if SQOL_RepWatch_ScheduleScan then
            SQOL_RepWatch_ScheduleScan()
        end
        return true
    end

    local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(nil, id, name)
    if ok then
        SQOL.dprint("RepWatch -> Now watching:", name)
        return true
    end

    SQOL.dprint("RepWatch -> Failed to set watched faction for:", name)
    return false
end

local function SQOL_RepWatch_ScanAndSwitch()
    if not SQOL.DB or not SQOL.DB.RepWatch then
        return
    end

    local skipSwitch = false
    if type(SQOL._repPendingName) == "string" and SQOL._repPendingName ~= "" then
        local pendingName = SQOL._repPendingName
        local pendingId = SQOL_Rep_FindFactionIDByName(pendingName)
        if type(pendingId) == "number" then
            local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(nil, pendingId, pendingName)
            if ok then
                SQOL.dprint("RepWatch -> Now watching (pending):", pendingName)
            else
                SQOL.dprint("RepWatch -> Failed to set watched faction (pending):", pendingName)
            end
            SQOL._repPendingName = nil
            SQOL._repPendingAt = nil
            return
        end

        local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(nil, nil, pendingName)
        if ok then
            SQOL.dprint("RepWatch -> Now watching (pending name):", pendingName)
            SQOL._repPendingName = nil
            SQOL._repPendingAt = nil
            return
        end

        local now = (type(GetTime) == "function") and GetTime() or 0
        if SQOL._repPendingAt and (now - SQOL._repPendingAt) < 5 then
            skipSwitch = true
            SQOL.dprint("RepWatch -> Pending faction not in list yet:", pendingName)
        else
            SQOL._repPendingName = nil
            SQOL._repPendingAt = nil
        end
    end

    SQOL_Rep_WithLegacyShown(function()
        return SQOL_Rep_WithExpandedHeaders(function()
            local num = SQOL_Rep_GetNumFactions()
            if not num then
                if SQOL.DB.DebugTrack and not SQOL._repApiWarned then
                    SQOL._repApiWarned = true
                    SQOL.dprint("RepWatch -> Reputation APIs not available in this client build.")
                end
                return nil
            end

            if type(SQOL._repLastStanding) ~= "table" then
                SQOL._repLastStanding = SQOL_Rep_BuildSnapshot()
                SQOL.dprint("RepWatch -> Snapshot initialized.")
                return nil
            end

            local bestDelta = 0
            local bestIndex, bestFactionID, bestName = nil, nil, nil

            for i = 1, num do
                local data = SQOL_Rep_GetFactionDataByIndex(i)
                if data and type(data.factionID) == "number" and type(data.currentStanding) == "number" then
                    local id = data.factionID
                    local prev = SQOL._repLastStanding[id]
                    local cur = data.currentStanding

                    if type(prev) == "number" then
                        local delta = cur - prev
                        if delta > bestDelta then
                            bestDelta = delta
                            bestIndex = i
                            bestFactionID = id
                            bestName = data.name
                        end
                    end

                    SQOL._repLastStanding[id] = cur
                end
            end

            if not skipSwitch and bestDelta > 0 and (bestFactionID or bestIndex) then
                local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(bestIndex, bestFactionID, bestName)
                if ok then
                    SQOL.dprint(string.format("RepWatch -> Now watching: %s (+%d)", tostring(bestName or bestFactionID), bestDelta))
                else
                    SQOL.dprint("RepWatch -> Could not set watched faction.")
                end
            end

            return nil
        end)
    end)
end

function SQOL_RepWatch_ScheduleScan(reason)
    if SQOL._repWatchPending then
        return
    end
    if SQOL_RepWatch_CollectionsOpen() then
        SQOL._repWatchDeferred = true
        if SQOL._repWatchRetryPending then
            return
        end
        SQOL._repWatchRetryPending = true
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.5, function()
                SQOL._repWatchRetryPending = false
                if SQOL.DB and SQOL.DB.RepWatch then
                    SQOL_RepWatch_ScheduleScan()
                else
                    SQOL._repWatchDeferred = false
                end
            end)
        else
            SQOL._repWatchRetryPending = false
        end
        return
    end
    if reason == "update_faction" and SQOL.DB and SQOL.DB.DebugTrack then
        local now = (type(GetTime) == "function") and GetTime() or 0
        local last = SQOL._repWatchLastUpdateDebug or 0
        if (now - last) > 1.0 then
            SQOL._repWatchLastUpdateDebug = now
            SQOL.dprint("RepWatch -> UPDATE_FACTION (queued)")
        end
    end
    SQOL._repWatchPending = true
    C_Timer.After(0.20, function()
        SQOL._repWatchDeferred = false
        SQOL_RepWatch_ScanAndSwitch()
        -- Header changes can synchronously emit UPDATE_FACTION. Keep the scan
        -- marked pending until it is finished to avoid rescheduling itself.
        SQOL._repWatchPending = false
    end)
end

------------------------------------------------------------
-- Reputation Memory: one preferred faction per character.
------------------------------------------------------------
local function memoryEnabled()
    return memoryDB and SQOL.DB and SQOL.DB.RepMemory and SQOL.DB.RepWatch
        and type(memoryDB.preferredFaction) == "table"
end

local function wallTime()
    local query = rawget(_G, "GetServerTime") or rawget(_G, "time")
    if type(query) == "function" then
        local ok, value = pcall(query)
        if ok and usableNumber(value) then return value end
    end
end

cancelReturn = function()
    returnGeneration = returnGeneration + 1
    if returnTimer and type(returnTimer.Cancel) == "function" then returnTimer:Cancel() end
    returnTimer, returnPending = nil, nil
    pendingWatch = nil
    if memoryDB then memoryDB.pendingReturn = nil end
end

-- Returns true when an external selection superseded our work. Checking on
-- UPDATE_FACTION also catches selecting a different faction and switching back
-- before the deadline; comparing only at the deadline would miss that case.
function SQOL.RepMemory_OnFactionUpdate()
    if internalWatchChange or not memoryEnabled() then return false end
    local id, name, valid = SQOL_Rep_GetWatchedFaction()
    if pendingWatch then
        local request = pendingWatch
        if valid and SQOL_Rep_WatchedMatches(request.factionID, request.name) then
            pendingWatch = nil
            observedID, observedName, observedValid = id, name, valid
            SQOL.dprint("RepMemory -> watched faction confirmed:", name)
            if not request.restoring then queueReturn() end
            return false
        elseif GetTime() >= request.deadline then
            pendingWatch = nil
            SQOL.dprint("RepMemory -> watched faction was not confirmed:", request.name)
        end
    end
    local changed = observedValid and (not valid or id ~= observedID or name ~= observedName)
    observedID, observedName, observedValid = id, name, valid
    if changed then
        SQOL.dprint("RepMemory -> external watched faction change; cancelling return:", name or "<none>")
        cancelReturn()
        SQOL._repPendingName, SQOL._repPendingAt = nil, nil
        SQOL._repLastStanding = nil
        return true
    end
    return false
end

local function scheduleReturn(delay)
    local generation = returnGeneration
    local function callback()
        if generation ~= returnGeneration then return end
        returnTimer = nil
        if not returnPending or not memoryEnabled() then cancelReturn(); return end
        if SQOL.RepMemory_OnFactionUpdate() then return end
        if not SQOL_Rep_WatchedMatches(returnPending.factionID, returnPending.name) then cancelReturn(); return end
        local remaining = returnPending.deadline - GetTime()
        if remaining > 0 then scheduleReturn(remaining); return end
        local preferred = memoryDB.preferredFaction
        cancelReturn()
        -- Never expand/rearrange panels that the player is currently using.
        if SQOL.RepWatch_ReputationFrameOpen() or SQOL_RepWatch_CollectionsOpen() then
            SQOL.dprint("RepMemory -> return cancelled while Reputation or Collections is open")
            return
        end
        local restored = SQOL_Rep_SetWatchedFactionByIndexOrID(nil, preferred.factionID, preferred.name, true)
        SQOL.dprint("RepMemory -> return requested:", preferred.name, "accepted:", tostring(restored))
    end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        returnTimer = C_Timer.NewTimer(delay, callback)
    elseif C_Timer and type(C_Timer.After) == "function" then
        returnTimer = {} -- A generation token invalidates uncancellable callbacks.
        C_Timer.After(delay, callback)
    else
        cancelReturn()
    end
end

queueReturn = function()
    if not memoryEnabled() then return end
    local preferred = memoryDB.preferredFaction
    if SQOL_Rep_WatchedMatches(preferred.factionID, preferred.name) then cancelReturn(); return end
    local id, name, valid = SQOL_Rep_GetWatchedFaction()
    if not valid or not usableName(name) then cancelReturn(); return end
    returnPending = { factionID = id, name = name, deadline = GetTime() + 10 }
    SQOL.dprint("RepMemory -> return queued:", preferred.name, "deadline:", returnPending.deadline)
    local wall = wallTime()
    memoryDB.pendingReturn = wall and { factionID = id, name = name, expiresAt = wall + 10 } or nil
    -- Bursts extend one deadline; they do not allocate one timer per gain.
    if not returnTimer then scheduleReturn(10) end
end

function SQOL.RepMemory_Init()
    if type(SQOL_CharacterDB) ~= "table" then SQOL_CharacterDB = {} end
    memoryDB = SQOL_CharacterDB
    local preferred = memoryDB.preferredFaction
    if type(preferred) ~= "table" or not usableName(preferred.name)
        or (preferred.factionID ~= nil and not usableNumber(preferred.factionID)) then
        memoryDB.preferredFaction = nil
    end
    observedID, observedName, observedValid = SQOL_Rep_GetWatchedFaction()
    local saved = memoryDB.pendingReturn
    if memoryEnabled() and type(saved) == "table" and usableName(saved.name)
        and usableNumber(saved.expiresAt) and wallTime()
        and SQOL_Rep_WatchedMatches(saved.factionID, saved.name) then
        returnPending = { factionID = saved.factionID, name = saved.name,
            deadline = GetTime() + math.min(10, math.max(0, saved.expiresAt - wallTime())) }
        scheduleReturn(math.max(0, returnPending.deadline - GetTime()))
    else
        cancelReturn()
    end
end

function SQOL.RepMemory_OnOptionChanged()
    cancelReturn()
    SQOL._repPendingName, SQOL._repPendingAt = nil, nil
    SQOL._repLastStanding = nil
    observedID, observedName, observedValid = SQOL_Rep_GetWatchedFaction()
end

function SQOL.RepMemory_Command(command)
    if not memoryDB then SQOL.RepMemory_Init() end
    local prefix = "|cff33ff99SQoL:|r "
    if command == "clear" then
        cancelReturn()
        memoryDB.preferredFaction = nil
        print(prefix .. L["Preferred reputation cleared."])
    elseif command == "status" then
        local preferred = memoryDB.preferredFaction
        print(prefix .. (preferred and string.format(L["Preferred reputation: %s"], preferred.name)
            or L["No preferred reputation saved."]))
    elseif command == "" then
        local id, name, valid = SQOL_Rep_GetWatchedFaction()
        if not valid or not usableName(name) then
            print(prefix .. L["Choose a watched faction in Blizzard's Reputation panel first."])
            return
        end
        cancelReturn()
        memoryDB.preferredFaction = { factionID = id, name = name }
        observedID, observedName, observedValid = id, name, valid
        print(prefix .. string.format(L["Preferred reputation saved: %s"], name))
    else
        print(prefix .. "/sqol repfocus [clear | status]")
    end
end

