local ADDON_NAME, SQOL = ...
local L = SQOL.L

------------------------------------------------------------
-- Damage text font
------------------------------------------------------------
local SQOL_DAMAGE_TEXT_FONT = "Interface\\AddOns\\SMoRGsQoL\\Media\\trashhand.ttf"
local defaultDamageFont = "Fonts\\FRIZQT__.TTF"

function SQOL.ApplyDamageTextFont()
    SQOL.dprint("Set new damage font")
    DAMAGE_TEXT_FONT = SQOL_DAMAGE_TEXT_FONT
end

function SQOL.RestoreDamageTextFont()
    SQOL.dprint("Restore damage font")
    DAMAGE_TEXT_FONT = defaultDamageFont
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
                SQOL.dprint("CursorShake: GetCursorPosition returned nil.")
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
            and SQOL.clamp01(self._flashTime / self._flashDuration)
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
            -- SQOL.dprint(string.format(
            --     "CursorShake: samples=%d total=%.1f net=%.1f speed=%.0f dirX=%d dirY=%d cooldown=%.2f flash=%.2f",
            --     #samples, total, net, maxSpeed, dirChangesX, dirChangesY, self._cooldown or 0, self._flashTime or 0
            -- ))
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
                SQOL.dprint(string.format(
                    "CursorShake: TRIGGER total=%.1f net=%.1f speed=%.0f dirX=%d dirY=%d",
                    total, net, maxSpeed, dirChangesX, dirChangesY
                ))
            end
        end
    end
end

function SQOL.CursorShake_Enable()
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

function SQOL.CursorShake_Disable()
    if not SQOL.CursorShakeFrame then return end
    SQOL.CursorShakeFrame:SetScript("OnUpdate", nil)
    SQOL_CursorShake_ResetState(SQOL.CursorShakeFrame)
end

function SQOL.CursorShake_FlashNow(duration)
    if not SQOL.DB or not SQOL.DB.CursorShakeHighlight then
        SQOL.PrintOptionOff("CursorShakeHighlight", "/sqol cursor")
        return
    end

    SQOL.CursorShake_Enable()
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
        SQOL.dprint("CursorShake: manual flash.")
    end
end

------------------------------------------------------------
-- Apply the achievement filter according to saved setting
------------------------------------------------------------
-- WoW Forever replaces achievements with the Legacy system, so the
-- achievement filter only exists on clients that ship Blizzard_AchievementUI.
-- Classic Era and TBC ship it too, but achievements arrived with Wrath.
function SQOL.IsAchievementFilterSupported()
    if SQOL.IsForever or SQOL.IsClassicEra or SQOL.IsClassicTBC then return false end
    if not C_AddOns then return false end
    if type(C_AddOns.DoesAddOnExist) == "function" then
        return C_AddOns.DoesAddOnExist("Blizzard_AchievementUI") and true or false
    end
    if type(C_AddOns.GetAddOnInfo) == "function" then
        local reason = select(5, C_AddOns.GetAddOnInfo("Blizzard_AchievementUI"))
        return reason ~= "MISSING"
    end
    return true
end

-- Load Blizzard_AchievementUI on demand; returns true when it is loaded.
function SQOL.EnsureAchievementUILoaded()
    if not SQOL.IsAchievementFilterSupported() then return false end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AchievementUI")
    end
    return C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") and true or false
end

function SQOL.ApplyAchievementFilter()
    if not SQOL.DB then return end
    if not SQOL.IsAchievementFilterSupported() then return end
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
-- Unit tooltip: show who the unit is targeting
------------------------------------------------------------
local SQOL_TOOLTIP_TARGET_LABEL = "|cffffd100" .. L["Target:"] .. "|r "
local SQOL_TOOLTIP_TARGET_NONE = "|cff808080" .. L["none"] .. "|r"
local SQOL_TOOLTIP_TARGET_REFRESH = 0.2

-- The unit and line currently showing a target on GameTooltip.
local tooltipTarget = { unit = nil, line = nil, text = nil, elapsed = 0 }

