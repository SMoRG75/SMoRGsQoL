------------------------------------------------------------
-- SMoRGsQoL - Range icon and distance for the target
-- On the target's nameplate (where Blizzard's soft target sword icon sits),
-- or by the target frame without a nameplate, shows the distance to an
-- attackable target as a range in yards (e.g. "8-30 yd"), plus an icon when
-- none of the offensive abilities on your action bars can reach it ("> 40 yd").
-- Uses C_ActionBar.IsActionInRange, the check Blizzard uses to tint action
-- buttons red, so it needs no per-class spell lists and handles forms and
-- bonus bars through the visible action buttons. The client has no exact
-- distance API for enemies; the yards come from the max range of the
-- abilities that do and don't reach.
-- While enabled, Blizzard's soft target sword icon (SoftTargetIconEnemy) is
-- turned off so the two aren't confused, and restored when disabled.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...

local ICON_TEXTURE = "Interface\\AddOns\\SMoRGsQoL\\Media\\range.png"
local ICON_SIZE = 24
local UPDATE_INTERVAL = 0.15
local MAX_ACTION_SLOT = 180
local MELEE_RANGE = 5              -- melee abilities report a max range of 0
local SOFT_TARGET_ICON_CVAR = "SoftTargetIconEnemy"

local indicator            -- holder frame with .Icon and .Text, created on first use
local updater              -- drives polling while there is a target
local elapsedSinceUpdate = 0

------------------------------------------------------------
-- Range state
------------------------------------------------------------
local function SQOL_Range_IsTrue(value)
    return SQOL.CanUseValue(value) and value and true or false
end

local function SQOL_Range_HasAttackableTarget()
    return SQOL_Range_IsTrue(UnitExists("target"))
        and SQOL_Range_IsTrue(UnitCanAttack("player", "target"))
        and not SQOL_Range_IsTrue(UnitIsDeadOrGhost("target"))
end

local function SQOL_Range_HasAction(slot)
    return type(slot) == "number" and slot > 0 and SQOL_Range_IsTrue(HasAction(slot))
end

-- Calls func(slot) for the actions on the visible Blizzard action buttons,
-- or for every action slot when another bar addon replaces them.
local function SQOL_Range_ForEachAction(func)
    local eventsFrame = rawget(_G, "ActionBarButtonEventsFrame")
    local buttons = type(eventsFrame) == "table" and eventsFrame.frames
    local sawButton = false

    if type(buttons) == "table" then
        for _, button in pairs(buttons) do
            if type(button) == "table" and button.IsVisible and button:IsVisible() then
                local slot = button.action
                if SQOL_Range_HasAction(slot) then
                    sawButton = true
                    func(slot)
                end
            end
        end
    end

    if not sawButton then
        for slot = 1, MAX_ACTION_SLOT do
            if SQOL_Range_HasAction(slot) then
                func(slot)
            end
        end
    end
end

-- Returns the spell ID when the action is a spell (or spell macro) that can be
-- cast on hostile targets. Self and pet spells such as Play Dead or Mend Pet
-- report "in range" for any target, so they don't count. Items, flyouts and
-- item macros are skipped.
local function SQOL_Range_GetOffensiveSpell(slot)
    local actionType, id, subType = GetActionInfo(slot)
    local spellID
    if actionType == "spell" then
        spellID = id
    elseif actionType == "macro" and subType == "spell" then
        spellID = id
    end
    if type(spellID) ~= "number" or not SQOL.CanUseValue(spellID) then
        return nil
    end

    local isHarmful = C_Spell and C_Spell.IsSpellHarmful
    if type(isHarmful) ~= "function" then
        return spellID
    end
    local ok, harmful = pcall(isHarmful, spellID)
    return (ok and SQOL_Range_IsTrue(harmful)) and spellID or nil
end

local function SQOL_Range_IsActionInRange(slot)
    local isActionInRange = (C_ActionBar and C_ActionBar.IsActionInRange) or rawget(_G, "IsActionInRange")
    if type(isActionInRange) ~= "function" then return nil end
    local ok, inRange = pcall(isActionInRange, slot, "target")
    if not ok or inRange == nil or not SQOL.CanUseValue(inRange) then
        return nil
    end
    return inRange and true or false
end

-- Max range in yards, with melee abilities (max range 0) counted as melee range.
local function SQOL_Range_GetMaxRange(spellID)
    local getSpellInfo = C_Spell and C_Spell.GetSpellInfo
    if type(getSpellInfo) ~= "function" then return nil end
    local ok, info = pcall(getSpellInfo, spellID)
    local maxRange = ok and type(info) == "table" and info.maxRange
    if type(maxRange) ~= "number" or not SQOL.CanUseValue(maxRange) then
        return nil
    end
    return math.max(maxRange, MELEE_RANGE)
