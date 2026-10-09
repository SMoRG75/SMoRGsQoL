local ADDON_NAME, SQOL = ...
-- Feature modules are loaded first by the TOC. This file owns saved settings,
-- commands and event routing; shared entry points live on the SQOL namespace.
local L = SQOL.L
local f = CreateFrame("Frame")

local SQOL_CHAT_PREFIX = "|cff33ff99SQoL:|r "

------------------------------------------------------------
-- SQOL_Init & Reset: ensure saved variables exist
------------------------------------------------------------
function SQOL.Init(reset)
    -- Ensure SavedVariables table exists
    if reset or type(SQOL_DB) ~= "table" then
        SQOL_DB = {}
    end

    -- Preserve the old combined preference once; new settings are independent.
    if SQOL_DB.ShowIlvlSpd ~= nil then
        if SQOL_DB.ShowItemLevel == nil then SQOL_DB.ShowItemLevel = SQOL_DB.ShowIlvlSpd end
        if SQOL_DB.ShowMovementSpeed == nil then SQOL_DB.ShowMovementSpeed = SQOL_DB.ShowIlvlSpd end
        SQOL_DB.ShowIlvlSpd = nil
    end

    -- Apply defaults into SQOL_DB without clobbering user values
    for k, v in pairs(SQOL.defaults) do
        if SQOL_DB[k] == nil then
            SQOL_DB[k] = v
        end
    end

    if not SQOL.QuestSoundProfiles[SQOL_DB.QuestSoundProfile] then
        SQOL_DB.QuestSoundProfile = SQOL.defaults.QuestSoundProfile
    end

    -- Bind runtime DB reference
    SQOL.DB = SQOL_DB

    if reset then
        if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        SQOL.RepGains_Hide()
        if SQOL.RefreshStatusBarProgress then SQOL.RefreshStatusBarProgress() end
        print(SQOL_CHAT_PREFIX .. L["Settings have been reset to defaults."])

        -- 🟢 Apply Achievement filter after reset
        if SQOL.EnsureAchievementUILoaded() then
            C_Timer.After(0.1, function()
                SQOL.ApplyAchievementFilter()
            end)
        end
    end
end

------------------------------------------------------------
-- Get version (Retail APIs)
------------------------------------------------------------
local function SQOL_GetVersion()
    local ok, version = pcall(function()
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            return C_AddOns.GetAddOnMetadata(SQOL.ADDON_NAME, "Version")
        end
        if GetAddOnMetadata then
            return GetAddOnMetadata(SQOL.ADDON_NAME, "Version")
        end
    end)
    if ok and type(version) == "string" and version ~= "" then
        return version
    end
    return "?.?.?"
end

------------------------------------------------------------
-- Status output (splash and /sqol), built from the option list
------------------------------------------------------------
local SQOL_RULE = "|cff33ff99------------------------------------------------------------------------------|r"

local function SQOL_PrintHeader()
    print(SQOL_RULE)
    print("|cff33ff99" .. (SQOL.ADDON_NAME or "SMoRGsQoL") .. " (SQOL)|r |cffffffffv" .. SQOL_GetVersion() .. "|r")
    print(SQOL_RULE)
end

-- "<label>: ON" in chat, e.g. after a slash command toggled it.
function SQOL.PrintOptionState(key)
    local option = SQOL.GetOption(key)
    if option then
        print(SQOL_CHAT_PREFIX .. option.label .. ": " .. SQOL.GetOptionStateText(option))
    end
end

-- "<label> is OFF. Enable it with <command>."
function SQOL.PrintOptionOff(key, command)
    local option = SQOL.GetOption(key)
    if option then
        print(SQOL_CHAT_PREFIX .. string.format(L["%s is OFF. Enable it with %s."],
            option.label, "|cff00ff00" .. command .. "|r"))
    end
end

local function SQOL_PrintStatus()
    SQOL_PrintHeader()
    SQOL.ForEachOption(function(_, option)
        print("|cff33ff99" .. option.label .. ":|r " .. SQOL.GetOptionStateText(option))
    end)
    print("|cffcccccc" .. string.format(L["Type %s for the command list."], "|cff00ff00/sqol help|cffcccccc") .. "|r")
    print(SQOL_RULE)
