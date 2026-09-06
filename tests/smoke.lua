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
    for _, method in ipairs({ 'SetSize', 'SetPoint', 'ClearAllPoints', 'SetWidth',
        'SetFrameStrata', 'SetJustifyH', 'SetWordWrap', 'SetMaxLines', 'SetTextColor',
        'SetTexture', 'SetBlendMode', 'SetAlpha', 'SetAllPoints', 'EnableMouse', 'SetVertexColor',
        'SetFading', 'SetTimeVisible', 'SetFadeDuration', 'SetMaxLines',
        'SetInsertMode', 'SetSpacing', 'AddMessage' }) do
        w[method] = function() end
    end
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

local sqol = {}
local files = {}
if arg[1] then
    -- Optional pre-refactor baseline, for behavioral comparison during extraction.
    files = { arg[1], 'Options.lua', 'StatusBarProgress.lua' }
else
    for line in io.lines('SMoRGsQoL.toc') do
        local file = line:match('^([^#].-%.lua)%s*$')
        if file then files[#files + 1] = file end
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
    'rep', 'rep', 'nameplate', 'nameplate', 'partylevel', 'partylevel',
    'rctest', 'lfgtest', 'help', '' }) do
    SlashCmdList.SQOL(command)
end
assert(not sqol.DB.ShowItemLevel and not sqol.DB.ShowMovementSpeed)
assert(not sqol.DB.ColorProgress and not sqol.DB.ColorStatusBarProgress)
assert(sqol.iLvlHolder and not sqol.iLvlHolder:IsShown())
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
sqol.SetOption('ColorStatusBarProgress', false)
assert(repBar.OverlayFrame.Text.text == 'Avengers of Hyjal 6000 / 12000')
C_Reputation, StatusTrackingBarInfo, StatusTrackingBarManager = nil, nil, nil
hooksecurefunc = oldHook

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
repFrame.scripts.OnUpdate(repFrame, 3)
assert(not repFrame:IsShown(), 'Floating labels must expire')
SlashCmdList.SQOL('reptexttest')
assert(repFrame:IsShown())
SlashCmdList.SQOL('rt')
assert(not repFrame:IsShown() and not sqol.DB.ShowRepGains)
SlashCmdList.SQOL('reptexttest')
SlashCmdList.SQOL('reset')
assert(not repFrame:IsShown() and not sqol.DB.ShowRepGains)
assert(not sqol.DB.ShowItemLevel and not sqol.DB.ShowMovementSpeed)
for _, message in ipairs(messages) do io.write(message, '\n') end
io.write('PASS: TOC loading, login, commands, independent options, events, deferred callbacks, reset\n')
