------------------------------------------------------------
-- SMoRGsQoL v1.0.5 by SMoRG75
-- Retail-only.
-- Optional auto-tracking for newly accepted quests.
-- Now with throttled updates and a stable PlayerFrame iLvl+Speed line.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"

SQOL = SQOL or {}        -- addon namespace table (shared across files)
SQOL.ADDON_NAME = ADDON_NAME
local f = CreateFrame("Frame")

------------------------------------------------------------
-- Defaults
------------------------------------------------------------
SQOL.defaults = {
    AutoTrack     = false,
    DebugTrack    = false,
    ShowSplash    = false,
    ColorProgress = false,
    HideDoneAchievements = false,
    RepWatch     = false,

    -- PlayerFrame line: "iLvl: xx.x  Spd: yy%"
    ShowIlvlSpd  = true
}

------------------------------------------------------------
-- Internal utils
------------------------------------------------------------
local function dprint(...)
    if SQOL.DB and SQOL.DB.DebugTrack then
        print("|cff9999ff[SQOL Debug]|r", ...)
    end
end

local function safe_pcall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and SQOL.DB and SQOL.DB.DebugTrack then
        dprint("pcall error:", err)
    end
    return ok
end

local function clamp01(x)
    if x ~= x then return 0 end
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

------------------------------------------------------------
-- Apply the achievement filter according to saved setting
------------------------------------------------------------
local function SQOL_ApplyAchievementFilter()
    if not SQOL.DB then return end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then return end

    local filter = SQOL.DB.HideDoneAchievements and ACHIEVEMENT_FILTER_INCOMPLETE or ACHIEVEMENT_FILTER_ALL

    if AchievementFrame and AchievementFrame_SetFilter then
        AchievementFrame_SetFilter(filter)

        -- Update dropdown UI
        if AchievementFrame.Header and AchievementFrame.Header.FilterDropDown then
            UIDropDownMenu_SetSelectedValue(AchievementFrame.Header.FilterDropDown, filter)
        end

        -- Refresh category tree so change is visible immediately
        if AchievementFrameCategories_Update then
            AchievementFrameCategories_Update()
        end
    end
end

