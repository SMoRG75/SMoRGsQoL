local ADDON_NAME, SQOL = ...

------------------------------------------------------------
-- Color utilities
------------------------------------------------------------
local function SQOL_GetProgressColor(progress)
    progress = SQOL.clamp01(progress or 0)
    if progress >= 1 then
        return "|cff00ff00"
    elseif progress <= 0 then
        return "|cffff0000"
    end
    local r, g
    if progress < 0.5 then
        r, g = 1, progress * 2
    else
        r, g = 1 - ((progress - 0.5) * 2), 1
    end
    local R = math.floor(r * 255 + 0.5)
    local G = math.floor(g * 255 + 0.5)
    return string.format("|cff%02x%02x%02x", R, G, 0)
end

SQOL.GetProgressColor = SQOL_GetProgressColor

local function SQOL_FormatProgressText(cur, total)
    if type(cur) ~= "number" or type(total) ~= "number" or total <= 0 then
        return nil
    end
    if total == 100 then
        return string.format("%d%%", cur)
    end
    return string.format("%d/%d", cur, total)
end

local function SQOL_ParseProgressMessage(message)
    if type(message) ~= "string" then
        return nil
    end

    local label, cur, total = message:match("^(.+):%s*(%d+)%s*/%s*(%d+)$")
    if label and cur and total then
        return label, tonumber(cur), tonumber(total)
    end

    label, cur = message:match("^(.+):%s*(%d+)%%$")
    if label and cur then
        return label, tonumber(cur), 100
    end

    label, cur = message:match("^(.+)%s+%((%d+)%%%)$")
    if label and cur then
        return label, tonumber(cur), 100
    end

    cur = message:match("^(%d+)%%$")
    if cur then
        return nil, tonumber(cur), 100
    end

    return nil
end

local function SQOL_EnsureProgressMessageFrame()
    if SQOL.MessageFrame then
        return
    end

    SQOL.MessageFrame = CreateFrame("MessageFrame", "SQOL_MessageFrame", UIParent)
    SQOL.MessageFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    SQOL.MessageFrame:SetSize(512, 60)
    SQOL.MessageFrame:SetInsertMode("TOP")
    SQOL.MessageFrame:SetFading(true)
    SQOL.MessageFrame:SetFadeDuration(1.5)
    SQOL.MessageFrame:SetTimeVisible(2.5)
    -- Ensure this overlay never blocks clicks on nearby UI (e.g., Transmog paging).
    if SQOL.MessageFrame.EnableMouse then
        SQOL.MessageFrame:EnableMouse(false)
    end
    if SQOL.MessageFrame.EnableMouseWheel then
        SQOL.MessageFrame:EnableMouseWheel(false)
    end
    -- Use explicit font to avoid dependency on UI object availability
    SQOL.MessageFrame:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
end

local SQOL_MESSAGE_HISTORY_LIMIT = 100

local function SQOL_AddProgressFrameMessage(...)
    SQOL_EnsureProgressMessageFrame()
    SQOL._messageFrameHistoryCount = (SQOL._messageFrameHistoryCount or 0) + 1
    if SQOL._messageFrameHistoryCount > SQOL_MESSAGE_HISTORY_LIMIT then
        -- MessageFrame has no SetMaxLines API. Clear its native message objects
        -- periodically so a long session cannot retain an unbounded history.
        SQOL.MessageFrame:Clear()
        SQOL._messageFrameHistoryCount = 1
    end
    SQOL.MessageFrame:AddMessage(...)
end

local function SQOL_ShowProgressMessage(label, cur, total)
    if not SQOL.DB or not SQOL.DB.ColorProgress then return end
    if type(cur) ~= "number" or type(total) ~= "number" or total <= 0 then return end

    local key = string.format("%s:%d:%d", tostring(label or ""), cur, total)
    local now = type(GetTimePreciseSec) == "function" and GetTimePreciseSec() or 0
    if SQOL._lastProgressMessageKey == key and now > 0
        and SQOL._lastProgressMessageAt and (now - SQOL._lastProgressMessageAt) < 0.75 then
        return SQOL.clamp01(cur / total)
    end
    SQOL._lastProgressMessageKey = key
    SQOL._lastProgressMessageAt = now

    SQOL_EnsureProgressMessageFrame()

    local progress = SQOL.clamp01(cur / total)
    local colorCode = SQOL_GetProgressColor(progress)
    local progressText = SQOL_FormatProgressText(cur, total)
    local displayMessage = progressText and label and string.format("%s: %s", label, progressText)
        or progressText
        or string.format("%d/%d", cur, total)

    SQOL_AddProgressFrameMessage(colorCode .. displayMessage .. "|r")
    return progress
end

------------------------------------------------------------
-- Colorize tracker objective lines (Retail tracker)
-- Throttled to avoid excess work during rapid updates.
------------------------------------------------------------
SQOL._recolorPending = false
SQOL._lastRecolorAt  = 0

-- Quest APIs return freshly allocated tables. Several SQOL features consume
-- the same data after the same quest event, so share one bounded snapshot
-- until the next quest-data change instead of asking the client repeatedly.
SQOL._questObjectiveCache = SQOL._questObjectiveCache or {}
SQOL._questLogSnapshot = nil
local SQOL_NO_QUEST_OBJECTIVES = {}

