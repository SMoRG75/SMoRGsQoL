-- Run from the repository root: lua tests/radar.lua
-- Uses the real cache, parser and nameplate lifecycle with mocked client data.
local pending, tooltipCalls = {}, 0
local function widget()
    local w = { shown = false }
    function w:SetText(value) self.text = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:CreateFontString() return widget() end
    for _, method in ipairs({ "SetJustifyH", "SetWordWrap", "SetMaxLines", "ClearAllPoints", "SetPoint" }) do
        w[method] = function() end
    end
    return w
end
function UnitExists() return true end
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
Enum = { TooltipDataLineType = { None = 0, UnitName = 2, UnitThreat = 7,
    QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 } }
local types = Enum.TooltipDataLineType
local snapshot, objectives, tooltip, plates = {}, {}, {}, {}
local secret = setmetatable({}, { __index = function() error("Read secret table") end,
    __tostring = function() error("Converted secret value") end })
function canaccessvalue(value) return value ~= secret end
function canaccesstable(value) return value ~= secret end
C_QuestLog = {
    GetNumQuestLogEntries = function() return #snapshot end,
    GetInfo = function(index) return snapshot[index] end,
    GetQuestObjectives = function(id) return objectives[id] end,
}
C_TooltipInfo = { GetUnit = function()
    tooltipCalls = tooltipCalls + 1
    return tooltip
end }
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
    GetNamePlates = function()
        local list = {}
        for _, plate in pairs(plates) do list[#list + 1] = plate end
        return list
    end,
}
local sqol = {}
for _, file in ipairs({ "Locales/Locales.lua", "Core.lua", "QuestProgress.lua", "QuestRadar.lua" }) do
    assert(loadfile(file))("SMoRGsQoL", sqol)
