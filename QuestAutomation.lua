local ADDON_NAME, SQOL = ...
local L = SQOL.L

------------------------------------------------------------
-- Quest automation
-- Accepts and turns in quests at quest givers, like Leatrix Plus'
-- "Automate quests". The override key works both ways: normally holding
-- it pauses automation for that quest giver; with "Require override key"
-- on, quests are only automated while it is held.
--
-- To stay safe it never picks between several rewards, never hands in
-- money, currency or items that aren't quest items, never accepts quests
-- that flag you for PvP or that another player shared (escorts, group
-- quests in instances), does nothing in combat inside instances, and in
-- gossip only clicks quest lines, never gossip options (dungeon NPCs often
-- start an event from there). A quest it leaves for you is not picked
-- again for a while, so Back in the quest frame returns to the list.
------------------------------------------------------------
local SQOL_DECLINED_SECONDS = 30
local SQOL_ITEM_CLASS_QUEST = 12 -- Enum.ItemClass.Questitem
local SQOL_FREQUENCY_DAILY = 1   -- Enum.QuestFrequency / LE_QUEST_FREQUENCY_*

-- The modifier check for each override key setting.
local SQOL_OVERRIDE_KEY_CHECKS = {
    SHIFT = "IsShiftKeyDown",
    ALT = "IsAltKeyDown",
    CONTROL = "IsControlKeyDown",
    CMD = "IsMetaKeyDown",
}
local SQOL_OVERRIDE_KEY_ORDER = { "SHIFT", "ALT", "CONTROL", "CMD" }
local SQOL_OVERRIDE_KEY_ALIASES = { CTRL = "CONTROL", META = "CMD", COMMAND = "CMD" }

local SQOL_QUEST_EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_GREETING", "GOSSIP_SHOW", "QUEST_AUTOCOMPLETE" }

local declinedAt = {}
local eventFrame = CreateFrame("Frame")

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

