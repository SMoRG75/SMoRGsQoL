local ADDON_NAME, SQOL = ...

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
    if not SQOL.DB or not SQOL.DB.ShowItemLevel then return end
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
local function SQOL_CanUseValue(value)
    local accessChecked = false

    if type(canaccessvalue) == "function" then
        local ok, canAccess = pcall(canaccessvalue, value)
        if not ok then
            return false
        end

        accessChecked = true
        if canAccess == false then
            return false
        end
    end

    if type(issecretvalue) == "function" then
        local ok, isSecret = pcall(issecretvalue, value)
        if not ok then
            return false
        end

        if isSecret and not accessChecked then
            return false
        end
    end

    return true
end

local function SQOL_GetMovementSpeedPercent()
    local baseRunSpeed = 7 -- yards/sec (100% run speed)

    if type(GetUnitSpeed) ~= "function" then
        return nil
    end

    local speed = GetUnitSpeed("player")
    if type(speed) ~= "number" then
        return nil
    end

    if not SQOL_CanUseValue(speed) then
        return SQOL._lastSpeedPct
    end

    -- When standing still, speed is 0; keep the last known non-zero value.
    if speed <= 0 then
        return SQOL._lastSpeedPct
    end

    local pct = (speed / baseRunSpeed) * 100
    SQOL._lastSpeedPct = pct
    return pct
end

function SQOL.UpdateCharacterIlvlText(forceIlvlRefresh)
    if SQOL.DB and (not SQOL.DB.ShowItemLevel and not SQOL.DB.ShowMovementSpeed) then
        if SQOL.iLvlHolder then SQOL.iLvlHolder:Hide() end
        return
    end
    if not SQOL.iLvlText then return end

    -- Keep iLvl cached so speed polling is cheap.
    SQOL_RefreshIlvlCache(forceIlvlRefresh == true)

    if SQOL.DB.ShowItemLevel and SQOL._cachedIlvlMissingInfo and not SQOL._ilvlRetryPending then
        SQOL._ilvlRetryPending = true
        C_Timer.After(0.5, function()
            SQOL._ilvlRetryPending = false
            SQOL_RefreshIlvlCache(true)
            SQOL.UpdateCharacterIlvlText(true)
        end)
    end

    local speedPct = SQOL.DB.ShowMovementSpeed and SQOL_GetMovementSpeedPercent() or nil

    local ilvlText = SQOL._cachedIlvlText or "--"
    local speedText
    if type(speedPct) == "number" then
        speedText = string.format("%d%%", math.floor(speedPct + 0.5))
    else
        speedText = "--"
    end

    local parts = {}
    if SQOL.DB.ShowItemLevel then parts[#parts + 1] = "iLvl: " .. ilvlText end
    if SQOL.DB.ShowMovementSpeed then parts[#parts + 1] = "Spd: " .. speedText end
    local line = table.concat(parts, "  ")
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

function SQOL.UpdatePlayerFrameIlvlAnchor()
    if not SQOL.iLvlHolder or not SQOL.iLvlText then
        return false
    end

    if SQOL.DB and (not SQOL.DB.ShowItemLevel and not SQOL.DB.ShowMovementSpeed) then
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

    -- Don't build or show the line when both fields are disabled.
    if SQOL.DB and (not SQOL.DB.ShowItemLevel and not SQOL.DB.ShowMovementSpeed) then
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
        SQOL._lastStatLineText = nil
        SQOL.iLvlText:SetText("")
    end

    if not SQOL._playerFrameHooked and playerFrame.HookScript then
        SQOL._playerFrameHooked = true
        playerFrame:HookScript("OnShow", function()
            SQOL.UpdatePlayerFrameIlvlAnchor()
            SQOL.UpdateCharacterIlvlText(true)
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
            if not SQOL.DB or not SQOL.DB.ShowMovementSpeed then return end
            self._elapsed = (self._elapsed or 0) + (elapsed or 0)
            if self._elapsed < 0.20 then return end
            self._elapsed = 0

            if SQOL.iLvlHolder and SQOL.iLvlHolder.IsShown and SQOL.iLvlHolder:IsShown() then
                SQOL.UpdateCharacterIlvlText(false)
            end
        end)
    end

    SQOL.UpdatePlayerFrameIlvlAnchor()
    SQOL.UpdateCharacterIlvlText(true)
    return true
end

function SQOL.TryEnsurePlayerFrameIlvlUI(retries)
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
        SQOL.TryEnsurePlayerFrameIlvlUI(retries + 1)
    end)
end