function SQOL.InvalidateQuestDataCache()
    SQOL._questLogSnapshot = nil
    for questID in pairs(SQOL._questObjectiveCache) do
        SQOL._questObjectiveCache[questID] = nil
    end
end

function SQOL.GetQuestObjectivesCached(questID)
    if type(questID) ~= "number" or not C_QuestLog
        or type(C_QuestLog.GetQuestObjectives) ~= "function" then
        return nil
    end

    local cached = SQOL._questObjectiveCache[questID]
    if cached ~= nil then
        return cached ~= SQOL_NO_QUEST_OBJECTIVES and cached or nil
    end

    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" then
        SQOL._questObjectiveCache[questID] = SQOL_NO_QUEST_OBJECTIVES
        return nil
    end

    SQOL._questObjectiveCache[questID] = objectives
    return objectives
end

function SQOL.GetQuestLogSnapshot()
    if SQOL._questLogSnapshot then
        return SQOL._questLogSnapshot
    end

    local snapshot = {}
    if C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function"
        and type(C_QuestLog.GetInfo) == "function" then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info then
                snapshot[#snapshot + 1] = info
            end
        end
    end
    SQOL._questLogSnapshot = snapshot
    return snapshot
end

local function SQOL_RecolorQuestObjectives_Impl()
    if not SQOL.DB.ColorProgress then return end
    for _, info in ipairs(SQOL.GetQuestLogSnapshot()) do
        if info and not info.isHeader and info.questID then
            local objectives = SQOL.GetQuestObjectivesCached(info.questID)
            if objectives then
                for _, obj in ipairs(objectives) do
                    local numItems     = rawget(obj, "numItems")
                    local numRequired  = rawget(obj, "numRequired")
                    local numFulfilled = rawget(obj, "numFulfilled")
                    local objText      = rawget(obj, "text")
                    local hasCounter = (type(numItems) == "number" and numItems > 0)
                                    or (type(numRequired) == "number" and numRequired > 0)
                    if hasCounter then
                        local required  = (type(numRequired) == "number" and numRequired)
                                       or (type(numItems) == "number" and numItems)
                                       or 0
                        local fulfilled = (type(numFulfilled) == "number" and numFulfilled) or 0
                        local progress = (required > 0) and (fulfilled / required) or 0
                        local color = SQOL_GetProgressColor(progress)
                        local progressText = SQOL_FormatProgressText(fulfilled, required) or string.format("%d/%d",
                            fulfilled, required)
                        local text = string.format("%s%s|r %s", color, progressText, objText or "")
                        local block = ObjectiveTrackerBlocksFrame and ObjectiveTrackerBlocksFrame:GetBlock(info.questID)
                        if block and block.lines then
                            for _, line in pairs(block.lines) do
                                local lineText = line.text and line.text:GetText()
                                if lineText and objText and lineText:find(objText, 1, true) then
                                    line.text:SetText(text)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    SQOL.RequestIncrementalGC()
end

function SQOL.RecolorQuestObjectives_Throttle()
    if SQOL._recolorPending then return end
    SQOL._recolorPending = true
    C_Timer.After(0.2, function()
        SQOL_RecolorQuestObjectives_Impl()
        SQOL._recolorPending = false
        SQOL._lastRecolorAt = GetTimePreciseSec()
    end)
end

------------------------------------------------------------
-- Nameplate objective counts
------------------------------------------------------------
SQOL._npUnits = SQOL._npUnits or {}
SQOL._npUpdatePending = false
local SQOL_NAMEPLATE_UPDATE_DELAY = 0.35

local function SQOL_NameplateObjectives_SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP safety:", a)
        end
        return false
    end
    return true, a, b, c, d, e
end

local function SQOL_NameplateObjectives_GetNpcID(unit)
    if type(UnitGUID) ~= "function" then
        return nil
    end

    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local npcId = select(6, strsplit("-", guid))
    return tonumber(npcId)
end

local function SQOL_NameplateObjectives_GetQuestEntries(unit)
    if not C_QuestLog then
        return nil
    end

    local entries
    if type(C_QuestLog.GetQuestsForNamePlate) == "function" then
        local ok, result = pcall(C_QuestLog.GetQuestsForNamePlate, unit)
        if ok then
            entries = result
        elseif SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP GetQuestsForNamePlate error:", result)
        end
    elseif type(C_QuestLog.GetQuestsForNameplate) == "function" then
        local ok, result = pcall(C_QuestLog.GetQuestsForNameplate, unit)
        if ok then
            entries = result
        elseif SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP GetQuestsForNameplate error:", result)
        end
    end

    if SQOL.DB and SQOL.DB.DebugTrack then
        if type(entries) == "table" then
            local count = 0
            for _ in pairs(entries) do
                count = count + 1
            end
            SQOL.dprint("NP quests for unit:", unit, "count:", count)
        else
            SQOL.dprint("NP quests for unit:", unit, "-> none")
        end
    end

    return entries
end

local function SQOL_NameplateObjectives_ParseProgressFromText(text)
    if type(text) ~= "string" then
        return nil
    end

    local cur, total = text:match("(%d+)%s*/%s*(%d+)")
    if not cur or not total then
        return nil
    end

    cur, total = tonumber(cur), tonumber(total)
    if not cur or not total or total <= 0 then
        return nil
    end

    return cur, total
end

local function SQOL_NameplateObjectives_IsIgnoredTooltipLine(text)
    if type(text) ~= "string" then
        return true
    end
    local lower = text:lower()
    if lower:find("threat", 1, true) then
        return true
    end
    return false
end

local function SQOL_NameplateObjectives_GetTooltipProgress(unit)
    if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
        return nil
    end

    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP tooltip error:", data)
        end
        return nil
    end
    if not data or type(data.lines) ~= "table" then
        return nil
    end

    local inQuestBlock = false
    local questTitle = nil
    local fallbackLine = nil

    for _, line in ipairs(data.lines) do
        local leftText = line.leftText
        local rightText = line.rightText
        local leftColor = line.leftColor

        local isQuestTitle = false
        if leftText and leftColor then
            -- leftColor can be a "secret" value under Blizzard's taint
            -- protection; indexing it directly throws. Guard the access so
            -- parsing continues instead of aborting the whole function.
            local okColor, r, g, b = pcall(function()
                return leftColor.r, leftColor.g, leftColor.b
            end)
            if okColor and type(r) == "number" then
                if r > 0.99 and g > 0.8 and b < 0.1 then
                    isQuestTitle = true
                end
            end
        end

        if isQuestTitle then
            inQuestBlock = true
            questTitle = leftText
        else
            local texts = { leftText, rightText }
            for _, text in ipairs(texts) do
                if SQOL_NameplateObjectives_IsIgnoredTooltipLine(text) then
                    if SQOL.DB and SQOL.DB.DebugTrack and type(text) == "string" and text ~= "" then
                        SQOL.dprint("NP tooltip: ignoring line:", text)
                    end
                else
                    local cur, total = SQOL_NameplateObjectives_ParseProgressFromText(text)
                    if cur then
                        if inQuestBlock then
                            return cur, total, text, questTitle
                        end
                        if not fallbackLine then
                            fallbackLine = { cur = cur, total = total, text = text, questTitle = questTitle }
                        end
                    else
                        local pct = text and text:match("(%d+)%%")
                        if pct then
                            cur, total = tonumber(pct), 100
                            if inQuestBlock then
                                return cur, total, text, questTitle
                            end
                            if not fallbackLine then
                                fallbackLine = { cur = cur, total = total, text = text, questTitle = questTitle }
                            end
                        end
                    end
                end
            end
        end
    end

    if fallbackLine then
        return fallbackLine.cur, fallbackLine.total, fallbackLine.text, fallbackLine.questTitle
    end

    return nil
end

local function SQOL_NameplateObjectives_GetObjectiveInfo(questID, objectiveIndex)
    if type(questID) ~= "number" or type(objectiveIndex) ~= "number" then
        return nil
    end

    local function try(fn)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, a, b, c, d, e = pcall(fn, questID, objectiveIndex, false)
        if not ok then
            return nil
        end
        if type(a) == "table" then
            return a
        end
        if a ~= nil then
            return {
                text = a,
                objectiveType = b,
                finished = c,
                numFulfilled = d,
                numRequired = e,
            }
        end
        return nil
    end

    local info = try(C_QuestLog and C_QuestLog.GetQuestObjectiveInfo)
    if not info and C_TaskQuest then
        info = try(C_TaskQuest.GetQuestObjectiveInfoByQuestID)
    end
    if not info and type(GetQuestObjectiveInfo) == "function" then
        info = try(GetQuestObjectiveInfo)
    end

    return info
end

local function SQOL_NameplateObjectives_GetProgressBarInfo(questID)
    if type(questID) ~= "number" then
        return nil
    end

    local function try(fn)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, a, b = pcall(fn, questID)
        if not ok then
            return nil
        end
        if type(a) == "table" then
            local cur = a.numFulfilled or a.progress or a.currentValue or a.value
            local total = a.numRequired or a.total or a.maxValue or a.max
            return cur, total
        end
        return a, b
    end

    local cur, total = try(C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo)
    if not cur then
        cur, total = try(C_QuestLog and C_QuestLog.GetQuestProgressBarInfo)
    end
    if not cur and type(GetQuestProgressBarInfo) == "function" then
        local ok, a, b = pcall(GetQuestProgressBarInfo, questID)
        if ok then
            cur, total = a, b
        end
    end

    -- Standard retail API for progress-bar objectives returns a single 0-100
    -- percentage. Treat it as cur/100 so quests like "Umbral Attuning Shard
    -- charged" report progress even when the *Info variants above are absent.
    if not (type(cur) == "number" and type(total) == "number" and total > 0)
        and type(GetQuestProgressBarPercent) == "function" then
        local ok, pct = pcall(GetQuestProgressBarPercent, questID)
        if ok and type(pct) == "number" and pct > 0 then
            cur, total = math.floor(pct + 0.5), 100
        end
    end

    if type(cur) == "number" and type(total) == "number" and total > 0 then
        return cur, total
    end

    return nil
end

local function SQOL_NameplateObjectives_GetProgressBarCandidate(questID)
    local cur, total = SQOL_NameplateObjectives_GetProgressBarInfo(questID)
    if type(cur) == "number" and type(total) == "number" and total > 0 then
        return {
            questID = questID,
            fulfilled = cur,
            required = total,
            text = nil,
            index = nil,
            priority = 4,
        }
    end

    return nil
end

SQOL._questProgressBarState = SQOL._questProgressBarState or {}
SQOL._questProgressBarScanPending = false

local function SQOL_GetQuestProgressBarLabel(questID)
    -- Progress-bar objective text often already carries the percentage, either
    -- as a leading "NN% " prefix or a trailing "(NN%)"/"NN%"; drop it so the
    -- percentage isn't printed twice once the count is appended.
    local function stripPercent(text)
        text = text:gsub("^%s*%d+%%%s*", "")
        text = text:gsub("%s*%(?%d+%%%)?%s*$", "")
        return text
    end

    if C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
        local objectives = SQOL.GetQuestObjectivesCached(questID)
        if type(objectives) == "table" then
            -- Prefer the progress-bar objective's own text; a quest can have
            -- several objectives and the bar rarely belongs to the first one.
            local fallback
            for _, obj in ipairs(objectives) do
                local text = type(obj) == "table" and rawget(obj, "text")
                if type(text) == "string" and text ~= "" then
                    if rawget(obj, "type") == "progressbar" then
                        return stripPercent(text)
                    end
                    fallback = fallback or text
                end
            end
            if fallback then
                return fallback
            end
        end
    end

    if C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end

    return nil
end

local function SQOL_CollectProgressBarQuestIDs()
    local questIDs = {}

    local function addQuestID(questID)
        if type(questID) == "number" and questID > 0 then
            questIDs[questID] = true
        end
    end

    if C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function"
        and type(C_QuestLog.GetInfo) == "function" then
        for _, info in ipairs(SQOL.GetQuestLogSnapshot()) do
            if info and not info.isHeader then
                addQuestID(info.questID)
            end
        end
    end

    if C_QuestLog and type(C_QuestLog.GetNumQuestWatches) == "function" then
        local ok, numWatches = pcall(C_QuestLog.GetNumQuestWatches)
        if ok and type(numWatches) == "number" then
            for i = 1, numWatches do
                if type(C_QuestLog.GetQuestIDForQuestWatchIndex) == "function" then
                    local idOk, questID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
                    if idOk then
                        addQuestID(questID)
                    end
                elseif type(C_QuestLog.GetQuestWatchInfo) == "function" then
                    local infoOk, a = pcall(C_QuestLog.GetQuestWatchInfo, i)
                    if infoOk then
                        if type(a) == "table" then
                            addQuestID(a.questID or a.questId)
                        else
                            addQuestID(a)
                        end
                    end
                end
            end
        end
    elseif type(GetNumQuestWatches) == "function" and type(GetQuestIndexForWatch) == "function"
        and C_QuestLog and type(C_QuestLog.GetInfo) == "function" then
        local ok, numWatches = pcall(GetNumQuestWatches)
        if ok and type(numWatches) == "number" then
            for i = 1, numWatches do
                local indexOk, questLogIndex = pcall(GetQuestIndexForWatch, i)
                if indexOk and type(questLogIndex) == "number" then
                    local infoOk, info = pcall(C_QuestLog.GetInfo, questLogIndex)
                    if infoOk and info then
                        addQuestID(info.questID)
                    end
                end
            end
        end
    end

    if C_Map and type(C_Map.GetBestMapForUnit) == "function"
        and C_TaskQuest and type(C_TaskQuest.GetQuestsOnMap) == "function" then
        local mapOk, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if mapOk and type(mapID) == "number" then
            local tasksOk, tasks = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
            if tasksOk and type(tasks) == "table" then
                for _, task in ipairs(tasks) do
                    if type(task) == "table" then
                        addQuestID(task.questID)
                    else
                        addQuestID(task)
                    end
                end
            end
        end
    end

    return questIDs
end

local function SQOL_ScanQuestProgressBars(showChanges)
    if not SQOL.DB or not SQOL.DB.ColorProgress or not C_QuestLog then
        return
    end

    local seen = {}
    for questID in pairs(SQOL_CollectProgressBarQuestIDs()) do
        local cur, total = SQOL_NameplateObjectives_GetProgressBarInfo(questID)
        if type(cur) == "number" and type(total) == "number" and total > 0 then
            seen[questID] = true

            local previous = SQOL._questProgressBarState[questID]
            local changed = previous and (previous.cur ~= cur or previous.total ~= total)
            local firstVisibleProgress = (not previous) and cur > 0 and cur < total
            local label = SQOL_GetQuestProgressBarLabel(questID)

            if showChanges and (changed or firstVisibleProgress) then
                local progress = SQOL_ShowProgressMessage(label, cur, total)
                if SQOL.DB.DebugTrack then
                    SQOL.dprint(string.format("Progress bar message: quest %d %s (%d/%d, %.2f)",
                        questID, label or "-", cur, total, progress or 0))
                end
            end

            SQOL._questProgressBarState[questID] = {
                cur = cur,
                total = total,
                label = label,
            }
        end
    end

    for questID in pairs(SQOL._questProgressBarState) do
        if not seen[questID] then
            SQOL._questProgressBarState[questID] = nil
        end
    end
    SQOL.RequestIncrementalGC()
end

function SQOL.ScheduleQuestProgressBarScan(showChanges)
    if SQOL._questProgressBarScanPending then return end
    SQOL._questProgressBarScanPending = true

    local function scan()
        SQOL._questProgressBarScanPending = false
        SQOL_ScanQuestProgressBars(showChanges)
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.2, scan)
    else
        scan()
    end