------------------------------------------------------------
-- SQOL_Init & Reset: ensure saved variables exist
------------------------------------------------------------
function SQOL.Init(reset)
    -- Ensure SavedVariables table exists
    if reset or type(SQOL_DB) ~= "table" then
        SQOL_DB = {}
    end

    -- Apply defaults into SQOL_DB without clobbering user values
    for k, v in pairs(SQOL.defaults) do
        if SQOL_DB[k] == nil then
            SQOL_DB[k] = v
        end
    end

    -- Bind runtime DB reference
    SQOL.DB = SQOL_DB

    if reset then
        print("|cff33ff99SQoL:|r Settings have been reset to defaults.")

        -- 🟢 Apply Achievement filter after reset
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        end
        C_Timer.After(0.1, function()
            SQOL_ApplyAchievementFilter()
            print("|cff33ff99SQoL:|r Achievement filter reset to show all achievements.")
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
    local loState = SQOL.DB.HideDoneAchievements and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local repState = SQOL.DB.RepWatch and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local statsState = SQOL.DB.ShowIlvlSpd and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    return version, atState, spState, coState, loState, repState, statsState
end

------------------------------------------------------------
-- Color utilities
------------------------------------------------------------
local function SQOL_GetProgressColor(progress)
    progress = clamp01(progress or 0)
    if progress >= 1 then
        return "|cff00ff00"
    elseif progress <= 0 then
        return "|cffff0000"
    end
    local r, g
    if progress < 0.5 then
        r, g = 1, progress * 2
    else
        r, g = 1 - ((progress - 0.5) * 2), 1
    end
    local R = math.floor(r * 255 + 0.5)
    local G = math.floor(g * 255 + 0.5)
    return string.format("|cff%02x%02x%02x", R, G, 0)
end

------------------------------------------------------------
-- Colorize tracker objective lines (Retail tracker)
-- Throttled to avoid excess work during rapid updates.
------------------------------------------------------------
SQOL._recolorPending = false
SQOL._lastRecolorAt  = 0

local function SQOL_RecolorQuestObjectives_Impl()
    if not SQOL.DB.ColorProgress then return end
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                for _, obj in ipairs(objectives) do
                    local numItems     = rawget(obj, "numItems")
                    local numRequired  = rawget(obj, "numRequired")
                    local numFulfilled = rawget(obj, "numFulfilled")
                    local objText      = rawget(obj, "text")
                    local hasCounter = (type(numItems) == "number" and numItems > 0)
                                    or (type(numRequired) == "number" and numRequired > 0)
                    if hasCounter then
                        local required  = (type(numRequired) == "number" and numRequired)
                                       or (type(numItems) == "number" and numItems)
                                       or 0
                        local fulfilled = (type(numFulfilled) == "number" and numFulfilled) or 0
                        local progress = (required > 0) and (fulfilled / required) or 0
                        local color = SQOL_GetProgressColor(progress)
                        local text = string.format("%s%d/%d|r %s", color, fulfilled, required, objText or "")
                        local block = ObjectiveTrackerBlocksFrame and ObjectiveTrackerBlocksFrame:GetBlock(info.questID)
                        if block and block.lines then
                            for _, line in pairs(block.lines) do
                                local lineText = line.text and line.text:GetText()
                                if lineText and objText and lineText:find(objText, 1, true) then
                                    line.text:SetText(text)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function SQOL_RecolorQuestObjectives_Throttle()
    if SQOL._recolorPending then return end
    SQOL._recolorPending = true
    C_Timer.After(0.2, function()
        SQOL_RecolorQuestObjectives_Impl()
        SQOL._recolorPending = false
        SQOL._lastRecolorAt = GetTimePreciseSec()
    end)
end

------------------------------------------------------------
-- Custom colored UI_INFO_MESSAGE (Retail-safe)
------------------------------------------------------------
local function SQOL_EnableCustomInfoMessages()
    if UIErrorsFrame and UIErrorsFrame.UnregisterEvent then
        UIErrorsFrame:UnregisterEvent("UI_INFO_MESSAGE")
        dprint("Disabled Blizzard UI_INFO_MESSAGE display.")
    end

    if not SQOL.MessageFrame then
        SQOL.MessageFrame = CreateFrame("MessageFrame", "SQOL_MessageFrame", UIParent)
        SQOL.MessageFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
        SQOL.MessageFrame:SetSize(512, 60)
        SQOL.MessageFrame:SetInsertMode("TOP")
        SQOL.MessageFrame:SetFading(true)
        SQOL.MessageFrame:SetFadeDuration(1.5)
        SQOL.MessageFrame:SetTimeVisible(2.5)
        -- Use explicit font to avoid dependency on UI object availability
        SQOL.MessageFrame:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    end

    if not SQOL.InfoEventFrame then
        SQOL.InfoEventFrame = CreateFrame("Frame", "SQOL_InfoEventFrame")
        SQOL.InfoEventFrame:RegisterEvent("UI_INFO_MESSAGE")
        SQOL.InfoEventFrame:SetScript("OnEvent", function(_, event, messageType, message)
            if event ~= "UI_INFO_MESSAGE" or not SQOL.DB.ColorProgress then return end
            if type(message) ~= "string" then return end

            local label, cur, total = message:match("^(.+):%s*(%d+)%s*/%s*(%d+)$")
            if not (label and cur and total) then
                -- Keep Blizzard's standard UI_INFO_MESSAGE colors (e.g. discoveries are yellow).
                local r, g, b = 1, 0.82, 0
                if type(GetGameMessageInfo) == "function" then
                    local rr, gg, bb = GetGameMessageInfo(messageType)
                    if type(rr) == "number" and type(gg) == "number" and type(bb) == "number" then
                        r, g, b = rr, gg, bb
                    end
                end

                SQOL.MessageFrame:AddMessage(message, r, g, b)
                return
            end

            cur, total = tonumber(cur), tonumber(total)
            local progress = (total and total > 0) and clamp01(cur / total) or 0
            local colorCode = SQOL_GetProgressColor(progress)

            SQOL.MessageFrame:AddMessage(colorCode .. message .. "|r")

            dprint(string.format("Custom UI_INFO_MESSAGE: %s (%d/%d, %.2f)",
                label, cur or -1, total or -1, progress))
        end)
    end
end

------------------------------------------------------------
-- PlayerFrame: show equipped iLvl
------------------------------------------------------------
SQOL._ilvlRetryPending = false
SQOL._playerFrameHooked = false
SQOL._ilvlEnsureRetryPending = false

SQOL._lastSpeedPct = nil

SQOL._cachedIlvlText = "--"
SQOL._cachedIlvlMissingInfo = false
SQOL._cachedIlvlAt = 0

SQOL._lastStatLineText = nil

local function SQOL_GetEquippedItemLevel()
    if type(GetAverageItemLevel) == "function" then
        local avg, equipped = GetAverageItemLevel()
        if type(equipped) == "number" and equipped > 0 then
            return equipped
        end
        if type(avg) == "number" and avg > 0 then
            return avg
        end
    end

    local function getItemLevelFromLink(link)
        if C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
            return C_Item.GetDetailedItemLevelInfo(link)
        end
        local legacy = rawget(_G, "GetDetailedItemLevelInfo")
        if type(legacy) == "function" then
            return legacy(link)
        end
        return nil
    end

    local total, count = 0, 0
    local missingInfo = false

    for slot = 1, 17 do
        if slot ~= 4 then -- skip shirt slot
            local link = GetInventoryItemLink("player", slot)
            if link then
                local ilvl = getItemLevelFromLink(link)
                if ilvl then
                    total = total + ilvl
                    count = count + 1
                else
                    missingInfo = true
                end
            end
        end
    end

    if count == 0 then
        return nil
    end

    return (total / count), missingInfo
end

local function SQOL_RefreshIlvlCache(force)
    local now = (type(GetTime) == "function") and GetTime() or 0
    if not force and (now - (SQOL._cachedIlvlAt or 0)) < 1.5 then
        return
    end

    local ilvl, missingInfo = SQOL_GetEquippedItemLevel()
    if type(ilvl) == "number" then
        SQOL._cachedIlvlText = string.format("%.1f", ilvl)
    else
        SQOL._cachedIlvlText = "--"
    end

    SQOL._cachedIlvlMissingInfo = (missingInfo == true)
    SQOL._cachedIlvlAt = now
end

-- Returns movement speed as a percentage of normal run speed (100% = base).
-- Note: GetUnitSpeed() returns 0 when standing still; we keep the last non-zero value as fallback.
local function SQOL_GetMovementSpeedPercent()
    local baseRunSpeed = 7 -- yards/sec (100% run speed)

    if type(GetUnitSpeed) ~= "function" then
        return nil
    end

    local speed = GetUnitSpeed("player")
    if type(speed) ~= "number" then
        return nil
    end

    -- When standing still, speed is 0; keep the last known non-zero value.
    if speed <= 0 then
        return SQOL._lastSpeedPct
    end

    local pct = (speed / baseRunSpeed) * 100
    SQOL._lastSpeedPct = pct
    return pct
end

local function SQOL_UpdateCharacterIlvlText(forceIlvlRefresh)
    if SQOL.DB and SQOL.DB.ShowIlvlSpd == false then
        if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        return
    end
    if not SQOL.iLvlText then return end

    -- Keep iLvl cached so speed polling is cheap.
    SQOL_RefreshIlvlCache(forceIlvlRefresh == true)

    if SQOL._cachedIlvlMissingInfo and not SQOL._ilvlRetryPending then
        SQOL._ilvlRetryPending = true
        C_Timer.After(0.5, function()
            SQOL._ilvlRetryPending = false
            SQOL_RefreshIlvlCache(true)
            SQOL_UpdateCharacterIlvlText(true)
        end)
    end

    local speedPct = SQOL_GetMovementSpeedPercent()

    local ilvlText = SQOL._cachedIlvlText or "--"
    local speedText
    if type(speedPct) == "number" then
        speedText = string.format("%d%%", math.floor(speedPct + 0.5))
    else
        speedText = "--"
    end

    local line = string.format("iLvl: %s  Spd: %s", ilvlText, speedText)
    if SQOL._lastStatLineText ~= line then
        SQOL._lastStatLineText = line
        SQOL.iLvlText:SetText(line)
    end
end

local function SQOL_GetPlayerPortraitFrame(playerFrame)
    if not playerFrame then return nil end

    local portrait = rawget(_G, "PlayerPortrait") or rawget(_G, "PlayerFramePortrait")
    if portrait then return portrait end

    local container = rawget(playerFrame, "PlayerFrameContainer")
    local containerPortrait = container and (rawget(container, "PlayerPortrait") or rawget(container, "Portrait"))
    if containerPortrait then return containerPortrait end

    local content = rawget(playerFrame, "PlayerFrameContent")
    local main = content and rawget(content, "PlayerFrameContentMain")
    portrait = main and rawget(main, "Portrait")
    if portrait then return portrait end

    portrait = rawget(playerFrame, "portrait")
    return portrait
end

local function SQOL_GetPlayerHealthBarFrame(playerFrame)
    if not playerFrame then return nil end

    local globalHealth = rawget(_G, "PlayerFrameHealthBar")
    if globalHealth then return globalHealth end

    local container = rawget(playerFrame, "PlayerFrameContainer")
    local containerHealth = container and (rawget(container, "HealthBar") or rawget(container, "PlayerFrameHealthBar"))
    if containerHealth then return containerHealth end

    local content = rawget(playerFrame, "PlayerFrameContent")
    local main = content and rawget(content, "PlayerFrameContentMain")
    local healthBarsContainer = main and rawget(main, "HealthBarsContainer")
    local mainHealth = healthBarsContainer and (rawget(healthBarsContainer, "HealthBar") or rawget(healthBarsContainer, "PlayerFrameHealthBar"))
    if mainHealth then return mainHealth end

    local fallback = rawget(playerFrame, "healthbar") or rawget(playerFrame, "HealthBar")
    return fallback
end

local function SQOL_UpdatePlayerFrameIlvlAnchor()
    if not SQOL.iLvlHolder or not SQOL.iLvlText then
        return false
    end

    if SQOL.DB and SQOL.DB.ShowIlvlSpd == false then
        SQOL.iLvlHolder:Hide()
        return true
    end

    local playerFrame = rawget(_G, "PlayerFrame")
    if not playerFrame then
        SQOL.iLvlHolder:Hide()
        return false
    end

    SQOL.iLvlHolder:ClearAllPoints()

    -- Prefer anchoring next to the level text to avoid overlap with the level badge.
    -- The user wants iLvl + Spd on the SAME line as PlayerName + PlayerLevelText.
    local levelText = rawget(_G, "PlayerLevelText")
        or rawget(playerFrame, "PlayerLevelText")
        or (playerFrame and playerFrame.PlayerLevelText)

    -- Best-effort lookup for the name FontString (Retail has moved this around a few times).
    local nameText = rawget(_G, "PlayerName")
        or rawget(_G, "PlayerFrameName")
        or rawget(playerFrame, "name")
        or rawget(playerFrame, "PlayerName")
        or rawget(playerFrame, "PlayerFrameName")
        or (playerFrame and playerFrame.name)

    if levelText and levelText.GetCenter then
        -- Build to the left: iLvl + speed will be right-justified and won't get covered by the level badge.
        -- Use RIGHT/LEFT anchoring (not TOP/BOTTOM) to stay on the same line as the level text.
        local padding = 6
        local defaultWidth = 240

        -- Try to auto-fit between name and level (so long names don't overlap the stat line).
        local width = defaultWidth
        if nameText and nameText.GetRight and levelText.GetLeft then
            local nameRight = nameText:GetRight()
            local levelLeft = levelText:GetLeft()
            if type(nameRight) == "number" and type(levelLeft) == "number" then
                local available = (levelLeft - padding) - (nameRight + 8)
                if available and available > 60 then
                    width = math.min(defaultWidth, available)
                end
            end
        end

        SQOL.iLvlHolder:SetSize(width, 14)
        SQOL.iLvlText:SetWidth(width)
        SQOL.iLvlHolder:SetPoint("RIGHT", levelText, "LEFT", -padding, 0)
    else
        -- Ensure we don't keep a reduced width from the auto-fit branch.
        SQOL.iLvlHolder:SetSize(240, 14)
        SQOL.iLvlText:SetWidth(240)

        local healthBar = SQOL_GetPlayerHealthBarFrame(playerFrame)
        local portrait = SQOL_GetPlayerPortraitFrame(playerFrame)

        if healthBar and healthBar.GetCenter then
            -- Fallback: top-right of HP bar, shifted left to keep clear of the level badge.
            SQOL.iLvlHolder:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", -110, 10)
        elseif portrait and portrait.GetCenter then
            SQOL.iLvlHolder:SetPoint("BOTTOM", portrait, "BOTTOM", 0, 4)
        else
            SQOL.iLvlHolder:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 70, -22)
        end
    end

    if playerFrame.IsShown and playerFrame:IsShown() then
        SQOL.iLvlHolder:Show()
    else
        SQOL.iLvlHolder:Hide()
    end

    return true
end

local function SQOL_EnsurePlayerFrameIlvlUI()
    local playerFrame = rawget(_G, "PlayerFrame")
    if not playerFrame then
        return false
    end

    -- If disabled via /SQOL stats, don't build or show anything.
    if SQOL.DB and SQOL.DB.ShowIlvlSpd == false then
        if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        return true
    end

    if not SQOL.iLvlHolder then
        SQOL.iLvlHolder = CreateFrame("Frame", "SQOL_PlayerFrameIlvlHolder", UIParent)
        SQOL.iLvlHolder:SetSize(240, 14)
        SQOL.iLvlHolder:SetFrameStrata("HIGH")
        SQOL.iLvlHolder:Hide()
    end

    if not SQOL.iLvlText then
        SQOL.iLvlText = SQOL.iLvlHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        SQOL.iLvlText:SetPoint("CENTER", SQOL.iLvlHolder, "CENTER", 0, 0)
        SQOL.iLvlText:SetJustifyH("RIGHT")
        SQOL.iLvlText:SetWidth(240)
        SQOL.iLvlText:SetWordWrap(false)
        if SQOL.iLvlText.SetMaxLines then SQOL.iLvlText:SetMaxLines(1) end
        SQOL.iLvlText:SetText("iLvl: --  Spd: --")
    end

    if not SQOL._playerFrameHooked and playerFrame.HookScript then
        SQOL._playerFrameHooked = true
        playerFrame:HookScript("OnShow", function()
            SQOL_UpdatePlayerFrameIlvlAnchor()
            SQOL_UpdateCharacterIlvlText(true)
        end)
        playerFrame:HookScript("OnHide", function()
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end)
    end

    -- Poll speed periodically so we still show a meaningful value even when movement events are missed.
    if not SQOL._speedPoller then
        SQOL._speedPoller = CreateFrame("Frame", nil, SQOL.iLvlHolder)
        SQOL._speedPoller._elapsed = 0
        SQOL._speedPoller:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = (self._elapsed or 0) + (elapsed or 0)
            if self._elapsed < 0.20 then return end
            self._elapsed = 0

            if SQOL.iLvlHolder and SQOL.iLvlHolder.IsShown and SQOL.iLvlHolder:IsShown() then
                SQOL_UpdateCharacterIlvlText(false)
            end
        end)
    end

    SQOL_UpdatePlayerFrameIlvlAnchor()
    SQOL_UpdateCharacterIlvlText(true)
    return true
