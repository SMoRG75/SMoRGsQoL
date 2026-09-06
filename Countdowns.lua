local ADDON_NAME, SQOL = ...

------------------------------------------------------------
-- Countdown timers
-- Shared machinery for the ready check and LFG proposal countdowns:
-- a fontstring on its own frame, ticked ten times a second, turning red
-- for the last few seconds. Each timer supplies its own anchor rule.
------------------------------------------------------------
local SQOL_COUNTDOWN_WARN_SECONDS = 5

local SQOL_Countdown = {}
SQOL_Countdown.__index = SQOL_Countdown

local function SQOL_Countdown_OnUpdate(updater, elapsed)
    local countdown = updater.countdown
    updater.accum = (updater.accum or 0) + elapsed
    if updater.accum < 0.1 then return end
    updater.accum = 0

    local remaining = (updater.expires or 0) - GetTime()
    if remaining < 0 then remaining = 0 end

    local fs = countdown.text
    if fs then
        local secs = math.ceil(remaining)
        if secs <= SQOL_COUNTDOWN_WARN_SECONDS then
            fs:SetTextColor(1, 0.2, 0.2)
        else
            fs:SetTextColor(1, 0.82, 0)
        end
        fs:SetFormattedText("%ds", secs)
        -- The popup can appear a frame or two after the event fires.
        countdown:Anchor()
    end

    if remaining <= 0 then
        countdown:Stop()
    end
end

-- anchorFn positions the holder frame; onStop is optional cleanup.
local function SQOL_Countdown_New(anchorFn, onStop)
    return setmetatable({ anchorFn = anchorFn, onStop = onStop }, SQOL_Countdown)
end

-- The timer lives on its own frame parented to UIParent rather than on
-- the popup it belongs to: those popups are not always shown (see the
-- ready check initiator case), and anything parented to a hidden frame
-- stays invisible.
function SQOL_Countdown:Ensure()
    if self.text then
        return self.text
    end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("FULLSCREEN_DIALOG")
    holder:SetSize(160, 24)

    local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 0.82, 0)

    self.holder = holder
    self.text = fs
    return fs
end

function SQOL_Countdown:Anchor()
    if not self.holder then return end
    self.holder:ClearAllPoints()
    self.anchorFn(self.holder)
end

function SQOL_Countdown:Start(duration)
    duration = tonumber(duration)
    if not duration or duration <= 0 then return end

    local fs = self:Ensure()
    if not fs then return end

    if not self.updater then
        self.updater = CreateFrame("Frame")
        self.updater.countdown = self
    end
    local updater = self.updater
    updater.expires = GetTime() + duration
    updater.accum = 1 -- Force an immediate draw on the next OnUpdate.
    updater:SetScript("OnUpdate", SQOL_Countdown_OnUpdate)
    updater:Show()

    fs:SetFormattedText("%ds", math.ceil(duration))
    self:Anchor()
    self.holder:Show()
end

function SQOL_Countdown:Stop()
    if self.onStop then
        self.onStop(self)
    end
    if self.updater then
        self.updater:SetScript("OnUpdate", nil)
        self.updater:Hide()
    end
    if self.holder then
        self.holder:Hide()
    end
end

------------------------------------------------------------
-- Ready check countdown (party/raid ready check, READY_CHECK event)
------------------------------------------------------------
local SQOL_READY_CHECK_DURATION = 30 -- Blizzard default; used as a fallback.

-- ReadyCheckFrame is only an invisible container: the artwork, text and
-- buttons all live in its ReadyCheckListenerFrame child, which Blizzard
-- keeps hidden for the initiator. So the container being shown says
-- nothing about anything being on screen - check the child.
local function SQOL_ReadyCheck_PopupVisible()
    return ReadyCheckFrame and ReadyCheckFrame:IsShown()
        and ReadyCheckListenerFrame and ReadyCheckListenerFrame:IsShown()
end

