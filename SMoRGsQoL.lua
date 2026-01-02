------------------------------------------------------------
-- SMoRGsQoL v1.0.7 by SMoRG75
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
    ShowNameplateObjectives = false,

    -- PlayerFrame line: "iLvl: xx.x  Spd: yy%"
    ShowIlvlSpd  = false,

    -- Floating combat text damage numbers font.
    DamageTextFont = false,

    -- Highlight the cursor when shaking the mouse.
    CursorShakeHighlight = false
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
-- Damage text font
------------------------------------------------------------
local SQOL_DAMAGE_TEXT_FONT = "Interface\\AddOns\\SMoRGsQoL\\trashhand.ttf"

local function SQOL_ApplyDamageTextFont()
    if not SQOL._damageFontOriginal then
        SQOL._damageFontOriginal = {
            damage_text_font = _G.damage_text_font,
            DAMAGE_TEXT_FONT = _G.DAMAGE_TEXT_FONT,
        }
    end
    _G.damage_text_font = SQOL_DAMAGE_TEXT_FONT
    _G.DAMAGE_TEXT_FONT = SQOL_DAMAGE_TEXT_FONT
end

local function SQOL_RestoreDamageTextFont()
    if not SQOL._damageFontOriginal then return end
    _G.damage_text_font = SQOL._damageFontOriginal.damage_text_font
    _G.DAMAGE_TEXT_FONT = SQOL._damageFontOriginal.DAMAGE_TEXT_FONT
end

------------------------------------------------------------
-- Cursor shake highlight
------------------------------------------------------------
local SQOL_CURSOR_SHAKE_TEXTURE = "Interface\\Minimap\\Ping\\ping4"

local function SQOL_CursorShake_CreateFrame()
    if SQOL.CursorShakeFrame then return end

    local frame = CreateFrame("Frame", "SQOL_CursorShakeFrame", UIParent)
    frame:SetSize(120, 120)
    frame:SetFrameStrata("TOOLTIP")
    frame:EnableMouse(false)
    frame:Hide()

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(frame)
    tex:SetTexture(SQOL_CURSOR_SHAKE_TEXTURE)
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 0.9, 0.2)
    tex:SetAlpha(0.95)
    frame.texture = tex

    frame._samples = {}
    frame._elapsed = 0
    frame._flashTime = 0
    frame._flashDuration = 0.45
    frame._cooldown = 0

    SQOL.CursorShakeFrame = frame
end

local function SQOL_CursorShake_ResetState(frame)
    if not frame then return end
    frame._samples = {}
    frame._lastX = nil
    frame._lastY = nil
    frame._lastT = nil
    frame._elapsed = 0
    frame._flashTime = 0
    frame._cooldown = 0
    frame._debugNextPrint = nil
    frame._debugNoCursorAt = nil
    frame:Hide()
end