-- Calls a global API. A missing function gives the fallback; an error or a
-- secret value (12.x) gives UNKNOWN, which callers treat as the unsafe case.
local UNKNOWN = {}
local function SQOL_Ask(name, fallback, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return fallback
    end
    local ok, value = pcall(fn, ...)
    if ok and SQOL.CanUseValue(value) then
        return value
    end
    return UNKNOWN
end

-- true/false (older APIs answer 1 or nil), or nil when unknown.
local function SQOL_Flag(name, fallback, ...)
    local value = SQOL_Ask(name, fallback, ...)
    if value == UNKNOWN then return nil end
    return value and true or false
end

-- A count or amount (nil counts as 0), or nil when unknown.
local function SQOL_Number(name, ...)
    local value = SQOL_Ask(name, 0, ...)
    if value == UNKNOWN then return nil end
    return tonumber(value or 0)
end

local function SQOL_Usable(...)
    for i = 1, select("#", ...) do
        if not SQOL.CanUseValue((select(i, ...))) then
            return false
        end
    end
    return true
end

local function SQOL_AcceptsQuests()
    local db = SQOL.DB
    return db and (db.AutoAcceptQuests or db.AutoAcceptDailyQuests or db.AutoAcceptWeeklyQuests)
end

local function SQOL_TurnsInQuests()
    return SQOL.DB and SQOL.DB.AutoTurnInQuests
end

-- Retail and the gossip API report a frequency number (0 regular, 1 daily,
-- 2 weekly, 3 other scheduled resets); Classic's GetAvailableQuestInfo
-- reports isDaily instead.
local function SQOL_FrequencyAllowed(frequency)
    local db = SQOL.DB
    if frequency == true then
        frequency = SQOL_FREQUENCY_DAILY
    end
    if frequency == nil or frequency == false or frequency == 0 then
        return db.AutoAcceptQuests
    elseif frequency == SQOL_FREQUENCY_DAILY then
        return db.AutoAcceptDailyQuests
    elseif type(frequency) == "number" then
        return db.AutoAcceptWeeklyQuests
    end
    return false
end

local function SQOL_OverrideKeyDown()
    local check = _G[SQOL_OVERRIDE_KEY_CHECKS[SQOL.DB.QuestAutomationKey] or "IsShiftKeyDown"]
    return type(check) == "function" and check() and true or false
end

local function SQOL_AutomationAllowed()
    if not SQOL.DB then return false end
    if SQOL_Flag("InCombatLockdown", false) ~= false and SQOL_Flag("IsInInstance", false) ~= false then
        return false
    end
    if SQOL.DB.QuestAutomationRequireKey then
        return SQOL_OverrideKeyDown()
    end
    return not SQOL_OverrideKeyDown()
end

-- Quests this module left for the player, by title, so the quest list
-- doesn't open them again right away.
local function SQOL_Decline(reason)
    local title = SQOL_Ask("GetTitleText")
    if title == UNKNOWN then title = nil end
    SQOL.dprint("Quest automation skipped", tostring(title), reason)
    if not title then return end
    local now = GetTime()
    for key, at in pairs(declinedAt) do
        if now - at >= SQOL_DECLINED_SECONDS then
            declinedAt[key] = nil
        end
    end
    declinedAt[title] = now
end

local function SQOL_IsDeclined(title)
    local at = declinedAt[title]
    return at ~= nil and GetTime() - at < SQOL_DECLINED_SECONDS
end

-- Low-level (gray) quests are picked only while the minimap shows them.
local function SQOL_ShowsTrivialQuests()
    local minimap = rawget(_G, "C_Minimap")
    if not (minimap and type(minimap.IsTrackingHiddenQuests) == "function") then
        return false
    end
    local ok, tracking = pcall(minimap.IsTrackingHiddenQuests)
    return ok and SQOL.CanUseValue(tracking) and tracking == true
end

local function SQOL_ShouldPickAvailable(title, frequency, isTrivial, isIgnored)
    if not SQOL_Usable(title, frequency, isTrivial, isIgnored) or not title then
        return false
    end
    if isIgnored or (isTrivial and not SQOL_ShowsTrivialQuests()) or SQOL_IsDeclined(title) then
        return false
    end
    return SQOL_FrequencyAllowed(frequency) and true or false
end

local function SQOL_ShouldPickActive(title, isComplete)
    return SQOL_Usable(title, isComplete) and title ~= nil
        and isComplete and not SQOL_IsDeclined(title) or false
end

-- True when the quest frame's quest was offered by another player: shared
-- quests and escort/group quests started by a party member. A quest from an
-- item in your own bags shows you as the giver.
local function SQOL_SharedByPlayer()
    local isPlayer = SQOL_Flag("UnitIsPlayer", false, "npc")
    if isPlayer == false then return false end
    if isPlayer == nil then return true end
    return SQOL_Flag("UnitIsUnit", false, "npc", "player") ~= true
end

local function SQOL_GetItemClass(link)
    local itemAPI = rawget(_G, "C_Item")
    local getInfo = itemAPI and itemAPI.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
    if type(getInfo) ~= "function" or not link then return nil end
    local ok, _, _, _, _, _, classID = pcall(getInfo, link)
    if ok and SQOL.CanUseValue(classID) then
        return classID
    end
end

-- True when turning the quest in costs money, currency or items that are
-- not quest items. Unknown counts as a cost.
local function SQOL_TurnInCosts()
    local money = SQOL_Number("GetQuestMoneyToGet")
    if not money or money > 0 then return true end

    -- Classic Era and Anniversary have no quest currencies.
    local currencies = SQOL_Number("GetNumQuestCurrencies")
    if not currencies or currencies > 0 then return true end

    local items = SQOL_Number("GetNumQuestItems")
    if not items then return true end
    for i = 1, items do
        local link = SQOL_Ask("GetQuestItemLink", nil, "required", i)
        if link == UNKNOWN or SQOL_GetItemClass(link) ~= SQOL_ITEM_CLASS_QUEST then
            return true
        end
    end
    return false
end

------------------------------------------------------------
-- Quest frame
------------------------------------------------------------
local function SQOL_OnQuestDetail()
    if not SQOL_AcceptsQuests() then return end

    if SQOL_SharedByPlayer() then
        return SQOL_Decline("shared by a player")
    end
    if SQOL_Flag("QuestFlagsPVP", false) ~= false then
        return SQOL_Decline("flags for PvP")
    end

    local frequency = 0
    local isDaily, isWeekly = SQOL_Flag("QuestIsDaily", false), SQOL_Flag("QuestIsWeekly", false)
    if isDaily == nil or isWeekly == nil then
        return SQOL_Decline("unknown frequency")
    elseif isDaily then
        frequency = SQOL_FREQUENCY_DAILY
    elseif isWeekly then
        frequency = 2
    end
    if not SQOL_FrequencyAllowed(frequency) then
        return SQOL_Decline("frequency is off")
    end

    -- Some quests are already accepted when offered; Blizzard's button
    -- then only acknowledges them.
    if SQOL_Flag("QuestGetAutoAccept", false) and type(AcknowledgeAutoAcceptQuest) == "function" then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end

local function SQOL_OnQuestProgress()
    if not SQOL_TurnsInQuests() then return end
    if SQOL_Flag("IsQuestCompletable", false) ~= true then return end
    if SQOL_TurnInCosts() then
        return SQOL_Decline("costs money, currency or items")
    end
    CompleteQuest()
end

local function SQOL_OnQuestComplete()
    if not SQOL_TurnsInQuests() then return end
    if SQOL_TurnInCosts() then
        return SQOL_Decline("costs money, currency or items")
    end
    local choices = SQOL_Number("GetNumQuestChoices")
    if not choices or choices > 1 then
        return SQOL_Decline("reward choice")
    end
    GetQuestReward(choices)
end

-- Quest givers whose quests show up in the tracker as complete (Retail).
local function SQOL_OnQuestAutoComplete(questID)
    if not SQOL_TurnsInQuests() or SQOL_Flag("InCombatLockdown", false) ~= false then return end
    if questID and SQOL.CanUseValue(questID) and type(ShowQuestComplete) == "function" then
        pcall(ShowQuestComplete, questID)
    end
end

------------------------------------------------------------
-- Quest lists: one quest per event. Turning in or accepting refreshes the
-- list, which picks the next one. Completed quests go first.
------------------------------------------------------------

-- QuestFrame's greeting panel (NPCs without gossip).
local function SQOL_OnQuestGreeting()
    if SQOL_TurnsInQuests() then
        for i = 1, SQOL_Number("GetNumActiveQuests") or 0 do
            local ok, title, isComplete = pcall(GetActiveTitle, i)
            if ok and SQOL_ShouldPickActive(title, isComplete) then
                return SelectActiveQuest(i)
            end
        end
    end
    if SQOL_AcceptsQuests() then
        for i = 1, SQOL_Number("GetNumAvailableQuests") or 0 do
            local title = SQOL_Ask("GetAvailableTitle", nil, i)
            if title == UNKNOWN then title = nil end
            local isTrivial, frequency
            if type(GetAvailableQuestInfo) == "function" then
                local ok
                ok, isTrivial, frequency = pcall(GetAvailableQuestInfo, i)
                if not ok then title = nil end
            end
            if SQOL_ShouldPickAvailable(title, frequency, isTrivial, nil) then
                return SelectAvailableQuest(i)
            end
        end
    end
end

local function SQOL_OnGossipShow()
    local gossip = rawget(_G, "C_GossipInfo")
    if not gossip then return end

    if SQOL_TurnsInQuests() and type(gossip.GetActiveQuests) == "function" then
        local ok, quests = pcall(gossip.GetActiveQuests)
        for _, info in ipairs(ok and type(quests) == "table" and quests or {}) do
            if SQOL_ShouldPickActive(info.title, info.isComplete) and SQOL.CanUseValue(info.questID) then
                return gossip.SelectActiveQuest(info.questID)
            end
        end
    end
    if SQOL_AcceptsQuests() and type(gossip.GetAvailableQuests) == "function" then
        local ok, quests = pcall(gossip.GetAvailableQuests)
        for _, info in ipairs(ok and type(quests) == "table" and quests or {}) do
            if SQOL_ShouldPickAvailable(info.title, info.frequency, info.isTrivial, info.isIgnored)
                and SQOL.CanUseValue(info.questID) then
                return gossip.SelectAvailableQuest(info.questID)
            end
        end
    end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
local SQOL_HANDLERS = {
    QUEST_DETAIL = SQOL_OnQuestDetail,
    QUEST_PROGRESS = SQOL_OnQuestProgress,
    QUEST_COMPLETE = SQOL_OnQuestComplete,
    QUEST_GREETING = SQOL_OnQuestGreeting,
    GOSSIP_SHOW = SQOL_OnGossipShow,
    QUEST_AUTOCOMPLETE = SQOL_OnQuestAutoComplete,
}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not SQOL_AutomationAllowed() then return end
    SQOL_HANDLERS[event](...)
end)