end
sqol.DB = { SmartQuestRadar = true }
sqol.RequestIncrementalGC = function() end
local function line(kind, text) return { type = kind, leftText = text } end
local function quest(title, ...)
    local result = { line(types.QuestTitle, title) }
    for _, text in ipairs({...}) do result[#result + 1] = line(types.QuestObjective, text) end
    return result
end
local function prepare(rows, log, own)
    tooltip = { lines = rows, dataInstanceID = 42 }
    snapshot = log or { { questID = 100, title = "Wolf Hunt" } }
    objectives = own or { [100] = { { text = "Wolves: 2/8", finished = false } } }
    sqol.InvalidateQuestDataCache()
end
local function text()
    local result = sqol.QuestRadar_GetProgressText("nameplate1")
    return result and result:gsub("|T.-|t ", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
prepare(quest("Wolf Hunt", "Wolves: 2/8", "Pelts: 1/5"))
equal(text(), "2/8  ·  1/5", "Multiple objectives on the same unit")
sqol.DB.SmartQuestRadar = false
local callsBefore = tooltipCalls
equal(text(), nil, "Disabled")
equal(tooltipCalls, callsBefore, "Disabled radar does not request tooltips")
sqol.DB.SmartQuestRadar = true
prepare(quest("Not in my log", "Wolves: 2/8"))
equal(text(), nil, "Only active player quests")
prepare({ line(types.UnitThreat, "Threat: 1/100"), line(types.UnitName, "Wolf") })
equal(text(), nil, "Threat and names are not quest evidence")
prepare(quest("Wolf Hunt", "Wolves: 8/8", "Progress: 100%", "Invalid: 1/0"))
equal(text(), nil, "Completed and invalid counters are hidden")
prepare(quest("Wolf Hunt", "Progress: 0%", "Wolves: 0/8"))
equal(text(), "0%  ·  0/8", "Zero progress is valid")
prepare({ line(types.QuestTitle, "Wolf Hunt"),
    { type = types.QuestObjective, leftText = "Wolves slain", rightText = "2/8" } })
equal(text(), "2/8", "Typed objective counter in the right column")
prepare({ line(types.QuestTitle, "Wolf Hunt"),
    { type = types.QuestObjective, leftText = "Wolves: 2/8", completed = true } })
equal(text(), nil, "Explicit completion overrides an unfinished counter")
prepare({ line(types.QuestTitle, "Wolf Hunt"),
    { type = types.QuestObjective, leftText = "Speak to the scout", completed = false } }, nil, {})
equal(text(), "Quest objective", "Typed unfinished state without cached objective text")
prepare({ line(types.QuestTitle, "Wolf Hunt"),
    { type = types.QuestObjective, leftText = "Wolves: 2/8", completed = secret } })
equal(text(), nil, "Secret completion state is skipped")
prepare(quest("Wolf Hunt", "Wolves: 2/8", "Wolves: 2/8", "Pelts: 1/5", "Tags: 2/9", "Marks: 3/7"))
equal(text(), "2/8  ·  1/5  ·  2/9  ·  +1", "Deduplicate and cap visible objectives")
prepare({ line(types.QuestTitle, "Wolf Hunt"), line(types.QuestObjective, "Wolves: 2/8"),
    line(types.QuestPlayer, "Friend"), line(types.QuestObjective, "Wolves: 1/8"),
    line(types.QuestTitle, "Pelts"), line(types.QuestObjective, "Pelts: 3/5") },
    { { questID = 100, title = "Wolf Hunt" }, { questID = 200, title = "Pelts" } })
equal(text(), "2/8  ·  3/5", "Skip party progress and resume at the next quest")
prepare(quest("Wolf Hunt", "Speak to the scout"), nil,
    { [100] = { { text = "Speak to the scout", finished = false } } })
equal(text(), "Quest objective", "Confirmed unfinished non-numeric objective")
objectives[100][1].finished = true
sqol.InvalidateQuestDataCache()
equal(text(), nil, "Finished non-numeric objective")
prepare(quest("Wolf Hunt", "Unknown status"))
equal(text(), nil, "No guessed completion state")
prepare({ line(nil, "Wolf Hunt"), line(nil, "Wolves: 2/8"), line(nil, "Threat: 1/100") })
equal(text(), "2/8", "Text-only client requires an exact own-objective match")
local savedTypes = Enum.TooltipDataLineType
Enum.TooltipDataLineType = nil
equal(text(), "2/8", "Client without tooltip line enums")
Enum.TooltipDataLineType = savedTypes
prepare(quest("|cffffff00Wolf Hunt|r", "Wolves: 2/8"))
equal(text(), "2/8", "Colored quest titles")
prepare(quest("Wolf Hunt", "Wolves: 2/8"), {
    { questID = 100, title = "Wolf Hunt" }, { questID = 101, title = "Wolf Hunt" } })
equal(text(), nil, "Ambiguous quest titles")
prepare(quest("Wolf Hunt", "Wolves: 2/8"))
snapshot = {}
sqol.InvalidateQuestDataCache()
equal(text(), nil, "Abandoned or turned-in quest disappears")

-- Restrictions may apply to the entire tooltip, its lines, or individual fields.
for _, data in ipairs({ secret, { lines = secret }, { lines = { secret } },
    { lines = { line(types.QuestTitle, secret), line(types.QuestObjective, "Wolves: 2/8") } },
    { lines = { line(types.QuestTitle, "Wolf Hunt"), line(types.QuestObjective, secret) } } }) do
    prepare({})
    tooltip = data
    equal(text(), nil, "Unreadable data is skipped")
end
prepare({ line(types.QuestTitle, "Wolf Hunt"), line(types.QuestObjective, "Wolves: 2/8"),
    line(types.QuestTitle, secret), line(types.QuestObjective, "Other: 1/5") })
equal(text(), "2/8", "Unreadable next title ends the previous quest block")

-- Shared UI: radar wins over old counts, recycled plates lose stale text, and
-- pending callbacks cannot redisplay text after disabling both options.
prepare(quest("Wolf Hunt", "Wolves: 2/8"))
plates.nameplate1 = { namePlateUnitToken = "nameplate1", UnitFrame = widget() }
sqol.NameplateObjectives_RefreshVisibleUnits()
local label = plates.nameplate1.SQOLObjectiveText
assert(label.shown and label.text:find("ActiveQuestIcon", 1, true), "Quest icon on visible plate")
sqol.DB.ColorProgress = true
sqol.NameplateObjectives_UpdateUnit("nameplate1")
assert(label.text:find("|c", 1, true), "Existing progress colors work")
sqol.DB.ShowNameplateObjectives = true
sqol.NameplateObjectives_UpdateUnit("nameplate1")
assert(label.text:find("ActiveQuestIcon", 1, true), "Radar replaces rather than duplicates old counts")
sqol.DB.SmartQuestRadar = false
function UnitName() return "Wolf" end
C_QuestLog.GetQuestsForNamePlate = function() return { 100 } end
sqol.NameplateObjectives_UpdateUnit("nameplate1")
assert(label.shown and label.text:find("2/8", 1, true)
    and not label.text:find("ActiveQuestIcon", 1, true), "Disabling radar restores old counts")
sqol.DB.SmartQuestRadar = true
local getUnit = C_TooltipInfo.GetUnit
C_TooltipInfo.GetUnit = function() error("Restricted API") end
sqol.NameplateObjectives_UpdateUnit("nameplate1")
assert(not label.shown and label.text == "", "API failure clears stale text")
C_TooltipInfo.GetUnit = getUnit
sqol.NameplateObjectives_UpdateUnit("nameplate1")
sqol.QuestRadar_OnTooltipDataUpdate(999)
equal(#pending, 0, "Ignore unrelated tooltip updates")
sqol.QuestRadar_OnTooltipDataUpdate(42)
sqol.QuestRadar_OnTooltipDataUpdate(42)
equal(#pending, 1, "Tooltip bursts share one refresh")
local callback = table.remove(pending, 1)
tooltip.lines = quest("Wolf Hunt", "Wolves: 3/8")
callback()
assert(label.text:find("3/8", 1, true), "Deferred tooltip refresh")
sqol.NameplateObjectives_ClearUnit("nameplate1")
assert(not label.shown and not sqol._npUnits.nameplate1, "Removed plate cleared")
sqol.QuestRadar_OnTooltipDataUpdate(42)
equal(#pending, 0, "Removed plate no longer tracks tooltip updates")
sqol.NameplateObjectives_RefreshVisibleUnits()
assert(label.shown, "Visible plates refresh after enabling")
sqol.NameplateObjectives_ScheduleUpdateAll()
sqol.DB.SmartQuestRadar, sqol.DB.ShowNameplateObjectives = false, false
sqol.NameplateObjectives_HideAll()
table.remove(pending, 1)()
assert(not label.shown, "Pending update respects disable")
sqol.DB.SmartQuestRadar = true
sqol.NameplateObjectives_RefreshVisibleUnits()
tooltip.lines = quest("Not in my log", "Other: 2/8")
sqol.NameplateObjectives_UpdateUnit("nameplate1")
assert(not label.shown, "Recycled plate does not retain previous unit progress")
tooltip.lines = quest("Wolf Hunt", "Wolves: 2/8")
sqol.NameplateObjectives_UpdateUnit("nameplate1")
plates = {}
sqol.NameplateObjectives_RefreshVisibleUnits()
assert(not label.shown, "Refresh hides plates no longer enumerated")
C_TooltipInfo = nil
equal(text(), nil, "Missing tooltip API")
print("PASS: radar relevance, multiple objectives, completion, party data, text-only fallback, secrets and nameplate lifecycle")
