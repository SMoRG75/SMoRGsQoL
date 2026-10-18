-- Run from the repository root: lua tests/reputation.lua
-- Exercises the real reputation module with deterministic APIs and timers.
local addon, state, timers, timestamp = nil, {}, {}, 0
local messages = {}
local secret = setmetatable({}, { __tostring = function() error("Secret value was formatted") end })
function canaccessvalue(value) return value ~= secret end
function canaccesstable(value) return value ~= secret end
function GetTime() return timestamp end
function GetServerTime() return 1700000000 + math.floor(timestamp) end
function print(message) messages[#messages + 1] = message end
local function addTimer(delay, callback, cancellable)
    local timer = { at = timestamp + delay, callback = callback, cancellable = cancellable }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
C_Timer = {
    After = function(delay, fn) addTimer(delay, fn, false) end,
    NewTimer = function(delay, fn) return addTimer(delay, fn, true) end,
}
local function advance(seconds)
    local target, steps = timestamp + seconds, 0
    while true do
        local nextTimer
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.fired and timer.at <= target
                and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end
        end
        if not nextTimer then break end
        timestamp, nextTimer.fired = nextTimer.at, true
        nextTimer.callback()
        steps = steps + 1
        assert(steps < 100, "Events or timers are rescheduling themselves indefinitely")
    end
    timestamp = target
end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function updateFaction()
    local external = addon.RepMemory_OnFactionUpdate()
    if not external and addon.DB.RepWatch and not addon.RepWatch_ReputationFrameOpen() then
        SQOL_RepWatch_ScheduleScan("update_faction")
    end
end
local function boot(saved, memory, autoWatch)
    C_Timer.NewTimer = function(delay, fn) return addTimer(delay, fn, true) end
    timers, state = {}, { watched = 1, legacy = false, collapsed = true, writes = 0,
        factions = {
            [1] = { factionID = 1, name = "Darnassus", currentStanding = 1000 },
            [2] = { factionID = 2, name = "Stormwind", currentStanding = 2000 },
            [3] = { factionID = 3, name = "Silvermoon Court", currentStanding = 3000 },
        } }
    ReputationFrame = {
        IsShown = function() return state.panelOpen end,
        IsVisible = function() return state.panelOpen and not state.panelParentHidden end,
    }
    WardrobeFrame = {
        IsShown = function() return state.collectionsOpen end,
        IsVisible = function() return state.collectionsOpen and not state.collectionsParentHidden end,
    }
    local function rows()
        local list = { { name = "Expansion", isHeader = true, isCollapsed = state.collapsed } }
        if not state.collapsed then
            for id = 1, 3 do
                if state.legacy or id ~= 1 then list[#list + 1] = state.factions[id] end
            end
        end
        return list
    end
    C_Reputation = {
        GetWatchedFactionData = function()
            if state.apiError then error("Unavailable client data") end
            if state.secretWatched then return secret end
            return state.factions[state.watched]
        end,
        SetWatchedFactionByID = function(id)
            if state.failedWrite then return end
            assert(state.factions[id], "Unknown faction ID")
            state.watched, state.writes = id, state.writes + 1
            updateFaction()
        end,
        SetWatchedFactionByIndex = function(index)
            local row = rows()[index]
            assert(row and row.factionID, "Stale or invalid faction index")
            state.watched, state.writes = row.factionID, state.writes + 1
            updateFaction()
        end,
        GetNumFactions = function() return #rows() end,
        GetFactionDataByIndex = function(index) return rows()[index] end,
        AreLegacyReputationsShown = function() return state.legacy end,
        SetLegacyReputationsShown = function(shown) state.legacy = shown; updateFaction() end,
        ExpandAllFactionHeaders = function() state.collapsed = false; updateFaction() end,
        CollapseFactionHeader = function() state.collapsed = true; updateFaction() end,
    }
    SQOL_CharacterDB = saved
    addon = {}
    for _, file in ipairs({ "Locales/Locales.lua", "Core.lua", "Reputation.lua" }) do
        assert(loadfile(file))("SMoRGsQoL", addon)
    end
    addon.DB = { RepWatch = autoWatch ~= false, RepMemory = memory ~= false }
    addon.RepMemory_Init()
    addon.Rep_RebuildNameMap()
    SQOL_RepWatch_ScheduleScan()
    advance(0.3)
end
local function saveFavorite()
    addon.RepMemory_Command("")
    equal(SQOL_CharacterDB.preferredFaction.factionID,
        C_Reputation.GetWatchedFactionData and state.watched or nil, "Save watched faction")
end
local function gain(id, amount)
    state.factions[id].currentStanding = state.factions[id].currentStanding + amount
    equal(addon.RepWatch_HandleFactionChangeMessage("Reputation with " .. state.factions[id].name
        .. " increased by " .. amount .. "."), true, "Handle a gain")
end
local function choose(id)
    state.watched = id
    updateFaction()
end
local function activeReturnTimers()
    local count = 0
    for _, timer in ipairs(timers) do
        if timer.cancellable and not timer.cancelled and not timer.fired then count = count + 1 end
    end
    return count
end
boot(nil)
equal(addon.defaults.RepMemory, false, "Memory defaults to off")
equal(activeReturnTimers(), 0, "Idle memory has no timer")
saveFavorite()
gain(2, 25)
equal(state.watched, 2, "Auto-watch displays the gain")
advance(0.3) -- Let the existing delta scan catch up.
advance(9.8)
equal(state.watched, 2, "Return waits ten seconds after the latest switch")
advance(0.3)
equal(state.watched, 1, "Return to preferred faction")
equal(activeReturnTimers(), 0, "Return leaves no repeating timer")
gain(2, 10)
advance(5)
gain(3, 15)
advance(0.3)
equal(activeReturnTimers(), 1, "Burst gains share a single return timer")
advance(5)
equal(state.watched, 3, "A later gain extends the deadline")
advance(5.2)
equal(state.watched, 1, "Extended deadline returns to preferred faction")
gain(2, 10)
choose(3) -- Also cancels a delta scan that was queued by our own setter.
advance(15)
equal(state.watched, 3, "External selection wins over return and queued scans")
equal(SQOL_CharacterDB.pendingReturn, nil, "External selection clears saved pending return")
gain(2, 10)
advance(0.3)
choose(3)
choose(2)
advance(15)
equal(state.watched, 2, "Changing away and back still cancels return")
gain(3, 20)
choose(nil)
advance(15)
equal(state.watched, nil, "Clearing the watched bar cancels return")
choose(1)
gain(2, 10)
addon.DB.RepMemory = false
addon.RepMemory_OnOptionChanged()
advance(15)
equal(state.watched, 2, "Disabling memory cancels return")
addon.DB.RepMemory = true
gain(3, 10)
addon.DB.RepWatch = false
addon.RepMemory_OnOptionChanged()
advance(15)
equal(state.watched, 3, "Disabling auto-watch cancels return")
addon.DB.RepWatch = true
gain(2, 10)
addon.RepMemory_Command("clear")
advance(15)
equal(state.watched, 2, "Clearing preferred faction cancels return")
equal(SQOL_CharacterDB.preferredFaction, nil, "Clear removes only the preference")
choose(1)
saveFavorite()
gain(2, 10)
advance(0.3)
state.panelOpen = true
advance(11)
equal(state.watched, 2, "Do not restore while the Reputation panel is open")
state.panelOpen = false
gain(3, 10)
advance(0.3)
state.collectionsOpen = true
advance(11)
equal(state.watched, 3, "Do not restore while Collections is open")
state.collectionsOpen = false
gain(2, 10)
advance(0.3)
local writes = state.writes
addon.RepWatch_HandleFactionChangeMessage("Reputation with Silvermoon Court decreased by 10.")
addon.RepWatch_HandleFactionChangeMessage(secret)
equal(state.writes, writes, "Losses and secret messages never switch reputation")
equal(addon.Rep_ParseMessage(secret), nil, "Public parser rejects secrets")
state.secretWatched = true
addon.RepMemory_OnFactionUpdate()
state.secretWatched = false
advance(11)
equal(state.watched, 2, "Unreadable watched faction cancels pending work safely")
state.apiError = true
addon.RepMemory_Command("")
state.apiError = false
equal(SQOL_CharacterDB.preferredFaction.factionID, 1, "Failed read preserves preferred faction")
state.factions[3].currentStanding = secret
addon.Rep_RebuildNameMap()
SQOL_RepWatch_ScheduleScan()
advance(1)
equal(addon._repLastStanding[3], nil, "Secret standings never enter delta snapshots")
state.factions[3].currentStanding = 3000
-- Only real deltas can trigger fallback; discovering an existing faction is not a gain.
addon._repLastStanding[3] = nil
SQOL_RepWatch_ScheduleScan()
advance(1)
equal(state.watched, 2, "Discovering an existing standing is not a reputation gain")
-- A pending return survives a new UI lifetime, keeping its wall-clock deadline.
gain(2, 10)
advance(0.3)
local saved = SQOL_CharacterDB
local remaining = saved.pendingReturn.expiresAt - GetServerTime()
boot(saved)
-- The test boot starts on the preferred faction, so a stale pending marker is discarded.
equal(SQOL_CharacterDB.pendingReturn, nil, "Login respects a changed watched faction")
equal(SQOL_CharacterDB.preferredFaction.factionID, 1, "Preference survives reload/login")
gain(2, 10)
advance(0.3)
-- Reload only the module without resetting the simulated client selection.
timers = {}
local reloaded = {}
for _, file in ipairs({ "Locales/Locales.lua", "Core.lua", "Reputation.lua" }) do
    assert(loadfile(file))("SMoRGsQoL", reloaded)
end
addon = reloaded
addon.DB = { RepWatch = true, RepMemory = true }
addon.RepMemory_Init()
equal(state.watched, 2, "Reload initially keeps the temporary faction")
advance(11)
equal(state.watched, 1, "Reload restores pending return")
assert(remaining <= 10, "Persisted deadline is bounded")
local originalCharacter = SQOL_CharacterDB
boot(nil)
equal(SQOL_CharacterDB.preferredFaction, nil, "Another character has no preference")
equal(originalCharacter.preferredFaction.factionID, 1, "Alt cannot change original preference")
-- Exercise the modern index-only path and preserve collapsed/legacy state.
saveFavorite()
C_Reputation.SetWatchedFactionByID = nil
gain(2, 25)
advance(11)
equal(state.watched, 1, "Modern index API restores a hidden legacy faction")
equal(state.legacy, false, "Legacy visibility is restored")
equal(state.collapsed, true, "Collapsed header is restored")
-- Exercise the old API names and legacy index setter used by older clients.
SetWatchedFactionIndex = C_Reputation.SetWatchedFactionByIndex
C_Reputation.SetWatchedFactionByIndex = nil
C_Reputation.AreLegacyFactionsShown = C_Reputation.AreLegacyReputationsShown
C_Reputation.SetLegacyFactionIsShown = C_Reputation.SetLegacyReputationsShown
C_Reputation.AreLegacyReputationsShown, C_Reputation.SetLegacyReputationsShown = nil, nil
gain(2, 25)
advance(11)
equal(state.watched, 1, "Older client API fallback restores preferred faction")
GetWatchedFactionInfo = function() return state.factions[state.watched].name end
C_Reputation.GetWatchedFactionData = nil
saveFavorite()
equal(SQOL_CharacterDB.preferredFaction.name, "Darnassus", "Legacy watched name can be saved")
gain(2, 25)
advance(11)
equal(state.watched, 1, "Name-only preference restores through legacy APIs")
SetWatchedFactionIndex, GetWatchedFactionInfo = nil, nil
-- A client with only After() still supports cancellation through generations.
boot(nil)
C_Timer.NewTimer = nil
saveFavorite()
gain(2, 25)
choose(3)
advance(15)
equal(state.watched, 3, "Uncancellable timer callback cannot undo external selection")
gain(2, 25)
advance(11)
equal(state.watched, 1, "After-only timer fallback returns correctly")
boot({ preferredFaction = { name = 123, factionID = false }, pendingReturn = "invalid" })
equal(SQOL_CharacterDB.preferredFaction, nil, "Malformed saved preference is rejected")
equal(SQOL_CharacterDB.pendingReturn, nil, "Malformed pending state is rejected")
boot(nil, false)
saveFavorite()
gain(2, 10)
advance(15)
equal(state.watched, 2, "Memory off preserves ordinary auto-watch")
equal(activeReturnTimers(), 0, "Memory off never schedules a return")
boot(nil, true, false)
saveFavorite()
addon.RepWatch_HandleFactionChangeMessage("Reputation with Stormwind increased by 10.")
advance(15)
equal(state.watched, 1, "Memory alone does not enable auto-watch")
boot(nil)
saveFavorite()
for i = 1, 50 do gain(2, 1) end
equal(activeReturnTimers(), 1, "Fifty gains allocate one active return timer")
advance(11)
equal(state.watched, 1, "Burst completes without a callback loop")
boot(nil)
saveFavorite()
gain(2, 25)
advance(0.3)
state.panelOpen, state.panelParentHidden = true, true
advance(11)
equal(state.watched, 1, "A shown Reputation child of a hidden CharacterFrame does not block return")
boot(nil)
saveFavorite()
gain(2, 25)
advance(0.3)
state.collectionsOpen, state.collectionsParentHidden = true, true
advance(11)
equal(state.watched, 1, "A shown wardrobe child of a hidden Collections frame does not block return")
for _, frameName in ipairs({ "ReputationFrame", "WardrobeFrame", "WardrobeCollectionFrame", "CollectionsJournal" }) do
    boot(nil)
    saveFavorite()
    local previous = _G[frameName]
    _G[frameName] = { IsShown = function() return true end, IsVisible = function() return false end }
    gain(2, 25)
    advance(11)
    equal(state.watched, 1, "An already hidden " .. frameName .. " does not block auto-watch or return")
    _G[frameName] = previous
end
boot(nil)
saveFavorite()
ReputationFrame.IsVisible = nil
gain(2, 25)
advance(0.3)
state.panelOpen = true
advance(11)
equal(state.watched, 2, "Older frame API falls back to IsShown and still protects an open panel")
-- Retail may publish the watched faction after the setter has returned. The
-- immediate read still sees the old faction; the later event is our own change.
local function delayedSetter(withEvent)
    C_Reputation.SetWatchedFactionByIndex = nil
    C_Reputation.SetWatchedFactionByID = function(id)
        addTimer(0.1, function()
            state.watched, state.writes = id, state.writes + 1
            if withEvent then updateFaction() end
        end, false)
    end
end
boot(nil)
saveFavorite()
delayedSetter(true)
gain(2, 25)
advance(0.11)
equal(state.watched, 2, "Delayed gain faction is confirmed")
assert(SQOL_CharacterDB.pendingReturn, "Delayed confirmation starts a persisted return")
advance(10.5)
equal(state.watched, 1, "Delayed setters also restore the preferred faction")
equal(activeReturnTimers(), 0, "Delayed restore leaves no repeating return timer")
boot(nil)
saveFavorite()
delayedSetter(true)
gain(2, 25)
advance(0.11)
choose(3)
advance(15)
equal(state.watched, 3, "External choice after delayed confirmation still cancels")
boot(nil)
saveFavorite()
delayedSetter(true)
gain(2, 25)
choose(3)
advance(15)
-- The already submitted client setter can still finish, but SQOL must not
-- interpret its late completion as permission to return to the preferred bar.
equal(state.watched, 2, "External choice cancels the return even before acknowledgement")
equal(SQOL_CharacterDB.pendingReturn, nil, "Cancelled request cannot arm a late return")
boot(nil)
saveFavorite()
delayedSetter(true)
gain(2, 25)
addon.DB.RepMemory = false
addon.RepMemory_OnOptionChanged()
advance(15)
equal(state.watched, 2, "Disabling memory cancels unconfirmed returns")
equal(SQOL_CharacterDB.pendingReturn, nil, "No persisted return after disable")
boot(nil)
saveFavorite()
delayedSetter(false)
gain(2, 25)
advance(12.5)
equal(state.watched, 1, "Bounded confirmation check handles a missing update event")
boot(nil)
saveFavorite()
C_Reputation.SetWatchedFactionByIndex = nil
C_Reputation.SetWatchedFactionByID = function() end
gain(2, 25)
advance(15)
equal(state.watched, 1, "Silent rejected setter never invents a switch")
equal(activeReturnTimers(), 0, "Rejected setter leaves no repeating return timer")
equal(SQOL_CharacterDB.pendingReturn, nil, "Rejected setter leaves no persisted return")
io.write("PASS: reputation memory deadlines, bursts, manual changes, reload, characters, panel visibility, delayed acknowledgements, secrets and API fallbacks\n")
