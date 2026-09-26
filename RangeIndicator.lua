------------------------------------------------------------
-- SMoRGsQoL - Out-of-range icon on the target frame
-- Shows an icon next to the target portrait when none of the offensive
-- abilities on your action bars can reach your (attackable) target.
-- Uses C_ActionBar.IsActionInRange, the check Blizzard uses to tint action
-- buttons red, so it needs no per-class spell lists and handles forms and
-- bonus bars through the visible action buttons.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...

local ICON_TEXTURE = "Interface\\Icons\\Ability_Rogue_Sprint"
local ICON_SIZE = 28
local UPDATE_INTERVAL = 0.15
local MAX_ACTION_SLOT = 180

local indicator            -- the icon frame, created on first use
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
-- Stops and returns true as soon as func returns true.
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
                    if func(slot) then return true end
                end
            end
        end
    end

    if not sawButton then
        for slot = 1, MAX_ACTION_SLOT do
            if SQOL_Range_HasAction(slot) and func(slot) then
                return true
            end
        end
    end
    return false
end

-- Only spells that can be cast on hostile targets count: self and pet spells
-- such as Play Dead or Mend Pet report "in range" for any target. Items,
-- flyouts and item macros are skipped.
local function SQOL_Range_IsOffensiveAction(slot)
    local actionType, id, subType = GetActionInfo(slot)
    local spellID
    if actionType == "spell" then
        spellID = id
    elseif actionType == "macro" and subType == "spell" then
        spellID = id
    end
    if type(spellID) ~= "number" or not SQOL.CanUseValue(spellID) then
        return false
    end

    local isHarmful = C_Spell and C_Spell.IsSpellHarmful
    if type(isHarmful) ~= "function" then
        return true
    end
    local ok, harmful = pcall(isHarmful, spellID)
    return ok and SQOL_Range_IsTrue(harmful)
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

-- True when at least one offensive action could be range-checked against the
-- target and none of them reach it. Abilities without range are skipped
-- (their range check returns nil).
function SQOL.RangeIndicator_IsOutOfRange()
    if not SQOL_Range_HasAttackableTarget() then
        return false
    end

    local checked = false
    local anyInRange = SQOL_Range_ForEachAction(function(slot)
        if not SQOL_Range_IsOffensiveAction(slot) then return false end
        local inRange = SQOL_Range_IsActionInRange(slot)
        if inRange ~= nil then
            checked = true
            return inRange
        end
    end)
    return checked and not anyInRange
end

------------------------------------------------------------
-- Icon
------------------------------------------------------------
local function SQOL_Range_GetAnchor()
    local targetFrame = rawget(_G, "TargetFrame")
    local container = targetFrame and targetFrame.TargetFrameContainer
    local portrait = (container and container.Portrait) or rawget(_G, "TargetFramePortrait")
    return portrait or targetFrame, targetFrame
end

local function SQOL_Range_CreateIndicator()
    local frame = CreateFrame("Frame", "SQOL_RangeIndicator", UIParent)
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Thin red frame behind the icon.
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(1, 0.1, 0.1, 0.6)

    -- Gentle pulse so it catches the eye without flashing.
    if type(frame.CreateAnimationGroup) == "function" then
        local pulse = frame:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.45)
        fade:SetDuration(0.6)
        frame:SetScript("OnShow", function() pulse:Play() end)
        frame:SetScript("OnHide", function() pulse:Stop() end)
    end

    local anchor = SQOL_Range_GetAnchor()
    if anchor then
        -- Right of the portrait, where nothing else sits on the default target frame.
        frame:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
    return frame
end

local function SQOL_Range_Update()
    local show = false
    if SQOL.DB and SQOL.DB.ShowRangeIndicator then
        local _, targetFrame = SQOL_Range_GetAnchor()
        local frameShown = not targetFrame or (targetFrame.IsVisible and targetFrame:IsVisible())
        show = frameShown and SQOL.RangeIndicator_IsOutOfRange()
    end

    if show and not indicator then
        indicator = SQOL_Range_CreateIndicator()
    end
    if indicator then
        indicator:SetShown(show)
    end
end

------------------------------------------------------------
-- Polling while there is an attackable target
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

updater = CreateFrame("Frame")
updater:RegisterEvent("PLAYER_TARGET_CHANGED")
updater:RegisterEvent("PLAYER_ENTERING_WORLD")
updater:SetScript("OnEvent", function()
    SQOL.RangeIndicator_Refresh()
end)
