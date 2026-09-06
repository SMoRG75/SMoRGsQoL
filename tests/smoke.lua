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
    function w:CreateFontString() return widget() end
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
local scheduled = pending
pending = {}
for _, fn in ipairs(scheduled) do fn() end
SlashCmdList.SQOL('reset')
assert(not sqol.DB.ShowItemLevel and not sqol.DB.ShowMovementSpeed)
for _, message in ipairs(messages) do io.write(message, '\n') end
io.write('PASS: TOC loading, login, commands, independent options, events, deferred callbacks, reset\n')
