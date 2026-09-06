local ADDON_NAME, SQOL = ...
-- Feature modules are loaded first by the TOC. This file owns saved settings,
-- commands and event routing; shared entry points live on the SQOL namespace.
local f = CreateFrame("Frame")

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
        if SQOL.RefreshStatusBarProgress then SQOL.RefreshStatusBarProgress() end
        print("|cff33ff99SQoL:|r Settings have been reset to defaults.")

        -- 🟢 Apply Achievement filter after reset
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        end
        C_Timer.After(0.1, function()
            SQOL.ApplyAchievementFilter()
        end)
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

local function SQOL_GetStateStrings()
    local version = SQOL_GetVersion()
    local atState = SQOL.DB.AutoTrack     and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local spState = SQOL.DB.ShowSplash    and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local coState = SQOL.DB.ColorProgress and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local qsState = SQOL.DB.QuestCompleteSound and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local loState = SQOL.DB.HideDoneAchievements and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local repState = SQOL.DB.RepWatch and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local statsState = "iLvl " .. (SQOL.DB.ShowItemLevel and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        .. " / Speed " .. (SQOL.DB.ShowMovementSpeed and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    local npState = SQOL.DB.ShowNameplateObjectives and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local dmgState = SQOL.DB.DamageTextFont and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local cursorState = SQOL.DB.CursorShakeHighlight and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    return version, atState, spState, coState, qsState, loState, repState, statsState, npState, dmgState, cursorState
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
        print("|cffff0000SQOL:|r Failed to auto-track quest after multiple attempts:", questID)
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
    print("And |cff33ff99SQoL|r auto-tracked it")

end

------------------------------------------------------------
-- Splash
------------------------------------------------------------
local function SQOL_Splash()
    local version, atState, spState, coState, qsState, loState, repState, statsState, npState, dmgState, cursorState = SQOL_GetStateStrings()
    local qoState = SQOL.DB.QuestObjectiveSound and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local questSoundProfile = SQOL.DB.QuestSoundProfile or SQOL.defaults.QuestSoundProfile
    print("|cff33ff99-----------------------------------|r")
    print("|cff33ff99" .. (SQOL.ADDON_NAME or "SMoRGsQoL") .. " (SQOL)|r |cffffffffv" .. version .. "|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
    print("|cff33ff99AutoTrack:|r " .. atState)
    print("|cff33ff99Splash:|r " .. spState)
    print("|cff33ff99ColorProgress:|r " .. coState)
    print("|cff33ff99XP/Rep colors:|r " .. (SQOL.DB.ColorStatusBarProgress and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    print("|cff33ff99QuestSound:|r " .. qsState)
    print("|cff33ff99ObjectiveSound:|r " .. qoState)
    print("|cff33ff99QuestSoundProfile:|r " .. questSoundProfile)
    print("|cff33ff99HideDoneAchievements:|r " .. loState)
    print("|cff33ff99RepWatch:|r " .. repState)
    print("|cff33ff99NameplateObjectives:|r " .. npState)
    print("|cff33ff99StatsLine:|r " .. statsState)
    print("|cff33ff99DamageTextFont:|r " .. dmgState)
    print("|cff33ff99CursorShake:|r " .. cursorState)
    print("|cff33ff99ReadyCheckTimer:|r " .. (SQOL.DB.ShowReadyCheckTimer and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    print("|cff33ff99LFGQueuePopTimer:|r " .. (SQOL.DB.ShowLFGProposalTimer and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    print("|cffccccccType |cff00ff00/SQOL help|r for command list.|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
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

    local displayTitle = title or questID
    if isTask or isWorld then
        print("|cff33ff99SQoL:|r |cffffff00" ..
            displayTitle .. "|r |cff00ff00is done!|r")
    else
        print("|cff33ff99SQoL:|r |cffffff00" ..
            displayTitle .. "|r |cff00ff00is ready to turn in!|r")
    end
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
-- Help
------------------------------------------------------------
local function SQOL_Help()
    local version, atState, spState, coState, qsState, loState, repState, statsState, npState, dmgState, cursorState = SQOL_GetStateStrings()
    local qoState = SQOL.DB.QuestObjectiveSound and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local questSoundProfile = SQOL.DB.QuestSoundProfile or SQOL.defaults.QuestSoundProfile
    print("|cff33ff99-----------------------------------|r")
    print("|cff33ff99" .. (SQOL.ADDON_NAME or "SMoRGsQoL") .. " (SQOL)|r |cffffffffv" .. version .. "|r")
    print("|cff33ff99-----------------------------------|r")
    print("|cff00ff00/SQOL autotrack|r   |cffcccccc- Toggle automatic quest tracking|r")
    print("|cff00ff00/SQOL at|r          |cffcccccc- Shorthand for autotrack|r")
    print("|cff00ff00/SQOL color|r       |cffcccccc- Toggle quest progress colorization|r")
    print("|cff00ff00/SQOL barcolor|r    |cffcccccc- Toggle XP/reputation number colors|r")
    print("|cff00ff00/SQOL col|r         |cffcccccc- Shorthand for color|r")
    print("|cff00ff00/SQOL questsound|r  |cffcccccc- Toggle quest completion sound|r")
    print("|cff00ff00/SQOL qs|r          |cffcccccc- Shorthand for questsound|r")
    print("|cff00ff00/SQOL objectivesound|r |cffcccccc- Toggle objective completion sound|r")
    print("|cff00ff00/SQOL os|r          |cffcccccc- Shorthand for objectivesound|r")
    print("|cff00ff00/SQOL soundprofile|r |cffcccccc- Switch Horde/Alliance quest sounds|r")
    print("|cff00ff00/SQOL hideach|r     |cffcccccc- Toggle hiding completed achievements|r")
    print("|cff00ff00/SQOL ha|r          |cffcccccc- Shorthand for hideach|r")
    print("|cff00ff00/SQOL splash|r      |cffcccccc- Toggle splash on login|r")
    print("|cff00ff00/SQOL rep|r         |cffcccccc- Toggle watched reputation auto-switch on rep gain|r")
    print("|cff00ff00/SQOL rw|r          |cffcccccc- Shorthand for rep|r")
    print("|cff00ff00/SQOL nameplate|r   |cffcccccc- Toggle nameplate objective counts|r")
    print("|cff00ff00/SQOL np|r          |cffcccccc- Shorthand for nameplate|r")
    print("|cff00ff00/SQOL ilvl|r        |cffcccccc- Toggle PlayerFrame item level (alias: stats)|r")
    print("|cff00ff00/SQOL speed|r       |cffcccccc- Toggle PlayerFrame movement speed|r")
    print("|cff00ff00/SQOL damagefont|r  |cffcccccc- Toggle custom damage text font|r")
    print("|cff00ff00/SQOL df|r          |cffcccccc- Shorthand for damagefont|r")
    print("|cff00ff00/SQOL cursor|r      |cffcccccc- Highlight cursor when you shake the mouse|r")
    print("|cff00ff00/SQOL cs|r          |cffcccccc- Shorthand for cursor|r")
    print("|cff00ff00/SQOL cursorflash|r |cffcccccc- Flash cursor ring once (debug)|r")
    print("|cff00ff00/SQOL cf|r          |cffcccccc- Shorthand for cursorflash|r")
    print("|cff00ff00/SQOL readycheck|r  |cffcccccc- Toggle ready check countdown timer|r")
    print("|cff00ff00/SQOL rc|r          |cffcccccc- Shorthand for readycheck|r")
    print("|cff00ff00/SQOL rctest|r      |cffcccccc- Preview the ready check timer (add 'popup' for the frame)|r")
    print("|cff00ff00/SQOL lfgtimer|r    |cffcccccc- Toggle LFG queue pop countdown timer|r")
    print("|cff00ff00/SQOL lfg|r         |cffcccccc- Shorthand for lfgtimer|r")
    print("|cff00ff00/SQOL lfgtest|r     |cffcccccc- Preview the LFG queue pop timer|r")
    print("|cff00ff00/SQOL partylevel|r  |cffcccccc- Toggle party member level display|r")
    print("|cff00ff00/SQOL pl|r          |cffcccccc- Shorthand for partylevel|r")
    print("|cff00ff00/SQOL debugtrack|r  |cffcccccc- Toggle verbose tracking debug|r")
    print("|cff00ff00/SQOL dbg|r         |cffcccccc- Shorthand for debugtrack|r")
    print("|cff00ff00/SQOL reset|r       |cffcccccc- Reset all settings to defaults|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
    print("|cff33ff99AutoTrack:|r " .. atState .. "  |cff33ff99Splash:|r " .. spState .. "  |cff33ff99ColorProgress:|r " .. coState .. "  |cff33ff99QuestSound:|r " .. qsState)
    print("|cff33ff99ObjectiveSound:|r " .. qoState .. "  |cff33ff99QuestSoundProfile:|r " .. questSoundProfile)
    print("|cff33ff99HideDoneAchievements:|r " .. loState .. "  |cff33ff99RepWatch:|r " .. repState .. "  |cff33ff99NameplateObjectives:|r " .. npState)
    print("|cff33ff99StatsLine:|r " .. statsState)
    local rcState = SQOL.DB.ShowReadyCheckTimer and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local lfgState = SQOL.DB.ShowLFGProposalTimer and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local plState = SQOL.DB.ShowPartyLevel and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    print("|cff33ff99DamageTextFont:|r " .. dmgState .. "  |cff33ff99CursorShake:|r " .. cursorState .. "  |cff33ff99ReadyCheckTimer:|r " .. rcState .. "  |cff33ff99LFGQueuePopTimer:|r " .. lfgState .. "  |cff33ff99PartyLevel:|r " .. plState)
    print("|cff33ff99------------------------------------------------------------------------------|r")
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
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        end
        SQOL.ApplyAchievementFilter()

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
SLASH_SQOL1 = "/SQOL"
SlashCmdList["SQOL"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    local function toggle(key, label)
        SQOL.ToggleOption(key)
        local s = SQOL.DB[key] and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff33ff99SQoL:|r " .. label .. " " .. s)
    end

    if msg == "autotrack" or msg == "at" then
        toggle("AutoTrack", "Auto-track is")

    elseif msg == "color" or msg == "col" then
        toggle("ColorProgress", "Quest progress colorization is")

    elseif msg == "barcolor" or msg == "bc" then
        toggle("ColorStatusBarProgress", "XP/reputation number colorization is")

    elseif msg == "questsound" or msg == "qs" then
        toggle("QuestCompleteSound", "Quest completion sound is")

    elseif msg == "objectivesound" or msg == "os" then
        toggle("QuestObjectiveSound", "Objective completion sound is")

    elseif msg == "soundprofile" or msg == "soundset" then
        local profile = SQOL.DB.QuestSoundProfile == "Alliance" and "Horde" or "Alliance"
        SQOL.SetOption("QuestSoundProfile", profile)
        print("|cff33ff99SQoL:|r Quest sound profile is now |cffffff00" .. profile .. "|r")

    elseif msg == "splash" then
        toggle("ShowSplash", "Splash is")

    elseif msg == "rep" or msg == "rw" then
        toggle("RepWatch", "RepWatch is")

    elseif msg == "nameplate" or msg == "np" then
        toggle("ShowNameplateObjectives", "Nameplate objectives are")

    elseif msg == "stats" or msg == "ilvl" then
        toggle("ShowItemLevel", "PlayerFrame item level is")

    elseif msg == "speed" or msg == "spd" then
        toggle("ShowMovementSpeed", "PlayerFrame movement speed is")

    elseif msg == "damagefont" or msg == "df" then
        toggle("DamageTextFont", "Damage text font is")

    elseif msg == "cursor" or msg == "cs" then
        toggle("CursorShakeHighlight", "Cursor shake highlight is")

    elseif msg == "cursorflash" or msg == "cf" then
        SQOL.CursorShake_FlashNow(0.8)

    elseif msg == "readycheck" or msg == "rc" then
        toggle("ShowReadyCheckTimer", "Ready check timer is")

    elseif msg == "rctest" or msg == "rctest popup" then
        if SQOL.DB.ShowReadyCheckTimer then
            SQOL_ReadyCheck_Test(nil, msg == "rctest popup")
        else
            print("|cff33ff99SQoL:|r Ready check timer is |cffff0000OFF|r - enable it with /sqol rc")
        end

    elseif msg == "lfgtimer" or msg == "lfg" then
        toggle("ShowLFGProposalTimer", "LFG queue pop timer is")

    elseif msg == "partylevel" or msg == "pl" then
        toggle("ShowPartyLevel", "Party member level display is")

    elseif msg == "lfgtest" then
        SQOL_LFGProposal_Test()

    elseif msg == "debugtrack" or msg == "dbg" then
        toggle("DebugTrack", "Debug tracking")

    elseif msg == "hideach" or msg == "ha" then
        toggle("HideDoneAchievements", "Hide completed achievements is")

    elseif msg == "reset" then
        SQOL.Init(true)
        if SQOL.SyncAllSettingsObjects then
            SQOL.SyncAllSettingsObjects()
        end

    elseif msg == "help" then
        SQOL_Help()

    else
        local version, at, sp, co, qs, lo, rep, stats, np, dmg, cursor = SQOL_GetStateStrings()
        local qo = SQOL.DB.QuestObjectiveSound and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        local profile = SQOL.DB.QuestSoundProfile or SQOL.defaults.QuestSoundProfile
        local rc = SQOL.DB.ShowReadyCheckTimer and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        local lfg = SQOL.DB.ShowLFGProposalTimer and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff33ff99SQoL|r v" .. version .. " - AutoTrackQuests:" .. at .. " Splash:" .. sp .. " ColorProgress:" .. co .. " QuestSound:" .. qs .. " ObjectiveSound:" .. qo .. " QuestSoundProfile:" .. profile .. " HideDoneAchievements:" .. lo .. " RepWatch:" .. rep .. " NameplateObjectives:" .. np .. " StatsLine:" .. stats .. " DamageTextFont:" .. dmg .. " CursorShake:" .. cursor .. " ReadyCheckTimer:" .. rc .. " LFGQueuePopTimer:" .. lfg)
        print("|cff33ff99XP/Rep colors:|r " .. (SQOL.DB.ColorStatusBarProgress and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        print("|cffccccccCommands:|r help for more info")
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

        if SQOL.DB.ColorProgress then
            SQOL.EnableCustomInfoMessages()
            SQOL.ScheduleQuestProgressBarScan(false)
            SQOL.ScheduleScenarioProgressScan(false)
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