local function SQOL_ColorCode(color)
    return string.format("|cff%02x%02x%02x",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
end

-- Class color for players, reaction color for NPCs; nil when unknown or secret.
local function SQOL_UnitColor(unit)
    local isPlayer = UnitIsPlayer(unit)
    if SQOL.CanUseValue(isPlayer) and isPlayer then
        local _, classFile = UnitClass(unit)
        if SQOL.CanUseValue(classFile) and classFile and RAID_CLASS_COLORS then
            return RAID_CLASS_COLORS[classFile]
        end
    else
        local reaction = UnitReaction(unit, "player")
        if SQOL.CanUseValue(reaction) and reaction and FACTION_BAR_COLORS then
            return FACTION_BAR_COLORS[reaction]
        end
    end
    return nil
end

local function SQOL_TooltipTarget_ColorCode(targetUnit)
    local color = SQOL_UnitColor(targetUnit)
    return color and SQOL_ColorCode(color) or "|cffffffff"
end

-- Returns the colored target name, "You", or nil when the unit has no target.
-- Unit data can be secret in 12.x (e.g. in instances); such values are skipped.
function SQOL.TooltipTarget_GetText(unit)
    if type(unit) ~= "string" or not SQOL.CanUseValue(unit) then return nil end

    local targetUnit = unit .. "target"
    local exists = UnitExists(targetUnit)
    if not SQOL.CanUseValue(exists) or not exists then return nil end

    local isYou = UnitIsUnit(targetUnit, "player")
    if SQOL.CanUseValue(isYou) and isYou then
        return "|cffff4040" .. (YOU or "You") .. "|r"
    end

    local name = UnitName(targetUnit)
    if not SQOL.CanUseValue(name) or type(name) ~= "string" or name == "" then return nil end
    return SQOL_TooltipTarget_ColorCode(targetUnit) .. name .. "|r"
end

local function SQOL_TooltipTarget_SafeGetText(unit)
    local ok, text = pcall(SQOL.TooltipTarget_GetText, unit)
    return ok and text or nil
end

local function SQOL_TooltipTarget_Reset()
    tooltipTarget.unit, tooltipTarget.line, tooltipTarget.text = nil, nil, nil
end

-- Runs just before Blizzard shows the unit tooltip, so the added line is sized in.
local function SQOL_TooltipTarget_OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not (SQOL.DB and SQOL.DB.ShowTooltipTarget) then return end

    SQOL_TooltipTarget_Reset()
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or type(unit) ~= "string" or not SQOL.CanUseValue(unit) then return end

    tooltipTarget.unit = unit
    tooltipTarget.text = SQOL_TooltipTarget_SafeGetText(unit)
    if tooltipTarget.text then
        tooltip:AddLine(SQOL_TOOLTIP_TARGET_LABEL .. tooltipTarget.text)
        tooltipTarget.line = tooltip:NumLines()
    end
end

-- Blizzard doesn't rebuild the tooltip when the hovered unit changes target,
-- so poll a few times per second while it is shown.
local function SQOL_TooltipTarget_OnUpdate(tooltip, elapsed)
    if not tooltipTarget.unit or not (SQOL.DB and SQOL.DB.ShowTooltipTarget) then return end
    tooltipTarget.elapsed = tooltipTarget.elapsed + (elapsed or 0)
    if tooltipTarget.elapsed < SQOL_TOOLTIP_TARGET_REFRESH then return end
    tooltipTarget.elapsed = 0

    -- The mouseover unit is gone while the tooltip fades out; keep the last target.
    local exists = UnitExists(tooltipTarget.unit)
    if not SQOL.CanUseValue(exists) or not exists then return end

    local text = SQOL_TooltipTarget_SafeGetText(tooltipTarget.unit)
    if text == tooltipTarget.text then return end
    tooltipTarget.text = text

    if tooltipTarget.line then
        local fontString = _G["GameTooltipTextLeft" .. tooltipTarget.line]
        if not fontString then return end
        fontString:SetText(SQOL_TOOLTIP_TARGET_LABEL .. (text or SQOL_TOOLTIP_TARGET_NONE))
    elseif text then
        tooltip:AddLine(SQOL_TOOLTIP_TARGET_LABEL .. text)
        tooltipTarget.line = tooltip:NumLines()
    end
    -- Resize for the new text.
    tooltip:Show()
end

------------------------------------------------------------
-- Unit tooltip: class, reaction, guild, level and faction colors
------------------------------------------------------------
local SQOL_TOOLTIP_GUILD_COLOR = { r = 0.25, g = 1, b = 0.25 }
local SQOL_TOOLTIP_BOSS_LEVEL_COLOR = { r = 1, g = 0.1, b = 0.1 }
local SQOL_TOOLTIP_TAPPED_COLOR = { r = 0.6, g = 0.6, b = 0.6 }
local SQOL_TOOLTIP_HEALTH_COLOR = { r = 0, g = 1, b = 0 }
local SQOL_TOOLTIP_FACTION_COLORS = {
    Horde = { r = 1, g = 0.3, b = 0.25 },
    Alliance = { r = 0.35, g = 0.6, b = 1 },
}

-- The color on GameTooltip's border and health bar while a styled unit is shown.
-- The unit whose health the bar text shows.
local tooltipStyle = { color = nil, unit = nil, healthText = nil }

local function SQOL_TooltipStyle_GetLine(index)
    local fontString = _G["GameTooltipTextLeft" .. index]
    if not fontString then return nil, nil end
    local text = fontString:GetText()
    if not SQOL.CanUseValue(text) or type(text) ~= "string" or text == "" then
        return fontString, nil
    end
    return fontString, text
end

local function SQOL_TooltipStyle_UnitColor(unit)
    local isPlayer = UnitIsPlayer(unit)
    if not (SQOL.CanUseValue(isPlayer) and isPlayer) and type(UnitIsTapDenied) == "function" then
        local tapped = UnitIsTapDenied(unit)
        if SQOL.CanUseValue(tapped) and tapped then return SQOL_TOOLTIP_TAPPED_COLOR end
    end
    return SQOL_UnitColor(unit)
end

-- Blizzard's difficulty color for the level, as on the target frame.
local function SQOL_TooltipStyle_LevelColor(unit, level)
    if level == -1 then return SQOL_TOOLTIP_BOSS_LEVEL_COLOR end
    if C_PlayerInfo and type(C_PlayerInfo.GetContentDifficultyCreatureForPlayer) == "function"
        and type(GetDifficultyColor) == "function" then
        local difficulty = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit)
        if SQOL.CanUseValue(difficulty) and difficulty then
            local color = GetDifficultyColor(difficulty)
            if color then return color end
        end
    end
    local getColor = rawget(_G, "GetCreatureDifficultyColor") or rawget(_G, "GetQuestDifficultyColor")
    if type(getColor) == "function" then return getColor(level) end
    return nil