-- Test helper: force the Blizzard popup open so the anchoring can be
-- checked solo. A real ready check needs a group, and the initiator is
-- auto-readied and never sees the popup at all.
local function SQOL_ReadyCheck_ShowFakePopup()
    if not (ReadyCheckFrame and ReadyCheckListenerFrame) then return end

    -- Mirror what ShowReadyCheck() does for a non-initiator: fill in the
    -- portrait and text, then show the child that holds the artwork.
    if ReadyCheckPortrait then
        SetPortraitTexture(ReadyCheckPortrait, "player")
    end
    if ReadyCheckFrameText then
        ReadyCheckFrameText:SetFormattedText(READY_CHECK_MESSAGE, UnitName("player") or "?")
    end

    ReadyCheckFrame:Show()
    ReadyCheckListenerFrame:Show()
    SQOL.readyCheckFakePopup = true
end

local SQOL_ReadyCheckTimer = SQOL_Countdown_New(
    -- Snap to the ready check popup when it is visible, otherwise park
    -- the countdown near the top so the initiator can see it too.
    function(holder)
        if SQOL_ReadyCheck_PopupVisible() then
            holder:SetPoint("TOP", ReadyCheckFrame, "BOTTOM", 0, -4)
        else
            holder:SetPoint("TOP", UIParent, "TOP", 0, -180)
        end
    end,
    function()
        if not SQOL.readyCheckFakePopup then return end
        SQOL.readyCheckFakePopup = nil
        if ReadyCheckFrame then
            ReadyCheckFrame:Hide()
        end
    end
)

function SQOL.ReadyCheck_Hide()
    SQOL_ReadyCheckTimer:Stop()
end

function SQOL.ReadyCheck_Start(duration)
    if not (SQOL.DB and SQOL.DB.ShowReadyCheckTimer) then return end

    duration = tonumber(duration)
    if not duration or duration <= 0 then
        duration = SQOL_READY_CHECK_DURATION
    end
    SQOL_ReadyCheckTimer:Start(duration)
end

-- Manual test: fakes a ready check (popup + countdown) without a group.
function SQOL_ReadyCheck_Test(duration, withPopup)
    if withPopup then
        SQOL_ReadyCheck_ShowFakePopup()
    end
    SQOL.ReadyCheck_Start(duration or SQOL_READY_CHECK_DURATION)
end

------------------------------------------------------------
-- LFG proposal countdown (queue pop, LFG_PROPOSAL_SHOW event)
-- Blizzard's LFGDungeonReadyStatus frame is labelled "Ready Check" but
-- belongs to the group finder, not the READY_CHECK event, and no API
-- exposes how long is left. The accept window is a fixed 40 seconds, so
-- the countdown is driven from when the proposal appears.
------------------------------------------------------------
local SQOL_LFG_PROPOSAL_DURATION = 40

local SQOL_LFGProposalTimer = SQOL_Countdown_New(function(holder)
    if LFGDungeonReadyStatus and LFGDungeonReadyStatus:IsShown() then
        holder:SetPoint("TOP", LFGDungeonReadyStatus, "BOTTOM", 0, -4)
    elseif LFGDungeonReadyPopup and LFGDungeonReadyPopup:IsShown() then
        holder:SetPoint("TOP", LFGDungeonReadyPopup, "BOTTOM", 0, -4)
    else
        holder:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
end)

function SQOL.LFGProposal_Hide()
    SQOL_LFGProposalTimer:Stop()
end

function SQOL.LFGProposal_Start()
    if not (SQOL.DB and SQOL.DB.ShowLFGProposalTimer) then return end
    SQOL_LFGProposalTimer:Start(SQOL_LFG_PROPOSAL_DURATION)
end

-- Manual test: the countdown alone, without a queue pop.
function SQOL_LFGProposal_Test(duration)
    SQOL_LFGProposalTimer:Start(duration or SQOL_LFG_PROPOSAL_DURATION)
end