end

------------------------------------------------------------
-- Helpers: trackable types
------------------------------------------------------------
local function SQOL_HandleTrackableTypes(questID)
    -- Bonus objectives / task quests: don't try to add a watch (Blizzard handles these automatically)
    if C_QuestLog.IsQuestTask(questID) then
        SQOL.dprint("Skipping task/bonus objective:", questID)
        return "skip"
    end

    -- World quests: use the correct API if available
    if C_QuestLog.IsWorldQuest(questID) then
        if C_QuestLog.AddWorldQuestWatch then
            local ok = SQOL.safe_pcall(function() C_QuestLog.AddWorldQuestWatch(questID) end)
            if ok then
                SQOL.dprint("Added world quest watch:", questID)
                return "done"
            end
        end
        SQOL.dprint("Could not add world quest watch:", questID)
        return "skip"
    end

    return "normal" -- regular quest, OK to track
end

------------------------------------------------------------
-- Auto-track
------------------------------------------------------------
local function SQOL_TryAutoTrack(questID, retries)
    if not questID then return end

    retries = retries or 0
    if retries > 5 then
        print("|cffff0000SQOL:|r " .. string.format(L["Could not auto-track quest %s."], tostring(questID)))
        return
    end

    local mode = SQOL_HandleTrackableTypes(questID)
    if mode == "skip" or mode == "done" then
        return
    end

    local title = C_QuestLog.GetTitleForQuestID(questID)
    if not title then
        C_Timer.After(0.5, function() SQOL_TryAutoTrack(questID, retries + 1) end)
        return
    end

    -- Already tracked?
    if C_QuestLog.GetQuestWatchType(questID) then
        SQOL.dprint("Already tracked:", title)
        return
    end

    SQOL.dprint("Attempting to track:", title)

    C_QuestLog.AddQuestWatch(questID)
    print(L["And |cff33ff99SQoL|r auto-tracked it"])

end

------------------------------------------------------------
-- Splash
------------------------------------------------------------
local function SQOL_Splash()
    SQOL_PrintStatus()
end

------------------------------------------------------------
-- Event: QUEST_LOG_UPDATE (play sounds for objective and quest completion)
------------------------------------------------------------
SQOL.fullyCompleted = {}
SQOL.questObjectiveStates = {}
SQOL._seenQuestProgress = SQOL._seenQuestProgress or {}
SQOL._questProgressCheckPending = false
SQOL._questProgressNeedsBaseline = true
local SQOL_QUEST_PROGRESS_SCAN_DELAY = 0.20
local SQOL_QUEST_HANDLED_TTL = 10

local function SQOL_PlayQuestSound(soundType)
    if not SQOL.DB then return end

    local profile = SQOL.QuestSoundProfiles[SQOL.DB.QuestSoundProfile]
        or SQOL.QuestSoundProfiles.Horde
    local sound = profile and profile[soundType]

    if type(sound) == "number" then
        PlaySound(sound, "Master")
    elseif type(sound) == "string" then
        PlaySoundFile(sound, "Master")
    end
end

local function SQOL_GetQuestCompletionDetails(questID)
    if not questID or not C_QuestLog then
        return nil, false, false
    end

    local title, isTask, isWorld
    if type(C_QuestLog.GetTitleForQuestID) == "function" then
        local ok, result = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok then title = result end
    end
    if type(C_QuestLog.IsQuestTask) == "function" then
        local ok, result = pcall(C_QuestLog.IsQuestTask, questID)
        if ok then isTask = result end
    end
    if type(C_QuestLog.IsWorldQuest) == "function" then
        local ok, result = pcall(C_QuestLog.IsWorldQuest, questID)
        if ok then isWorld = result end
    end

    return title, isTask, isWorld
end

local function SQOL_NotifyQuestCompletion(questID, title, isTask, isWorld)
    if SQOL.DB and SQOL.DB.QuestCompleteSound then
        SQOL_PlayQuestSound("complete")
    end

    -- Yellow title inside a green sentence.
    local displayTitle = "|cffffff00" .. tostring(title or questID) .. "|cff00ff00"
    local text = (isTask or isWorld) and L["%s is done!"] or L["%s is ready to turn in!"]
    print(SQOL_CHAT_PREFIX .. "|cff00ff00" .. string.format(text, displayTitle) .. "|r")