end

local function SQOL_TooltipStyle_Guild(numLines, unit)
    local guildName = GetGuildInfo(unit)
    if not SQOL.CanUseValue(guildName) or type(guildName) ~= "string" or guildName == "" then return nil end

    for i = 2, numLines do
        local fontString, text = SQOL_TooltipStyle_GetLine(i)
        local start = text and text:find(guildName, 1, true)
        if start == 1 or (start == 2 and text:sub(1, 1) == "<") then
            if start == 1 then
                fontString:SetText("<" .. text .. ">")
            end
            local c = SQOL_TOOLTIP_GUILD_COLOR
            fontString:SetTextColor(c.r, c.g, c.b)
            return i
        end
    end
    return nil
end

-- Colors the level number on the level line ("Level 90 Highmountain Tauren")
-- and returns that line. Prefers a line with the client's word for "Level".
local function SQOL_TooltipStyle_Level(numLines, unit, guildLine)
    local levels = {}
    local function addLevel(level)
        if SQOL.CanUseValue(level) and type(level) == "number" and (level > 0 or level == -1) then
            levels[#levels + 1] = level
        end
    end
    if type(UnitEffectiveLevel) == "function" then addLevel(UnitEffectiveLevel(unit)) end
    addLevel(UnitLevel(unit))
    if #levels == 0 then return nil end

    local label = type(LEVEL) == "string" and LEVEL ~= "" and LEVEL or nil
    for _, needLabel in ipairs({ true, false }) do
        for i = 2, numLines do
            local fontString, text = SQOL_TooltipStyle_GetLine(i)
            if text and i ~= guildLine and (not needLabel or (label and text:find(label, 1, true))) then
                for _, level in ipairs(levels) do
                    local shown = level == -1 and "??" or tostring(level)
                    local pattern = level == -1 and "%?%?" or ("%f[%w]" .. shown .. "%f[%W]")
                    if text:find(pattern) then
                        local color = SQOL_TooltipStyle_LevelColor(unit, level)
                        if color then
                            fontString:SetText((text:gsub(pattern, SQOL_ColorCode(color) .. shown .. "|r", 1)))
                        end
                        return i
                    end
                end
            end
        end
    end
    return nil
end

-- Retail's spec line ("Balance Druid") gets the class color; in Classic the
-- class sits on the level line ("Level 60 Tauren Druid"), so only the word does.
local function SQOL_TooltipStyle_Class(numLines, unit, color, guildLine, levelLine)
    local className = UnitClass(unit)
    if not SQOL.CanUseValue(className) or type(className) ~= "string" or className == "" then return end

    for i = 2, numLines do
        local fontString, text = SQOL_TooltipStyle_GetLine(i)
        local start, stop = nil, nil
        if text and i ~= guildLine then
            start, stop = text:find(className, 1, true)
        end
        if start then
            if i == levelLine then
                fontString:SetText(text:sub(1, start - 1) .. SQOL_ColorCode(color) .. className .. "|r" .. text:sub(stop + 1))
            else
                fontString:SetTextColor(color.r, color.g, color.b)
            end
            return
        end
    end
end

local function SQOL_TooltipStyle_Faction(numLines, unit)
    local faction, localized = UnitFactionGroup(unit)
    if not (SQOL.CanUseValue(faction) and SQOL.CanUseValue(localized)) then return end
    local color = SQOL_TOOLTIP_FACTION_COLORS[faction or ""]
    if not color or type(localized) ~= "string" then return end

    for i = numLines, 2, -1 do
        local fontString, text = SQOL_TooltipStyle_GetLine(i)
        if text == localized then
            fontString:SetTextColor(color.r, color.g, color.b)
            return
        end
    end
end

local function SQOL_TooltipStyle_SetBarColor(color)
    local bar = GameTooltip.StatusBar or rawget(_G, "GameTooltipStatusBar")
    if bar and bar.SetStatusBarColor then
        bar:SetStatusBarColor(color.r, color.g, color.b)
    end
end

local function SQOL_TooltipStyle_Abbreviate(value)
    local abbreviate = rawget(_G, "AbbreviateLargeNumbers") or rawget(_G, "BreakUpLargeNumbers") or tostring
    return abbreviate(value)
end

-- "18.8K / 23.8K (79%)". In 12.x other units' health can be secret: no math
-- on it then, but the client can still abbreviate and show the numbers.
function SQOL.TooltipStyle_GetHealthText(unit)
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if SQOL.CanUseValue(cur) and SQOL.CanUseValue(max) then
        if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
        return string.format("%s / %s (%d%%)", SQOL_TooltipStyle_Abbreviate(cur),
            SQOL_TooltipStyle_Abbreviate(max), math.floor(cur / max * 100 + 0.5))
    end
    local ok, text = pcall(function()
        return SQOL_TooltipStyle_Abbreviate(cur) .. " / " .. SQOL_TooltipStyle_Abbreviate(max)
    end)
    return ok and text or nil
end

local function SQOL_TooltipStyle_GetHealthFontString(bar)
    if not tooltipStyle.healthText then
        local text = bar:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(rawget(_G, "TextStatusBarText") or GameFontHighlightSmall)
        local font = text:GetFont()
        if font then text:SetFont(font, 10, "OUTLINE") end
        text:SetPoint("CENTER", bar, "CENTER", 0, 0)
        tooltipStyle.healthText = text
    end
    return tooltipStyle.healthText
end

local function SQOL_TooltipStyle_UpdateHealthText()
    local bar = GameTooltip.StatusBar or rawget(_G, "GameTooltipStatusBar")
    if not (bar and bar.CreateFontString) then return end
    local fontString = SQOL_TooltipStyle_GetHealthFontString(bar)

    -- The mouseover unit is gone while the tooltip fades out; keep the last value.
    local unit = tooltipStyle.unit
    local exists = unit and UnitExists(unit)
    if unit and not (SQOL.CanUseValue(exists) and exists) then return end

    local ok, text = pcall(SQOL.TooltipStyle_GetHealthText, unit)
    if unit and ok and text and pcall(fontString.SetText, fontString, text) then
        fontString:Show()
    else
        fontString:Hide()
    end
end

local function SQOL_TooltipStyle_SetBorderColor(tooltip, color)
    if tooltip.NineSlice and tooltip.NineSlice.SetBorderColor then
        tooltip.NineSlice:SetBorderColor(color.r, color.g, color.b)
    elseif tooltip.SetBackdropBorderColor then
        tooltip:SetBackdropBorderColor(color.r, color.g, color.b)
    end
end

function SQOL.TooltipStyle_Apply(tooltip, unit)
    local numLines = tooltip:NumLines()
    local color = SQOL_TooltipStyle_UnitColor(unit)
    local isPlayer = UnitIsPlayer(unit)
    isPlayer = SQOL.CanUseValue(isPlayer) and isPlayer

    local guildLine = isPlayer and SQOL_TooltipStyle_Guild(numLines, unit) or nil
    local levelLine = SQOL_TooltipStyle_Level(numLines, unit, guildLine)
    if isPlayer and color then
        local nameLine = SQOL_TooltipStyle_GetLine(1)
        if nameLine then nameLine:SetTextColor(color.r, color.g, color.b) end
        SQOL_TooltipStyle_Class(numLines, unit, color, guildLine, levelLine)
    end
    SQOL_TooltipStyle_Faction(numLines, unit)

    if color then
        tooltipStyle.color = color
        SQOL_TooltipStyle_SetBorderColor(tooltip, color)
        SQOL_TooltipStyle_SetBarColor(color)
    end
    tooltipStyle.unit = unit
    SQOL_TooltipStyle_UpdateHealthText()
end

-- Puts Blizzard's white border and plain green health bar back for the next tooltip.
local function SQOL_TooltipStyle_Reset()
    if tooltipStyle.unit then
        tooltipStyle.unit = nil
        SQOL_TooltipStyle_UpdateHealthText()
    end
    if not tooltipStyle.color then return end
    tooltipStyle.color = nil
    SQOL_TooltipStyle_SetBorderColor(GameTooltip, TOOLTIP_DEFAULT_COLOR or { r = 1, g = 1, b = 1 })
    SQOL_TooltipStyle_SetBarColor(SQOL_TOOLTIP_HEALTH_COLOR)
end

-- Blizzard recolors the health bar as the value changes; keep ours and the text.
local function SQOL_TooltipStyle_OnBarValueChanged()
    if tooltipStyle.color then
        SQOL_TooltipStyle_SetBarColor(tooltipStyle.color)
    end
    if tooltipStyle.unit then
        SQOL_TooltipStyle_UpdateHealthText()
    end
end

local function SQOL_TooltipStyle_OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not (SQOL.DB and SQOL.DB.ColorUnitTooltips) then return end

    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or type(unit) ~= "string" or not SQOL.CanUseValue(unit) then return end
    SQOL.safe_pcall(SQOL.TooltipStyle_Apply, tooltip, unit)
end

------------------------------------------------------------
-- Unit tooltip hooks
------------------------------------------------------------
local function SQOL_UnitTooltip_OnPostCall(tooltip)
    SQOL_TooltipStyle_OnUnitTooltip(tooltip)
    SQOL_TooltipTarget_OnUnitTooltip(tooltip)
end

local function SQOL_UnitTooltip_OnClear()
    SQOL_TooltipTarget_Reset()
    SQOL_TooltipStyle_Reset()
end

function SQOL.UnitTooltip_Init()
    if SQOL._unitTooltipHooked then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and GameTooltip and GameTooltip.HookScript) then
        return
    end
    SQOL._unitTooltipHooked = true

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, SQOL_UnitTooltip_OnPostCall)
    GameTooltip:HookScript("OnUpdate", SQOL_TooltipTarget_OnUpdate)
    GameTooltip:HookScript("OnTooltipCleared", SQOL_UnitTooltip_OnClear)
    GameTooltip:HookScript("OnHide", SQOL_UnitTooltip_OnClear)

    local bar = GameTooltip.StatusBar or rawget(_G, "GameTooltipStatusBar")
    if bar and bar.HookScript then
        bar:HookScript("OnValueChanged", SQOL_TooltipStyle_OnBarValueChanged)
    end
end

SQOL.UnitTooltip_Init()