end

------------------------------------------------------------
-- Scenario progress bars (weighted-progress criteria, e.g. Void Incursion)
--
-- Scenarios live outside the quest system, so the quest scan above never sees
-- them. Their segmented progress bar is a "weighted progress" criterion read
-- via C_ScenarioInfo; we surface it through the same splash message as quests.
------------------------------------------------------------
SQOL._scenarioCriteriaState = SQOL._scenarioCriteriaState or {}
SQOL._scenarioScanPending = false

local function SQOL_IsInScenario()
    if C_Scenario and type(C_Scenario.IsInScenario) == "function" then
        local ok, active = pcall(C_Scenario.IsInScenario)
        if ok then
            return active and true or false
        end
    end
    -- Fallback: a valid current step implies an active scenario.
    if C_ScenarioInfo and type(C_ScenarioInfo.GetScenarioStepInfo) == "function" then
        local ok, info = pcall(C_ScenarioInfo.GetScenarioStepInfo)
        if ok and type(info) == "table" then
            return true
        end
    end
    return false
end

-- Reads a single weighted-progress scenario criterion. Returns cur, total,
-- description, key -- with cur/total normalized to a 0-100 percentage so the
-- splash message mirrors the on-screen bar (e.g. "Stillwhisper defended: 40%").
local function SQOL_GetScenarioCriterion(index)
    if not (C_ScenarioInfo and type(C_ScenarioInfo.GetCriteriaInfo) == "function") then
        return nil
    end
    local ok, info = pcall(C_ScenarioInfo.GetCriteriaInfo, index)
    if not ok or type(info) ~= "table" or not info.isWeightedProgress then
        return nil
    end

    if SQOL.DB and SQOL.DB.DebugTrack then
        SQOL.dprint(string.format(
            "Scenario criterion raw: idx=%d id=%s desc=%q qty=%s total=%s qtyStr=%q",
            index, tostring(info.criteriaID), tostring(info.description),
            tostring(info.quantity), tostring(info.totalQuantity),
            tostring(info.quantityString)))
    end

    -- For weighted-progress criteria the client already reports `quantity` as a
    -- 0-100 percentage -- the exact number Blizzard renders on the bar (e.g. a
    -- delve criterion with quantity=29 shows "29%", while totalQuantity=17 and
    -- quantityString="5%/17" are internal weights that do NOT map to the bar).
    -- Use quantity directly; only fall back to a leading percentage in
    -- quantityString when quantity is unavailable.
    local cur = tonumber(info.quantity)
    if type(cur) ~= "number" then
        local pct = type(info.quantityString) == "string" and info.quantityString:match("^(%d+)%%")
        cur = pct and tonumber(pct) or nil
    end
    if type(cur) ~= "number" then
        return nil
    end
    local total = 100

    local description = (type(info.description) == "string" and info.description ~= "")
        and info.description or nil
    local key = info.criteriaID or index

    return cur, total, description, key