end

local function SQOL_CheckQuestProgress()
    if not SQOL.DB
        or (not SQOL.DB.QuestCompleteSound and not SQOL.DB.QuestObjectiveSound) then
        return
    end

    local seenQuests = SQOL._seenQuestProgress
    local suppressAlerts = SQOL._questProgressNeedsBaseline
    SQOL.TableWipe(seenQuests)

    for _, info in ipairs(SQOL.GetQuestLogSnapshot()) do
        if info and not info.isHeader and info.questID then
            seenQuests[info.questID] = true
            local objectives = SQOL.GetQuestObjectivesCached(info.questID)
            if objectives and #objectives > 0 then
                local allDone = true
                local objectiveCompleted = false
                local previousObjectives = SQOL.questObjectiveStates[info.questID]
                -- Reuse the per-quest table. QUEST_LOG_UPDATE can fire in bursts;
                -- replacing every table on every event produced large amounts of
                -- short-lived garbage even though the live state was tiny.
                local currentObjectives = previousObjectives or {}

                for objectiveIndex, obj in ipairs(objectives) do
                    local finished = not not obj.finished

                    if previousObjectives
                        and previousObjectives[objectiveIndex] == false
                        and finished then
                        objectiveCompleted = true
                    end

                    if not obj.finished then
                        allDone = false
                    end

                    currentObjectives[objectiveIndex] = finished
                end

                -- A quest can change its objective list while it remains in the
                -- log. Drop any stale tail entries from the reused table.
                for objectiveIndex = #objectives + 1, #currentObjectives do
                    currentObjectives[objectiveIndex] = nil
                end

                SQOL.questObjectiveStates[info.questID] = currentObjectives

                -- If all objectives done and not previously marked complete
                if allDone and not SQOL.fullyCompleted[info.questID] then
                    local title, isTask, isWorld = SQOL_GetQuestCompletionDetails(info.questID)
                    title = info.title or title

                    SQOL.fullyCompleted[info.questID] = {
                        title = title,
                        isTask = isTask,
                        isWorld = isWorld,
                    }
                    if not suppressAlerts then
                        SQOL_NotifyQuestCompletion(info.questID, title, isTask, isWorld)
                    end
                elseif not allDone
                    and objectiveCompleted
                    and not suppressAlerts
                    and SQOL.DB
                    and SQOL.DB.QuestObjectiveSound then
                    SQOL_PlayQuestSound("objective")
                end
            else
                SQOL.questObjectiveStates[info.questID] = nil
            end
        end
    end

    for questID in pairs(SQOL.questObjectiveStates) do
        if not seenQuests[questID] then
            SQOL.questObjectiveStates[questID] = nil
        end
    end

    SQOL._questProgressNeedsBaseline = false
    SQOL.RequestIncrementalGC()
end

local function SQOL_ScheduleQuestProgressCheck()
    if not SQOL.DB
        or (not SQOL.DB.QuestCompleteSound and not SQOL.DB.QuestObjectiveSound)
        or SQOL._questProgressCheckPending then
        return
    end

    SQOL._questProgressCheckPending = true
    C_Timer.After(SQOL_QUEST_PROGRESS_SCAN_DELAY, function()
        SQOL._questProgressCheckPending = false
        SQOL_CheckQuestProgress()
    end)
end

-- A short-lived marker suppresses delayed QUEST_LOG_UPDATE events during a
-- turn-in/removal. Previously these entries stayed in fullyCompleted for the
-- entire session, so the table grew monotonically with every handled quest.
local function SQOL_MarkQuestHandledTemporarily(questID)
    if not questID then return end

    local marker = {}
    SQOL.fullyCompleted[questID] = marker
    C_Timer.After(SQOL_QUEST_HANDLED_TTL, function()
        if SQOL.fullyCompleted[questID] == marker then
            SQOL.fullyCompleted[questID] = nil
        end
    end)
end

------------------------------------------------------------
-- Public option helpers (used by Settings UI and slash commands)
------------------------------------------------------------
SQOL._settingsObjects = SQOL._settingsObjects or {}
SQOL._settingsSync = SQOL._settingsSync or false