end

-- Returns nil without an attackable target or without any offensive action
-- that can be range-checked against it. Otherwise returns:
--   outOfRange - none of the offensive actions reach the target
--   minYards   - farther than this (the longest range that doesn't reach), or nil
--   maxYards   - within this (the shortest range that reaches), or nil
function SQOL.RangeIndicator_GetState()
    if not SQOL_Range_HasAttackableTarget() then
        return nil
    end

    local checked, anyInRange = false, false
    local shortestReach, longestMiss
    SQOL_Range_ForEachAction(function(slot)
        local spellID = SQOL_Range_GetOffensiveSpell(slot)
        if not spellID then return end
        local inRange = SQOL_Range_IsActionInRange(slot)
        if inRange == nil then return end

        checked = true
        local maxRange = SQOL_Range_GetMaxRange(spellID)
        if inRange then
            anyInRange = true
            if maxRange and (not shortestReach or maxRange < shortestReach) then
                shortestReach = maxRange
            end
        elseif maxRange and (not longestMiss or maxRange > longestMiss) then
            longestMiss = maxRange
        end
    end)

    if not checked then
        return nil
    end
    -- A miss at a longer range than a reach (e.g. a minimum range) says nothing useful.
    if shortestReach and longestMiss and longestMiss >= shortestReach then
        longestMiss = nil
    end
    return { outOfRange = not anyInRange, minYards = longestMiss, maxYards = anyInRange and shortestReach or nil }
end

function SQOL.RangeIndicator_IsOutOfRange()
    local state = SQOL.RangeIndicator_GetState()
    return state and state.outOfRange or false
end

-- "> 40 yd", "8-30 yd", "< 5 yd", or nil when nothing is known.
function SQOL.RangeIndicator_FormatDistance(state)
    if not state then return nil end
    if state.outOfRange then
        return state.minYards and string.format("> %d yd", state.minYards) or nil
    end
    if state.minYards and state.maxYards then
        return string.format("%d-%d yd", state.minYards, state.maxYards)
    end
    return state.maxYards and string.format("< %d yd", state.maxYards) or nil
end

------------------------------------------------------------
-- Blizzard's soft target sword icon
------------------------------------------------------------
local function SQOL_Range_GetCVar(name)
    local getCVar = (C_CVar and C_CVar.GetCVar) or rawget(_G, "GetCVar")
    if type(getCVar) ~= "function" then return nil end
    local ok, value = pcall(getCVar, name)
    return ok and value or nil
end

local function SQOL_Range_SetCVar(name, value)
    local setCVar = (C_CVar and C_CVar.SetCVar) or rawget(_G, "SetCVar")
    if type(setCVar) == "function" then
        pcall(setCVar, name, value)
    end
end

-- Turn the sword icon off while the range icon is enabled, and back on only if
-- this addon was the one that turned it off.
local function SQOL_Range_ApplySoftTargetIcon()
    if not SQOL.DB then return end
    if SQOL.DB.ShowRangeIndicator then
        if SQOL_Range_GetCVar(SOFT_TARGET_ICON_CVAR) == "1" then
            SQOL_Range_SetCVar(SOFT_TARGET_ICON_CVAR, "0")
            SQOL.DB.RangeHidSoftTargetIcon = true
        end
    elseif SQOL.DB.RangeHidSoftTargetIcon then
        SQOL_Range_SetCVar(SOFT_TARGET_ICON_CVAR, "1")
        SQOL.DB.RangeHidSoftTargetIcon = nil
    end
end

------------------------------------------------------------
-- Icon and distance text
------------------------------------------------------------
-- Where to show the icon, as point, relativeTo, relativePoint, x, y:
-- 1. On the target's nameplate, where Blizzard's soft target sword icon sits
--    (its SoftTargetFrame), or just above our quest objective count when that
--    is shown there.
-- 2. Otherwise (no nameplate: off screen, nameplates off, or forbidden in
--    instances) right of the target frame portrait.
local function SQOL_Range_GetAnchor()
    local getNamePlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(getNamePlate) == "function" then
        local ok, nameplate = pcall(getNamePlate, "target")
        local unitFrame = ok and type(nameplate) == "table" and nameplate.UnitFrame
        if unitFrame then
            local objectiveText = nameplate.SQOLObjectiveText
            if objectiveText and objectiveText:IsShown() then
                return "BOTTOM", objectiveText, "TOP", 0, 2
            end
            if unitFrame.SoftTargetFrame then
                return "CENTER", unitFrame.SoftTargetFrame, "CENTER", 0, 0
            end
            return "BOTTOM", unitFrame, "TOP", 0, 2
        end
    end

    local targetFrame = rawget(_G, "TargetFrame")
    if not (targetFrame and targetFrame.IsVisible and targetFrame:IsVisible()) then
        return nil
    end
    local container = targetFrame.TargetFrameContainer
    local portrait = (container and container.Portrait) or rawget(_G, "TargetFramePortrait")
    return "LEFT", portrait or targetFrame, "RIGHT", 4, 0
end

-- Re-anchor only when the anchor changes (e.g. the nameplate appears).
local function SQOL_Range_PlaceIndicator(frame, point, relativeTo, relativePoint, x, y)
    if frame.anchorTo == relativeTo and frame.anchorPoint == point then
        return true
    end
    frame:ClearAllPoints()
    if not pcall(frame.SetPoint, frame, point, relativeTo, relativePoint, x, y) then
        frame.anchorTo, frame.anchorPoint = nil, nil
        return false
    end
    frame.anchorTo, frame.anchorPoint = relativeTo, point
    return true
end

local function SQOL_Range_CreateIndicator()
    local frame = CreateFrame("Frame", "SQOL_RangeIndicator", UIParent)
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON_TEXTURE)
    icon:Hide()
    frame.Icon = icon

    -- Gentle pulse so the icon catches the eye without flashing.
    if type(icon.CreateAnimationGroup) == "function" then
        local pulse = icon:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.45)
        fade:SetDuration(0.6)
        icon.Pulse = pulse
    end

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetShadowOffset(1, -1)
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.Text = text
    return frame