end

local function SQOL_TryEnsurePlayerFrameIlvlUI(retries)
    retries = retries or 0
    if SQOL_EnsurePlayerFrameIlvlUI() then
        return
    end

    if retries >= 10 then
        return
    end

    if SQOL._ilvlEnsureRetryPending then
        return
    end

    SQOL._ilvlEnsureRetryPending = true
    C_Timer.After(0.2, function()
        SQOL._ilvlEnsureRetryPending = false
        SQOL_TryEnsurePlayerFrameIlvlUI(retries + 1)
    end)
end

------------------------------------------------------------
-- Helpers: trackable types
------------------------------------------------------------
local function SQOL_HandleTrackableTypes(questID)
    -- Bonus objectives / task quests: don't try to add a watch (Blizzard handles these automatically)
    if C_QuestLog.IsQuestTask(questID) then
        dprint("Skipping task/bonus objective:", questID)
        return "skip"
    end

    -- World quests: use the correct API if available
    if C_QuestLog.IsWorldQuest(questID) then
        if C_QuestLog.AddWorldQuestWatch then
            local ok = safe_pcall(function() C_QuestLog.AddWorldQuestWatch(questID) end)
            if ok then
                dprint("Added world quest watch:", questID)
                return "done"
            end
        end
        dprint("Could not add world quest watch:", questID)
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
        dprint("Already tracked:", title)
        return
    end

    dprint("Attempting to track:", title)

    C_QuestLog.AddQuestWatch(questID)
    print("And |cff33ff99SQoL|r auto-tracked it")

