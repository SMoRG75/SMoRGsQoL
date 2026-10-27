-- Standalone Lua smoke test. Run from the repository root: lua tests/smoke.lua
-- This mocks UI objects; it does not replace testing inside the WoW client.
local frames, pending, messages = {}, {}, {}
local function widget()
    local w = { scripts = {}, events = {}, shown = false }
    function w:RegisterEvent(event) self.events[event] = true end
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
    function w:CreateFontString()
        local text = widget()
        self.fontStrings = self.fontStrings or {}
        self.fontStrings[#self.fontStrings + 1] = text
        return text
    end
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
        'SetFading', 'SetTimeVisible', 'SetFadeDuration', 'SetMaxLines',
        'SetInsertMode', 'SetSpacing', 'AddMessage', 'SetToplevel', 'SetClampedToScreen',
        'SetMovable', 'RegisterForDrag', 'StartMoving', 'StopMovingOrSizing', 'SetHitRectInsets',
        'SetFontObject', 'SetColorTexture', 'SetHeight', 'SetOwner', 'SetTexCoord', 'SetShadowOffset',
        'SetBackdrop', 'SetBackdropColor', 'SetBackdropBorderColor', 'SetAutoFocus',
        'SetBlinkSpeed', 'HighlightText', 'SetFocus', 'ClearFocus', 'SetFrameLevel' }) do
        w[method] = function() end
    end
    function w:IsMouseOver() return self.mouseOver == true end
    function w:EnableKeyboard(value) self.keyboard = value end
    return w