end

local function SQOL_Range_ShowState(state)
    local distance = SQOL.RangeIndicator_FormatDistance(state)
    local showIcon = state and state.outOfRange or false
    local point, relativeTo, relativePoint, x, y
    if showIcon or distance then
        point, relativeTo, relativePoint, x, y = SQOL_Range_GetAnchor()
    end
    if not point then
        if indicator then indicator:Hide() end
        return
    end

    if not indicator then
        indicator = SQOL_Range_CreateIndicator()
    end
    if not SQOL_Range_PlaceIndicator(indicator, point, relativeTo, relativePoint, x, y) then
        indicator:Hide()
        return
    end

    local icon, text = indicator.Icon, indicator.Text
    if icon:IsShown() ~= showIcon then
        icon:SetShown(showIcon)
        if icon.Pulse then
            if showIcon then icon.Pulse:Play() else icon.Pulse:Stop() end
        end
        -- The distance sits right of the icon, or in its place when it is hidden.
        text:ClearAllPoints()
        if showIcon then
            text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        else
            text:SetPoint("CENTER", indicator, "CENTER", 0, 0)
        end
    end

    if text:GetText() ~= (distance or "") then
        text:SetText(distance or "")
    end
    if showIcon then
        text:SetTextColor(1, 0.25, 0.2)
    else
        text:SetTextColor(1, 1, 1)
    end
    indicator:Show()
end

local function SQOL_Range_Update()
    local state
    if SQOL.DB and SQOL.DB.ShowRangeIndicator then
        state = SQOL.RangeIndicator_GetState()
    end
    SQOL_Range_ShowState(state)
end

------------------------------------------------------------
-- Polling while there is a target
------------------------------------------------------------
local function SQOL_Range_OnUpdate(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + (elapsed or 0)
    if elapsedSinceUpdate < UPDATE_INTERVAL then return end
    elapsedSinceUpdate = 0
    SQOL_Range_Update()
end

-- Poll while the option is on and something is targeted; each poll also
-- re-checks that the target is alive and attackable.
function SQOL.RangeIndicator_Refresh()
    if not updater then return end
    local active = SQOL.DB and SQOL.DB.ShowRangeIndicator and SQOL_Range_IsTrue(UnitExists("target"))
    if active then
        elapsedSinceUpdate = 0
        updater:SetScript("OnUpdate", SQOL_Range_OnUpdate)
    else
        updater:SetScript("OnUpdate", nil)
    end
    SQOL_Range_Update()
end

-- Called when the option changes (and at login).
function SQOL.RangeIndicator_OnOptionChanged()
    SQOL_Range_ApplySoftTargetIcon()
    SQOL.RangeIndicator_Refresh()
end

updater = CreateFrame("Frame")
updater:RegisterEvent("PLAYER_LOGIN")
updater:RegisterEvent("PLAYER_TARGET_CHANGED")
updater:RegisterEvent("PLAYER_ENTERING_WORLD")
updater:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        SQOL.RangeIndicator_OnOptionChanged()
    else
        SQOL.RangeIndicator_Refresh()
    end
end)