end

------------------------------------------------------------
-- RepWatch: auto-switch watched reputation on rep gain
-- Uses C_Reputation APIs when available (TWW/11.0.2+), with legacy fallback.
------------------------------------------------------------
SQOL._repWatchPending = false
SQOL._repLastStanding = nil
SQOL._repApiWarned = false

local function SQOL_Rep_GetNumFactions()
    if C_Reputation and type(C_Reputation.GetNumFactions) == "function" then
        return C_Reputation.GetNumFactions()
    end
    local legacy = rawget(_G, "GetNumFactions")
    if type(legacy) == "function" then
        return legacy()
    end
    return nil
end

local function SQOL_Rep_GetFactionDataByIndex(index)
    if C_Reputation and type(C_Reputation.GetFactionDataByIndex) == "function" then
        local data = C_Reputation.GetFactionDataByIndex(index)
        if data and type(data) == "table" then
            -- Field names have shifted a bit over time; normalize to "currentStanding" when possible.
            if type(data.currentStanding) ~= "number" then
                data.currentStanding =
                    data.currentStanding
                    or data.earnedValue
                    or data.barValue
                    or data.currentValue
                    or data.currentReputation
            end
        end
        return data
    end

    local legacy = rawget(_G, "GetFactionInfo")
    if type(legacy) == "function" then
        local name, description, standingId, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar,
            isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = legacy(index)

        if not name then
            return nil
        end

        return {
            factionID = factionID,
            name = name,
            description = description,
            reaction = standingId,
            currentReactionThreshold = bottomValue,
            nextReactionThreshold = topValue,
            -- For legacy APIs, "earnedValue" changes with rep gain and is stable for delta detection.
            currentStanding = earnedValue,
            atWarWith = atWarWith,
            canToggleAtWar = canToggleAtWar,
            isHeader = isHeader,
            isCollapsed = isCollapsed,
            hasRep = hasRep,
            isWatched = isWatched,
            isChild = isChild,
        }
    end

    return nil