end

local function SQOL_ScanScenarioProgress(showChanges)
    if not SQOL.DB or not SQOL.DB.ColorProgress then
        return
    end

    if not SQOL_IsInScenario() then
        if next(SQOL._scenarioCriteriaState) ~= nil then
            SQOL._scenarioCriteriaState = {}
        end
        return
    end

    local seen = {}
    -- Criteria indices are contiguous within a step; 20 is a safe upper bound.
    for index = 1, 20 do
        local cur, total, description, key = SQOL_GetScenarioCriterion(index)
        if cur and key then
            seen[key] = true

            local previous = SQOL._scenarioCriteriaState[key]
            local changed = previous and (previous.cur ~= cur or previous.total ~= total)
            local firstVisibleProgress = (not previous) and cur > 0 and cur < total

            if showChanges and (changed or firstVisibleProgress) then
                local progress = SQOL_ShowProgressMessage(description, cur, total)
                if SQOL.DB.DebugTrack then
                    SQOL.dprint(string.format("Scenario progress message: criterion %s %s (%d/%d, %.2f)",
                        tostring(key), description or "-", cur, total, progress or 0))
                end
            end

            SQOL._scenarioCriteriaState[key] = { cur = cur, total = total, label = description }
        end
    end

    for key in pairs(SQOL._scenarioCriteriaState) do
        if not seen[key] then
            SQOL._scenarioCriteriaState[key] = nil
        end
    end
    SQOL.RequestIncrementalGC()
