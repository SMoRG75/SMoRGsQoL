-- Classic Era load test. Run from the repository root: lua tests/classic.lua
-- Mocks a Classic Era client (no Retail-only events, frames or quest APIs) and
-- checks that the addon loads, hides what Classic lacks and plays quest sounds.
local frames, pending, messages, sounds = {}, {}, {}, {}

-- Registering an event the client doesn't know errors, like in-game.
local missingEvents = {}
for _, event in ipairs({ 'EDIT_MODE_LAYOUTS_UPDATED', 'PLAYER_AVG_ITEM_LEVEL_UPDATE',
    'QUEST_POI_UPDATE', 'QUEST_CRITERIA_UPDATE', 'SCENARIO_CRITERIA_UPDATE',
    'QUEST_REMOVED', 'QUEST_TURNED_IN', 'TOOLTIP_DATA_UPDATE', 'QUEST_AUTOCOMPLETE',
    'LFG_PROPOSAL_SHOW', 'LFG_PROPOSAL_DONE', 'LFG_PROPOSAL_FAILED', 'LFG_PROPOSAL_SUCCEEDED' }) do
    missingEvents[event] = true
end

local function widget()
    local w = { scripts = {}, events = {}, shown = false }
    function w:RegisterEvent(event)
        if missingEvents[event] then error('Attempt to register unknown event "' .. event .. '"') end
        self.events[event] = true
    end
    function w:UnregisterEvent(event) self.events[event] = nil end
    function w:SetScript(event, fn) self.scripts[event] = fn end
    function w:HookScript(event, fn) self.scripts[event] = fn end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown end
    function w:SetShown(value) self.shown = value end
    function w:SetText(text) self.text = text end
    function w:GetText() return self.text end
    function w:SetFormattedText(...) self.text = string.format(...) end
    function w:SetFont(font, size, flags) self.font, self.size, self.flags = font, size, flags end
    function w:GetFont() return self.font or 'font.ttf', self.size or 12, self.flags or '' end
    function w:CreateFontString() return widget() end
    function w:CreateTexture() return widget() end
    function w:GetEffectiveScale() return 1 end
    function w:GetCenter() return 100, 100 end
    function w:SetChecked(value) self.checked = value end
    function w:GetChecked() return self.checked end
    function w:GetStringWidth() return 100 end
    function w:GetPoint() return 'CENTER', nil, 'CENTER', 0, 0 end
    for _, method in ipairs({ 'SetSize', 'SetPoint', 'ClearAllPoints', 'SetWidth',
        'SetFrameStrata', 'SetJustifyH', 'SetWordWrap', 'SetMaxLines', 'SetTextColor',
        'SetTexture', 'SetBlendMode', 'SetAlpha', 'SetAllPoints', 'EnableMouse', 'SetVertexColor',
        'SetFading', 'SetTimeVisible', 'SetFadeDuration', 'SetInsertMode', 'SetSpacing',
        'AddMessage', 'SetToplevel', 'SetClampedToScreen', 'SetMovable', 'RegisterForDrag',
        'StartMoving', 'StopMovingOrSizing', 'SetHitRectInsets', 'SetFontObject', 'SetColorTexture',
        'SetHeight', 'SetOwner', 'SetTexCoord', 'SetShadowOffset', 'AddLine',
        'SetBackdrop', 'SetBackdropColor', 'SetBackdropBorderColor', 'SetAutoFocus',
        'SetBlinkSpeed', 'EnableKeyboard', 'HighlightText', 'SetFocus', 'ClearFocus', 'SetFrameLevel' }) do
        w[method] = function() end
    end
    function w:IsMouseOver() return false end
    return w
end
function CreateFrame(_, name)
    local frame = widget()
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

-- Classic Era client identity.
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_ID = WOW_PROJECT_CLASSIC
function GetBuildInfo() return '1.15.9', '1', 'Jul 21 2026', 11509 end

UIParent = widget()
PlayerFrame = widget()
PlayerFrame:Show()
GameTooltip = widget()
function GameTooltip:NumLines() return 0 end
SlashCmdList = {}
UISpecialFrames = {}
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
C_AddOns = { IsAddOnLoaded = function() return false end, LoadAddOn = function() end,
    GetAddOnMetadata = function() return 'test' end,
    -- Classic Era ships Blizzard_AchievementUI even though it has no achievements.
    DoesAddOnExist = function() return true end }
