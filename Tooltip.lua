------------------------------------------------------------
-- SMoRGsQoL - TinyTooltip-inspired Unit Tooltip Tweaks
-- Retail v12+ only.
--
-- Features:
--   - Adds a text overlay to GameTooltipStatusBar showing:
--       Health / Max (Percent with 2 decimals)
--   - Colors the status bar automatically (class / reaction)
--   - Adds a "Target: >>NAME<<" line for units with a target
--
-- This module intentionally does NOT change tooltip anchoring/
-- placement. Blizzard's default tooltip positioning is preserved.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"
SQOL = SQOL or {}

-- Guard: Retail v12+ only.
local _, _, _, clientToc = GetBuildInfo()
local DEAD = DEAD
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end
if not clientToc or clientToc < 120000 then return end

-- Option toggle (Settings: TooltipTinyTooltip)
local function IsEnabled()
    if SQOL and SQOL.DB and SQOL.DB.TooltipTinyTooltip ~= nil then
        return SQOL.DB.TooltipTinyTooltip and true or false
    end
    if SQOL and SQOL.defaults and SQOL.defaults.TooltipTinyTooltip ~= nil then
        return SQOL.defaults.TooltipTinyTooltip and true or false
    end
    return true
end

function SQOL.TooltipTinyTooltip_SetEnabled(isEnabled)
    -- Do not mutate the DB here; SMoRGsQoL.SetOption already did that.
    local enabled = isEnabled and true or false

    -- Clear any state we keep on the status bar.
    if GameTooltipStatusBar then
        GameTooltipStatusBar.SQOL_unit = nil
        if GameTooltipStatusBar.TextString then
            GameTooltipStatusBar.TextString:Hide()
        end
    end

    -- Refresh currently visible tooltip to immediately apply/remove styling.
    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
        if GameTooltip.RefreshData then
            pcall(GameTooltip.RefreshData, GameTooltip)
        else
            -- Fallback: hide to clear modified lines.
            GameTooltip:Hide()
        end
    end
end

-- NOTE: Retail may return "secret" numeric-like values that error on arithmetic.
-- This helper only returns a plain Lua number when it is safe to do math on it.
local function ToSafeNumber(v)
    local ok, n = pcall(function()
        return v + 0
    end)
    if ok and type(n) == "number" then
        return n
    end
    return nil
end

local function GetTooltipUnit(tip)
    if not tip or not tip.GetUnit then return nil end
    local _, unit = tip:GetUnit()
    if unit then return unit end

    -- Fallback: emulate TinyTooltip's approach (Retail v12 has GetMouseFoci()).
    if type(GetMouseFoci) == "function" then
        local focus = GetMouseFoci()
        if focus and focus.unit then
            return focus.unit
        end
    end

    return "mouseover"
end

local function GetUnitColor(unit)
    if not unit then return 1, 1, 1 end

    if UnitIsPlayer(unit) then
        local classToken = select(2, UnitClass(unit))
        if classToken then
            if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken] then
                local c = CUSTOM_CLASS_COLORS[classToken]
                return c.r, c.g, c.b
            end
            local r, g, b = GetClassColor(classToken)
            if r and g and b then
                return r, g, b
            end
        end
        return 1, 1, 1
    end

    local r, g, b = GameTooltip_UnitColor(unit)
    -- TinyTooltip does a small tweak to make neutral mobs pop a bit more.
    if g == 0.6 then g = 0.9 end
    if r == 1 and g == 1 and b == 1 then
        r, g, b = 0, 0.9, 0.1
    end
    return r, g, b
end

local function TryGetHealthFromUnit(unit)
    -- IMPORTANT: In Retail, these may return "secret" values in some contexts.
    -- We only accept plain numbers.
    local okHp, hp = pcall(UnitHealth, unit)
    local okMax, maxhp = pcall(UnitHealthMax, unit)

    if okHp and okMax then
        hp = ToSafeNumber(hp)
        maxhp = ToSafeNumber(maxhp)
        if hp and maxhp and maxhp > 0 then
            return hp, maxhp
        end
    end

    return nil, nil
end

local function TryGetHealthPercent(unit)
    if type(UnitHealthPercent) ~= "function" then
        return nil
    end

    local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants and CurveConstants.ScaleTo100 or nil)
    if ok then
        pct = ToSafeNumber(pct)
        if pct then
            return pct
        end
    end

    return nil
end

local function TryGetHealthFromBar(bar)
    if not bar then return nil, nil end

    -- IMPORTANT: These may be "secret" too. Only accept numbers.
    local okV, value = pcall(bar.GetValue, bar)
    local okMM, minv, maxv = pcall(bar.GetMinMaxValues, bar)

    if okV and okMM then
        value = ToSafeNumber(value)
        maxv = ToSafeNumber(maxv)
        if value and maxv and maxv > 0 then
            local hp = math.floor(value + 0.5)
            local maxhp = math.floor(maxv + 0.5)
            return hp, maxhp
        end
    end

    return nil, nil
