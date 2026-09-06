local ADDON_NAME, SQOL = ...

------------------------------------------------------------
-- RepWatch: auto-switch watched reputation on rep gain
-- Uses C_Reputation APIs when available (TWW/11.0.2+), with legacy fallback.
------------------------------------------------------------
SQOL._repWatchPending = false
SQOL._repLastStanding = nil
SQOL._repApiWarned = false

local function SQOL_Rep_GetNumFactions()
    if C_Reputation and type(C_Reputation.GetNumFactions) == "function" then
        return C_Reputation.GetNumFactions()
    end
    local legacy = rawget(_G, "GetNumFactions")
    if type(legacy) == "function" then
        return legacy()
    end
    return nil
end

local function SQOL_Rep_GetFactionDataByIndex(index)
    if C_Reputation and type(C_Reputation.GetFactionDataByIndex) == "function" then
        local data = C_Reputation.GetFactionDataByIndex(index)
        if data and type(data) == "table" then
            -- Field names have shifted a bit over time; normalize to "currentStanding" when possible.
            if type(data.currentStanding) ~= "number" then
                data.currentStanding =
                    data.currentStanding
---@diagnostic disable-next-line: undefined-field
                    or data.earnedValue
---@diagnostic disable-next-line: undefined-field
                    or data.barValue
---@diagnostic disable-next-line: undefined-field
                    or data.currentValue
---@diagnostic disable-next-line: undefined-field
                    or data.currentReputation
            end
        end
        return data
    end

    local legacy = rawget(_G, "GetFactionInfo")
    if type(legacy) == "function" then
        local name, description, standingId, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar,
            isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = legacy(index)

        if not name then
            return nil
        end

        return {
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
        }
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
    if not C_Reputation
        or type(C_Reputation.AreLegacyFactionsShown) ~= "function"
        or type(C_Reputation.SetLegacyFactionIsShown) ~= "function" then
        return fn()
    end

    local wasShown = C_Reputation.AreLegacyFactionsShown()
    if not wasShown then
        SQOL.safe_pcall(C_Reputation.SetLegacyFactionIsShown, true)
    end

    local ok, result = pcall(fn)

    if not wasShown then
        SQOL.safe_pcall(C_Reputation.SetLegacyFactionIsShown, false)
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
        local data = C_Reputation.GetWatchedFactionData()
        if data and type(data.factionID) == "number" then
            return data.factionID, data.name
        end
        if data and type(data.name) == "string" and data.name ~= "" then
            return nil, data.name
        end
    end

    local legacy = rawget(_G, "GetWatchedFactionInfo")
    if type(legacy) == "function" then
        local name = legacy()
        if type(name) == "string" and name ~= "" then
            return nil, name
        end
    end

    return nil, nil
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

local function SQOL_Rep_SetWatchedFactionByIndexOrID(index, factionID, factionName)
    local result = SQOL_Rep_WithLegacyShown(function()
        local ok = false
        if C_Reputation and type(C_Reputation.SetWatchedFactionByID) == "function" and type(factionID) == "number" then
            ok = SQOL.safe_pcall(C_Reputation.SetWatchedFactionByID, factionID)
            if ok and SQOL_Rep_WatchedMatches(factionID, factionName) then
                return true
            end
            ok = false
        end

        local legacy = rawget(_G, "SetWatchedFactionIndex")
        if type(legacy) == "function" then
            local legacyResult = SQOL_Rep_WithExpandedHeaders(function()
                local useIndex = index
                if type(useIndex) ~= "number" then
                    if type(factionID) == "number" then
                        useIndex = SQOL_Rep_FindFactionIndexByID(factionID)
                    elseif type(factionName) == "string" and factionName ~= "" then
                        useIndex = SQOL_Rep_FindFactionIndexByName(factionName)
                    end
                end
                if type(useIndex) == "number" then
                    local legacyOk = SQOL.safe_pcall(legacy, useIndex)
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
    end)

    return result or false
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
    return msg
end

local function SQOL_Rep_ParseFactionNameFromMessage(msg)
    if type(msg) ~= "string" then
        return nil
    end

    msg = SQOL_Rep_StripChatCodes(msg)

    -- enUS patterns (Retail default). If you ever play another locale,
    -- we can switch this over to use global string templates instead.
    local name =
        string.match(msg, "^Reputation with (.-) increased") or
        string.match(msg, "^Reputation with (.-) decreased") or
        string.match(msg, "^Your reputation with (.-) has increased") or
        string.match(msg, "^Your reputation with (.-) has decreased")

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
    line:SetText("+" .. amount .. " Rep — " .. name)
    line:SetPoint("CENTER", repGainFrame, "CENTER", 0, 65)
    line:SetAlpha(1)
    line:Show()
    repGainFrame:Show()
end

function SQOL.RepGains_HandleMessage(msg)
    if not SQOL.DB or not SQOL.DB.ShowRepGains then return end
    if issecretvalue and issecretvalue(msg) then return end
    if type(msg) ~= "string" then return end
    -- The addon currently supports enUS, matching RepWatch's parser above.
    msg = SQOL_Rep_StripChatCodes(msg)
    local amount = string.match(msg, "increased by ([%d,]+)")
    amount = amount and tonumber((string.gsub(amount, ",", "")))
    if not amount or amount <= 0 then return end
    local name = SQOL_Rep_ParseFactionNameFromMessage(msg)
    if name then SQOL.RepGains_Show(name, amount) end
end

local function SQOL_Rep_FindFactionIDFromMessage(msg)
    if type(msg) ~= "string" then
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
local function SQOL_RepWatch_CollectionsOpen()
    local wardrobe = rawget(_G, "WardrobeFrame")
    if wardrobe and wardrobe.IsShown and wardrobe:IsShown() then
        return true
    end
    local collection = rawget(_G, "WardrobeCollectionFrame")
    if collection and collection.IsShown and collection:IsShown() then
        return true
    end
    local journal = rawget(_G, "CollectionsJournal")
    if journal and journal.IsShown and journal:IsShown() then
        return true
    end
    return false
end

-- Avoid the expand-all/re-collapse scan while the Reputation panel is open.
-- That scan re-lays out the reputation list, which makes the text visibly jump
-- when the user simply clicks an expansion header to collapse/expand it.
function SQOL.RepWatch_ReputationFrameOpen()
    local repFrame = rawget(_G, "ReputationFrame")
    if repFrame and repFrame.IsShown and repFrame:IsShown() then
        return true
    end
    return false
end

function SQOL.RepWatch_HandleFactionChangeMessage(msg)
    if not SQOL.DB or not SQOL.DB.RepWatch then
        return false
    end
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
                    elseif type(cur) == "number" and cur > 0 and bestDelta <= 0 then
                        -- New faction discovered after the snapshot: treat current standing as the delta.
                        bestDelta = cur
                        bestIndex = i
                        bestFactionID = id
                        bestName = data.name
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
        SQOL._repWatchPending = false
        SQOL._repWatchDeferred = false
        SQOL_RepWatch_ScanAndSwitch()
    end)
end