end

function SQOL.ScheduleScenarioProgressScan(showChanges)
    if SQOL._scenarioScanPending then return end
    SQOL._scenarioScanPending = true

    local function scan()
        SQOL._scenarioScanPending = false
        SQOL_ScanScenarioProgress(showChanges)
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.2, scan)
    else
        scan()
    end
end

local function SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
    local questID, objectiveIndex

    if type(entry) == "number" then
        questID = entry
    elseif type(entry) == "table" then
        questID = entry.questID or entry.questId
        objectiveIndex = entry.objectiveIndex or entry.objectiveID or entry.objectiveId
        if not questID and type(entry.questLogIndex) == "number"
            and C_QuestLog and type(C_QuestLog.GetQuestIDForLogIndex) == "function" then
            questID = C_QuestLog.GetQuestIDForLogIndex(entry.questLogIndex)
        end
    end

    if type(questID) ~= "number" then questID = nil end
    if type(objectiveIndex) ~= "number" then objectiveIndex = nil end
    return questID, objectiveIndex
end

local function SQOL_NameplateObjectives_ExtractProgress(questID, objectiveIndex, obj)
    local text = nil
    if type(obj) == "table" then
        text = rawget(obj, "text")

        local numItems = rawget(obj, "numItems")
        local numRequired = rawget(obj, "numRequired")
        local numFulfilled = rawget(obj, "numFulfilled")

        local required = (type(numRequired) == "number" and numRequired)
                      or (type(numItems) == "number" and numItems)
                      or 0

        if required > 0 then
            local fulfilled = (type(numFulfilled) == "number" and numFulfilled) or 0
            return fulfilled, required, text
        end

        local cur, total = SQOL_NameplateObjectives_ParseProgressFromText(text)
        if cur then
            return cur, total, text
        end
    end

    local info = SQOL_NameplateObjectives_GetObjectiveInfo(questID, objectiveIndex)
    if info then
        text = text or rawget(info, "text")

        local numItems = rawget(info, "numItems")
        local numRequired = rawget(info, "numRequired")
        local numFulfilled = rawget(info, "numFulfilled")

        local required = (type(numRequired) == "number" and numRequired)
                      or (type(numItems) == "number" and numItems)
                      or 0

        if required > 0 then
            local fulfilled = (type(numFulfilled) == "number" and numFulfilled) or 0
            return fulfilled, required, text
        end

        local cur, total = SQOL_NameplateObjectives_ParseProgressFromText(text)
        if cur then
            return cur, total, text
        end
    end

    return nil
