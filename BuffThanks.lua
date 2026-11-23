local _, SQOL = ...

------------------------------------------------------------
-- Thank players who buff you (WoW Forever): when another player puts a
-- helpful aura on you in the open world, do the /thank emote on them.
-- 12.x gives addons no combat log, so the caster comes from the aura's
-- sourceUnit in UNIT_AURA. Casters the client has no unit token for
-- (not targeted, no nameplate, not in your group) can't be named and
-- are skipped. Aura data that is secret (combat) is skipped too.
------------------------------------------------------------
local THANK_COOLDOWN = 300 -- seconds before the same player is thanked again
local THANK_DELAY = 1      -- a short pause, so the thanks follows the buff

local thankedAt = {}
local eventFrame = CreateFrame("Frame")

local function SQOL_Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or not SQOL.CanUseValue(a) or not SQOL.CanUseValue(b) then return nil end
    return a, b
end

local function SQOL_Enabled()
    return SQOL.IsForever and SQOL.DB and SQOL.DB.ThankBuffs
end

-- Open world: not in a dungeon, raid, battleground, arena or scenario.
function SQOL.BuffThanks_InOpenWorld()
    local ok, inInstance = pcall(IsInInstance)
    return ok and SQOL.CanUseValue(inInstance) and inInstance == false
end

-- "Name" or "Name-Realm" for another player, nil for anyone else.
local function SQOL_PlayerName(unit)
    if not SQOL.CanUseValue(unit) or type(unit) ~= "string" or unit == "" then return nil end
    if SQOL_Call(UnitIsPlayer, unit) ~= true then return nil end
    if SQOL_Call(UnitIsUnit, unit, "player") ~= false then return nil end
    local name, realm = SQOL_Call(UnitName, unit)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function SQOL_Thank(name)
    if not SQOL_Enabled() or not SQOL.BuffThanks_InOpenWorld() then return end
    if C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
        pcall(C_ChatInfo.PerformEmote, "THANK", name)
    elseif type(DoEmote) == "function" then
        pcall(DoEmote, "THANK", name)
    end
end

local function SQOL_OnAuraAdded(aura)
    if type(aura) ~= "table" then return end
    local helpful, source = aura.isHelpful, aura.sourceUnit
    if not SQOL.CanUseValue(helpful) or helpful ~= true then return end
    local name = SQOL_PlayerName(source)
    if not name then return end

    local now = GetTime()
    if thankedAt[name] and now - thankedAt[name] < THANK_COOLDOWN then return end
    thankedAt[name] = now
    SQOL.dprint("Thanking", name, "for", tostring(aura.name))
    C_Timer.After(THANK_DELAY, function() SQOL_Thank(name) end)
end

eventFrame:SetScript("OnEvent", function(_, _, unit, updateInfo)
    if unit ~= "player" or not SQOL_Enabled() then return end
    if type(updateInfo) ~= "table" or not SQOL.CanUseValue(updateInfo.isFullUpdate) then return end
    -- A full update (login, zoning) lists auras you already had.
    if updateInfo.isFullUpdate or type(updateInfo.addedAuras) ~= "table" then return end
    if not SQOL.BuffThanks_InOpenWorld() then return end
    for _, aura in ipairs(updateInfo.addedAuras) do
        SQOL_OnAuraAdded(aura)
    end
end)

-- Listens to your own auras only while the option is on.
function SQOL.BuffThanks_OnOptionChanged()
    if SQOL_Enabled() then
        if type(eventFrame.RegisterUnitEvent) == "function" then
            pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_AURA", "player")
        else
            pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_AURA")
        end
    else
        eventFrame:UnregisterEvent("UNIT_AURA")
        SQOL.TableWipe(thankedAt)
    end
end