function SQOL.RegisterSettingObject(key, settingObj)
    if type(key) ~= "string" then return end
    SQOL._settingsObjects[key] = settingObj
end

function SQOL.SyncSettingObject(key)
    if SQOL.OptionsPopup_Refresh then
        SQOL.OptionsPopup_Refresh()
    end

    local settingObj = SQOL._settingsObjects and SQOL._settingsObjects[key]
    if not settingObj or not SQOL.DB then return end
    if type(settingObj.GetValue) ~= "function" or type(settingObj.SetValue) ~= "function" then return end

    local desired = SQOL.DB[key]
    local ok, cur = pcall(settingObj.GetValue, settingObj)
    if ok and cur ~= desired then
        SQOL._settingsSync = true
        pcall(settingObj.SetValue, settingObj, desired)
        SQOL._settingsSync = false
    end
end

function SQOL.SyncAllSettingsObjects()
    if not SQOL.defaults then return end
    for k in pairs(SQOL.defaults) do
        SQOL.SyncSettingObject(k)
    end
end

function SQOL.ApplyOption(key)
    if not SQOL.DB then return end

    if key == "QuestCompleteSound" or key == "QuestObjectiveSound" then
        if not SQOL.DB.QuestCompleteSound and not SQOL.DB.QuestObjectiveSound then
            -- No progress history is needed while both notifications are off.
            SQOL.TableWipe(SQOL.questObjectiveStates)
            SQOL.TableWipe(SQOL.fullyCompleted)
            SQOL.TableWipe(SQOL._seenQuestProgress)
            SQOL._questProgressNeedsBaseline = true
        else
            -- When notifications are re-enabled after being fully disabled,
            -- establish a silent baseline before reporting later transitions.
            if next(SQOL.questObjectiveStates) == nil then
                SQOL._questProgressNeedsBaseline = true
            end
            SQOL_ScheduleQuestProgressCheck()
        end

    elseif key == "ColorStatusBarProgress" then
        if SQOL.RefreshStatusBarProgress then SQOL.RefreshStatusBarProgress() end

    elseif key == "ColorProgress" then
        SQOL.RefreshQuestTrackerColors()
        if SQOL.DB.ColorProgress then
            SQOL.EnableCustomInfoMessages()
            SQOL.ScheduleQuestProgressBarScan(false)
            SQOL.ScheduleScenarioProgressScan(false)
        else
            if UIErrorsFrame and UIErrorsFrame.RegisterEvent then
                UIErrorsFrame:RegisterEvent("UI_INFO_MESSAGE")
            end
        end

    elseif key == "HideDoneAchievements" then
        if SQOL.EnsureAchievementUILoaded() then
            SQOL.ApplyAchievementFilter()
        end

    elseif key == "ShowRepGains" then
        if not SQOL.DB.ShowRepGains then SQOL.RepGains_Hide() end

    elseif key == "RepWatch" then
        if SQOL.DB.RepWatch then
            SQOL._repLastStanding = nil
            if SQOL.Rep_RebuildNameMap then
                SQOL.Rep_RebuildNameMap()
            end
            if SQOL_RepWatch_ScheduleScan then
                SQOL_RepWatch_ScheduleScan()
            end
        end

    elseif key == "ShowNameplateObjectives" then
        if SQOL.DB.ShowNameplateObjectives then
            SQOL.NameplateObjectives_RefreshVisibleUnits()
        else
            SQOL.NameplateObjectives_HideAll()
        end

    elseif key == "ShowItemLevel" or key == "ShowMovementSpeed" then
        if (SQOL.DB.ShowItemLevel or SQOL.DB.ShowMovementSpeed) then
            SQOL.TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

    elseif key == "DamageTextFont" then
        if SQOL.DB.DamageTextFont then
            SQOL.ApplyDamageTextFont()
        else
            SQOL.RestoreDamageTextFont()
        end

    elseif key == "CursorShakeHighlight" then
        if SQOL.DB.CursorShakeHighlight then
            SQOL.CursorShake_Enable()
        else
            SQOL.CursorShake_Disable()
        end

    elseif key == "ShowReadyCheckTimer" then
        if not SQOL.DB.ShowReadyCheckTimer then
            SQOL.ReadyCheck_Hide()
        end

    elseif key == "ShowLFGProposalTimer" then
        if not SQOL.DB.ShowLFGProposalTimer then
            SQOL.LFGProposal_Hide()
        end

    elseif key == "ShowPartyLevel" then
        SQOL.RefreshPartyMemberLevels()

    elseif key == "ShowMinimapButton" then
        SQOL.UpdateMinimapButton()

    elseif key == "ShowRangeIndicator" then
        SQOL.RangeIndicator_OnOptionChanged()

    end

    SQOL.SyncSettingObject(key)
