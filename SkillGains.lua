local _, SQOL = ...
local L = SQOL.L

------------------------------------------------------------
-- Floating skill gains: "+1 Staves (18/20)" in the same floating labels as
-- reputation gains. Driven by Blizzard's skill-up chat line, so skill caps
-- rising (training, levelling) never show up as gains.
------------------------------------------------------------
local lastRank = {}

-- enUS fallback for clients without the SKILL_RANK_UP template.
local FALLBACK_PATTERN = { pattern = "^Your skill in (.-) has increased to ([%d,%.]+)", kinds = { "s", "d" } }

local patterns
local function getPatterns()
    if patterns then return patterns end
    patterns = {}
    local template = rawget(_G, "SKILL_RANK_UP")
    if SQOL.CanUseValue(template) and type(template) == "string" and SQOL.Chat_TemplateToPattern then
        local pattern, kinds = SQOL.Chat_TemplateToPattern(template)
        if pattern then patterns[#patterns + 1] = { pattern = pattern, kinds = kinds } end
    end
    patterns[#patterns + 1] = FALLBACK_PATTERN
    return patterns
end

-- Returns skill name and new rank for a skill-up chat line.
function SQOL.Skill_ParseMessage(msg)
    if not SQOL.CanUseValue(msg) or type(msg) ~= "string" then return nil end
    local ok, name, rank = pcall(function()
        local text = SQOL.Chat_StripCodes and SQOL.Chat_StripCodes(msg) or msg
        for _, entry in ipairs(getPatterns()) do
            local captures = { string.match(text, entry.pattern) }
            if captures[1] then
                local skill, value
                for i, kind in ipairs(entry.kinds) do
                    if kind == "s" and not skill then
                        skill = captures[i]
                    elseif kind == "d" and not value then
                        value = tonumber((string.gsub(captures[i], "[,%.]", "")))
                    end
                end
                if skill and value then
                    skill = string.match(skill, "^%s*(.-)%s*$")
                    if skill ~= "" then return skill, value end
                end
            end
        end
    end)
    if ok and SQOL.CanUseValue(name) and SQOL.CanUseValue(rank) then
        return name, rank
    end
end

function SQOL.Skill_ResetPatterns()
    patterns = nil
end

local function usableNumber(value)
    return SQOL.CanUseValue(value) and type(value) == "number" and value == value and value > 0
end

-- The skill's cap, when the client can tell: C_SkillInfo in WoW Forever
-- (weapon skills on the Mainline engine), the skill list in Classic, the
-- profession list in Retail. Nil otherwise.
local function findMaxRank(name)
    local ok, maxRank = pcall(function()
        local skillInfo = rawget(_G, "C_SkillInfo")
        if type(skillInfo) == "table" and type(skillInfo.GetNumSkillLines) == "function"
            and type(skillInfo.GetSkillLineInfo) == "function" then
            for i = 1, skillInfo.GetNumSkillLines() or 0 do
                local info = skillInfo.GetSkillLineInfo(i)
                if type(info) == "table" and not info.isHeader and info.name == name then
                    return info.maxRank
                end
            end
        end
        local numLines, lineInfo = rawget(_G, "GetNumSkillLines"), rawget(_G, "GetSkillLineInfo")
        if type(numLines) == "function" and type(lineInfo) == "function" then
            for i = 1, numLines() or 0 do
                local skill, isHeader, _, _, _, _, skillMax = lineInfo(i)
                if not isHeader and skill == name then return skillMax end
            end
        end
        local professions, professionInfo = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
        if type(professions) == "function" and type(professionInfo) == "function" then
            for _, index in ipairs({ professions() }) do
                if index then
                    local skill, _, _, skillMax, _, _, _, _, _, _, lineName = professionInfo(index)
                    if skill == name or lineName == name then return skillMax end
                end
            end
        end
    end)
    if ok and usableNumber(maxRank) then return maxRank end
end

function SQOL.SkillGains_Show(name, rank, maxRank, amount)
    local text
    if maxRank and maxRank >= rank then
        text = string.format(L["+%d %s (%d/%d)"], amount or 1, name, rank, maxRank)
    else
        text = string.format(L["+%d %s (%d)"], amount or 1, name, rank)
    end
    SQOL.FloatingGains_Show("skill", text, 0.45, 0.7, 1)
end

function SQOL.SkillGains_Hide()
    SQOL.FloatingGains_Hide("skill")
end

function SQOL.SkillGains_HandleMessage(msg)
    if not SQOL.DB or not SQOL.DB.ShowSkillGains then return end
    local name, rank = SQOL.Skill_ParseMessage(msg)
    if not name or not usableNumber(rank) then return end
    -- The chat line only carries the new rank; one line is normally one point.
    local previous = lastRank[name]
    local amount = (previous and rank > previous) and (rank - previous) or 1
    lastRank[name] = rank
    SQOL.SkillGains_Show(name, rank, findMaxRank(name), amount)
end