end

local function SQOL_NameplateObjectives_SelectObjective(questID, unitName, npcId, objectiveIndex)
    if not questID then return nil end

    local progressBarCandidate = SQOL_NameplateObjectives_GetProgressBarCandidate(questID)
    local objectives = SQOL.GetQuestObjectivesCached(questID)
    if not objectives then
        if progressBarCandidate then
            return progressBarCandidate
        end
        if objectiveIndex then
            local fulfilled, required, text = SQOL_NameplateObjectives_ExtractProgress(questID, objectiveIndex, nil)
            if required then
                return {
                    questID = questID,
                    fulfilled = fulfilled,
                    required = required,
                    text = text,
                    index = objectiveIndex,
                    priority = 3,
                }
            end
        end
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP objectives missing for quest:", questID, "objectiveIndex:", tostring(objectiveIndex))
        end
        return nil
    end

    local best, bestPriority, bestRequired
    local numericCount = 0
    local singleCandidate = nil

    for i, obj in ipairs(objectives) do
        local fulfilled, required, text = SQOL_NameplateObjectives_ExtractProgress(questID, i, obj)
        if required then
            local candidate = {
                questID = questID,
                fulfilled = fulfilled,
                required = required,
                text = text,
                index = i,
                priority = nil,
            }

            numericCount = numericCount + 1
            singleCandidate = candidate

            local priority
            if objectiveIndex and i == objectiveIndex then
                priority = 3
            elseif npcId then
                local objId = rawget(obj, "objectID") or rawget(obj, "objectId")
                if type(objId) == "number" and objId == npcId then
                    priority = 2
                end
            end

            if not priority and unitName and type(candidate.text) == "string" then
                local textLower = candidate.text:lower()
                local nameLower = unitName:lower()
                if textLower:find(nameLower, 1, true) then
                    priority = 1
                end
            end

            if priority then
                candidate.priority = priority
                if not best or priority > bestPriority or (priority == bestPriority and required > (bestRequired or 0)) then
                    best = candidate
                    bestPriority = priority
                    bestRequired = required
                end
            end
        end
    end

    if progressBarCandidate then
        return progressBarCandidate
    end

    if best then
        return best
    end

    if numericCount == 1 and singleCandidate then
        singleCandidate.priority = 0
        return singleCandidate
    end

    return nil
end