end

function SQOL.SetOption(key, value)
    if not SQOL.DB then return end
    SQOL.DB[key] = value
    SQOL.ApplyOption(key)
end

function SQOL.ToggleOption(key)
    if not SQOL.DB then return end
    SQOL.SetOption(key, not SQOL.DB[key])
end

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
-- Each command lists its names (the first is shown in help) and either the
-- option it toggles (help and feedback use the option's label) or its own
-- description and handler. The order here is the order in /sqol help.
local SQOL_Help

local SQOL_COMMANDS = {
    { names = { "config", "options", "opt" }, desc = L["Open the options window"],
      run = function() SQOL.OptionsPopup_Toggle() end },
    { names = { "minimap", "mm" }, key = "ShowMinimapButton" },
    { names = { "autotrack", "at" }, key = "AutoTrack" },
    { names = { "color", "col" }, key = "ColorProgress" },
    { names = { "nameplate", "np" }, key = "ShowNameplateObjectives" },
    { names = { "questsound", "qs" }, key = "QuestCompleteSound" },
    { names = { "objectivesound", "os" }, key = "QuestObjectiveSound" },
    { names = { "soundprofile", "soundset" }, desc = L["Switch between the Horde and Alliance quest sounds"],
      run = function()
          SQOL.SetOption("QuestSoundProfile", SQOL.DB.QuestSoundProfile == "Alliance" and "Horde" or "Alliance")
          SQOL.PrintOptionState("QuestSoundProfile")
      end },
    { names = { "ilvl", "stats" }, key = "ShowItemLevel" },
    { names = { "speed", "spd" }, key = "ShowMovementSpeed" },
    { names = { "barcolor", "bc" }, key = "ColorStatusBarProgress" },
    { names = { "rep", "rw" }, key = "RepWatch" },
    { names = { "reptext", "rt" }, key = "ShowRepGains" },
    { names = { "reptexttest" }, desc = L["Preview floating reputation gains"],
      run = function() SQOL.RepGains_Show("Valarjar", 25) end },
    { names = { "readycheck", "rc" }, key = "ShowReadyCheckTimer" },
    { names = { "rctest" }, desc = L["Preview the ready check countdown (add 'popup' to show the frame)"],
      run = function(rest)
          if SQOL.DB.ShowReadyCheckTimer then
              SQOL_ReadyCheck_Test(nil, rest == "popup")
          else
              SQOL.PrintOptionOff("ShowReadyCheckTimer", "/sqol rc")
          end
      end },
    { names = { "lfgtimer", "lfg" }, key = "ShowLFGProposalTimer" },
    { names = { "lfgtest" }, desc = L["Preview the queue pop countdown"],
      run = function() SQOL_LFGProposal_Test() end },
    { names = { "partylevel", "pl" }, key = "ShowPartyLevel" },
    { names = { "tooltiptarget", "tt" }, key = "ShowTooltipTarget" },
    { names = { "range", "rng" }, key = "ShowRangeIndicator" },
    { names = { "damagefont", "df" }, key = "DamageTextFont" },
    { names = { "cursor", "cs" }, key = "CursorShakeHighlight" },
    { names = { "cursorflash", "cf" }, desc = L["Flash the cursor highlight once"],
      run = function() SQOL.CursorShake_FlashNow(0.8) end },
    { names = { "hideach", "ha" }, key = "HideDoneAchievements" },
    { names = { "splash" }, key = "ShowSplash" },
    { names = { "debugtrack", "dbg" }, key = "DebugTrack" },
    { names = { "reset" }, desc = L["Reset all settings to defaults"],
      run = function()
          -- Turn the range icon off first so it restores Blizzard's soft target icon.
          if SQOL.DB and SQOL.DB.ShowRangeIndicator then
              SQOL.SetOption("ShowRangeIndicator", false)
          end
          SQOL.Init(true)
          if SQOL.SyncAllSettingsObjects then
              SQOL.SyncAllSettingsObjects()
          end
          SQOL.UpdateMinimapButton()
      end },
    { names = { "help" }, desc = L["Show this command list"],
      run = function() SQOL_Help() end },
}

-- Toggles the option behind a command, or explains why it can't.
local function SQOL_RunOptionCommand(key)
    local option = SQOL.GetOption(key)
    if option and option.isAvailable and not option.isAvailable() then
        print(SQOL_CHAT_PREFIX .. string.format(L["%s is not available in this client."], option.label))
        return
    end
    SQOL.ToggleOption(key)
    SQOL.PrintOptionState(key)
end

SQOL_Help = function()
    SQOL_PrintHeader()
    for _, command in ipairs(SQOL_COMMANDS) do
        local option = command.key and SQOL.GetOption(command.key)
        if not (option and option.isAvailable and not option.isAvailable()) then
            local text = "|cff00ff00/sqol " .. command.names[1] .. "|r"
            if command.names[2] then
                text = text .. " |cff888888(" .. table.concat(command.names, ", ", 2) .. ")|r"
            end
            local desc = option and option.label or command.desc
            print(text .. " |cffcccccc- " .. desc .. "|r")
        end
    end
    print("|cffcccccc" .. string.format(L["Type %s to see which features are on."], "|cff00ff00/sqol|cffcccccc") .. "|r")
    print(SQOL_RULE)
end

local SQOL_CommandByName = {}
for _, command in ipairs(SQOL_COMMANDS) do
    for _, name in ipairs(command.names) do
        SQOL_CommandByName[name] = command
    end
end

SLASH_SQOL1 = "/SQOL"
SlashCmdList["SQOL"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local name, rest = msg:match("^(%S*)%s*(.-)$")

    local command = SQOL_CommandByName[name]
    if not command then
        SQOL_PrintStatus()
    elseif command.key then
        SQOL_RunOptionCommand(command.key)
    else
        command.run(rest)
    end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
local function SQOL_RegisterOptionalEvent(event)
    local ok, err = pcall(f.RegisterEvent, f, event)
    if not ok and SQOL.DB and SQOL.DB.DebugTrack then
        SQOL.dprint("Could not register optional event:", tostring(event), tostring(err))
    end
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_LOG_UPDATE")
SQOL_RegisterOptionalEvent("QUEST_WATCH_UPDATE")
SQOL_RegisterOptionalEvent("QUEST_POI_UPDATE")
SQOL_RegisterOptionalEvent("QUEST_CRITERIA_UPDATE")
SQOL_RegisterOptionalEvent("SCENARIO_CRITERIA_UPDATE")
f:RegisterEvent("UPDATE_FACTION")
f:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_LEVEL")
SQOL_RegisterOptionalEvent("READY_CHECK")
SQOL_RegisterOptionalEvent("READY_CHECK_FINISHED")
SQOL_RegisterOptionalEvent("LFG_PROPOSAL_SHOW")
SQOL_RegisterOptionalEvent("LFG_PROPOSAL_DONE")
SQOL_RegisterOptionalEvent("LFG_PROPOSAL_FAILED")
SQOL_RegisterOptionalEvent("LFG_PROPOSAL_SUCCEEDED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        SQOL.Init()
        if SQOL.DB.ShowSplash then
            SQOL_Splash()
        end

        -- Always hook the quest tracker; the hook checks ColorProgress itself.
        SQOL.HookQuestTrackerColors()

        if SQOL.DB.ColorProgress then
            SQOL.EnableCustomInfoMessages()
            SQOL.ScheduleQuestProgressBarScan(false)
            SQOL.ScheduleScenarioProgressScan(false)
            SQOL.RecolorQuestObjectives_Throttle()
        end

        -- Apply saved preference when logging in (only if already loaded)
        SQOL.ApplyAchievementFilter()

        if SQOL.DB.DamageTextFont then
            SQOL.ApplyDamageTextFont()
        end

        if SQOL.DB.CursorShakeHighlight then
            SQOL.CursorShake_Enable()
        else
            SQOL.CursorShake_Disable()
        end

        -- Ensure PlayerFrame iLvl display.
        if (SQOL.DB.ShowItemLevel or SQOL.DB.ShowMovementSpeed) then
            SQOL.TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

        if SQOL.DB.ShowNameplateObjectives then
            SQOL.NameplateObjectives_RefreshVisibleUnits()
        else
            SQOL.NameplateObjectives_HideAll()
        end

        -- Party member level labels on the default party frames.
        SQOL.RefreshPartyMemberLevels()

        -- Initialize RepWatch snapshot (if enabled)
        if SQOL.DB.RepWatch and SQOL_RepWatch_ScheduleScan then
            SQOL._repLastStanding = nil
            if SQOL.Rep_RebuildNameMap then
                SQOL.Rep_RebuildNameMap()
            end
            SQOL_RepWatch_ScheduleScan()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if SQOL.DB and (SQOL.DB.ShowItemLevel or SQOL.DB.ShowMovementSpeed) then
            SQOL.TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

        if SQOL.DB and SQOL.DB.ColorProgress then
            SQOL.ScheduleQuestProgressBarScan(false)
            SQOL.ScheduleScenarioProgressScan(false)
        end

        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            SQOL.NameplateObjectives_RefreshVisibleUnits()
        end

        SQOL.RefreshPartyMemberLevels()

    elseif event == "GROUP_ROSTER_UPDATE" then
        SQOL.RefreshPartyMemberLevels()

    elseif event == "UNIT_LEVEL" then
        if SQOL.DB and SQOL.DB.ShowPartyLevel then
            SQOL.UpdateAllPartyMemberLevels()
        end

    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            if not SQOL.DB then
                SQOL.Init()
            end
            if SQOL.DB and SQOL.DB.DamageTextFont then
                SQOL.ApplyDamageTextFont()
            end
        elseif addonName == "Blizzard_AchievementUI" then
            C_Timer.After(0.1, SQOL.ApplyAchievementFilter)
        elseif addonName == "Blizzard_ObjectiveTracker" then
            SQOL.HookQuestTrackerColors()
        end

    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            if SQOL.DB and (SQOL.DB.ShowItemLevel or SQOL.DB.ShowMovementSpeed) then
                if not SQOL.iLvlText then
                    SQOL.TryEnsurePlayerFrameIlvlUI(0)
                end
                SQOL.UpdateCharacterIlvlText()
            else
                if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
            end
        end

    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if SQOL.DB and (SQOL.DB.ShowItemLevel or SQOL.DB.ShowMovementSpeed) then
            SQOL.UpdatePlayerFrameIlvlAnchor()
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            local unit = ...
            SQOL.NameplateObjectives_UpdateUnit(unit)
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        SQOL.NameplateObjectives_ClearUnit(unit)

    elseif event == "READY_CHECK" then
        if SQOL.DB and SQOL.DB.ShowReadyCheckTimer then
            local initiator, timeLeft = ...
            SQOL.ReadyCheck_Start(timeLeft)
        end

    elseif event == "READY_CHECK_FINISHED" then
        SQOL.ReadyCheck_Hide()

    elseif event == "LFG_PROPOSAL_SHOW" then
        SQOL.LFGProposal_Start()

    elseif event == "LFG_PROPOSAL_DONE" or event == "LFG_PROPOSAL_FAILED"
        or event == "LFG_PROPOSAL_SUCCEEDED" then
        SQOL.LFGProposal_Hide()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        if SQOL.DB and (SQOL.DB.ShowItemLevel or SQOL.DB.ShowMovementSpeed) then
            if not SQOL.iLvlText then
                SQOL.TryEnsurePlayerFrameIlvlUI(0)
            end
            SQOL.UpdatePlayerFrameIlvlAnchor()
            SQOL.UpdateCharacterIlvlText()
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

    elseif event == "QUEST_ACCEPTED" then
        SQOL.InvalidateQuestDataCache()
        local a1, a2 = ...
        local questIndex, questID
        if a2 then questIndex, questID = a1, a2 else questID = a1 end
        if (not questID or questID == 0) and questIndex then
            local info = C_QuestLog.GetInfo(questIndex)
            if info and info.questID then
                questID = info.questID
                SQOL.dprint("Recovered questID", questID, "from questIndex", questIndex)
            end
        end

        if questID then
            SQOL.fullyCompleted[questID] = nil
            SQOL.questObjectiveStates[questID] = nil
            if SQOL.DB.AutoTrack then
                SQOL_TryAutoTrack(questID)
            end
        elseif SQOL.DB.AutoTrack then
            SQOL.dprint("Could not resolve questID on QUEST_ACCEPTED:", tostring(a1), tostring(a2))
        end

    elseif event == "QUEST_TURNED_IN" then
        SQOL.InvalidateQuestDataCache()
        local questID = ...
        if questID then
            -- Keep the quest marked as handled so delayed QUEST_LOG_UPDATE events
            -- during turn-in do not fire the completion alert again.
            SQOL_MarkQuestHandledTemporarily(questID)
            SQOL.questObjectiveStates[questID] = nil
        end

    elseif event == "QUEST_REMOVED" then
        SQOL.InvalidateQuestDataCache()
        local questID = ...
        if questID then
            -- QUEST_ACCEPTED also clears this if the quest is picked up again
            -- before the short suppression window expires.
            SQOL_MarkQuestHandledTemporarily(questID)
            SQOL.questObjectiveStates[questID] = nil
        end

    elseif event == "UPDATE_FACTION" then
        -- Clicking an expansion header in the Reputation panel fires UPDATE_FACTION.
        -- Skip the header-expanding scan while the panel is open so the list does
        -- not jump; actual rep gains are still caught by CHAT_MSG_COMBAT_FACTION_CHANGE.
        if SQOL.DB and SQOL.DB.RepWatch and SQOL_RepWatch_ScheduleScan
            and not SQOL.RepWatch_ReputationFrameOpen() then
            SQOL_RepWatch_ScheduleScan("update_faction")
        end

    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        SQOL.RepGains_HandleMessage(...)
        if SQOL.DB and SQOL.DB.RepWatch then
            local msg = ...
            local handled = false

            if SQOL.DB.DebugTrack then
                SQOL.dprint("RepWatch -> CHAT_MSG_COMBAT_FACTION_CHANGE:", tostring(msg))
            end
            if SQOL.RepWatch_HandleFactionChangeMessage then
                handled = SQOL.RepWatch_HandleFactionChangeMessage(msg)
            end

            -- Fallback: if we couldn't parse/resolve the faction, do a delta-based scan.
            if not handled and SQOL_RepWatch_ScheduleScan then
                SQOL_RepWatch_ScheduleScan("chat_fallback")
            end
        end

    elseif event == "QUEST_LOG_UPDATE" then
        SQOL.InvalidateQuestDataCache()
        SQOL_ScheduleQuestProgressCheck()
        if SQOL.DB and SQOL.DB.ColorProgress then
            SQOL.RecolorQuestObjectives_Throttle()
            SQOL.ScheduleQuestProgressBarScan(true)
        end
        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            SQOL.NameplateObjectives_ScheduleUpdateAll()
        end

    elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_POI_UPDATE"
        or event == "QUEST_CRITERIA_UPDATE" then
        SQOL.InvalidateQuestDataCache()
        if event ~= "QUEST_POI_UPDATE" then
            SQOL_ScheduleQuestProgressCheck()
        end
        if SQOL.DB and SQOL.DB.ColorProgress then
            SQOL.RecolorQuestObjectives_Throttle()
            SQOL.ScheduleQuestProgressBarScan(true)
        end
        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            SQOL.NameplateObjectives_ScheduleUpdateAll()
        end

    elseif event == "SCENARIO_CRITERIA_UPDATE" then
        -- Scenario criteria do not change quest objectives or nameplate data.
        -- Keep this high-frequency event on the scenario-only path.
        if SQOL.DB and SQOL.DB.ColorProgress then
            SQOL.ScheduleScenarioProgressScan(true)
        end
    end
end)
