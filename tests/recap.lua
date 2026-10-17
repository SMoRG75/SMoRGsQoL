-- Run from the repository root: lua tests/recap.lua
-- Simulates separate UI lifetimes while preserving per-character variables.
local timestamp, frames, messages = 0, {}, {}
local function widget()
    local w = { scripts = {}, shown = false, texts = {} }
    function w:SetScript(key, callback) self.scripts[key] = callback end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetText(value) self.text = value end
    function w:GetPoint() return "CENTER", UIParent, "CENTER", 42, -18 end
    function w:CreateFontString()
        local label = widget()
        self.texts[#self.texts + 1] = label
        return label
    end
    function w:CreateTexture() return widget() end
    for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetFrameStrata",
        "SetToplevel", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
        "StartMoving", "StopMovingOrSizing", "SetBackdrop", "SetBackdropColor",
        "SetBackdropBorderColor", "SetJustifyH", "SetTextColor", "SetColorTexture" }) do
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
function GetTime() return timestamp end
function print(message) messages[#messages + 1] = message end
C_Timer = { After = function() error("Recap must not schedule tracking timers") end }
UIParent, UISpecialFrames = widget(), {}
local secret = setmetatable({}, { __tostring = function() error("Read a secret value") end })
function canaccessvalue(value) return value ~= secret end
local function loadRecap(enabled, reload)
    local addon = {}
    for _, file in ipairs({ "Locales/Locales.lua", "Core.lua", "Reputation.lua", "SessionRecap.lua" }) do
        assert(loadfile(file))("SMoRGsQoL", addon)
    end
    addon.DB = { AdventureRecap = enabled }
    addon.Recap_EnteringWorld(not reload, reload)
    return addon
end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function enabled(addon, value)
    addon.DB.AdventureRecap = value
    addon.Recap_OnOptionChanged()
end
C_QuestLog = { IsWorldQuest = function(id) return id == 200 end }
SQOL_RecapDB = nil
local addon = loadRecap(false, false)
equal(addon.Recap_GetSummary(), nil, "Disabled by default")
equal(#frames, 0, "No UI allocation during tracking initialization")
addon.Recap_QuestTurnedIn(100)
addon.Recap_ReputationMessage("Reputation with Valarjar increased by 25.")
equal(SQOL_RecapDB.current, nil, "Disabled events do not create a session")
addon.Recap_Command("test")
local frame = SQOL_AdventureRecap
equal(frame.values[1].text, "18", "Sample quests")
equal(frame.values[4].text, "2h 15m", "Sample duration")
equal(SQOL_RecapDB.current, nil, "Preview does not enable collection")
frame:Hide()
enabled(addon, true)
timestamp = 60
addon.Recap_QuestTurnedIn(100)
addon.Recap_QuestTurnedIn(100)
addon.Recap_QuestTurnedIn(200)
equal(addon.Recap_GetSummary().quests, 2, "Duplicate turn-in event")
equal(addon.Recap_GetSummary().worldQuests, 1, "World quests are a subset")
addon.Recap_QuestAccepted(100)
addon.Recap_QuestTurnedIn(100)
equal(addon.Recap_GetSummary().quests, 3, "Repeatable quest accepted again")
addon.Recap_QuestTurnedIn(secret)
addon.Recap_QuestTurnedIn(0)
addon.Recap_QuestTurnedIn(nil)
equal(addon.Recap_GetSummary().quests, 3, "Invalid and secret quest IDs")
addon.Recap_ReputationMessage("Reputation with Valarjar increased by 25.", 1)
addon.Recap_ReputationMessage("Reputation with Valarjar increased by 25.", 1)
addon.Recap_ReputationMessage("Reputation with Valarjar increased by 25.", 2)
addon.Recap_ReputationMessage("Reputation with Stormwind decreased by 10.", 3)
addon.Recap_ReputationMessage("|cff00ff00Reputation with Stormwind increased by 1,250.|r", 4)
addon.Recap_ReputationMessage("Your Warband's reputation with Valarjar increased by 30.", 5)
equal(addon.Recap_GetSummary().reputation, 1330, "Gains only, deduplicate by chat ID")
equal(addon.Recap_GetSummary().topFaction, "Stormwind", "Top faction")
equal(addon.Recap_GetSummary().topAmount, 1250, "Top faction gain")
local snapshot = addon.Recap_GetSummary()
snapshot.quests = 999
equal(addon.Recap_GetSummary().quests, 3, "Detached summary")
addon.Recap_EnteringWorld(false, false)
equal(addon.Recap_GetSummary().quests, 3, "Zone change keeps the session")
timestamp = 120
enabled(addon, false)
timestamp = 360
addon.Recap_QuestTurnedIn(300)
addon.Recap_ReputationMessage("Reputation with Stormwind increased by 900.")
equal(addon.Recap_GetSummary().elapsed, 120, "Disabled time is excluded")
equal(addon.Recap_GetSummary().quests, 3, "Disabled quests are excluded")
enabled(addon, true)
timestamp = 420
addon.Recap_Save()
addon.Recap_Save()
equal(SQOL_RecapDB.current.elapsed, 180, "Repeated checkpoints never double time")
-- A new Lua environment is created by /reload; only saved state survives.
timestamp = 440
addon = loadRecap(true, true)
equal(addon.Recap_GetSummary().quests, 3, "Reload keeps quests")
equal(addon.Recap_GetSummary().elapsed, 180, "Reload excludes loading gap")
equal(addon.Recap_GetSummary(true), nil, "Reload does not create a previous session")
addon.Recap_QuestTurnedIn(200)
equal(addon.Recap_GetSummary().quests, 3, "Duplicate quest across reload")
timestamp = 500
addon.Recap_Save()
local characterA = SQOL_RecapDB
SQOL_RecapDB = nil
local alt = loadRecap(true, false)
equal(alt.Recap_GetSummary().quests, 0, "A different character starts empty")
alt.Recap_QuestTurnedIn(700)
equal(characterA.current.quests, 3, "Alt cannot change original character")
SQOL_RecapDB = characterA
timestamp = 10000
addon = loadRecap(true, false)
equal(addon.Recap_GetSummary().quests, 0, "Login starts a new session")
equal(addon.Recap_GetSummary(true).quests, 3, "Login archives the previous session")
equal(addon.Recap_GetSummary(true).elapsed, 240, "Offline time is excluded")
equal(next(SQOL_RecapDB.last.seenQuests), nil, "Discard previous duplicate markers")
addon.Recap_QuestTurnedIn(100)
equal(addon.Recap_GetSummary().quests, 1, "Old quest ID can count in a new session")
addon.Recap_ReputationMessage(secret)
equal(addon.Recap_GetSummary().reputationIncomplete, true, "Secret reputation marks partial")
equal(addon.Recap_GetSummary().reputation, 0, "Secret reputation is never guessed")
addon.Recap_ReputationMessage("Reputation with Valarjar increased by 25.")
equal(addon.Recap_GetSummary().topFaction, nil, "Partial totals cannot claim a top faction")
addon.Recap_Command("")
frame = SQOL_AdventureRecap
equal(frame.values[3].text, "+25*", "Partial reputation is visible")
frame.scripts.OnDragStop(frame)
equal(SQOL_RecapDB.position[4], -18, "Window position is per character")
local beforePreview = SQOL_RecapDB.current
addon.Recap_Command("test")
equal(frame.values[1].text, "18", "Preview after real data")
equal(SQOL_RecapDB.current, beforePreview, "Preview keeps real session")
addon.Recap_Command("last")
equal(frame.values[1].text, "3", "Previous session display")
addon.Recap_Command("reset")
equal(addon.Recap_GetSummary().quests, 0, "Reset current totals")
equal(addon.Recap_GetSummary(true).quests, 3, "Reset preserves previous session")
equal(addon.Recap_GetSummary().reputationIncomplete, nil, "Reset clears partial flag")
C_QuestLog = nil
addon.Recap_QuestTurnedIn(400)
equal(addon.Recap_GetSummary().quests, 1, "Missing classification API keeps quest totals")
equal(addon.Recap_GetSummary().worldQuestsIncomplete, true, "Missing classification marks partial")
addon.Recap_Command("")
equal(frame.values[2].text, "0+", "Partial world quests are visible")
QuestUtils_IsQuestWorldQuest = function() return true end
addon.Recap_QuestTurnedIn(401)
equal(addon.Recap_GetSummary().worldQuests, 1, "Legacy classification fallback")
QuestUtils_IsQuestWorldQuest = function() error("Client API failure") end
addon.Recap_QuestTurnedIn(402)
equal(addon.Recap_GetSummary().quests, 3, "API errors do not lose the turn-in")
QuestUtils_IsQuestWorldQuest = function() return secret end
addon.Recap_QuestTurnedIn(403)
equal(addon.Recap_GetSummary().worldQuests, 1, "Secret classification is not counted")
QuestUtils_IsQuestWorldQuest = nil
addon.Recap_Command("reset")
addon.Recap_ReputationMessage("Reputation with Valarjar increased.")
equal(addon.Recap_GetSummary().reputationIncomplete, true, "Generic gain has unknown amount")
addon.Recap_Command("reset")
addon.Recap_ReputationMessage("Unrecognized client reputation message")
equal(addon.Recap_GetSummary().reputationIncomplete, true, "Unrecognized message marks partial")
-- Reuse localized templates rather than parsing English-only messages.
FACTION_STANDING_INCREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verbessert."
addon.Rep_ResetPatterns()
addon.Recap_Command("reset")
addon.Recap_ReputationMessage("Euer Ruf bei der Fraktion 'Valdrakken' hat sich um 250 verbessert.")
equal(addon.Recap_GetSummary().reputation, 250, "Localized reputation gain")
equal(addon.Recap_GetSummary().topFaction, "Valdrakken", "Localized faction name")
FACTION_STANDING_INCREASED = nil
-- Restore a paused session across reload; enabling resumes only from now.
enabled(addon, false)
addon.Recap_Save()
timestamp = timestamp + 200
addon = loadRecap(false, true)
local paused = addon.Recap_GetSummary().elapsed
timestamp = timestamp + 200
enabled(addon, true)
equal(addon.Recap_GetSummary().elapsed, paused, "Paused reload does not add playtime")
-- Tolerate malformed saved data without touching account settings.
SQOL_RecapDB = { version = 1, current = { quests = -2 }, last = "invalid" }
addon = loadRecap(true, true)
equal(addon.Recap_GetSummary().quests, 0, "Malformed current session")
equal(addon.Recap_GetSummary(true), nil, "Malformed previous session")
io.write("PASS: recap quests, repeatables, reputation, secrets, fallback APIs, reload, login, characters, pause, reset and preview\n")
