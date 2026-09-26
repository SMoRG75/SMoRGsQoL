------------------------------------------------------------
-- SMoRGsQoL by SMoRG75 (Retail and WoW Forever).
-- Shared namespace, defaults and utilities. Loaded before feature modules.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"

SQOL = SQOL or {}        -- addon namespace table (shared across files)
SQOL.ADDON_NAME = ADDON_NAME

-- WoW Forever runs the Mainline client (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
-- but reports a 1.x interface version (16001), so detect it by build number.
local interfaceVersion = type(GetBuildInfo) == "function" and select(4, GetBuildInfo())
SQOL.IsForever = type(interfaceVersion) == "number" and interfaceVersion < 100000

SQOL.QuestSoundProfiles = {
    Horde = {
        label = "Horde (Peon)",
        objective = 6197, -- B_PeonYes3: "Work, work."
        complete = 6199,  -- B_PeonBuildingComplete1: "Work complete."
    },
    Alliance = {
        label = "Alliance (Human worker)",
        objective = 6288, -- B_PeasantWhat3: "More work?"
        complete = "Interface\\AddOns\\SMoRGsQoL\\Sounds\\Peasant_job_done.mp3",
    },
}

------------------------------------------------------------
-- Defaults
------------------------------------------------------------
SQOL.defaults = {
    AutoTrack     = false,
    DebugTrack    = false,
    ShowSplash    = false,
    ColorProgress = false,
    ColorStatusBarProgress = false,
    QuestCompleteSound = true,
    QuestObjectiveSound = true,
    QuestSoundProfile = "Horde",
    HideDoneAchievements = false,
    RepWatch     = false,
    ShowRepGains = false,
    ShowNameplateObjectives = false,

    -- PlayerFrame line: "iLvl: xx.x  Spd: yy%"
    ShowItemLevel = false,
    ShowMovementSpeed = false,

    -- Floating combat text damage numbers font.
    DamageTextFont = false,

    -- Highlight the cursor when shaking the mouse.
    CursorShakeHighlight = false,

    -- Countdown timer on the ReadyCheckFrame showing time until it expires.
    ShowReadyCheckTimer = false,

    -- Countdown timer on the LFG queue pop showing time left to accept.
    ShowLFGProposalTimer = false,

    -- Show each party member's level on the default party frames.
    ShowPartyLevel = false,

    -- Add a "Target:" line to unit tooltips showing who the unit is targeting.
    ShowTooltipTarget = false,

    -- LibDBIcon minimap button (the LDB launcher and addon compartment are always there).
    ShowMinimapButton = false,

}

------------------------------------------------------------
-- Internal utils
------------------------------------------------------------
function SQOL.dprint(...)
    if SQOL.DB and SQOL.DB.DebugTrack then
        print("|cff9999ff[SQOL Debug]|r", ...)
    end
end

function SQOL.safe_pcall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and SQOL.DB and SQOL.DB.DebugTrack then
        SQOL.dprint("pcall error:", err)
    end
    return ok
end

-- False for secret values (12.x) that addon code may not read or compare.
function SQOL.CanUseValue(value)
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

function SQOL.clamp01(x)
    if x ~= x then return 0 end
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

-- WoW normally lets short-lived Lua allocations accumulate until its next GC
-- cycle, which makes the addon-memory display climb even after SQOL has dropped
-- every reference. Do a few small incremental steps after allocation-heavy
-- scans; unlike collectgarbage("collect"), this spreads the work across frames.
function SQOL.RequestIncrementalGC()
    if type(collectgarbage) ~= "function" then return end

    if not SQOL._gcStepper then
        local worker = CreateFrame("Frame")
        worker:Hide()
        worker:SetScript("OnUpdate", function(self)
            local cycleComplete = collectgarbage("step", 256)
            self.stepsRemaining = (self.stepsRemaining or 1) - 1
            if cycleComplete or self.stepsRemaining <= 0 then
                self:Hide()
            end
        end)
        SQOL._gcStepper = worker
    end

    -- At most 16 bounded steps per request. Repeated event bursts extend the
    -- worker instead of creating timers or closures of their own.
    SQOL._gcStepper.stepsRemaining = math.max(SQOL._gcStepper.stepsRemaining or 0, 16)
    SQOL._gcStepper:Show()
end

function SQOL.TableWipe(t)
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