end

local function SQOL_Rep_ExpandAllHeaders()
    if C_Reputation and type(C_Reputation.ExpandAllFactionHeaders) == "function" then
        safe_pcall(C_Reputation.ExpandAllFactionHeaders)
        return true
    end

    local legacy = rawget(_G, "ExpandFactionHeader")
    if type(legacy) ~= "function" then
        return false
    end

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return false
    end

    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and data.isHeader and data.isCollapsed then
            safe_pcall(legacy, i)
        end
    end

    return true
end

local function SQOL_Rep_SetWatchedFactionByIndexOrID(index, factionID)
    if C_Reputation and type(C_Reputation.SetWatchedFactionByID) == "function" and type(factionID) == "number" then
        return safe_pcall(C_Reputation.SetWatchedFactionByID, factionID)
    end

    local legacy = rawget(_G, "SetWatchedFactionIndex")
    if type(legacy) == "function" and type(index) == "number" then
        return safe_pcall(legacy, index)
    end

    return false
end

local function SQOL_Rep_BuildSnapshot()
    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return nil
    end

    SQOL_Rep_ExpandAllHeaders()

    local snap = {}
    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and type(data.factionID) == "number" and type(data.currentStanding) == "number" then
            snap[data.factionID] = data.currentStanding
        end
    end
    return snap