local function SQOL_NameplateObjectives_GetProgressText(unit)
    local entries = SQOL_NameplateObjectives_GetQuestEntries(unit)
    if type(entries) ~= "table" then
        local cur, total, line, questTitle = SQOL_NameplateObjectives_GetTooltipProgress(unit)
        if cur then
            if SQOL.DB and SQOL.DB.DebugTrack then
                SQOL.dprint("NP tooltip:", unit, "quest", tostring(questTitle), "line", tostring(line),
                    "progress", string.format("%d/%d", cur, total))
            end
            local text = SQOL_FormatProgressText(cur, total) or string.format("%d/%d", cur, total)
            if SQOL.DB and SQOL.DB.ColorProgress then
                local progress = (total > 0) and (cur / total) or 0
                local colorCode = SQOL_GetProgressColor(progress)
                text = colorCode .. text .. "|r"
            end
            return text
        end
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP tooltip:", unit, "no progress")
        end
        return nil
    end

    local unitName = UnitName(unit)
    local npcId = SQOL_NameplateObjectives_GetNpcID(unit)
    if SQOL.DB and SQOL.DB.DebugTrack then
        local count = 0
        local summaries = {}
        for _, entry in pairs(entries) do
            count = count + 1
            local questID, objectiveIndex = SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
            table.insert(summaries, string.format("%s:%s", tostring(questID), tostring(objectiveIndex or "-")))
        end
        SQOL.dprint("NP unit:", unit, "name:", tostring(unitName), "npcID:", tostring(npcId), "entries:", count,
            count > 0 and table.concat(summaries, ", ") or "none")
    end

    local best, bestPriority, bestRequired
    for _, entry in pairs(entries) do
        local questID, objectiveIndex = SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
        if questID then
            local candidate = SQOL_NameplateObjectives_SelectObjective(questID, unitName, npcId, objectiveIndex)
            if candidate then
                local priority = candidate.priority or 0
                if not best or priority > bestPriority or (priority == bestPriority and candidate.required > (bestRequired or 0)) then
                    best = candidate
                    bestPriority = priority
                    bestRequired = candidate.required
                end
            end
        end
    end

    if best then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP chosen:", "quest", tostring(best.questID), "obj", tostring(best.index),
                "progress", string.format("%d/%d", best.fulfilled or 0, best.required or 0),
                "priority", tostring(bestPriority), "text", tostring(best.text))
        end
    else
        for _, entry in pairs(entries) do
            local questID = SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
            if questID then
                local progressBarCandidate = SQOL_NameplateObjectives_GetProgressBarCandidate(questID)
                if progressBarCandidate then
                    if SQOL.DB and SQOL.DB.DebugTrack then
                        SQOL.dprint("NP progress bar:", "quest", tostring(questID),
                            "progress", string.format("%d/%d",
                                progressBarCandidate.fulfilled, progressBarCandidate.required))
                    end
                    best = progressBarCandidate
                    break
                end
            end
        end
        if not best and SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP no objective progress found for unit:", unit)
        end
    end

    if not best then
        local cur, total, line, questTitle = SQOL_NameplateObjectives_GetTooltipProgress(unit)
        if cur then
            if SQOL.DB and SQOL.DB.DebugTrack then
                SQOL.dprint("NP tooltip:", unit, "quest", tostring(questTitle), "line", tostring(line),
                    "progress", string.format("%d/%d", cur, total))
            end
            best = {
                questID = nil,
                fulfilled = cur,
                required = total,
                text = line,
                index = nil,
                priority = -2,
            }
        else
            if SQOL.DB and SQOL.DB.DebugTrack then
                SQOL.dprint("NP tooltip:", unit, "no progress")
            end
            return nil
        end
    end

    if type(best.required) == "number" and type(best.fulfilled) == "number" and best.required > 0 then
        if best.fulfilled >= best.required then
            return nil
        end
    end

    local text = SQOL_FormatProgressText(best.fulfilled or 0, best.required or 0)
        or string.format("%d/%d", best.fulfilled or 0, best.required or 0)
    if SQOL.DB and SQOL.DB.ColorProgress then
        local progress = (best.required and best.required > 0) and (best.fulfilled / best.required) or 0
        local colorCode = SQOL_GetProgressColor(progress)
        text = colorCode .. text .. "|r"
    end
    return text
end

local function SQOL_NameplateObjectives_GetUnitToken(nameplate)
    if not nameplate then
        return nil
    end

    local unit = rawget(nameplate, "namePlateUnitToken")
    if unit then
        return unit
    end

    local unitFrame = nameplate.UnitFrame or nameplate.unitFrame
    unit = unitFrame and unitFrame.unit
    return unit
end

local function SQOL_NameplateObjectives_GetAnchor(nameplate)
    if not nameplate then
        return nil
    end

    local unitFrame = nameplate.UnitFrame or nameplate.unitFrame or nameplate
    if not unitFrame then
        return nameplate
    end

    local healthBar = rawget(unitFrame, "healthBar")
        or rawget(unitFrame, "HealthBar")
        or rawget(unitFrame, "HealthBarsContainer")
    if healthBar then
        return healthBar
    end

    local nameText = rawget(unitFrame, "name")
        or rawget(unitFrame, "Name")
        or rawget(unitFrame, "nameText")
        or rawget(unitFrame, "NameText")
        or rawget(unitFrame, "nameplateName")
        or rawget(unitFrame, "NamePlateName")
        or rawget(unitFrame, "UnitName")
        or rawget(unitFrame, "NameLabel")
        or rawget(unitFrame, "nameLabel")

    if nameText and nameText.GetStringWidth then
        return nameText
    end

    return unitFrame
end