function GetTime() return 100 end
function GetUnitSpeed() return 7 end
function GetAverageItemLevel() return 40, 40 end
function GetCursorPosition() return 100, 100 end
function InCombatLockdown() return false end
function UnitExists() return false end
function hooksecurefunc() end
function print(...) messages[#messages + 1] = table.concat({...}, ' ') end
function PlaySound(id) sounds[#sounds + 1] = id end
function PlaySoundFile(file) sounds[#sounds + 1] = file end
local fakeLibs = {
    ['LibDataBroker-1.1'] = { NewDataObject = function(_, _, obj) return obj end },
    ['LibDBIcon-1.0'] = { IsRegistered = function() return false end, Register = function() end,
        Refresh = function() end, Show = function() end, Hide = function() end },
}
LibStub = setmetatable({}, { __call = function(_, name) return fakeLibs[name] end })

-- Classic Era quest log: GetQuestLogTitle plus C_QuestLog.GetQuestObjectives only.
local questLog = {
    { title = 'Elwynn Forest', isHeader = true },
    { title = 'Wolves Across the Border', questID = 33 },
}
local objectives = {
    [33] = {
        { text = 'Diseased Timber Wolf slain: 7/8', finished = false },
        { text = 'Tough Wolf Meat: 8/8', finished = true },
    },
}
function GetNumQuestLogEntries() return #questLog end
function GetQuestLogTitle(index)
    local q = questLog[index]
    if not q then return nil end
    return q.title, 10, 0, q.isHeader, false, nil, 0, q.questID or 0
end
C_QuestLog = { GetQuestObjectives = function(id) return objectives[id] end }

-- Classic quest frame: GetAvailableQuestInfo reports isDaily, no quest
-- currencies, and the global GetItemInfoInstant.
local questCalls, quest = {}, {}
local function questCall(name)
    return function(...) questCalls[#questCalls + 1] = table.concat({ name, ... }, ' ') end
end
local greeting = { active = { { 'The Fargodeep Mine', true } },
    available = { { 'Daily Patrol', false, true }, { 'Kobold Candles', false, false } } }
function GetNumActiveQuests() return #greeting.active end
function GetActiveTitle(i) return greeting.active[i][1], greeting.active[i][2] end
function GetNumAvailableQuests() return #greeting.available end
function GetAvailableTitle(i) return greeting.available[i][1] end
function GetAvailableQuestInfo(i) return greeting.available[i][2], greeting.available[i][3] end
SelectActiveQuest, SelectAvailableQuest = questCall('turnin'), questCall('pick')
function GetTitleText() return quest.title end
function IsQuestCompletable() return true end
function GetQuestMoneyToGet() return 0 end
function GetNumQuestItems() return #quest.items end
function GetQuestItemLink(_, index) return quest.items[index] end
function GetItemInfoInstant(link) return 1, nil, nil, nil, nil, link == 'Gold Dust' and 7 or 12 end
AcceptQuest, CompleteQuest, GetQuestReward = questCall('accept'), questCall('complete'), questCall('reward')

local sqol = {}
for line in io.lines('SMoRGsQoL.toc') do
    local file = line:match('^([^#].-%.lua)%s*$')
    if file and not file:find('^Libs[\\/]') then assert(loadfile(file))('SMoRGsQoL', sqol) end
end
local function fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end
local function flush()
    while #pending > 0 do
        local queue = pending
        pending = {}
        for _, fn in ipairs(queue) do fn() end
    end
end

assert(sqol.IsClassic and sqol.IsClassicEra and not sqol.IsForever, 'Classic Era is not WoW Forever')

fire('ADDON_LOADED', 'SMoRGsQoL')
fire('PLAYER_LOGIN')
fire('PLAYER_ENTERING_WORLD')
flush()
assert(sqol.DB and sqol.DB.QuestCompleteSound and sqol.DB.QuestObjectiveSound)

-- Options Classic Era can't support are hidden; the quest sounds stay.
local available = {}
sqol.ForEachOption(function(_, option) available[option.key] = true end)
for _, key in ipairs({ 'AutoTrack', 'SmartQuestRadar', 'ShowNameplateObjectives',
    'ColorStatusBarProgress', 'ShowLFGProposalTimer', 'ShowTooltipTarget', 'ColorUnitTooltips', 'HideDoneAchievements',
    'ShowRangeIndicator' }) do
    assert(not available[key], key .. ' must be hidden in Classic Era')
end
-- Options turned on before they were hidden are switched off at login.
sqol.DB.ShowRangeIndicator, sqol.DB.HideDoneAchievements = true, true
fire('PLAYER_LOGIN')
flush()
assert(not sqol.DB.ShowRangeIndicator and not sqol.DB.HideDoneAchievements, 'Hidden options stay off')
assert(sqol.DB.QuestCompleteSound and sqol.DB.QuestSoundProfile, 'Available options are kept')
for _, key in ipairs({ 'QuestCompleteSound', 'QuestObjectiveSound', 'QuestSoundProfile',
    'AdventureRecap', 'ColorProgress', 'RepWatch', 'ShowReadyCheckTimer', 'ShowPartyLevel' }) do
    assert(available[key], key .. ' must stay available in Classic Era')
end
SlashCmdList.SQOL('autotrack')
assert(not sqol.DB.AutoTrack and messages[#messages]:find('not available', 1, true),
    'Hidden options cannot be toggled by slash command')

-- The first scan is the baseline; later scans play the worker voice lines.
fire('QUEST_LOG_UPDATE')
flush()
assert(#sounds == 0, 'Baseline scan stays silent')

objectives[33][1].finished = false
objectives[33][2].finished = false
fire('QUEST_LOG_UPDATE')
flush()
objectives[33][2].finished = true
fire('QUEST_LOG_UPDATE')
flush()
assert(sounds[1] == sqol.QuestSoundProfiles.Horde.objective, 'Objective sound from the Classic quest log')

objectives[33][1].finished = true
fire('QUEST_LOG_UPDATE')
flush()
assert(sounds[2] == sqol.QuestSoundProfiles.Horde.complete, 'Completion sound from the Classic quest log')
assert(messages[#messages]:find('Wolves Across the Border', 1, true), 'Completion message uses the quest title')

-- Classic Era QUEST_ACCEPTED passes (questLogIndex, questID).
questLog[3] = { title = 'Princess Must Die!', questID = 88 }
objectives[88] = { { text = 'Princess slain: 0/1', finished = false } }
fire('QUEST_ACCEPTED', 3, 88)
fire('QUEST_LOG_UPDATE')
flush()
assert(#sounds == 2, 'Accepting a quest plays nothing')
assert(sqol.GetQuestLogInfo(3).questID == 88 and sqol.GetQuestLogInfo(1).isHeader)

-- Quest automation works from Classic's greeting panel and quest frame.
local function questEvent(event)
    questCalls = {}
    fire(event)
    return table.concat(questCalls, ', ')
end
assert(available.AutoAcceptQuests and available.AutoTurnInQuests and available.QuestAutomationKey,
    'Quest automation is offered in Classic Era')
SlashCmdList.SQOL('qa')
assert(questEvent('QUEST_GREETING') == 'pick 2', 'isDaily skips the daily while only regular quests are on')
SlashCmdList.SQOL('qt')
assert(questEvent('QUEST_GREETING') == 'turnin 1', 'Completed quests first')
quest = { title = 'Gold Dust Exchange', items = { 'Gold Dust' } }
assert(questEvent('QUEST_PROGRESS') == '', 'Trade goods are kept')
quest = { title = 'The Fargodeep Mine', items = { 'Fargodeep Ore Sample' } }
assert(questEvent('QUEST_PROGRESS') == 'complete' and questEvent('QUEST_COMPLETE') == 'reward 0')
assert(questEvent('QUEST_DETAIL') == 'accept', 'Classic has no QuestIsDaily; quests count as regular')

-- Wowhead links: Classic has no quest log on the world map; the link goes
-- on the quest log window, in each client's Wowhead section.
local plainHook = hooksecurefunc
function hooksecurefunc(object, method, callback)
    if type(object) == 'string' then object, method, callback = _G, object, method end
    local original = object[method]
    object[method] = function(...) original(...) callback(...) end
end
QuestLogFrame = widget()
QuestLogTitleText = widget()
QuestLogTitleText:Show()
local selectedQuest = 0
function SelectQuestLogEntry(index) selectedQuest = index end
function GetQuestLogSelection() return selectedQuest end
local before = #frames
SlashCmdList.SQOL('wowhead')
local logBox = frames[before + 1]
assert(sqol.DB.ShowWowheadLinks and logBox and not logBox:IsShown(), 'Wowhead links are offered in Classic Era')
SelectQuestLogEntry(2)
assert(logBox:IsShown() and logBox.text == 'https://wowhead.com/classic/quest=33'
    and logBox.title == 'Wolves Across the Border', tostring(logBox.text))
assert(not QuestLogTitleText:IsShown(), 'The link takes the place of the quest log title')
SelectQuestLogEntry(1)
assert(not logBox:IsShown() and QuestLogTitleText:IsShown(), 'Headers have no link')
sqol.Locale = 'esMX'
QuestLogFrame.scripts.OnShow(QuestLogFrame)
SelectQuestLogEntry(3)
assert(logBox.text == 'https://wowhead.com/classic/es/quest=88', 'Language after the section')
sqol.Locale = 'enUS'
sqol.IsClassicEra, sqol.IsClassicTBC = false, true
assert(sqol.WowheadURL('item', 1) == 'https://wowhead.com/tbc/item=1', 'Anniversary')
sqol.IsClassicTBC = false
assert(sqol.WowheadURL('item', 1) == 'https://wowhead.com/mop-classic/item=1', 'Mists of Pandaria Classic')
sqol.IsClassic, sqol.IsForever = false, true
sqol.Locale = 'deDE'
assert(sqol.WowheadURL('item', 1) == 'https://wowhead.com/forever/de/item=1', 'WoW Forever')
sqol.IsClassic, sqol.IsForever, sqol.IsClassicEra, sqol.Locale = true, false, true, 'enUS'
-- "Show web link": Classic spells, links set on the tooltip and auras.
GameTooltipTextLeft1 = widget()
function GameTooltip:GetName() return 'GameTooltip' end
GameTooltip:Show()
GameTooltipTextLeft1:SetText('Fireball')
GameTooltip.GetSpell = function() return 'Fireball', 133 end
SMoRGsQoL_ShowWebLink()
assert(SQOL_WebLinkPopup:IsShown() and SQOL_WebLinkPopup.box.text == 'https://wowhead.com/classic/spell=133')
GameTooltip.GetSpell = nil
function GameTooltip:SetHyperlink() GameTooltipTextLeft1:SetText('Wolves Across the Border') end
function GameTooltip:SetUnitBuff() GameTooltipTextLeft1:SetText('Power Word: Fortitude') end
function UnitAura(unit, index, filter)
    if unit == 'player' and index == 1 and filter == 'HELPFUL' then
        return 'Power Word: Fortitude', 135987, 0, 'Magic', 1800, 0, 'player', false, false, 1243
    end
end
sqol._webLinkTooltipsHooked = nil
sqol.WebLink_HookTooltips()
GameTooltip:SetHyperlink('|cffffff00|Hquest:33:10|h[Wolves Across the Border]|h|r')
SMoRGsQoL_ShowWebLink()
assert(SQOL_WebLinkPopup.box.text == 'https://wowhead.com/classic/quest=33', 'Quest link on the tooltip')
GameTooltip:SetUnitBuff('player', 1)
SMoRGsQoL_ShowWebLink()
assert(SQOL_WebLinkPopup.box.text == 'https://wowhead.com/classic/spell=1243', 'Buff on the tooltip')
-- Players have no armory link in Classic, like Leatrix Plus Classic.
SQOL_WebLinkPopup:Hide()
GameTooltipTextLeft1:SetText('Smorg')
function UnitExists(unit) return unit == 'mouseover' end
function UnitIsPlayer() return true end
SMoRGsQoL_ShowWebLink()
assert(not SQOL_WebLinkPopup:IsShown(), 'No player link in Classic')
UnitIsPlayer, UnitAura, GameTooltip.SetHyperlink, GameTooltip.SetUnitBuff = nil, nil, nil, nil
function UnitExists() return false end
GameTooltip:Hide()
SlashCmdList.SQOL('wh')
assert(not logBox:IsShown() and QuestLogTitleText:IsShown())
hooksecurefunc = plainHook

-- Range in yards: Classic Era's C_Spell.GetSpellInfo says 0 for Fireball, the
-- legacy GetSpellInfo says 35 (seen in-game). Slot 1 Fireball, 2 Attack, 3 Frost Armor.
local inRange = { [1] = true, [2] = false }
local spells = { [1] = 133, [2] = 6603, [3] = 168 }
local legacyRanges = { [133] = 35, [6603] = 0, [168] = 0 }
function UnitExists(unit) return unit == 'target' end
function UnitCanAttack() return true end
function UnitIsDeadOrGhost() return false end
function HasAction(slot) return spells[slot] ~= nil end
function GetActionInfo(slot) return 'spell', spells[slot] end
function IsActionInRange(slot) return inRange[slot] end
C_Spell = {
    IsSpellHarmful = function(id) return id ~= 168 end,
    GetSpellInfo = function() return { maxRange = 0 } end,
}
function GetSpellInfo(id) return 'Spell', nil, 0, 0, 0, legacyRanges[id], id end
local state = sqol.RangeIndicator_GetState()
assert(not state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '5-35 yd',
    'Fireball reaches 35 yd: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))
inRange[1] = false
state = sqol.RangeIndicator_GetState()
assert(state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '> 35 yd',
    'Out of Fireball range: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))

-- WoW Forever hunter (seen in-game): the action check says Serpent Sting is out
-- and Raptor Strike in range at any distance; C_Spell.IsSpellInRange is right
-- for Serpent Sting (8-35 yd) but also reports Raptor Strike in range at 20 yd.
sqol.IsForever = true
spells = { [1] = 1978, [2] = 2973 }
inRange = { [1] = false, [2] = true }
local spellInRange = {}
local forever = { [1978] = { minRange = 8, maxRange = 35 }, [2973] = { minRange = 0, maxRange = 0 } }
GetSpellInfo = nil
C_Spell = {
    IsSpellHarmful = function() return true end,
    GetSpellInfo = function(id) return forever[id] end,
    IsSpellInRange = function(id) return spellInRange[id] end,
}
spellInRange[1978], spellInRange[2973] = true, true
state = sqol.RangeIndicator_GetState()
assert(not state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '8-35 yd',
    'Forever hunter at 20 yd: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))
spellInRange[1978] = false
state = sqol.RangeIndicator_GetState()
assert(not state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '< 5 yd',
    'Forever hunter in melee: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))
-- Far away Raptor Strike still says in range; out of combat CheckInteractDistance
-- says the target is farther than ~10 yd (seen in-game: far false, melee true).
local interact
function CheckInteractDistance() return interact() end
interact = function() return false end
state = sqol.RangeIndicator_GetState()
assert(state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '> 35 yd',
    'Forever hunter far away: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))
interact = function() return true end
state = sqol.RangeIndicator_GetState()
assert(not state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '< 5 yd',
    'Forever hunter in melee with interact check: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))
-- Restricted in combat: nothing is known, so the melee reach is kept.
interact = function() error('restricted') end
state = sqol.RangeIndicator_GetState()
assert(not state.outOfRange and sqol.RangeIndicator_FormatDistance(state) == '< 5 yd',
    'Forever hunter in combat: ' .. tostring(sqol.RangeIndicator_FormatDistance(state)))
CheckInteractDistance = nil
sqol.IsForever = false

-- WoW Forever reports interface 16001 on its own project (18), not a Classic one.
local function detect(project, interface)
    WOW_PROJECT_ID = project
    GetBuildInfo = function() return '', '', '', interface end
    local ns = { L = setmetatable({}, { __index = function(_, key) return key end }) }
    assert(loadfile('Core.lua'))('SMoRGsQoL', ns)
    return ns
end
local forever = detect(18, 16001)
assert(forever.IsForever and not forever.IsClassic and not forever.IsClassicEra and forever.HasLFGQueue,
    'WoW Forever')
local retail = detect(WOW_PROJECT_MAINLINE, 120105)
assert(not retail.IsForever and not retail.IsClassic and retail.HasLFGQueue, 'Retail')
assert(not sqol.HasLFGQueue, 'Classic Era has no queue pop')
-- Anniversary (TBC) may not define WOW_PROJECT_BURNING_CRUSADE_CLASSIC; the known ID still counts.
local anniversary = detect(5, 20506)
assert(anniversary.IsClassic and anniversary.IsClassicTBC and not anniversary.IsClassicEra
    and not anniversary.IsForever and not anniversary.HasLFGQueue, 'Anniversary (TBC)')
local mists = detect(19, 50504)
assert(mists.IsClassic and not mists.IsClassicEra and not mists.IsForever and mists.HasLFGQueue, 'MoP Classic')

print = function(...) io.write(table.concat({...}, ' '), '\n') end
print('PASS: Classic Era, Anniversary and WoW Forever detection, optional events, hidden options, quest log fallback, quest sounds, quest automation and Wowhead links')