end

------------------------------------------------------------
-- RepWatch helpers: map "faction name" -> factionID.
-- This is the most reliable way to switch watched reputation in modern Retail,
-- because the chat event already tells us which faction changed.
------------------------------------------------------------
SQOL._repNameToID = SQOL._repNameToID or {}

local function SQOL_TableWipe(t)
    if type(t) ~= "table" then return end
    local wipeFn = rawget(_G, "wipe")
    if type(wipeFn) == "function" then
        wipeFn(t)
        return
    end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function SQOL_Rep_RebuildNameMap()
    SQOL_TableWipe(SQOL._repNameToID)

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        return false
    end

    SQOL_Rep_ExpandAllHeaders()

    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and type(data.factionID) == "number" and type(data.name) == "string" and data.name ~= "" then
            SQOL._repNameToID[data.name] = data.factionID
        end
    end

    return true
end

local function SQOL_Rep_FindFactionIDByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local id = SQOL._repNameToID[name]
    if type(id) == "number" then
        return id
    end

    -- Refresh once (headers / list may have changed)
    if SQOL_Rep_RebuildNameMap() then
        id = SQOL._repNameToID[name]
        if type(id) == "number" then
            return id
        end
    end

    return nil
end

local function SQOL_Rep_ParseFactionNameFromMessage(msg)
    if type(msg) ~= "string" then
        return nil
    end

    -- enUS patterns (Retail default). If you ever play another locale,
    -- we can switch this over to use global string templates instead.
    local name =
        msg:match("^Reputation with (.-) increased") or
        msg:match("^Reputation with (.-) decreased") or
        msg:match("^Your reputation with (.-) has increased") or
        msg:match("^Your reputation with (.-) has decreased")

    if type(name) ~= "string" then
        return nil
    end

    name = name:gsub("%.$", "")
    name = name:match("^%s*(.-)%s*$")

    if name == "" then
        return nil
    end

    return name
end

local function SQOL_RepWatch_HandleFactionChangeMessage(msg)
    if not SQOL.DB or not SQOL.DB.RepWatch then
        return false
    end

    local name = SQOL_Rep_ParseFactionNameFromMessage(msg)
    if not name then
        return false
    end

    local id = SQOL_Rep_FindFactionIDByName(name)
    if type(id) ~= "number" then
        dprint("RepWatch -> Could not resolve factionID for:", name)
        return false
    end

    local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(nil, id)
    if ok then
        dprint("RepWatch -> Now watching:", name)
        return true
    end

    dprint("RepWatch -> Failed to set watched faction for:", name)
    return false
end

local function SQOL_RepWatch_ScanAndSwitch()
    if not SQOL.DB or not SQOL.DB.RepWatch then
        return
    end

    local num = SQOL_Rep_GetNumFactions()
    if not num then
        if SQOL.DB.DebugTrack and not SQOL._repApiWarned then
            SQOL._repApiWarned = true
            dprint("RepWatch -> Reputation APIs not available in this client build.")
        end
        return
    end

    SQOL_Rep_ExpandAllHeaders()

    if type(SQOL._repLastStanding) ~= "table" then
        SQOL._repLastStanding = SQOL_Rep_BuildSnapshot()
        dprint("RepWatch -> Snapshot initialized.")
        return
    end

    local bestDelta = 0
    local bestIndex, bestFactionID, bestName = nil, nil, nil

    for i = 1, num do
        local data = SQOL_Rep_GetFactionDataByIndex(i)
        if data and type(data.factionID) == "number" and type(data.currentStanding) == "number" then
            local id = data.factionID
            local prev = SQOL._repLastStanding[id]
            local cur = data.currentStanding

            if type(prev) == "number" then
                local delta = cur - prev
                if delta > bestDelta then
                    bestDelta = delta
                    bestIndex = i
                    bestFactionID = id
                    bestName = data.name
                end
            end

            SQOL._repLastStanding[id] = cur
        end
    end

    if bestDelta > 0 and (bestFactionID or bestIndex) then
        local ok = SQOL_Rep_SetWatchedFactionByIndexOrID(bestIndex, bestFactionID)
        if ok then
            dprint(string.format("RepWatch -> Now watching: %s (+%d)", tostring(bestName or bestFactionID), bestDelta))
        else
            dprint("RepWatch -> Could not set watched faction.")
        end
    end
end

function SQOL_RepWatch_ScheduleScan()
    if SQOL._repWatchPending then
        return
    end
    SQOL._repWatchPending = true
    C_Timer.After(0.20, function()
        SQOL._repWatchPending = false
        SQOL_RepWatch_ScanAndSwitch()
    end)