end

local function FormatHealthText(unit, bar)
    if unit and (UnitIsDeadOrGhost(unit) or UnitIsGhost(unit)) then
        -- We do not trust maxhp in all contexts; keep it simple.
        return string.format("<%s>", DEAD)
    end

    -- Prefer unit health when it's a plain number (best match to screenshot).
    local hp, maxhp = nil, nil
    if unit and UnitExists(unit) then
        hp, maxhp = TryGetHealthFromUnit(unit)
    end

    -- Fallback to bar values.
    if (not hp or not maxhp) and bar then
        hp, maxhp = TryGetHealthFromBar(bar)
    end

    if hp and maxhp and maxhp > 0 then
        local percent = (hp / maxhp) * 100
        return string.format("%d / %d (%.2f%%)", hp, maxhp, percent)
    end

    -- If everything is "secret" (often out of range), try percent-only.
    if unit and UnitExists(unit) then
        local pct = TryGetHealthPercent(unit)
        if pct then
            return string.format("?? / ?? (%.2f%%)", pct)
        end
    end

    return nil
end

local function EnsureStatusBarOverlay()
    local bar = GameTooltipStatusBar
    if not bar or bar.SQOL_TinyTooltipInit then return end
    bar.SQOL_TinyTooltipInit = true

    -- Mimic TinyTooltip's behavior; helps avoid some Blizzard quirks.
    bar.capNumericDisplay = true
    bar.lockShow = 1

    -- Background (subtle).
    if not bar.bg then
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(1, 1, 1)
        bar.bg:SetVertexColor(0.2, 0.2, 0.2, 0.2)
    end

    -- Text overlay.
    if not bar.TextString then
        bar.TextString = bar:CreateFontString(nil, "OVERLAY")
        bar.TextString:SetPoint("CENTER")
        bar.TextString:SetFont(NumberFontNormal:GetFont(), 11, "THINOUTLINE")
    end

    local function Refresh(self)
        if not IsEnabled() then
            if self.TextString then
                self.TextString:Hide()
            end
            return
        end

        local unit = self.SQOL_unit
        if not unit or not UnitExists(unit) then
            if self.TextString then
                self.TextString:Hide()
            end
            return
        end

        local r, g, b = GetUnitColor(unit)
        self:SetStatusBarColor(r, g, b)

        if self.TextString then
            local text = FormatHealthText(unit, self)
            if text then
                self.TextString:SetText(text)
                self.TextString:Show()
            else
                self.TextString:Hide()
            end
        end
    end

    bar:HookScript("OnShow", Refresh)
    bar:HookScript("OnValueChanged", Refresh)
    bar:HookScript("OnHide", function(self)
        if self.TextString then
            self.TextString:Hide()
        end
    end)
end

local function AddOrUpdateTargetLine(tip, unit)
    if not tip or not unit or not UnitExists(unit) then return end

    local targetUnit = unit .. "target"
    if not UnitExists(targetUnit) then return end

    local targetName = UnitName(targetUnit)
    if not targetName then return end

    local displayName = targetName
    if UnitIsUnit(targetUnit, "player") then
        displayName = "YOU"
    end

    local r, g, b = GetUnitColor(targetUnit)
    local lineText = string.format("Target: >>%s<<", displayName)

    -- Avoid duplicates if the callback fires more than once.
    local numLines = tip:NumLines() or 0
    for i = 1, numLines do
        local fs = _G[tip:GetName() .. "TextLeft" .. i]
        if fs then
            local txt = fs:GetText()
            if txt and txt:find("^Target:") then
                fs:SetText(lineText)
                fs:SetTextColor(r, g, b)
                return
            end
        end
    end

    tip:AddLine(lineText, r, g, b)
end

local function RGBToHex(r, g, b)
    r = math.max(0, math.min(1, r or 1))
    g = math.max(0, math.min(1, g or 1))
    b = math.max(0, math.min(1, b or 1))
    return string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    )
end

local function Colorize(text, r, g, b)
    if not text or text == "" then
        return ""
    end
    return string.format("|cff%s%s|r", RGBToHex(r, g, b), text)
end