local function SQOL_NameplateObjectives_GetText(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil
    end

    local ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP GetNamePlateForUnit error:", nameplate)
        end
        return nil
    end
    if not nameplate then
        return nil
    end

    local text = nameplate.SQOLObjectiveText
    if not text then
---@diagnostic disable-next-line: undefined-field
        local unitFrame = nameplate.UnitFrame or nameplate.unitFrame or nameplate
        local anchor = SQOL_NameplateObjectives_GetAnchor(nameplate) or unitFrame

        text = unitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("BOTTOM", anchor, "TOP", 0, 15)
        text:SetJustifyH("CENTER")
        text:SetWordWrap(false)
        if text.SetMaxLines then text:SetMaxLines(1) end
---@diagnostic disable-next-line: inject-field
        nameplate.SQOLObjectiveText = text
    else
---@diagnostic disable-next-line: undefined-field
        local unitFrame = nameplate.UnitFrame or nameplate.unitFrame or nameplate
        local anchor = SQOL_NameplateObjectives_GetAnchor(nameplate) or unitFrame
        text:ClearAllPoints()
        text:SetPoint("BOTTOM", anchor, "TOP", 0, 15)
    end

    return text, nameplate
end

function SQOL.NameplateObjectives_UpdateUnit(unit)
    if not SQOL.DB or not SQOL.DB.ShowNameplateObjectives then
        return
    end
    if not unit or not UnitExists(unit) then
        return
    end

    local okText, text, nameplate = SQOL_NameplateObjectives_SafeCall(SQOL_NameplateObjectives_GetText, unit)
    if not okText or not text then
        return
    end

    local okProgress, progressText = SQOL_NameplateObjectives_SafeCall(SQOL_NameplateObjectives_GetProgressText, unit)
    if not okProgress then
        return
    end
    if progressText then
        text:SetText(progressText)
        text:Show()
    else
        text:SetText("")
        text:Hide()
    end

    SQOL._npUnits[unit] = nameplate
end

function SQOL.NameplateObjectives_ClearUnit(unit)
    local nameplate = SQOL._npUnits[unit]
    if not nameplate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    end

    if nameplate and nameplate.SQOLObjectiveText then
        nameplate.SQOLObjectiveText:SetText("")
        nameplate.SQOLObjectiveText:Hide()
    end

    SQOL._npUnits[unit] = nil
end

local function SQOL_NameplateObjectives_UpdateAll()
    if not SQOL.DB or not SQOL.DB.ShowNameplateObjectives then
        return
    end

    for unit in pairs(SQOL._npUnits) do
        SQOL.NameplateObjectives_UpdateUnit(unit)
    end
    SQOL.RequestIncrementalGC()
end

function SQOL.NameplateObjectives_ScheduleUpdateAll()
    if SQOL._npUpdatePending then return end
    SQOL._npUpdatePending = true

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(SQOL_NAMEPLATE_UPDATE_DELAY, function()
            SQOL._npUpdatePending = false
            SQOL_NameplateObjectives_UpdateAll()
        end)
    else
        SQOL._npUpdatePending = false
        SQOL_NameplateObjectives_UpdateAll()
    end
end

function SQOL.NameplateObjectives_RefreshVisibleUnits()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return
    end

    for unit in pairs(SQOL._npUnits) do
        SQOL._npUnits[unit] = nil
    end

    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok then
        if SQOL.DB and SQOL.DB.DebugTrack then
            SQOL.dprint("NP GetNamePlates error:", plates)
        end
        return
    end
    if type(plates) ~= "table" then
        return
    end

    for _, nameplate in ipairs(plates) do
        local unit = SQOL_NameplateObjectives_GetUnitToken(nameplate)
        if unit then
            SQOL._npUnits[unit] = nameplate
            SQOL.NameplateObjectives_UpdateUnit(unit)
        end
    end
end

function SQOL.NameplateObjectives_HideAll()
    for unit, nameplate in pairs(SQOL._npUnits) do
        if nameplate and nameplate.SQOLObjectiveText then
            nameplate.SQOLObjectiveText:SetText("")
            nameplate.SQOLObjectiveText:Hide()
        end
        SQOL._npUnits[unit] = nil
    end
end

------------------------------------------------------------
-- Custom colored UI_INFO_MESSAGE (Retail-safe)
------------------------------------------------------------
function SQOL.EnableCustomInfoMessages()
    if UIErrorsFrame and UIErrorsFrame.UnregisterEvent then
        UIErrorsFrame:UnregisterEvent("UI_INFO_MESSAGE")
        SQOL.dprint("Disabled Blizzard UI_INFO_MESSAGE display.")
    end

    SQOL_EnsureProgressMessageFrame()

    if not SQOL.InfoEventFrame then
        SQOL.InfoEventFrame = CreateFrame("Frame", "SQOL_InfoEventFrame")
        SQOL.InfoEventFrame:RegisterEvent("UI_INFO_MESSAGE")
        SQOL.InfoEventFrame:SetScript("OnEvent", function(_, event, messageType, message)
            if event ~= "UI_INFO_MESSAGE" or not SQOL.DB.ColorProgress then return end
            if type(message) ~= "string" then return end

            local label, cur, total = SQOL_ParseProgressMessage(message)
            if not (cur and total) then
                -- Keep Blizzard's standard UI_INFO_MESSAGE colors (e.g. discoveries are yellow).
                local r, g, b = 1, 0.82, 0
                if type(GetGameMessageInfo) == "function" then
                    local rr, gg, bb = GetGameMessageInfo(messageType)
                    if type(rr) == "number" and type(gg) == "number" and type(bb) == "number" then
                        r, g, b = rr, gg, bb
                    end
                end

                SQOL_AddProgressFrameMessage(message, r, g, b)
                return
            end

            local progress = SQOL_ShowProgressMessage(label, cur, total)

            if SQOL.DB.DebugTrack then
                SQOL.dprint(string.format("Custom UI_INFO_MESSAGE: %s (%d/%d, %.2f)",
                    label or "-", cur or -1, total or -1, progress))
            end
        end)
    end
end