end

------------------------------------------------------------
-- Splash
------------------------------------------------------------
local function SQOL_Splash()
    local version, atState, spState, coState, loState, repState = SQOL_GetStateStrings()
    print("|cff33ff99-----------------------------------|r")
    print("|cff33ff99" .. (SQOL.ADDON_NAME or "SMoRGsQoL") .. " (SQOL)|r |cffffffffv" .. version .. "|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
    print("|cff33ff99AutoTrack:|r " .. atState)
    print("|cff33ff99Splash:|r " .. spState)
    print("|cff33ff99ColorProgress:|r " .. coState)
    print("|cff33ff99HideDoneAchievements:|r " .. loState)
    print("|cff33ff99RepWatch:|r " .. repState)
    print("|cffccccccType |cff00ff00/SQOL help|r for command list.|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
end

------------------------------------------------------------
-- Event: QUEST_LOG_UPDATE (play sound when quest ready)
------------------------------------------------------------
SQOL.fullyCompleted = {}

local function SQOL_CheckQuestProgress()
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives and #objectives > 0 then
                local allDone = true
                for _, obj in ipairs(objectives) do
                    if not obj.finished then
                        allDone = false
                        break
                    end
                end

                -- If all objectives done and not previously marked complete
                if allDone and not SQOL.fullyCompleted[info.questID] then
                    SQOL.fullyCompleted[info.questID] = true
                    PlaySound(6199, "Master")

                    -- Determine quest type
                    local isTask = C_QuestLog.IsQuestTask(info.questID)
                    local isWorld = C_QuestLog.IsWorldQuest(info.questID)

                    if isTask or isWorld then
                        -- Bonus or world quest
                        print("|cff33ff99SQoL:|r |cffffff00" ..
                            (info.title or info.questID) .. "|r |cff00ff00is done!|r")
                    else
                        -- Normal quest
                        print("|cff33ff99SQoL:|r |cffffff00" ..
                            (info.title or info.questID) .. "|r |cff00ff00is ready to turn in!|r")
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Help
------------------------------------------------------------
local function SQOL_Help()
    local version, atState, spState, coState, loState, repState, statsState = SQOL_GetStateStrings()
    print("|cff33ff99-----------------------------------|r")
    print("|cff33ff99" .. (SQOL.ADDON_NAME or "SMoRGsQoL") .. " (SQOL)|r |cffffffffv" .. version .. "|r")
    print("|cff33ff99-----------------------------------|r")
    print("|cff00ff00/SQOL autotrack|r   |cffcccccc- Toggle automatic quest tracking|r")
    print("|cff00ff00/SQOL at|r          |cffcccccc- Shorthand for autotrack|r")
    print("|cff00ff00/SQOL color|r       |cffcccccc- Toggle progress colorization|r")
    print("|cff00ff00/SQOL col|r         |cffcccccc- Shorthand for color|r")
    print("|cff00ff00/SQOL hideach|r     |cffcccccc- Toggle hiding completed achievements|r")
    print("|cff00ff00/SQOL ha|r          |cffcccccc- Shorthand for hideach|r")
    print("|cff00ff00/SQOL splash|r      |cffcccccc- Toggle splash on login|r")
    print("|cff00ff00/SQOL rep|r         |cffcccccc- Toggle watched reputation auto-switch on rep gain|r")
    print("|cff00ff00/SQOL rw|r          |cffcccccc- Shorthand for rep|r")
    print("|cff00ff00/SQOL stats|r       |cffcccccc- Toggle PlayerFrame iLvl+Spd line|r")
    print("|cff00ff00/SQOL ilvl|r        |cffcccccc- Shorthand for stats|r")
    print("|cff00ff00/SQOL debugtrack|r  |cffcccccc- Toggle verbose tracking debug|r")
    print("|cff00ff00/SQOL dbg|r         |cffcccccc- Shorthand for debugtrack|r")
    print("|cff00ff00/SQOL reset|r       |cffcccccc- Reset all settings to defaults|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
    print("|cff33ff99AutoTrack:|r " .. atState .. "  |cff33ff99Splash:|r " .. spState .. "  |cff33ff99ColorProgress:|r " .. coState .. "  |cff33ff99HideDoneAchievements:|r " .. loState)
    print("|cff33ff99RepWatch:|r " .. repState .. "  |cff33ff99StatsLine:|r " .. statsState)
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

    if key == "ColorProgress" then
        if SQOL.DB.ColorProgress then
            SQOL_EnableCustomInfoMessages()
        else
            if UIErrorsFrame and UIErrorsFrame.RegisterEvent then
                UIErrorsFrame:RegisterEvent("UI_INFO_MESSAGE")
            end
        end

    elseif key == "HideDoneAchievements" then
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        end
        SQOL_ApplyAchievementFilter()

    elseif key == "RepWatch" then
        if SQOL.DB.RepWatch then
            SQOL._repLastStanding = nil
            if SQOL_Rep_RebuildNameMap then
                SQOL_Rep_RebuildNameMap()
            end
            if SQOL_RepWatch_ScheduleScan then
                SQOL_RepWatch_ScheduleScan()
            end
        end

    elseif key == "ShowIlvlSpd" then
        if SQOL.DB.ShowIlvlSpd then
            SQOL_TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end
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
        toggle("ColorProgress", "Progress colorization is")

    elseif msg == "splash" then
        toggle("ShowSplash", "Splash is")

    elseif msg == "rep" or msg == "rw" then
        toggle("RepWatch", "RepWatch is")

    elseif msg == "stats" or msg == "ilvl" then
        toggle("ShowIlvlSpd", "PlayerFrame iLvl+Spd line is")

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
        local version, at, sp, co, lo, rep, stats = SQOL_GetStateStrings()
        print("|cff33ff99SQoL|r v" .. version .. " - AutoTrackQuests:" .. at .. " Splash:" .. sp .. " ColorProgress:" .. co .. " HideDoneAchievements:" .. lo .. " RepWatch:" .. rep .. " StatsLine:" .. stats)
        print("|cffccccccCommands:|r help for more info")
    end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("UPDATE_FACTION")
f:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        SQOL.Init()
        if SQOL.DB.ShowSplash then
            SQOL_Splash()
        end

        if SQOL.DB.ColorProgress then
            SQOL_EnableCustomInfoMessages()
        end

        -- Apply saved preference when logging in (only if already loaded)
        SQOL_ApplyAchievementFilter()

        -- Ensure PlayerFrame iLvl display.
        if SQOL.DB.ShowIlvlSpd then
            SQOL_TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

        -- Initialize RepWatch snapshot (if enabled)
        if SQOL.DB.RepWatch and SQOL_RepWatch_ScheduleScan then
            SQOL._repLastStanding = nil
            if SQOL_Rep_RebuildNameMap then
                SQOL_Rep_RebuildNameMap()
            end
            SQOL_RepWatch_ScheduleScan()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if SQOL.DB and SQOL.DB.ShowIlvlSpd then
            SQOL_TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

     elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_AchievementUI" then
            C_Timer.After(0.1, SQOL_ApplyAchievementFilter)
        end

    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            if SQOL.DB and SQOL.DB.ShowIlvlSpd then
                if not SQOL.iLvlText then
                    SQOL_TryEnsurePlayerFrameIlvlUI(0)
                end
                SQOL_UpdateCharacterIlvlText()
            else
                if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
            end
        end

    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if SQOL.DB and SQOL.DB.ShowIlvlSpd then
            SQOL_UpdatePlayerFrameIlvlAnchor()
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        if SQOL.DB and SQOL.DB.ShowIlvlSpd then
            if not SQOL.iLvlText then
                SQOL_TryEnsurePlayerFrameIlvlUI(0)
            end
            SQOL_UpdatePlayerFrameIlvlAnchor()
            SQOL_UpdateCharacterIlvlText()
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

    elseif event == "QUEST_ACCEPTED" then
        if not SQOL.DB.AutoTrack then return end
        local a1, a2 = ...
        local questIndex, questID
        if a2 then questIndex, questID = a1, a2 else questID = a1 end
        if (not questID or questID == 0) and questIndex then
            local info = C_QuestLog.GetInfo(questIndex)
            if info and info.questID then
                questID = info.questID
                dprint("Recovered questID", questID, "from questIndex", questIndex)
            end
        end

        if questID then
            SQOL.fullyCompleted[questID] = nil
            SQOL_TryAutoTrack(questID)
        else
            dprint("Could not resolve questID on QUEST_ACCEPTED:", tostring(a1), tostring(a2))
        end

    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if questID then
            SQOL.fullyCompleted[questID] = nil
        end

    elseif event == "QUEST_REMOVED" then
        local questID = ...
        if questID then
            SQOL.fullyCompleted[questID] = nil
        end

    elseif event == "UPDATE_FACTION" then
        if SQOL.DB and SQOL.DB.RepWatch and SQOL_RepWatch_ScheduleScan then
            SQOL_RepWatch_ScheduleScan()
        end

    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if SQOL.DB and SQOL.DB.RepWatch then
            local msg = ...
            local handled = false

            if SQOL_RepWatch_HandleFactionChangeMessage then
                handled = SQOL_RepWatch_HandleFactionChangeMessage(msg)
            end

            -- Fallback: if we couldn't parse/resolve the faction, do a delta-based scan.
            if not handled and SQOL_RepWatch_ScheduleScan then
                SQOL_RepWatch_ScheduleScan()
            end
        end

    elseif event == "QUEST_LOG_UPDATE" then
        SQOL_CheckQuestProgress()
        SQOL_RecolorQuestObjectives_Throttle()
    end
end)

