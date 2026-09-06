local ADDON_NAME, SQOL = ...

------------------------------------------------------------
-- Damage text font
------------------------------------------------------------
local SQOL_DAMAGE_TEXT_FONT = "Interface\\AddOns\\SMoRGsQoL\\trashhand.ttf"
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
        print("|cff33ff99SQoL:|r Cursor shake highlight is OFF. Enable it with /sqol cursor.")
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
function SQOL.ApplyAchievementFilter()
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