local function SQOL_CursorShake_GetStats(samples)
    local total = 0
    local maxSpeed = 0
    local dirChangesX = 0
    local dirChangesY = 0
    local lastDx, lastDy
    for i = 1, #samples do
        local sample = samples[i]
        total = total + (sample.dist or 0)
        if sample.speed and sample.speed > maxSpeed then
            maxSpeed = sample.speed
        end
        if sample.dx and lastDx and (sample.dx * lastDx) < 0 then
            if math.abs(sample.dx) > 2 and math.abs(lastDx) > 2 then
                dirChangesX = dirChangesX + 1
            end
        end
        if sample.dy and lastDy and (sample.dy * lastDy) < 0 then
            if math.abs(sample.dy) > 2 and math.abs(lastDy) > 2 then
                dirChangesY = dirChangesY + 1
            end
        end
        lastDx = sample.dx or lastDx
        lastDy = sample.dy or lastDy
    end

    if #samples >= 2 then
        local first = samples[1]
        local last = samples[#samples]
        local netDx = last.x - first.x
        local netDy = last.y - first.y
        local net = math.sqrt(netDx * netDx + netDy * netDy)
        return total, net, maxSpeed, dirChangesX, dirChangesY
    end

    return total, 0, maxSpeed, dirChangesX, dirChangesY
end

local function SQOL_CursorShake_OnUpdate(self, elapsed)
    if not SQOL.DB or not SQOL.DB.CursorShakeHighlight then
        self:SetScript("OnUpdate", nil)
        SQOL_CursorShake_ResetState(self)
        return
    end

    self._elapsed = (self._elapsed or 0) + (elapsed or 0)
    if self._elapsed < 0.02 then return end
    local dt = self._elapsed
    self._elapsed = 0

    local now = (type(GetTimePreciseSec) == "function") and GetTimePreciseSec() or GetTime()
    local x, y = GetCursorPosition()
    if not x or not y then
        if SQOL.DB and SQOL.DB.DebugTrack then
            if (not self._debugNoCursorAt) or now >= self._debugNoCursorAt then
                self._debugNoCursorAt = now + 1.0
                dprint("CursorShake: GetCursorPosition returned nil.")
            end
        end
        return
    end

    local scale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
    x, y = x / scale, y / scale

    if not self._lastX then
        self._lastX, self._lastY, self._lastT = x, y, now
    else
        local dx, dy = x - self._lastX, y - self._lastY
        local dist = math.sqrt(dx * dx + dy * dy)
        local dtSample = now - (self._lastT or now)
        local speed = (dtSample and dtSample > 0) and (dist / dtSample) or 0
        if dist > 0 then
            table.insert(self._samples, { x = x, y = y, t = now, dist = dist, dx = dx, dy = dy, speed = speed })
        end
        self._lastX, self._lastY, self._lastT = x, y, now
    end

    -- Keep a short window and look for quick back-and-forth movement.
    local window = 0.22
    local samples = self._samples
    while #samples > 0 and (now - samples[1].t) > window do
        table.remove(samples, 1)
    end

    if self._flashTime and self._flashTime > 0 then
        self._flashTime = self._flashTime - dt
        local alpha = (self._flashDuration and self._flashDuration > 0)
            and clamp01(self._flashTime / self._flashDuration)
            or 0
        if self.texture then
            self.texture:SetAlpha(0.9 * alpha)
        end
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        if self._flashTime <= 0 then
            self._flashTime = 0
            if self.texture then
                self.texture:SetAlpha(0)
            end
            if self:GetAlpha() ~= 0 then
                self:SetAlpha(0)
            end
        else
            if self:GetAlpha() ~= 1 then
                self:SetAlpha(1)
            end
        end
    end

    if self._cooldown and self._cooldown > 0 then
        self._cooldown = self._cooldown - dt
    end

    local total, net, maxSpeed, dirChangesX, dirChangesY = 0, 0, 0, 0, 0
    local needStats = (self._cooldown and self._cooldown <= 0 and #samples >= 3)
        or (SQOL.DB and SQOL.DB.DebugTrack)
    if needStats then
        total, net, maxSpeed, dirChangesX, dirChangesY = SQOL_CursorShake_GetStats(samples)
    end

    if SQOL.DB and SQOL.DB.DebugTrack then
        if (not self._debugNextPrint) or now >= self._debugNextPrint then
            self._debugNextPrint = now + 0.6
            dprint(string.format(
                "CursorShake: samples=%d total=%.1f net=%.1f speed=%.0f dirX=%d dirY=%d cooldown=%.2f flash=%.2f",
                #samples, total, net, maxSpeed, dirChangesX, dirChangesY, self._cooldown or 0, self._flashTime or 0
            ))
        end
    end

    if self._cooldown and self._cooldown <= 0 and #samples >= 5 then

        local threshold = 220
        local netRatio = 0.50
        local minDirChanges = 2
        local hasBackAndForth = (dirChangesX >= minDirChanges or dirChangesY >= minDirChanges)
        local hasShake = (total >= threshold) and hasBackAndForth and (net <= (total * netRatio))

        if hasShake then
            self._cooldown = 0.40
            self._flashDuration = 0.45
            self:SetSize(120, 120)
            self.texture:SetAlpha(0.9)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            self._flashTime = self._flashDuration
            self:Show()
            if SQOL.DB and SQOL.DB.DebugTrack then
                dprint(string.format(
                    "CursorShake: TRIGGER total=%.1f net=%.1f speed=%.0f dirX=%d dirY=%d",
                    total, net, maxSpeed, dirChangesX, dirChangesY
                ))
            end
        end
    end
end

local function SQOL_CursorShake_Enable()
    SQOL_CursorShake_CreateFrame()
    local frame = SQOL.CursorShakeFrame
    if not frame then return end
    frame:SetAlpha(0)
    if frame.texture then
        frame.texture:SetAlpha(0)
    end
    frame:Show()
    frame:SetScript("OnUpdate", SQOL_CursorShake_OnUpdate)
end

local function SQOL_CursorShake_Disable()
    if not SQOL.CursorShakeFrame then return end
    SQOL.CursorShakeFrame:SetScript("OnUpdate", nil)
    SQOL_CursorShake_ResetState(SQOL.CursorShakeFrame)
end

local function SQOL_CursorShake_FlashNow(duration)
    if not SQOL.DB or not SQOL.DB.CursorShakeHighlight then
        print("|cff33ff99SQoL:|r Cursor shake highlight is OFF. Enable it with /sqol cursor.")
        return
    end

    SQOL_CursorShake_Enable()
    local frame = SQOL.CursorShakeFrame
    if not frame then return end

    local x, y = GetCursorPosition()
    if not x or not y then return end

    local scale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
    x, y = x / scale, y / scale

    frame._flashDuration = duration or 0.8
    frame._flashTime = frame._flashDuration
    frame._cooldown = 0.15
    frame:SetSize(120, 120)
    if frame.texture then
        frame.texture:SetAlpha(0.95)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    frame:Show()

    if SQOL.DB and SQOL.DB.DebugTrack then
        dprint("CursorShake: manual flash.")
    end
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
    local npState = SQOL.DB.ShowNameplateObjectives and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local dmgState = SQOL.DB.DamageTextFont and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local cursorState = SQOL.DB.CursorShakeHighlight and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    return version, atState, spState, coState, loState, repState, statsState, npState, dmgState, cursorState
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
-- Nameplate objective counts
------------------------------------------------------------
SQOL._npUnits = SQOL._npUnits or {}
SQOL._npUpdatePending = false

local function SQOL_NameplateObjectives_GetNpcID(unit)
    if type(UnitGUID) ~= "function" then
        return nil
    end

    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local npcId = select(6, strsplit("-", guid))
    return tonumber(npcId)
end

local function SQOL_NameplateObjectives_GetQuestEntries(unit)
    if not C_QuestLog then
        return nil
    end

    local entries
    if type(C_QuestLog.GetQuestsForNamePlate) == "function" then
        entries = C_QuestLog.GetQuestsForNamePlate(unit)
    elseif type(C_QuestLog.GetQuestsForNameplate) == "function" then
        entries = C_QuestLog.GetQuestsForNameplate(unit)
    end

    if SQOL.DB and SQOL.DB.DebugTrack then
        if type(entries) == "table" then
            local count = 0
            for _ in pairs(entries) do
                count = count + 1
            end
            dprint("NP quests for unit:", unit, "count:", count)
        else
            dprint("NP quests for unit:", unit, "-> none")
        end
    end

    return entries
end

local function SQOL_NameplateObjectives_ParseProgressFromText(text)
    if type(text) ~= "string" then
        return nil
    end

    local cur, total = text:match("(%d+)%s*/%s*(%d+)")
    if not cur or not total then
        return nil
    end

    cur, total = tonumber(cur), tonumber(total)
    if not cur or not total or total <= 0 then
        return nil
    end

    return cur, total
end

local function SQOL_NameplateObjectives_IsIgnoredTooltipLine(text)
    if type(text) ~= "string" then
        return true
    end
    local lower = text:lower()
    if lower:find("threat", 1, true) then
        return true
    end
    return false
end

local function SQOL_NameplateObjectives_GetTooltipProgress(unit)
    if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
        return nil
    end

    local data = C_TooltipInfo.GetUnit(unit)
    if not data or type(data.lines) ~= "table" then
        return nil
    end

    local inQuestBlock = false
    local questTitle = nil
    local fallbackLine = nil

    for _, line in ipairs(data.lines) do
        local leftText = line.leftText
        local rightText = line.rightText
        local leftColor = line.leftColor

        local isQuestTitle = false
        if leftText and leftColor and type(leftColor.r) == "number" then
            if leftColor.r > 0.99 and leftColor.g > 0.8 and leftColor.b < 0.1 then
                isQuestTitle = true
            end
        end

        if isQuestTitle then
            inQuestBlock = true
            questTitle = leftText
        else
            local texts = { leftText, rightText }
            for _, text in ipairs(texts) do
                if SQOL_NameplateObjectives_IsIgnoredTooltipLine(text) then
                    if SQOL.DB and SQOL.DB.DebugTrack and type(text) == "string" and text ~= "" then
                        dprint("NP tooltip: ignoring line:", text)
                    end
                else
                    local cur, total = SQOL_NameplateObjectives_ParseProgressFromText(text)
                    if cur then
                        if inQuestBlock then
                            return cur, total, text, questTitle
                        end
                        if not fallbackLine then
                            fallbackLine = { cur = cur, total = total, text = text, questTitle = questTitle }
                        end
                    else
                        local pct = text and text:match("(%d+)%%")
                        if pct then
                            cur, total = tonumber(pct), 100
                            if inQuestBlock then
                                return cur, total, text, questTitle
                            end
                            if not fallbackLine then
                                fallbackLine = { cur = cur, total = total, text = text, questTitle = questTitle }
                            end
                        end
                    end
                end
            end
        end
    end

    if fallbackLine then
        return fallbackLine.cur, fallbackLine.total, fallbackLine.text, fallbackLine.questTitle
    end

    return nil
end

local function SQOL_NameplateObjectives_GetObjectiveInfo(questID, objectiveIndex)
    if type(questID) ~= "number" or type(objectiveIndex) ~= "number" then
        return nil
    end

    local function try(fn)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, a, b, c, d, e = pcall(fn, questID, objectiveIndex, false)
        if not ok then
            return nil
        end
        if type(a) == "table" then
            return a
        end
        if a ~= nil then
            return {
                text = a,
                objectiveType = b,
                finished = c,
                numFulfilled = d,
                numRequired = e,
            }
        end
        return nil
    end

    local info = try(C_QuestLog and C_QuestLog.GetQuestObjectiveInfo)
    if not info and C_TaskQuest then
        info = try(C_TaskQuest.GetQuestObjectiveInfoByQuestID)
    end
    if not info and type(GetQuestObjectiveInfo) == "function" then
        info = try(GetQuestObjectiveInfo)
    end

    return info
end

local function SQOL_NameplateObjectives_GetProgressBarInfo(questID)
    if type(questID) ~= "number" then
        return nil
    end

    local function try(fn)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, a, b = pcall(fn, questID)
        if not ok then
            return nil
        end
        if type(a) == "table" then
            local cur = a.numFulfilled or a.progress or a.currentValue or a.value
            local total = a.numRequired or a.total or a.maxValue or a.max
            return cur, total
        end
        return a, b
    end

    local cur, total = try(C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo)
    if not cur then
        cur, total = try(C_QuestLog and C_QuestLog.GetQuestProgressBarInfo)
    end
    if not cur and type(GetQuestProgressBarInfo) == "function" then
        local ok, a, b = pcall(GetQuestProgressBarInfo, questID)
        if ok then
            cur, total = a, b
        end
    end

    if type(cur) == "number" and type(total) == "number" and total > 0 then
        return cur, total
    end

    return nil
end

local function SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
    local questID, objectiveIndex

    if type(entry) == "number" then
        questID = entry
    elseif type(entry) == "table" then
        questID = entry.questID or entry.questId
        objectiveIndex = entry.objectiveIndex or entry.objectiveID or entry.objectiveId
        if not questID and type(entry.questLogIndex) == "number"
            and C_QuestLog and type(C_QuestLog.GetQuestIDForLogIndex) == "function" then
            questID = C_QuestLog.GetQuestIDForLogIndex(entry.questLogIndex)
        end
    end

    if type(questID) ~= "number" then questID = nil end
    if type(objectiveIndex) ~= "number" then objectiveIndex = nil end
    return questID, objectiveIndex
end

local function SQOL_NameplateObjectives_ExtractProgress(questID, objectiveIndex, obj)
    local text = nil
    if type(obj) == "table" then
        text = rawget(obj, "text")

        local numItems = rawget(obj, "numItems")
        local numRequired = rawget(obj, "numRequired")
        local numFulfilled = rawget(obj, "numFulfilled")

        local required = (type(numRequired) == "number" and numRequired)
                      or (type(numItems) == "number" and numItems)
                      or 0

        if required > 0 then
            local fulfilled = (type(numFulfilled) == "number" and numFulfilled) or 0
            return fulfilled, required, text
        end

        local cur, total = SQOL_NameplateObjectives_ParseProgressFromText(text)
        if cur then
            return cur, total, text
        end
    end

    local info = SQOL_NameplateObjectives_GetObjectiveInfo(questID, objectiveIndex)
    if info then
        text = text or rawget(info, "text")

        local numItems = rawget(info, "numItems")
        local numRequired = rawget(info, "numRequired")
        local numFulfilled = rawget(info, "numFulfilled")

        local required = (type(numRequired) == "number" and numRequired)
                      or (type(numItems) == "number" and numItems)
                      or 0

        if required > 0 then
            local fulfilled = (type(numFulfilled) == "number" and numFulfilled) or 0
            return fulfilled, required, text
        end

        local cur, total = SQOL_NameplateObjectives_ParseProgressFromText(text)
        if cur then
            return cur, total, text
        end
    end

    return nil
end

local function SQOL_NameplateObjectives_SelectObjective(questID, unitName, npcId, objectiveIndex)
    if not questID then return nil end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then
        if objectiveIndex then
            local fulfilled, required, text = SQOL_NameplateObjectives_ExtractProgress(questID, objectiveIndex, nil)
            if required then
                return {
                    questID = questID,
                    fulfilled = fulfilled,
                    required = required,
                    text = text,
                    index = objectiveIndex,
                    priority = 3,
                }
            end
        end
        if SQOL.DB and SQOL.DB.DebugTrack then
            dprint("NP objectives missing for quest:", questID, "objectiveIndex:", tostring(objectiveIndex))
        end
        return nil
    end

    local best, bestPriority, bestRequired
    local numericCount = 0
    local singleCandidate = nil

    for i, obj in ipairs(objectives) do
        local fulfilled, required, text = SQOL_NameplateObjectives_ExtractProgress(questID, i, obj)
        if required then
            local candidate = {
                questID = questID,
                fulfilled = fulfilled,
                required = required,
                text = text,
                index = i,
                priority = nil,
            }

            numericCount = numericCount + 1
            singleCandidate = candidate

            local priority
            if objectiveIndex and i == objectiveIndex then
                priority = 3
            elseif npcId then
                local objId = rawget(obj, "objectID") or rawget(obj, "objectId")
                if type(objId) == "number" and objId == npcId then
                    priority = 2
                end
            end

            if not priority and unitName and type(candidate.text) == "string" then
                local textLower = candidate.text:lower()
                local nameLower = unitName:lower()
                if textLower:find(nameLower, 1, true) then
                    priority = 1
                end
            end

            if priority then
                candidate.priority = priority
                if not best or priority > bestPriority or (priority == bestPriority and required > (bestRequired or 0)) then
                    best = candidate
                    bestPriority = priority
                    bestRequired = required
                end
            end
        end
    end

    if best then
        return best
    end

    if numericCount == 1 and singleCandidate then
        singleCandidate.priority = 0
        return singleCandidate
    end

    return nil
end

local function SQOL_NameplateObjectives_GetProgressText(unit)
    local entries = SQOL_NameplateObjectives_GetQuestEntries(unit)
    if type(entries) ~= "table" then
        local cur, total, line, questTitle = SQOL_NameplateObjectives_GetTooltipProgress(unit)
        if cur then
            if SQOL.DB and SQOL.DB.DebugTrack then
                dprint("NP tooltip:", unit, "quest", tostring(questTitle), "line", tostring(line),
                    "progress", string.format("%d/%d", cur, total))
            end
            local text = string.format("%d/%d", cur, total)
            if SQOL.DB and SQOL.DB.ColorProgress then
                local progress = (total > 0) and (cur / total) or 0
                local colorCode = SQOL_GetProgressColor(progress)
                text = colorCode .. text .. "|r"
            end
            return text
        end
        if SQOL.DB and SQOL.DB.DebugTrack then
            dprint("NP tooltip:", unit, "no progress")
        end
        return nil
    end

    local unitName = UnitName(unit)
    local npcId = SQOL_NameplateObjectives_GetNpcID(unit)
    if SQOL.DB and SQOL.DB.DebugTrack then
        local count = 0
        local summaries = {}
        for _, entry in pairs(entries) do
            count = count + 1
            local questID, objectiveIndex = SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
            table.insert(summaries, string.format("%s:%s", tostring(questID), tostring(objectiveIndex or "-")))
        end
        dprint("NP unit:", unit, "name:", tostring(unitName), "npcID:", tostring(npcId), "entries:", count,
            count > 0 and table.concat(summaries, ", ") or "none")
    end

    local best, bestPriority, bestRequired
    for _, entry in pairs(entries) do
        local questID, objectiveIndex = SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
        if questID then
            local candidate = SQOL_NameplateObjectives_SelectObjective(questID, unitName, npcId, objectiveIndex)
            if candidate then
                local priority = candidate.priority or 0
                if not best or priority > bestPriority or (priority == bestPriority and candidate.required > (bestRequired or 0)) then
                    best = candidate
                    bestPriority = priority
                    bestRequired = candidate.required
                end
            end
        end
    end

    if best then
        if SQOL.DB and SQOL.DB.DebugTrack then
            dprint("NP chosen:", "quest", tostring(best.questID), "obj", tostring(best.index),
                "progress", string.format("%d/%d", best.fulfilled or 0, best.required or 0),
                "priority", tostring(bestPriority), "text", tostring(best.text))
        end
    else
        for _, entry in pairs(entries) do
            local questID = SQOL_NameplateObjectives_NormalizeQuestEntry(entry)
            if questID then
                local barCur, barTotal = SQOL_NameplateObjectives_GetProgressBarInfo(questID)
                if barCur then
                    if SQOL.DB and SQOL.DB.DebugTrack then
                        dprint("NP progress bar:", "quest", tostring(questID),
                            "progress", string.format("%d/%d", barCur, barTotal))
                    end
                    best = {
                        questID = questID,
                        fulfilled = barCur,
                        required = barTotal,
                        text = nil,
                        index = nil,
                        priority = -1,
                    }
                    break
                end
            end
        end
        if not best and SQOL.DB and SQOL.DB.DebugTrack then
            dprint("NP no objective progress found for unit:", unit)
        end
    end

    if not best then
        local cur, total, line, questTitle = SQOL_NameplateObjectives_GetTooltipProgress(unit)
        if cur then
            if SQOL.DB and SQOL.DB.DebugTrack then
                dprint("NP tooltip:", unit, "quest", tostring(questTitle), "line", tostring(line),
                    "progress", string.format("%d/%d", cur, total))
            end
            best = {
                questID = nil,
                fulfilled = cur,
                required = total,
                text = line,
                index = nil,
                priority = -2,
            }
        else
            if SQOL.DB and SQOL.DB.DebugTrack then
                dprint("NP tooltip:", unit, "no progress")
            end
            return nil
        end
    end

    if type(best.required) == "number" and type(best.fulfilled) == "number" and best.required > 0 then
        if best.fulfilled >= best.required then
            return nil
        end
    end

    local text = string.format("%d/%d", best.fulfilled or 0, best.required or 0)
    if SQOL.DB and SQOL.DB.ColorProgress then
        local progress = (best.required and best.required > 0) and (best.fulfilled / best.required) or 0
        local colorCode = SQOL_GetProgressColor(progress)
        text = colorCode .. text .. "|r"
    end
    return text
end

local function SQOL_NameplateObjectives_GetUnitToken(nameplate)
    if not nameplate then
        return nil
    end

    local unit = rawget(nameplate, "namePlateUnitToken")
    if unit then
        return unit
    end

    local unitFrame = nameplate.UnitFrame or nameplate.unitFrame
    unit = unitFrame and unitFrame.unit
    return unit
end

local function SQOL_NameplateObjectives_GetAnchor(nameplate)
    if not nameplate then
        return nil
    end

    local unitFrame = nameplate.UnitFrame or nameplate.unitFrame or nameplate
    if not unitFrame then
        return nameplate
    end

    local nameText = rawget(unitFrame, "name")
        or rawget(unitFrame, "Name")
        or rawget(unitFrame, "nameText")
        or rawget(unitFrame, "NameText")
        or rawget(unitFrame, "nameplateName")
        or rawget(unitFrame, "NamePlateName")
        or rawget(unitFrame, "UnitName")
        or rawget(unitFrame, "NameLabel")
        or rawget(unitFrame, "nameLabel")

    if nameText and nameText.GetStringWidth then
        return nameText
    end

    local healthBar = rawget(unitFrame, "healthBar")
        or rawget(unitFrame, "HealthBar")
        or rawget(unitFrame, "HealthBarsContainer")
    return healthBar or unitFrame
end

local function SQOL_NameplateObjectives_GetText(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then
        return nil
    end

    local text = nameplate.SQOLObjectiveText
    if not text then
---@diagnostic disable-next-line: undefined-field
        local unitFrame = nameplate.UnitFrame or nameplate.unitFrame or nameplate
        local anchor = SQOL_NameplateObjectives_GetAnchor(nameplate) or unitFrame

        text = unitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
        text:SetJustifyH("CENTER")
        text:SetWordWrap(false)
        if text.SetMaxLines then text:SetMaxLines(1) end
---@diagnostic disable-next-line: inject-field
        nameplate.SQOLObjectiveText = text
    else
---@diagnostic disable-next-line: undefined-field
        local unitFrame = nameplate.UnitFrame or nameplate.unitFrame or nameplate
        local anchor = SQOL_NameplateObjectives_GetAnchor(nameplate) or unitFrame
        text:ClearAllPoints()
        text:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    end

    return text, nameplate
end

local function SQOL_NameplateObjectives_UpdateUnit(unit)
    if not SQOL.DB or not SQOL.DB.ShowNameplateObjectives then
        return
    end
    if not unit or not UnitExists(unit) then
        return
    end

    local text, nameplate = SQOL_NameplateObjectives_GetText(unit)
    if not text then
        return
    end

    local progressText = SQOL_NameplateObjectives_GetProgressText(unit)
    if progressText then
        text:SetText(progressText)
        text:Show()
    else
        text:SetText("")
        text:Hide()
    end

    SQOL._npUnits[unit] = nameplate
end

local function SQOL_NameplateObjectives_ClearUnit(unit)
    local nameplate = SQOL._npUnits[unit]
    if not nameplate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    end

    if nameplate and nameplate.SQOLObjectiveText then
        nameplate.SQOLObjectiveText:SetText("")
        nameplate.SQOLObjectiveText:Hide()
    end

    SQOL._npUnits[unit] = nil
end

local function SQOL_NameplateObjectives_UpdateAll()
    if not SQOL.DB or not SQOL.DB.ShowNameplateObjectives then
        return
    end

    for unit in pairs(SQOL._npUnits) do
        SQOL_NameplateObjectives_UpdateUnit(unit)
    end
end

local function SQOL_NameplateObjectives_ScheduleUpdateAll()
    if SQOL._npUpdatePending then return end
    SQOL._npUpdatePending = true

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.2, function()
            SQOL._npUpdatePending = false
            SQOL_NameplateObjectives_UpdateAll()
        end)
    else
        SQOL._npUpdatePending = false
        SQOL_NameplateObjectives_UpdateAll()
    end
end

local function SQOL_NameplateObjectives_RefreshVisibleUnits()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return
    end

    for unit in pairs(SQOL._npUnits) do
        SQOL._npUnits[unit] = nil
    end

    local plates = C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then
        return
    end

    for _, nameplate in ipairs(plates) do
        local unit = SQOL_NameplateObjectives_GetUnitToken(nameplate)
        if unit then
            SQOL._npUnits[unit] = nameplate
            SQOL_NameplateObjectives_UpdateUnit(unit)
        end
    end
end

local function SQOL_NameplateObjectives_HideAll()
    for unit, nameplate in pairs(SQOL._npUnits) do
        if nameplate and nameplate.SQOLObjectiveText then
            nameplate.SQOLObjectiveText:SetText("")
            nameplate.SQOLObjectiveText:Hide()
        end
        SQOL._npUnits[unit] = nil
    end
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
        SQOL.iLvlHolder:SetFrameStrata("MEDIUM")
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
---@diagnostic disable-next-line: undefined-field
                    or data.earnedValue
---@diagnostic disable-next-line: undefined-field
                    or data.barValue
---@diagnostic disable-next-line: undefined-field
                    or data.currentValue
---@diagnostic disable-next-line: undefined-field
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
    local version, atState, spState, coState, loState, repState, statsState, npState, dmgState, cursorState = SQOL_GetStateStrings()
    print("|cff33ff99-----------------------------------|r")
    print("|cff33ff99" .. (SQOL.ADDON_NAME or "SMoRGsQoL") .. " (SQOL)|r |cffffffffv" .. version .. "|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
    print("|cff33ff99AutoTrack:|r " .. atState)
    print("|cff33ff99Splash:|r " .. spState)
    print("|cff33ff99ColorProgress:|r " .. coState)
    print("|cff33ff99HideDoneAchievements:|r " .. loState)
    print("|cff33ff99RepWatch:|r " .. repState)
    print("|cff33ff99NameplateObjectives:|r " .. npState)
    print("|cff33ff99StatsLine:|r " .. statsState)
    print("|cff33ff99DamageTextFont:|r " .. dmgState)
    print("|cff33ff99CursorShake:|r " .. cursorState)
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
    local version, atState, spState, coState, loState, repState, statsState, npState, dmgState, cursorState = SQOL_GetStateStrings()
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
    print("|cff00ff00/SQOL nameplate|r   |cffcccccc- Toggle nameplate objective counts|r")
    print("|cff00ff00/SQOL np|r          |cffcccccc- Shorthand for nameplate|r")
    print("|cff00ff00/SQOL stats|r       |cffcccccc- Toggle PlayerFrame iLvl+Spd line|r")
    print("|cff00ff00/SQOL ilvl|r        |cffcccccc- Shorthand for stats|r")
    print("|cff00ff00/SQOL damagefont|r  |cffcccccc- Toggle custom damage text font|r")
    print("|cff00ff00/SQOL df|r          |cffcccccc- Shorthand for damagefont|r")
    print("|cff00ff00/SQOL cursor|r      |cffcccccc- Highlight cursor when you shake the mouse|r")
    print("|cff00ff00/SQOL cs|r          |cffcccccc- Shorthand for cursor|r")
    print("|cff00ff00/SQOL cursorflash|r |cffcccccc- Flash cursor ring once (debug)|r")
    print("|cff00ff00/SQOL cf|r          |cffcccccc- Shorthand for cursorflash|r")
    print("|cff00ff00/SQOL debugtrack|r  |cffcccccc- Toggle verbose tracking debug|r")
    print("|cff00ff00/SQOL dbg|r         |cffcccccc- Shorthand for debugtrack|r")
    print("|cff00ff00/SQOL reset|r       |cffcccccc- Reset all settings to defaults|r")
    print("|cff33ff99------------------------------------------------------------------------------|r")
    print("|cff33ff99AutoTrack:|r " .. atState .. "  |cff33ff99Splash:|r " .. spState .. "  |cff33ff99ColorProgress:|r " .. coState .. "  |cff33ff99HideDoneAchievements:|r " .. loState)
    print("|cff33ff99RepWatch:|r " .. repState .. "  |cff33ff99NameplateObjectives:|r " .. npState .. "  |cff33ff99StatsLine:|r " .. statsState)
    print("|cff33ff99DamageTextFont:|r " .. dmgState .. "  |cff33ff99CursorShake:|r " .. cursorState)
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

    elseif key == "ShowNameplateObjectives" then
        if SQOL.DB.ShowNameplateObjectives then
            SQOL_NameplateObjectives_RefreshVisibleUnits()
        else
            SQOL_NameplateObjectives_HideAll()
        end

    elseif key == "ShowIlvlSpd" then
        if SQOL.DB.ShowIlvlSpd then
            SQOL_TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

    elseif key == "DamageTextFont" then
        if SQOL.DB.DamageTextFont then
            SQOL_ApplyDamageTextFont()
        else
            SQOL_RestoreDamageTextFont()
        end

    elseif key == "CursorShakeHighlight" then
        if SQOL.DB.CursorShakeHighlight then
            SQOL_CursorShake_Enable()
        else
            SQOL_CursorShake_Disable()
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

    elseif msg == "nameplate" or msg == "np" then
        toggle("ShowNameplateObjectives", "Nameplate objectives are")

    elseif msg == "stats" or msg == "ilvl" then
        toggle("ShowIlvlSpd", "PlayerFrame iLvl+Spd line is")

    elseif msg == "damagefont" or msg == "df" then
        toggle("DamageTextFont", "Damage text font is")

    elseif msg == "cursor" or msg == "cs" then
        toggle("CursorShakeHighlight", "Cursor shake highlight is")

    elseif msg == "cursorflash" or msg == "cf" then
        SQOL_CursorShake_FlashNow(0.8)

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
        local version, at, sp, co, lo, rep, stats, np, dmg, cursor = SQOL_GetStateStrings()
        print("|cff33ff99SQoL|r v" .. version .. " - AutoTrackQuests:" .. at .. " Splash:" .. sp .. " ColorProgress:" .. co .. " HideDoneAchievements:" .. lo .. " RepWatch:" .. rep .. " NameplateObjectives:" .. np .. " StatsLine:" .. stats .. " DamageTextFont:" .. dmg .. " CursorShake:" .. cursor)
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
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

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

        if SQOL.DB.DamageTextFont then
            SQOL_ApplyDamageTextFont()
        end

        if SQOL.DB.CursorShakeHighlight then
            SQOL_CursorShake_Enable()
        else
            SQOL_CursorShake_Disable()
        end

        -- Ensure PlayerFrame iLvl display.
        if SQOL.DB.ShowIlvlSpd then
            SQOL_TryEnsurePlayerFrameIlvlUI(0)
        else
            if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        end

        if SQOL.DB.ShowNameplateObjectives then
            SQOL_NameplateObjectives_RefreshVisibleUnits()
        else
            SQOL_NameplateObjectives_HideAll()
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

        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            SQOL_NameplateObjectives_RefreshVisibleUnits()
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

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            local unit = ...
            SQOL_NameplateObjectives_UpdateUnit(unit)
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        SQOL_NameplateObjectives_ClearUnit(unit)

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
        if SQOL.DB and SQOL.DB.ShowNameplateObjectives then
            SQOL_NameplateObjectives_ScheduleUpdateAll()
        end
    end
end)