local function StylePlayerTooltip(tip, unit)
    if not tip or not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end

    local tipName = tip:GetName()
    if not tipName then return end

    -- Line 1: Name (with title) + realm, colored by class.
    local name, realm = UnitName(unit)
    local pvpName = UnitPVPName(unit)
    local displayName = (pvpName and pvpName ~= "") and pvpName or name
    if realm and realm ~= "" then
        displayName = string.format("%s %s", displayName, realm)
    end

    local rClass, gClass, bClass = GetUnitColor(unit)
    local line1 = _G[tipName .. "TextLeft1"]
    if line1 then
        line1:SetText(displayName or (name or ""))
        line1:SetTextColor(rClass, gClass, bClass)
    end

    -- Line 2: Guild + rank (if any), magenta + grey.
    local guildName, guildRank = GetGuildInfo(unit)
    local levelLineIndex = 2
    if guildName and guildName ~= "" then
        local guildText = string.format("%s %s", Colorize("<" .. guildName .. ">", 1, 0, 1), Colorize("(" .. (guildRank or "") .. ")", 0.75, 0.75, 0.75))
        local line2 = _G[tipName .. "TextLeft2"]
        if line2 then
            line2:SetText(guildText)
            line2:SetTextColor(1, 1, 1)
        end
        levelLineIndex = 3
    end

    -- Level line: "80 Alliance Night Elf Druid" with colors similar to TinyTooltip.
    local level = UnitLevel(unit)
    local levelText = (level and level > 0) and tostring(level) or "??"
    local diffColor = (level and level > 0) and GetQuestDifficultyColor(level) or { r = 1, g = 1, b = 0 }
    local levelColored = Colorize(levelText, diffColor.r, diffColor.g, diffColor.b)

    local factionGroup, factionName = UnitFactionGroup(unit)
    local fR, fG, fB = 1, 1, 1
    if factionGroup == "Alliance" then
        fR, fG, fB = 0.35, 0.55, 1
    elseif factionGroup == "Horde" then
        fR, fG, fB = 1, 0.25, 0.25
    end
    local factionColored = factionName and factionName ~= "" and Colorize(factionName, fR, fG, fB) or ""

    local raceName = select(1, UnitRace(unit))
    local _, classToken = UnitClass(unit)
    local className = select(1, UnitClass(unit))
    local cR, cG, cB = rClass, gClass, bClass
    if classToken then
        if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken] then
            local c = CUSTOM_CLASS_COLORS[classToken]
            cR, cG, cB = c.r, c.g, c.b
        else
            local rr, gg, bb = GetClassColor(classToken)
            if rr and gg and bb then
                cR, cG, cB = rr, gg, bb
            end
        end
    end
    local classColored = className and className ~= "" and Colorize(className, cR, cG, cB) or ""

    local parts = {}
    if levelColored ~= "" then table.insert(parts, levelColored) end
    if factionColored ~= "" then table.insert(parts, factionColored) end
    if raceName and raceName ~= "" then table.insert(parts, raceName) end
    if classColored ~= "" then table.insert(parts, classColored) end
    local finalLevelLine = table.concat(parts, " ")

    local levelLine = _G[tipName .. "TextLeft" .. levelLineIndex]
    if levelLine then
        levelLine:SetText(finalLevelLine)
        levelLine:SetTextColor(1, 1, 1)
    end
end

-- Init
EnsureStatusBarOverlay()

local function OnUnitTooltip(tip)
    if not IsEnabled() then
        -- Ensure we do not leave stale UI behind.
        if GameTooltipStatusBar then
            GameTooltipStatusBar.SQOL_unit = nil
            if GameTooltipStatusBar.TextString then
                GameTooltipStatusBar.TextString:Hide()
            end
        end
        return
    end

    EnsureStatusBarOverlay()

    local unit = GetTooltipUnit(tip)
    if unit and UnitExists(unit) and UnitIsPlayer(unit) then
        StylePlayerTooltip(tip, unit)
    end

    -- Only bind statusbar updates to actual unit tooltips.
    if GameTooltipStatusBar then
        if unit and UnitExists(unit) then
            GameTooltipStatusBar.SQOL_unit = unit
        else
            GameTooltipStatusBar.SQOL_unit = nil
            if GameTooltipStatusBar.TextString then
                GameTooltipStatusBar.TextString:Hide()
            end
        end
    end

    AddOrUpdateTargetLine(tip, unit)

    -- Refresh immediately.
    if GameTooltipStatusBar and GameTooltipStatusBar.TextString and unit and UnitExists(unit) then
        local text = FormatHealthText(unit, GameTooltipStatusBar)
        if text then
            GameTooltipStatusBar.TextString:SetText(text)
            GameTooltipStatusBar.TextString:Show()
        else
            GameTooltipStatusBar.TextString:Hide()
        end
    end
end

local function RegisterUnitTooltipHook()
    -- Retail tooltip system (v10+): preferred way.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then

        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            -- We only modify the main GameTooltip to keep behavior predictable.
            if tooltip == GameTooltip then
                OnUnitTooltip(tooltip)
            end
        end)
        return
    end

    -- Fallback for older/edge environments.
    if GameTooltip and GameTooltip.HookScript and GameTooltip.HasScript
        and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
    end
end

RegisterUnitTooltipHook()

GameTooltip:HookScript("OnTooltipCleared", function()
    if GameTooltipStatusBar then
        GameTooltipStatusBar.SQOL_unit = nil
        if GameTooltipStatusBar.TextString then
            GameTooltipStatusBar.TextString:Hide()
        end
    end
end)