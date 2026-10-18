local _, SQOL = ...
local L = SQOL.L

-- Only inspect visible nameplates through Blizzard's unit tooltip. Never infer
-- quest relevance from unit names, GUIDs, combat state or arbitrary counters.
local MAX_VISIBLE = 3
local QUEST_ICON = "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12:0:0|t "
local cachedSnapshot, activeTitles
local tooltipIDs = {}

local function readable(value)
    return SQOL.CanUseValue(value)
end

local function accessibleTable(value)
    if not readable(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) == "function" then
        local ok, allowed = pcall(canaccesstable, value)
        if not ok or not allowed then return false end
    end
    return true
end

local function field(value, key)
    if not accessibleTable(value) then return nil end
    local result = rawget(value, key)
    if readable(result) then return result, true end
    return nil, false
end

local function plain(text)
    if not readable(text) or type(text) ~= "string" then return nil end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
end

local function positiveID(value)
    return readable(value) and type(value) == "number" and value > 0
end

local function titlesForSnapshot()
    local snapshot = SQOL.GetQuestLogSnapshot()
    if not accessibleTable(snapshot) then return {} end
    if snapshot == cachedSnapshot then return activeTitles end
    cachedSnapshot, activeTitles = snapshot, {}
    for _, info in ipairs(snapshot) do
        local title = plain(field(info, "title"))
        local questID = field(info, "questID")
        if title and title ~= "" and positiveID(questID) and not field(info, "isHeader") then
            -- Ambiguous titles cannot establish which of our quests is relevant.
            if activeTitles[title] then
                activeTitles[title] = false
            elseif activeTitles[title] == nil then
                activeTitles[title] = questID
            end
        end
    end
    return activeTitles
end

local function progress(text)
    local current, total = text:match("(%d+)%s*/%s*(%d+)")
    if current then
        current, total = tonumber(current), tonumber(total)
        if total > 0 and current < total then return current, total, false end
        return nil
    end
    local percent = text:match("(%d+)%s*%%")
    if percent then
        percent = tonumber(percent)
        if percent < 100 then return percent, 100, true end
    end
end

local function hasCounter(text)
    return text and (text:find("%d+%s*/%s*%d+") or text:find("%d+%s*%%"))
end

-- A text-only client needs an exact match with our own objective text. Yellow
-- text alone, party members' counters and threat percentages are not evidence.
local function ownObjective(questID, text)
    local objectives = SQOL.GetQuestObjectivesCached(questID)
    if not accessibleTable(objectives) then return nil end
    for index, objective in ipairs(objectives) do
        if plain(field(objective, "text")) == text then
            local finished = field(objective, "finished")
            if finished == false then return objective, index end
            return nil
        end
    end
end

function SQOL.QuestRadar_GetProgressText(unit)
    tooltipIDs[unit] = nil
    if not SQOL.DB or not SQOL.DB.SmartQuestRadar then return nil end
    if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok then return nil end
    local lines = field(data, "lines")
    if not accessibleTable(lines) then return nil end
    local instanceID = field(data, "dataInstanceID")
    if positiveID(instanceID) then tooltipIDs[unit] = instanceID end

    local titles = titlesForSnapshot()
    local types = Enum and Enum.TooltipDataLineType or {}
    local titleType, objectiveType, playerType = types.QuestTitle, types.QuestObjective, types.QuestPlayer
    local questID, partySection
    local labels, seen, count = {}, {}, 0
    for _, line in ipairs(lines) do
        local lineType = field(line, "type")
        local text = plain(field(line, "leftText"))
        local untyped = lineType == nil or lineType == types.None
        if (titleType and lineType == titleType) or (text and untyped and titles[text]) then
            questID, partySection = titles[text], false
        elseif playerType and lineType == playerType then
            partySection = true
        elseif questID and not partySection and text and text ~= "" then
            local typedObjective = objectiveType and lineType == objectiveType
            local completed, completionReadable = field(line, "completed")
            local objective, index
            if untyped or typedObjective then objective, index = ownObjective(questID, text) end
            if (typedObjective or objective) and completionReadable and completed ~= true then
                local counterText = text
                local rightText = plain(field(line, "rightText"))
                if typedObjective and not hasCounter(text) and hasCounter(rightText) then counterText = rightText end
                local current, total, percent = progress(counterText)
                -- Non-numeric objectives need an explicit unfinished state from
                -- the typed tooltip line or our own quest log (e.g. speak to an NPC).
                local label
                if current then
                    label = percent and string.format("%d%%", current)
                        or string.format("%d/%d", current, total)
                    if SQOL.DB.ColorProgress then
                        label = SQOL.GetProgressColor(current / total) .. label .. "|r"
                    end
                elseif (objective or (typedObjective and completed == false)) and not hasCounter(counterText) then
                    label = L["Quest objective"]
                end
                local key = tostring(questID) .. ":" .. tostring(index or (text .. ":" .. counterText))
                if label and not seen[key] then
                    seen[key] = true
                    count = count + 1
                    if count <= MAX_VISIBLE then labels[#labels + 1] = label end
                end
            end
        end
    end
    if count == 0 then return nil end
    if count > MAX_VISIBLE then labels[#labels + 1] = "+" .. (count - MAX_VISIBLE) end
    return QUEST_ICON .. table.concat(labels, "  ·  ")
end

function SQOL.QuestRadar_ClearUnit(unit)
    tooltipIDs[unit] = nil
end

function SQOL.QuestRadar_OnTooltipDataUpdate(instanceID)
    if not positiveID(instanceID) then return end
    for _, trackedID in pairs(tooltipIDs) do
        if trackedID == instanceID then
            SQOL.NameplateObjectives_ScheduleUpdateAll()
            return
        end
    end
end