end
function CreateFrame(_, name)
    local frame = widget()
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
UIParent = widget()
PlayerFrame = widget()
PlayerFrame:Show()
-- Unit tooltip: captures the post-call and records added lines.
local tooltipPostCalls = {}
Enum = { TooltipDataType = { Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) tooltipPostCalls[kind] = fn end }
GameTooltip = widget()
GameTooltip.StatusBar = widget()
GameTooltip.lines = {}
function GameTooltip:AddLine(text)
    local line = widget()
    line:SetText(text)
    self.lines[#self.lines + 1] = line
    _G['GameTooltipTextLeft' .. #self.lines] = line
end
function GameTooltip:NumLines() return #self.lines end
function GameTooltip:GetUnit() return 'Mob', self.unit end
SlashCmdList = {}
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
C_AddOns = { IsAddOnLoaded = function() return false end,
    LoadAddOn = function() end, GetAddOnMetadata = function() return 'test' end }
function GetTime() return 100 end
function GetUnitSpeed() return 7 end
function GetAverageItemLevel() return 123, 123 end
function GetCursorPosition() return 100, 100 end
function InCombatLockdown() return false end
function hooksecurefunc() end
function print(...) messages[#messages + 1] = table.concat({...}, ' ') end
UISpecialFrames = {}
-- Quest frame and gossip: record what quest automation clicks.
local questCalls, quest, gossip, modifiers = {}, {}, { active = {}, available = {} }, {}
local function questCall(name)
    return function(...) questCalls[#questCalls + 1] = table.concat({ name, ... }, ' ') end
end
function IsShiftKeyDown() return modifiers.SHIFT end
function IsAltKeyDown() return modifiers.ALT end
function IsControlKeyDown() return modifiers.CONTROL end
function IsMetaKeyDown() return modifiers.CMD end
function GetTitleText() return quest.title end
function QuestIsDaily() return quest.daily == true end
function QuestIsWeekly() return quest.weekly == true end
function QuestFlagsPVP() return quest.pvp == true end
function QuestGetAutoAccept() return quest.autoAccept == true end
function IsQuestCompletable() return quest.completable == true end
function GetQuestMoneyToGet() return quest.money or 0 end
function GetNumQuestCurrencies() return quest.currencies or 0 end
function GetNumQuestItems() return #(quest.items or {}) end
function GetQuestItemLink(_, index) return quest.items[index] end
function GetNumQuestChoices() return quest.choices or 0 end
-- Gnoll Paw is a quest item (class 12), Linen Cloth a trade good (7).
C_Item = { GetItemInfoInstant = function(link) return 1, nil, nil, nil, nil, link == 'Gnoll Paw' and 12 or 7 end }
AcceptQuest, AcknowledgeAutoAcceptQuest = questCall('accept'), questCall('acknowledge')
CompleteQuest, GetQuestReward, ShowQuestComplete = questCall('complete'), questCall('reward'), questCall('show')
C_GossipInfo = {
    GetActiveQuests = function() return gossip.active end,
    GetAvailableQuests = function() return gossip.available end,
    SelectActiveQuest = questCall('turnin'), SelectAvailableQuest = questCall('pick'),
}
-- The embedded libraries need the real client; stand-ins record what the launcher does.
local ldbObjects, minimapButton = {}, {}
local fakeLibs = {
    ['LibDataBroker-1.1'] = { NewDataObject = function(_, name, obj) ldbObjects[name] = obj return obj end },
    ['LibDBIcon-1.0'] = {
        IsRegistered = function() return minimapButton.db ~= nil end,
        Register = function(_, _, _, db) minimapButton.db = db end,
        Refresh = function(_, _, db) minimapButton.db = db end,
        Show = function() minimapButton.shown = true end,
        Hide = function() minimapButton.shown = false end,
    },
}
LibStub = setmetatable({}, { __call = function(_, name) return fakeLibs[name] end })

local sqol = {}
local files = {}
if arg[1] then
    -- Optional pre-refactor baseline, for behavioral comparison during extraction.
    files = { arg[1], 'Options.lua', 'StatusBarProgress.lua' }
else
    for line in io.lines('SMoRGsQoL.toc') do
        local file = line:match('^([^#].-%.lua)%s*$')
        if file and not file:find('^Libs[\\/]') then files[#files + 1] = file end
    end
end
for _, file in ipairs(files) do assert(loadfile(file))('SMoRGsQoL', sqol) end
local function fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end
fire('ADDON_LOADED', 'SMoRGsQoL')
fire('PLAYER_LOGIN')
fire('PLAYER_ENTERING_WORLD')
assert(sqol.DB and sqol.GetProgressColor(0.5) == '|cffffff00')
for _, command in ipairs({ 'ilvl', 'speed', 'speed', 'ilvl', 'color', 'barcolor',
    'color', 'barcolor', 'damagefont', 'damagefont', 'cursor', 'cursor',
    'rep', 'rep', 'nameplate', 'nameplate', 'radar', 'qr', 'partylevel', 'partylevel', 'tt', 'tt',
    'rctest', 'lfgtest', 'help', '' }) do
    SlashCmdList.SQOL(command)
end
assert(not sqol.DB.ShowItemLevel and not sqol.DB.ShowMovementSpeed)
assert(not sqol.DB.ColorProgress and not sqol.DB.ColorStatusBarProgress)
assert(not sqol.DB.ShowTooltipTarget)
assert(not sqol.DB.SmartQuestRadar, 'Radar defaults off and both slash commands toggle it')
assert(sqol.iLvlHolder and not sqol.iLvlHolder:IsShown())

-- Launcher: LDB object, minimap button (off by default) and addon compartment.
local launcher = ldbObjects.SMoRGsQoL
assert(launcher and launcher.type == 'launcher' and launcher.icon:find('smorgsqol', 1, true))
assert(minimapButton.db and minimapButton.db.hide == true and not minimapButton.shown, 'Minimap button is off by default')
SlashCmdList.SQOL('minimap')
assert(minimapButton.shown and sqol.DB.MinimapIcon.hide == false)
SlashCmdList.SQOL('mm')
assert(not minimapButton.shown and sqol.DB.MinimapIcon.hide == true)
assert(SMoRGsQoL_OnAddonCompartmentClick and SMoRGsQoL_OnAddonCompartmentEnter and SMoRGsQoL_OnAddonCompartmentLeave)
GameTooltip.lines = {}
launcher.OnTooltipShow(GameTooltip)
assert(GameTooltip.lines[1].text == "SMoRG's QoL" and GameTooltip.lines[2].text:find('features enabled', 1, true))

-- Options popup: one control per available option, changes go through SetOption
-- and changes made elsewhere show up while it is open.
launcher.OnClick(nil, 'LeftButton')
local popup = SQOL_OptionsPopup
assert(popup and popup:IsShown() and UISpecialFrames[1] == 'SQOL_OptionsPopup')
local popupControls, expectedControls = {}, 0
sqol.ForEachOption(function() expectedControls = expectedControls + 1 end)
for _, frame in ipairs(frames) do
    if frame.option then popupControls[frame.option.key] = frame end
end
local controlCount = 0
for _ in pairs(popupControls) do controlCount = controlCount + 1 end
assert(controlCount == expectedControls, 'Every available option needs a control')
local partyBox = popupControls.ShowPartyLevel
partyBox:SetChecked(true)
partyBox.scripts.OnClick(partyBox)
assert(sqol.DB.ShowPartyLevel == true)
SlashCmdList.SQOL('pl')
assert(sqol.DB.ShowPartyLevel == false and partyBox.checked == false, 'Popup follows slash commands')
local profileRow = popupControls.QuestSoundProfile
local cycleButton
for _, frame in ipairs(frames) do
    if frame.scripts.OnClick and frame.text == sqol.QuestSoundProfiles.Horde.label then cycleButton = frame end
end
assert(profileRow and cycleButton, 'Dropdown falls back to a cycle button')
cycleButton.scripts.OnClick(cycleButton)
assert(sqol.DB.QuestSoundProfile == 'Alliance' and cycleButton.text == sqol.QuestSoundProfiles.Alliance.label)
sqol.SetOption('QuestSoundProfile', 'Horde')
SMoRGsQoL_OnAddonCompartmentClick('SMoRGsQoL', 'LeftButton')
assert(not popup:IsShown())
SlashCmdList.SQOL('config')
assert(popup:IsShown())
SlashCmdList.SQOL('config')
assert(not popup:IsShown())
for _, event in ipairs({ 'READY_CHECK_FINISHED', 'LFG_PROPOSAL_FAILED',
    'GROUP_ROSTER_UPDATE', 'PLAYER_EQUIPMENT_CHANGED', 'QUEST_LOG_UPDATE',
    'UPDATE_FACTION', 'EDIT_MODE_LAYOUTS_UPDATED' }) do fire(event) end
-- Reputation suffix uses the current rank and remaining (not earned) percent.
local oldHook = hooksecurefunc
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
local function progressBar(text)
    local bar = { OverlayFrame = { Text = widget() } }
    function bar:SetBarText(value) self.OverlayFrame.Text:SetText(value) end
    -- Blizzard with xpBarText off: text only while hovered or locked.
    function bar:UpdateTextVisibility() self.OverlayFrame.Text:SetShown(self.textLocked == true) end
    bar:SetBarText(text)
    return bar
end
local repBar = progressBar('Avengers of Hyjal 4995 / 6000')
local xpBar = progressBar('XP 4995 / 6000')
StatusTrackingBarInfo = { BarsEnum = { Experience = 1, Reputation = 2 } }
StatusTrackingBarManager = { bars = { xpBar, repBar } }
local watched = { factionID = 1204, reaction = 5 }
C_Reputation = { GetWatchedFactionData = function() return watched end }
FACTION_STANDING_LABEL5, FACTION_STANDING_LABEL6 = 'Friendly', 'Honored'
sqol.SetOption('ColorStatusBarProgress', true)
local function plainRep() return repBar.OverlayFrame.Text.text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') end
assert(plainRep() == 'Avengers of Hyjal 4995 / 6000 · 16.8% left · Friendly')
sqol.RefreshStatusBarProgress()
assert(plainRep() == 'Avengers of Hyjal 4995 / 6000 · 16.8% left · Friendly')
assert(not xpBar.OverlayFrame.Text.text:find('left', 1, true))
watched.reaction = 6
repBar:SetBarText('Avengers of Hyjal 0 / 12000')
assert(plainRep() == 'Avengers of Hyjal 0 / 12000 · 100.0% left · Honored')
repBar:SetBarText('Avengers of Hyjal')
assert(plainRep() == 'Avengers of Hyjal')
repBar:SetBarText('Avengers of Hyjal 6000 / 12000')
-- Forever has no xpBarText setting, so the text stays visible after hovering.
assert(not xpBar.OverlayFrame.Text:IsShown(), 'Retail keeps Blizzard text visibility')
sqol.IsForever = true
sqol.RefreshStatusBarProgress()
assert(xpBar.OverlayFrame.Text:IsShown() and repBar.OverlayFrame.Text:IsShown())
xpBar.textLocked = true; xpBar:UpdateTextVisibility()
xpBar.textLocked = false; xpBar:UpdateTextVisibility()
assert(xpBar.OverlayFrame.Text:IsShown(), 'Forever text survives mouse leave')
sqol.SetOption('ColorStatusBarProgress', false)
assert(repBar.OverlayFrame.Text.text == 'Avengers of Hyjal 6000 / 12000')
assert(not repBar.OverlayFrame.Text:IsShown(), 'Disabling the option restores Blizzard visibility')
sqol.IsForever = false
C_Reputation, StatusTrackingBarInfo, StatusTrackingBarManager = nil, nil, nil

-- Quest tracker: only the current count is colored, also on finished lines.
local function trackerLine(text) local line = { Text = widget() } line.Text:SetText(text) return line end
local questBlock = { usedLines = {
    [1] = trackerLine('1/5 Boar Pelt'), [2] = trackerLine('5/5 Wolf Fang'),
    [3] = trackerLine('Speak to Marshal'), QuestComplete = trackerLine('0/1 extra line') } }
QuestObjectiveTracker = { usedBlocks = { QuestBlock = { [42] = questBlock } } }
function QuestObjectiveTracker:DoQuestObjectives(block) end
sqol.HookQuestTrackerColors()
sqol.SetOption('ColorProgress', true)
QuestObjectiveTracker:DoQuestObjectives(questBlock)
assert(questBlock.usedLines[1].Text.text == '|cffff66001|r/5 Boar Pelt')
assert(questBlock.usedLines[2].Text.text == '|cff00ff005|r/5 Wolf Fang')
assert(questBlock.usedLines[3].Text.text == 'Speak to Marshal')
assert(questBlock.usedLines.QuestComplete.Text.text == '0/1 extra line')
sqol.RefreshQuestTrackerColors()
assert(questBlock.usedLines[1].Text.text == '|cffff66001|r/5 Boar Pelt', 'Coloring must be idempotent')
-- World quests use BonusObjectiveTrackerMixin:SetUpQuestBlock instead.
local wqBlock = { usedLines = { [1] = trackerLine('4/5 Mana Spores gathered'), TimeLeft = trackerLine('1/2 h') } }
WorldQuestObjectiveTracker = { usedBlocks = { WQBlock = { [7] = wqBlock } } }
function WorldQuestObjectiveTracker:SetUpQuestBlock(block) end
sqol.HookQuestTrackerColors()
WorldQuestObjectiveTracker:SetUpQuestBlock(wqBlock)
assert(wqBlock.usedLines[1].Text.text == '|cff66ff004|r/5 Mana Spores gathered')
assert(wqBlock.usedLines.TimeLeft.Text.text == '1/2 h')
sqol.SetOption('ColorProgress', false)
assert(questBlock.usedLines[1].Text.text == '1/5 Boar Pelt' and questBlock.usedLines[2].Text.text == '5/5 Wolf Fang')
assert(wqBlock.usedLines[1].Text.text == '4/5 Mana Spores gathered')
QuestObjectiveTracker, WorldQuestObjectiveTracker = nil, nil
hooksecurefunc = oldHook

-- Nameplate counts: above the name when Blizzard's style puts it above the bar,
-- otherwise above the health bar (Retail's name-inside-bar style).
-- Nameplate regions are restricted in-game, so the mock name has no anchor data.
NamePlateConstants = { NAME_ANCHOR_STYLES = { InsideHealthBar = 1, CenteredAboveHealthBar = 2, AboveHealthBar = 3 } }
NamePlateSetupOptions = {}
local function nameplateWith(style)
    NamePlateSetupOptions.unitNameAnchorStyle = style
    local name = widget()
    function name:GetStringWidth() return 50 end
    local unitFrame = widget()
    unitFrame.name, unitFrame.HealthBarsContainer = name, widget()
    return { UnitFrame = unitFrame }
end
local function objectiveAnchor(nameplate)
    C_NamePlate = { GetNamePlateForUnit = function() return nameplate end }
    function UnitExists() return true end
    sqol.DB.ShowNameplateObjectives = true
    sqol.NameplateObjectives_UpdateUnit('nameplate1')
    local text = nameplate.SQOLObjectiveText
    assert(text, 'Nameplate objective text must be created')
    return text.anchor
end
local oldWidget = widget
widget = function()
    local w = oldWidget()
    function w:SetPoint(point, relativeTo, relativePoint, x, y) self.anchor = { point, relativeTo, relativePoint, x, y } end
    return w
end
for _, style in ipairs({ 2, 3 }) do
    local above = nameplateWith(style)
    local anchor = objectiveAnchor(above)
    assert(anchor[1] == 'BOTTOM' and anchor[2] == above.UnitFrame.name and anchor[3] == 'TOP' and anchor[5] == 3)
end
local inside = nameplateWith(1)
local anchor = objectiveAnchor(inside)
assert(anchor[2] == inside.UnitFrame.HealthBarsContainer and anchor[5] == 15)
local unknown = nameplateWith(nil)
NamePlateSetupOptions = nil
anchor = objectiveAnchor(unknown)
assert(anchor[2] == unknown.UnitFrame.HealthBarsContainer and anchor[5] == 15, 'Unknown style keeps the old anchor')
widget, C_NamePlate, UnitExists, NamePlateConstants = oldWidget, nil, nil, nil
sqol.DB.ShowNameplateObjectives = false
sqol._npUnits.nameplate1 = nil

-- Tooltip target line: off by default, "You", reaction/class colors, live refresh, secrets.
local units = { mouseovertarget = { name = 'Gnoll', reaction = 2 } }
function UnitExists(unit) return unit == 'mouseover' or units[unit] ~= nil end
function UnitIsUnit(unit, other) return other == 'player' and units[unit] and units[unit].isYou or false end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitIsPlayer(unit) return units[unit] and units[unit].class ~= nil end
function UnitClass(unit) return 'Druid', units[unit] and units[unit].class end
function UnitReaction(unit) return units[unit] and units[unit].reaction end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } }
FACTION_BAR_COLORS = { [2] = { r = 1, g = 0, b = 0 } }
local showUnitTooltip = tooltipPostCalls[Enum.TooltipDataType.Unit]
assert(showUnitTooltip and GameTooltip.scripts.OnUpdate, 'Tooltip hooks must be installed at load')
local function hoverUnit()
    GameTooltip.lines = {}
    GameTooltip.unit = 'mouseover'
    showUnitTooltip(GameTooltip, {})
    return GameTooltip.lines[#GameTooltip.lines]
end
assert(hoverUnit() == nil, 'Disabled option must not add a line')
SlashCmdList.SQOL('tt')
assert(hoverUnit().text == '|cffffd100Target:|r |cffff0000Gnoll|r')
units.mouseovertarget = { name = 'Soren', class = 'DRUID' }
GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
assert(GameTooltip.lines[1].text:find('Gnoll', 1, true), 'Refresh is throttled')
GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
assert(GameTooltip.lines[1].text == '|cffffd100Target:|r |cffff7d0aSoren|r')
units.mouseovertarget = { name = 'Me', isYou = true }
assert(hoverUnit().text == '|cffffd100Target:|r |cffff4040You|r')
units.mouseovertarget = nil
assert(hoverUnit() == nil, 'No target, no line')
units.mouseovertarget = { name = 'Gnoll', reaction = 2 }
issecretvalue = function() return true end
assert(hoverUnit() == nil, 'Secret unit data must be skipped')
issecretvalue = nil
SlashCmdList.SQOL('tt')
-- Colorful unit tooltips: class name/spec/border/bar, <guild>, level and faction colors.
GameTooltip.NineSlice = { SetBorderColor = function(self, r, g, b) self.color = { r, g, b } end }
function GameTooltip.StatusBar:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
units.mouseover = { name = 'Smorg', class = 'DRUID', guild = 'Danish Casuals' }
function GetGuildInfo(unit) return units[unit] and units[unit].guild end
function UnitLevel() return 90 end
function UnitFactionGroup() return 'Horde', 'Horde' end
function GetQuestDifficultyColor() return { r = 1, g = 1, b = 0 } end
local health = { cur = 18807, max = 23771 }
function UnitHealth() return health.cur end
function UnitHealthMax() return health.max end
function AbbreviateLargeNumbers(value) return string.format('%.1fK', value / 1000) end
LEVEL = 'Level'
local function hoverStyled(texts)
    GameTooltip.lines = {}
    for _, text in ipairs(texts) do GameTooltip:AddLine(text) end
    for _, line in ipairs(GameTooltip.lines) do
        function line:SetTextColor(r, g, b) self.color = { r, g, b } end
    end
    GameTooltip.unit = 'mouseover'
    showUnitTooltip(GameTooltip, {})
    return GameTooltip.lines
end
local retailLines = { 'Smorg', 'Danish Casuals', 'Level 90 Highmountain Tauren (Player)', 'Balance Druid',
    'Horde', 'Level 86 Some of the Things' }
local lines = hoverStyled(retailLines)
assert(not lines[1].color and lines[2].text == 'Danish Casuals', 'Disabled option leaves the tooltip alone')
SlashCmdList.SQOL('tc')
lines = hoverStyled(retailLines)
assert(lines[1].color[1] == 1 and lines[1].color[2] == 0.49, 'Player name in class color')
assert(lines[2].text == '<Danish Casuals>' and lines[2].color[2] == 1, 'Guild in green brackets')
assert(lines[3].text == 'Level |cffffff0090|r Highmountain Tauren (Player)', 'Level in difficulty color' .. ': ' .. tostring(lines[3].text))
assert(lines[4].color[2] == 0.49, 'Spec line in class color')
assert(lines[5].color[1] == 1 and lines[5].color[2] == 0.3, 'Horde in red')
assert(lines[6].text == 'Level 86 Some of the Things' and not lines[6].color, 'Other lines are kept')
assert(GameTooltip.NineSlice.color[2] == 0.49 and GameTooltip.StatusBar.color[2] == 0.49, 'Class border and bar')
GameTooltip.StatusBar:SetStatusBarColor(0, 1, 0)
GameTooltip.StatusBar.scripts.OnValueChanged(GameTooltip.StatusBar, 50)
assert(GameTooltip.StatusBar.color[2] == 0.49, 'Health bar keeps the class color')
local healthText = GameTooltip.StatusBar.fontStrings[1]
assert(healthText.shown and healthText.text == '18.8K / 23.8K (79%)', 'Health on the bar: ' .. tostring(healthText.text))
health.cur = 0
GameTooltip.StatusBar.scripts.OnValueChanged(GameTooltip.StatusBar, 0)
assert(healthText.text == '0.0K / 23.8K (0%)', 'Health text follows the bar')
health.cur = 18807
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
assert(GameTooltip.NineSlice.color[2] == 1 and GameTooltip.StatusBar.color[1] == 0, 'Clearing restores Blizzard colors')
assert(not healthText.shown, 'Clearing hides the health text')
lines = hoverStyled({ 'Smorg', '<Danish Casuals>', 'Level 90 Tauren Druid (Player)' })
assert(lines[2].text == '<Danish Casuals>', 'Bracketed guild is not bracketed twice' .. ': ' .. tostring(lines[2].text))
assert(lines[3].text == 'Level |cffffff0090|r Tauren |cffff7d0aDruid|r (Player)', 'Classic level line colors the class word' .. ': ' .. tostring(lines[3].text))
issecretvalue = function() return true end
lines = hoverStyled(retailLines)
assert(lines[2].text == 'Danish Casuals' and not lines[1].color, 'Secret unit data must be skipped')
issecretvalue = nil
SlashCmdList.SQOL('tc')
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
units.mouseover = nil
GetGuildInfo, UnitLevel, UnitFactionGroup, GetQuestDifficultyColor, LEVEL = nil, nil, nil, nil, nil
UnitHealth, UnitHealthMax, AbbreviateLargeNumbers = nil, nil, nil
GameTooltip.NineSlice = nil
UnitExists, UnitIsUnit, UnitName, UnitIsPlayer, UnitClass, UnitReaction = nil, nil, nil, nil, nil, nil
RAID_CLASS_COLORS, FACTION_BAR_COLORS = nil, nil

-- Range icon and distance: the icon shows only when some offensive action is
-- range-checked and none reach; the distance comes from the actions' max ranges.
local target = { exists = true, attackable = true, dead = false }
local actionRange = {}         -- slot -> true/false/nil (nil: no range check)
function UnitExists(unit) return unit == 'target' and target.exists end
function UnitCanAttack() return target.attackable end
function UnitIsDeadOrGhost() return target.dead end
function HasAction(slot) return actionRange[slot] ~= nil or slot == 3 or slot == 65 end
C_ActionBar = { IsActionInRange = function(slot) return slot == 65 or actionRange[slot] end }
-- Slot 65 is a self spell (Play Dead): "in range" for any target, but not offensive.
-- Slot 7 is an offensive macro.
local selfSpells = { [209997] = true }
function GetActionInfo(slot)
    if slot == 65 then return 'spell', 209997 end
    if slot == 7 then return 'macro', 700, 'spell' end
    return 'spell', slot * 100
end
-- Max ranges: slot 1 is melee (0, counted as 5 yd), the slot 7 macro reaches 40 yd.
local maxRanges = { [100] = 0, [700] = 40 }
C_Spell = {
    IsSpellHarmful = function(spellID) return not selfSpells[spellID] end,
    GetSpellInfo = function(spellID) return { maxRange = maxRanges[spellID] or 0 } end,
}
local cvars = { SoftTargetIconEnemy = '1' }
C_CVar = { GetCVar = function(name) return cvars[name] end, SetCVar = function(name, value) cvars[name] = value end }
local meleeButton, healButton, playDeadButton = widget(), widget(), widget()
meleeButton.action, healButton.action, playDeadButton.action = 1, 3, 65
meleeButton:Show(); healButton:Show(); playDeadButton:Show()
ActionBarButtonEventsFrame = { frames = { meleeButton, healButton, playDeadButton } }
TargetFrame = widget()
TargetFrame:Show()
-- Returns whether the icon shows and the distance text (nil when nothing is shown).
local function rangeDisplay()
    fire('PLAYER_TARGET_CHANGED')
    local frame = SQOL_RangeIndicator
    if not frame or not frame:IsShown() then return false, nil end
    return frame.Icon:IsShown(), frame.Text.text
end
actionRange[1] = false
local icon, distance = rangeDisplay()
assert(not icon and not distance, 'Off by default')
assert(cvars.SoftTargetIconEnemy == '1', 'The sword icon is untouched while off')
SlashCmdList.SQOL('range')
assert(cvars.SoftTargetIconEnemy == '0' and sqol.DB.RangeHidSoftTargetIcon, 'Enabling hides Blizzard\'s sword icon')
icon, distance = rangeDisplay()
assert(icon and distance == '> 5 yd', 'Melee out of range; the heal has no range check and Play Dead is not offensive')
actionRange[1] = true
icon, distance = rangeDisplay()
assert(not icon and distance == '< 5 yd', 'In melee range: distance only')
actionRange[1] = nil
icon, distance = rangeDisplay()
assert(not icon and not distance, 'Nothing range-checked, nothing to show')
actionRange[1] = false
target.dead = true
icon, distance = rangeDisplay()
assert(not icon and not distance, 'Dead targets are ignored')
target.dead = false
meleeButton:Hide(); healButton:Hide(); playDeadButton:Hide()
actionRange[7] = false
icon, distance = rangeDisplay()
assert(icon and distance == '> 40 yd', 'Falls back to all action slots without visible Blizzard buttons')
actionRange[7] = true
icon, distance = rangeDisplay()
assert(not icon and distance == '5-40 yd', 'Out of melee but within 40 yd')
-- Placement: where Blizzard's sword icon sits on the target's nameplate, above
-- our quest count when it is shown there, else by the target frame.
local softTarget = widget()
local rangePlate = { UnitFrame = { SoftTargetFrame = softTarget } }
C_NamePlate = { GetNamePlateForUnit = function(unit) return unit == 'target' and rangePlate or nil end }
local function rangeAnchor()
    function SQOL_RangeIndicator:SetPoint(point, relativeTo) self.pointTo = { point, relativeTo } end
    rangeDisplay()
    return SQOL_RangeIndicator.pointTo
end
local anchor = rangeAnchor()
assert(anchor[1] == 'CENTER' and anchor[2] == softTarget, 'On the sword icon spot')
local questCount = widget()
questCount:Show()
rangePlate.SQOLObjectiveText = questCount
anchor = rangeAnchor()
assert(anchor[1] == 'BOTTOM' and anchor[2] == questCount, 'Above the quest count')
C_NamePlate = nil
anchor = rangeAnchor()
assert(anchor[2] == TargetFrame, 'Target frame without a nameplate')
TargetFrame:Hide()
icon, distance = rangeDisplay()
assert(not icon and not distance, 'Nowhere to show it')
TargetFrame:Show()
issecretvalue = function() return true end
icon, distance = rangeDisplay()
assert(not icon and not distance, 'Secret values never show anything')
issecretvalue = nil
SlashCmdList.SQOL('range')
actionRange[7] = false
icon, distance = rangeDisplay()
assert(not icon and not distance, 'Turning the option off hides everything')
assert(cvars.SoftTargetIconEnemy == '1' and not sqol.DB.RangeHidSoftTargetIcon, 'Disabling restores the sword icon')
cvars.SoftTargetIconEnemy = '0'
SlashCmdList.SQOL('range')
SlashCmdList.SQOL('range')
assert(cvars.SoftTargetIconEnemy == '0', 'A sword icon the user turned off stays off')
UnitExists, UnitCanAttack, UnitIsDeadOrGhost, HasAction, C_ActionBar = nil, nil, nil, nil, nil
GetActionInfo, C_Spell, C_CVar = nil, nil, nil
ActionBarButtonEventsFrame, TargetFrame = nil, nil

-- Quest automation: off by default, the override key works both ways, and it
-- stops wherever the player has to decide or pay.
local function questEvent(event, ...)
    questCalls = {}
    fire(event, ...)
    return table.concat(questCalls, ', ')
end
quest = { title = 'Wanted: Hogger' }
assert(questEvent('QUEST_DETAIL') == '', 'Quest automation is off by default')
assert(popupControls.AutoAcceptQuests and popupControls.QuestAutomationKey, 'Options window shows quest automation')
SlashCmdList.SQOL('qa')
assert(questEvent('QUEST_DETAIL') == 'accept', 'Regular quest accepted')
quest.daily = true
assert(questEvent('QUEST_DETAIL') == '', 'Daily quests need their own option')
SlashCmdList.SQOL('questdaily')
assert(questEvent('QUEST_DETAIL') == 'accept')
quest.daily, quest.weekly = false, true
assert(questEvent('QUEST_DETAIL') == '', 'Weekly quests need their own option')
SlashCmdList.SQOL('qw')
assert(questEvent('QUEST_DETAIL') == 'accept')
quest = { title = 'Wanted: Hogger', autoAccept = true }
assert(questEvent('QUEST_DETAIL') == 'acknowledge', 'Auto-accepted quests are only acknowledged')
quest = { title = 'Wanted: Hogger', pvp = true }
assert(questEvent('QUEST_DETAIL') == '', 'PvP quests are left alone')
quest = { title = 'Escort: Corporal Keeshan' }
function UnitIsPlayer(unit) return unit == 'npc' end
function UnitIsUnit() return false end
assert(questEvent('QUEST_DETAIL') == '', 'Quests shared by a player are left alone')
function UnitIsUnit(unit, other) return unit == 'npc' and other == 'player' end
assert(questEvent('QUEST_DETAIL') == 'accept', 'Quests from your own items are accepted')
UnitIsPlayer, UnitIsUnit = nil, nil
-- Override key: bypasses by default, required when the option is on.
modifiers.SHIFT = true
assert(questEvent('QUEST_DETAIL') == '', 'Holding SHIFT pauses automation')
SlashCmdList.SQOL('qrk')
assert(questEvent('QUEST_DETAIL') == 'accept', 'Required key held')
modifiers.SHIFT = nil
assert(questEvent('QUEST_DETAIL') == '', 'Required key not held')
SlashCmdList.SQOL('questkey ctrl')
assert(sqol.DB.QuestAutomationKey == 'CONTROL' and messages[#messages]:find('CONTROL', 1, true))
modifiers.CONTROL = true
assert(questEvent('QUEST_DETAIL') == 'accept', 'Chosen key held')
SlashCmdList.SQOL('qk')
assert(sqol.DB.QuestAutomationKey == 'CMD', 'Without an argument the key steps to the next one')
SlashCmdList.SQOL('qk hyper')
assert(sqol.DB.QuestAutomationKey == 'CMD' and messages[#messages]:find('questkey', 1, true), 'Unknown keys print the usage')
SlashCmdList.SQOL('qk shift')
SlashCmdList.SQOL('qrk')
modifiers.CONTROL = nil
-- Turn-ins: only completable quests that cost nothing but quest items.
quest = { title = 'Wanted: Hogger', completable = true }
assert(questEvent('QUEST_PROGRESS') == '', 'Turn-ins have their own option')
SlashCmdList.SQOL('qt')
assert(questEvent('QUEST_PROGRESS') == 'complete')
quest.completable = false
assert(questEvent('QUEST_PROGRESS') == '', 'Unfinished quests are not handed in')
quest = { title = 'Gnoll Paws', completable = true, items = { 'Gnoll Paw' } }
assert(questEvent('QUEST_PROGRESS') == 'complete', 'Quest items are handed in')
quest = { title = 'Cloth Donation', completable = true, items = { 'Gnoll Paw', 'Linen Cloth' } }
assert(questEvent('QUEST_PROGRESS') == '', 'Other items are kept')
quest = { title = 'Pay the Toll', completable = true, money = 500 }
assert(questEvent('QUEST_PROGRESS') == '', 'Quests that cost money are left alone')
quest = { title = 'Spend Valor', completable = true, currencies = 1 }
assert(questEvent('QUEST_PROGRESS') == '', 'Quests that cost currency are left alone')
quest = { title = 'Wanted: Hogger', choices = 0 }
assert(questEvent('QUEST_COMPLETE') == 'reward 0')
quest.choices = 1
assert(questEvent('QUEST_COMPLETE') == 'reward 1', 'A single reward is taken')
quest.choices = 3
assert(questEvent('QUEST_COMPLETE') == '', 'Several rewards are left to the player')
-- Gossip lists: completed quests first, one per event, skipped quests stay skipped for a while.
gossip.active = { { title = 'Bounty', isComplete = false, questID = 1 }, { title = 'Wanted: Hogger', isComplete = true, questID = 2 } }
gossip.available = { { title = 'Daily Chores', frequency = 1, questID = 3 },
    { title = 'Gray Errand', frequency = 0, isTrivial = true, questID = 4 }, { title = 'New Lead', frequency = 0, questID = 5 } }
assert(questEvent('GOSSIP_SHOW') == 'pick 3', 'The quest with a reward choice is not reopened right away')
local realGetTime = GetTime
GetTime = function() return 131 end
assert(questEvent('GOSSIP_SHOW') == 'turnin 2', 'Completed quest picked again later')
GetTime = realGetTime
gossip.active = { gossip.active[1] }
assert(questEvent('GOSSIP_SHOW') == 'pick 3', 'Then available quests')
SlashCmdList.SQOL('qd')
assert(questEvent('GOSSIP_SHOW') == 'pick 5', 'Daily off; low-level quests skipped')
C_Minimap = { IsTrackingHiddenQuests = function() return true end }
assert(questEvent('GOSSIP_SHOW') == 'pick 4', 'Low-level quests while the minimap shows them')
C_Minimap = nil
issecretvalue = function() return true end
assert(questEvent('GOSSIP_SHOW') == '' and questEvent('QUEST_DETAIL') == '', 'Secret values are never acted on')
issecretvalue = nil
-- Greeting panel (NPCs without gossip).
local greeting = { active = { { 'Bounty', false } }, available = { { 'Daily Chores', false, 1 }, { 'New Lead', false, 0 } } }
function GetNumActiveQuests() return #greeting.active end
function GetActiveTitle(i) return greeting.active[i][1], greeting.active[i][2] end
function GetNumAvailableQuests() return #greeting.available end
function GetAvailableTitle(i) return greeting.available[i][1] end
function GetAvailableQuestInfo(i) return greeting.available[i][2], greeting.available[i][3] end
SelectActiveQuest, SelectAvailableQuest = questCall('greet-turnin'), questCall('greet-pick')
assert(questEvent('QUEST_GREETING') == 'greet-pick 2', 'Greeting skips unfinished and daily quests')
greeting.active[1][2] = true
assert(questEvent('QUEST_GREETING') == 'greet-turnin 1', 'Greeting turns in first')
GetNumActiveQuests, GetActiveTitle, GetNumAvailableQuests, GetAvailableTitle = nil, nil, nil, nil
GetAvailableQuestInfo, SelectActiveQuest, SelectAvailableQuest = nil, nil, nil
-- Combat inside instances pauses everything; auto-complete popups open the reward.
function IsInInstance() return true end
function InCombatLockdown() return true end
quest = { title = 'Wanted: Hogger' }
assert(questEvent('QUEST_DETAIL') == '' and questEvent('QUEST_AUTOCOMPLETE', 77) == '', 'No automation in instance combat')
function InCombatLockdown() return false end
IsInInstance = nil
assert(questEvent('QUEST_AUTOCOMPLETE', 77) == 'show 77')
for _, command in ipairs({ 'qa', 'qw', 'qt' }) do SlashCmdList.SQOL(command) end
assert(questEvent('QUEST_DETAIL') == '' and questEvent('GOSSIP_SHOW') == '', 'All off stops listening')

-- Wowhead links: the world map's quest, the opened achievement, and the
-- "Show web link" binding for what the mouse is over.
local plainHook = hooksecurefunc
function hooksecurefunc(object, method, callback)
    if type(object) == 'string' then object, method, callback = _G, object, method end
    local original = object[method]
    object[method] = function(...) original(...) callback(...) end
end
WorldMapFrame = widget()
WorldMapFrame.BorderFrame = widget()
WorldMapFrameTitleText = widget()
WorldMapFrameTitleText:Show()
QuestMapFrame = { DetailsFrame = widget() }
local superTracked, detailQuest = 0, nil
C_SuperTrack = { GetSuperTrackedQuestID = function() return superTracked end }
function QuestMapFrame_GetDetailQuestID() return detailQuest end
function QuestMapFrame_ShowQuestDetails(questID) detailQuest = questID QuestMapFrame.DetailsFrame:Show() end
function QuestMapFrame_CloseQuestDetails() QuestMapFrame.DetailsFrame:Hide() end
local savedQuestLog = C_QuestLog
C_QuestLog = { GetTitleForQuestID = function(id) return id == 176 and 'Wanted: Hogger' or nil end }
local before = #frames
SlashCmdList.SQOL('wowhead')
local mapBox = frames[before + 1]
assert(sqol.DB.ShowWowheadLinks and mapBox and not mapBox:IsShown(), 'No quest, no link')
assert(mapBox.keyboard == true, 'CTRL+C must reach the link, not the C key binding')
assert(WorldMapFrameTitleText:IsShown())
superTracked = 176
fire('SUPER_TRACKING_CHANGED')
assert(mapBox:IsShown() and mapBox.text == 'https://wowhead.com/quest=176' and mapBox.title == 'Wanted: Hogger')
assert(not WorldMapFrameTitleText:IsShown(), 'The link takes the place of the map title')
QuestMapFrame_ShowQuestDetails(26)
assert(mapBox.text == 'https://wowhead.com/quest=26', 'Quest details win over the super-tracked quest')
QuestMapFrame_CloseQuestDetails()
assert(mapBox.text == 'https://wowhead.com/quest=176')
mapBox:SetText('typed')
mapBox.scripts.OnTextChanged(mapBox, true)
assert(mapBox.text == 'https://wowhead.com/quest=176', 'The link cannot be edited')
sqol.Locale = 'deDE'
fire('SUPER_TRACKING_CHANGED')
assert(mapBox.text == 'https://de.wowhead.com/quest=176', 'Retail uses language subdomains')
sqol.Locale = 'enUS'
AchievementFrame = widget()
AchievementTemplateMixin = { DisplayObjectives = function() end }
function AchievementFrameComparisonTab_OnClick() end
function GetAchievementInfo(id) return id, 'Explore Elwynn Forest' end
before = #frames
fire('ADDON_LOADED', 'Blizzard_AchievementUI')
local achievementBox = frames[before + 1]
assert(achievementBox.keyboard == true, 'CTRL+C must reach the achievement link')
AchievementTemplateMixin:DisplayObjectives(776, false)
assert(achievementBox:IsShown() and achievementBox.text == 'https://wowhead.com/achievement=776'
    and achievementBox.title == 'Explore Elwynn Forest')
AchievementFrameComparisonTab_OnClick(2)
assert(not achievementBox:IsShown(), 'Comparison hides the link')
SlashCmdList.SQOL('wh')
AchievementTemplateMixin:DisplayObjectives(776, false)
assert(not sqol.DB.ShowWowheadLinks and not mapBox:IsShown() and not achievementBox:IsShown())
assert(WorldMapFrameTitleText:IsShown(), 'Turning the option off restores the map title')

-- "Show web link" works without the option, in this order: item, spell,
-- tooltip data, a link the tooltip was given, NPC, player, search.
ItemRefTooltip = widget()
function GameTooltip:GetName() return 'GameTooltip' end
function ItemRefTooltip:GetName() return 'ItemRefTooltip' end
local function tooltipShows(title)
    GameTooltip.lines = {}
    GameTooltip:AddLine(title)
    GameTooltip:Show()
end
local function webLink()
    if SQOL_WebLinkPopup then SQOL_WebLinkPopup:Hide() end
    SMoRGsQoL_ShowWebLink()
    local popup = SQOL_WebLinkPopup
    return popup and popup:IsShown() and popup.box.text or nil, popup and popup.label.text
end
tooltipShows('Thunderfury, Blessed Blade of the Windseeker')
GameTooltip.GetItem = function() return 'Thunderfury', '|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r' end
local url, label = webLink()
assert(url == 'https://wowhead.com/item=19019' and label:find('(19019)', 1, true), tostring(url))
assert(UISpecialFrames[#UISpecialFrames] == 'SQOL_WebLinkPopup', 'Escape closes the popup')
GameTooltip.GetItem = nil
GameTooltip.GetSpell = function() return 'Fireball', 133 end
assert(webLink() == 'https://wowhead.com/spell=133')
GameTooltip.GetSpell = nil
GameTooltip.GetPrimaryTooltipData = function() return { type = 23, id = 176 } end
assert(webLink() == 'https://wowhead.com/quest=176', 'Quest tooltip data')
GameTooltip.GetPrimaryTooltipData = function() return { type = 7, id = 1459 } end
assert(webLink() == 'https://wowhead.com/spell=1459', 'Aura tooltip data')
GameTooltip.GetPrimaryTooltipData = nil
-- A link set on the tooltip counts while the tooltip still shows its title.
function GameTooltip:SetHyperlink() tooltipShows('Explore Elwynn Forest') end
sqol._webLinkTooltipsHooked = nil
sqol.WebLink_HookTooltips()
GameTooltip:SetHyperlink('achievement:776:Player-1:0:0:0:0:0:0:0:0')
assert(webLink() == 'https://wowhead.com/achievement=776', 'Hyperlink on the tooltip')
-- NPCs under the mouse; players get their armory page.
local mouseover = { guid = 'Creature-0-1465-0-2105-448-000043F59F', name = 'Hogger' }
function UnitGUID(unit) return unit == 'mouseover' and mouseover.guid or nil end
function UnitName(unit) return mouseover.name, mouseover.realm end
function UnitExists(unit) return unit == 'mouseover' end
function UnitIsPlayer() return mouseover.player == true end
tooltipShows('Hogger')
assert(webLink() == 'https://wowhead.com/npc=448', 'NPC from the mouseover GUID')
mouseover = { guid = 'Player-1305-0ABCDEF1', name = 'Smorg', realm = 'TwistingNether', player = true }
function GetCurrentRegion() return 3 end
tooltipShows('Smorg')
url, label = webLink()
assert(url == 'https://worldofwarcraft.com/en-gb/character/eu/twisting-nether/smorg', tostring(url))
assert(label:find('Twisting Nether', 1, true))
mouseover.realm = 'Area52'
assert(webLink() == 'https://worldofwarcraft.com/en-gb/character/eu/area-52/smorg', 'Realm exceptions')
UnitGUID, UnitName, UnitExists, UnitIsPlayer, GetCurrentRegion = nil, nil, nil, nil, nil
-- Anything else searches Wowhead for the tooltip's title.
tooltipShows('|cffffffffCharacter Info|r')
assert(webLink() == 'https://wowhead.com/search?q=Character%20Info', 'Search fallback')
-- ItemRefTooltip (a link clicked in chat) wins while the mouse is over it.
ItemRefTooltip:Show()
ItemRefTooltip.mouseOver = true
ItemRefTooltip.GetItem = function() return 'Linen Cloth', 'item:2589' end
assert(webLink() == 'https://wowhead.com/item=2589', 'Chat link tooltip')
ItemRefTooltip:Hide()
issecretvalue = function() return true end
assert(webLink() == nil, 'Secret tooltip text is never linked')
issecretvalue = nil
GameTooltip:Hide()
assert(webLink() == nil, 'Nothing under the mouse, no popup')
-- CTRL+C closes the popup.
tooltipShows('Hogger')
webLink()
modifiers.CONTROL = true
SQOL_WebLinkPopup.box.scripts.OnKeyDown(SQOL_WebLinkPopup.box, 'C')
modifiers.CONTROL = nil
pending[#pending]()
table.remove(pending)
assert(not SQOL_WebLinkPopup:IsShown(), 'Copying closes the popup')
assert(BINDING_HEADER_SMORGSQOL == "SMoRG's QoL" and BINDING_NAME_SMORGSQOL_WEBLINK == 'Show web link')
GameTooltip.lines, GameTooltip.SetHyperlink, GameTooltip.GetName = {}, nil, nil
C_QuestLog, C_SuperTrack, QuestMapFrame = savedQuestLog, nil, nil
QuestMapFrame_GetDetailQuestID, QuestMapFrame_ShowQuestDetails, QuestMapFrame_CloseQuestDetails = nil, nil, nil
hooksecurefunc = plainHook

local scheduled = pending
pending = {}
for _, fn in ipairs(scheduled) do fn() end

-- Real chat routing: independent of RepWatch; ignore losses and hidden values.
local before = #frames
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Valarjar increased by 25.')
assert(#frames == before, 'Disabled rep text must not allocate a frame')
SlashCmdList.SQOL('reptext')
assert(sqol.DB.ShowRepGains and not sqol.DB.RepWatch)
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Valarjar decreased by 25.')
issecretvalue = function() return true end
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Valarjar increased by 25.')
issecretvalue = nil
assert(#frames == before, 'Losses and secret messages must be ignored')
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', '|cff00ff00Reputation with Valarjar increased by 1,250.|r')
local repFrame = frames[#frames]
assert(repFrame:IsShown() and repFrame.fontStrings[1].text == '+1250 Rep — Valarjar')
for i = 1, 6 do
    fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Your reputation with Stormwind has increased by 10.')
end
assert(#repFrame.fontStrings == 3, 'Burst gains must reuse the bounded label pool')
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', "Your Warband's reputation with The Wild Hunt increased by 30.")
local warbandShown = false
for _, fs in ipairs(repFrame.fontStrings) do
    if fs.text == '+30 Rep — The Wild Hunt' then warbandShown = true end
end
assert(warbandShown, 'Account-wide (Warband) gains must be shown')
-- Other client languages: patterns come from Blizzard's localized templates.
FACTION_STANDING_INCREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verbessert."
FACTION_STANDING_DECREASED = "Réputation auprès de la faction %s baissée de %d |4point:points;."
FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "Отношение |3-7(%s) к вашему отряду улучшилось на %d."
sqol.Rep_ResetPatterns()
local function parsed(msg) return table.concat({ tostring((sqol.Rep_ParseMessage(msg))), tostring(select(2, sqol.Rep_ParseMessage(msg))), tostring(select(3, sqol.Rep_ParseMessage(msg))) }, '|') end
assert(parsed("Euer Ruf bei der Fraktion 'Valdrakken' hat sich um 250 verbessert.") == 'Valdrakken|250|true')
assert(parsed('Réputation auprès de la faction Hurlevent baissée de 10 |4point:points;.') == 'Hurlevent|10|false')
assert(parsed('Réputation auprès de la faction Hurlevent baissée de 10 points.') == 'Hurlevent|10|false')
assert(parsed('Отношение |3-7(Орда) к вашему отряду улучшилось на 30.') == 'Орда|30|true')
assert(parsed('Reputation with Valarjar increased by 25.') == 'Valarjar|25|true', 'enUS fallback stays')
FACTION_STANDING_INCREASED, FACTION_STANDING_DECREASED, FACTION_STANDING_INCREASED_ACCOUNT_WIDE = nil, nil, nil
sqol.Rep_ResetPatterns()
repFrame.scripts.OnUpdate(repFrame, 3)
assert(not repFrame:IsShown(), 'Floating labels must expire')
SlashCmdList.SQOL('reptexttest')
assert(repFrame:IsShown())
SlashCmdList.SQOL('rt')
assert(not repFrame:IsShown() and not sqol.DB.ShowRepGains)
SlashCmdList.SQOL('reptexttest')
-- Adventure Recap is routed independently of quest sounds and reputation text.
sqol.SetOption('QuestCompleteSound', false)
sqol.SetOption('QuestObjectiveSound', false)
sqol.SetOption('AdventureRecap', true)
local recapBefore = sqol.Recap_GetSummary().quests
fire('QUEST_LOG_UPDATE')
fire('QUEST_REMOVED', 920001)
assert(sqol.Recap_GetSummary().quests == recapBefore, 'Ready/removal events never count as turn-ins')
fire('QUEST_TURNED_IN', 920001)
fire('QUEST_TURNED_IN', 920001)
assert(sqol.Recap_GetSummary().quests == recapBefore + 1, 'Turn-in routing deduplicates quests')
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Valarjar increased by 25.',
    nil, nil, nil, nil, nil, nil, nil, nil, nil, 72001)
fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Valarjar increased by 25.',
    nil, nil, nil, nil, nil, nil, nil, nil, nil, 72001)
assert(sqol.Recap_GetSummary().reputation == 25, 'Chat line ID reaches recap independently of rep text')
SlashCmdList.SQOL('recap test')
assert(SQOL_AdventureRecap:IsShown() and SQOL_AdventureRecap.values[1].text == '18')
SlashCmdList.SQOL('recap')
assert(SQOL_AdventureRecap.values[1].text == tostring(recapBefore + 1), 'Slash command shows real totals')
fire('PLAYER_LEAVING_WORLD')
fire('PLAYER_LOGOUT')
assert(SQOL_RecapDB.current.quests == recapBefore + 1, 'Logout saves per-character totals')
-- Commands and checkbox state use the same per-character preference.
local memoryWatched = { factionID = 69, name = 'Darnassus', currentStanding = 500 }
C_Reputation = { GetWatchedFactionData = function() return memoryWatched end }
SlashCmdList.SQOL('repfocus')
assert(SQOL_CharacterDB.preferredFaction.factionID == 69, 'Command saves watched faction per character')
SlashCmdList.SQOL('repfocus status')
SlashCmdList.SQOL('config')
SlashCmdList.SQOL('rm')
assert(sqol.DB.RepMemory and popupControls.RepMemory.checked, 'Memory checkbox follows slash command')
SlashCmdList.SQOL('config')
SlashCmdList.SQOL('rep')
memoryWatched = { factionID = 72, name = 'Stormwind', currentStanding = 800 }
fire('UPDATE_FACTION')
assert(sqol._repLastStanding == nil, 'External selection invalidates pending delta baseline')
SlashCmdList.SQOL('radar')
assert(sqol.DB.SmartQuestRadar, 'Radar enabled before settings reset')
local radarLabel = widget()
radarLabel:Show()
sqol._npUnits.nameplateReset = { SQOLObjectiveText = radarLabel }
SlashCmdList.SQOL('reset')
assert(not sqol.DB.SmartQuestRadar and not radarLabel:IsShown()
    and not sqol._npUnits.nameplateReset, 'Settings reset immediately clears radar overlays')
assert(not sqol.DB.RepMemory and not sqol.DB.RepWatch
    and SQOL_CharacterDB.preferredFaction.factionID == 69, 'Reset disables memory and preserves preference')
SlashCmdList.SQOL('repfocus clear')
assert(SQOL_CharacterDB.preferredFaction == nil, 'Clear command removes the preference')
assert(not sqol.DB.AdventureRecap and SQOL_RecapDB.current.quests == recapBefore + 1,
    'Settings reset pauses recap while preserving session data')
assert(not repFrame:IsShown() and not sqol.DB.ShowRepGains)
assert(not sqol.DB.ShowItemLevel and not sqol.DB.ShowMovementSpeed)
assert(not sqol.DB.AutoAcceptQuests and sqol.DB.QuestAutomationKey == 'SHIFT', 'Reset turns quest automation off')
assert(not sqol.DB.ShowWowheadLinks, 'Reset turns Wowhead links off')
for _, message in ipairs(messages) do io.write(message, '\n') end
io.write('PASS: TOC loading, login, commands, independent options, events, deferred callbacks, Wowhead links, reset\n')