function SQOL.QuestAutomation_IsKey(value)
    return SQOL_OVERRIDE_KEY_CHECKS[value] ~= nil
end

-- /sqol questkey [key]: sets the override key, or steps to the next one.
function SQOL.QuestAutomation_KeyCommand(rest)
    if not SQOL.DB then return end
    local wanted = (rest or ""):upper()
    wanted = SQOL_OVERRIDE_KEY_ALIASES[wanted] or wanted
    local value
    if wanted == "" then
        value = SQOL_OVERRIDE_KEY_ORDER[1]
        for i, key in ipairs(SQOL_OVERRIDE_KEY_ORDER) do
            if key == SQOL.DB.QuestAutomationKey then
                value = SQOL_OVERRIDE_KEY_ORDER[i % #SQOL_OVERRIDE_KEY_ORDER + 1]
            end
        end
    elseif SQOL.QuestAutomation_IsKey(wanted) then
        value = wanted
    else
        print("|cff33ff99SQoL:|r " .. L["Quest automation override key: /sqol questkey [shift | alt | control | cmd]"])
        return
    end
    SQOL.SetOption("QuestAutomationKey", value)
    SQOL.PrintOptionState("QuestAutomationKey")
end

-- Listens only while some automation option is on. Events a client
-- doesn't know (QUEST_AUTOCOMPLETE in Classic Era) are skipped.
function SQOL.QuestAutomation_OnOptionChanged()
    local enabled = SQOL_AcceptsQuests() or SQOL_TurnsInQuests()
    for _, event in ipairs(SQOL_QUEST_EVENTS) do
        if enabled then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        else
            eventFrame:UnregisterEvent(event)
        end
    end
    if not enabled then
        SQOL.TableWipe(declinedAt)
    end
end
