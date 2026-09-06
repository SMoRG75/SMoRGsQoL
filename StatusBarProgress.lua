-- Color the current value and append reputation progress/status. Let Blizzard
-- calculate renown, friendship, paragon and capped values and own bar visuals.
local _, SQOL = ...
local hooked = {}

local function IsReadable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function GetReputationStatus()
    local data = C_Reputation and C_Reputation.GetWatchedFactionData
        and C_Reputation.GetWatchedFactionData()
    if not data then return nil end
    local factionID = data.factionID
    if not IsReadable(factionID) then return nil end
    if factionID and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then
        local major = C_MajorFactions and C_MajorFactions.GetMajorFactionData(factionID)
        if major and IsReadable(major.renownLevel) and type(major.renownLevel) == "number" then
            return (RENOWN or "Renown") .. " " .. major.renownLevel
        end
        return nil
    end
    local friendship = factionID and C_GossipInfo and C_GossipInfo.GetFriendshipReputation
        and C_GossipInfo.GetFriendshipReputation(factionID)
    if friendship and IsReadable(friendship.friendshipFactionID)
        and type(friendship.friendshipFactionID) == "number" and friendship.friendshipFactionID > 0 then
        return IsReadable(friendship.reaction) and friendship.reaction or nil
    end
    if IsReadable(data.reaction) and type(data.reaction) == "number" then
        return _G["FACTION_STANDING_LABEL" .. data.reaction]
    end
end

local function Apply(bar, text)
    local state = hooked[bar]
    local fs = bar.OverlayFrame and bar.OverlayFrame.Text
    if not state or not fs or not IsReadable(text) or type(text) ~= "string" then return end
    state.text = text
    if not SQOL.DB or not SQOL.DB.ColorStatusBarProgress then
        if state.font then
            fs:SetFont(state.font, state.size, state.flags)
            state.font = nil
        end
        fs:SetText(text)
        return
    end

    -- Match the trailing numeric pair, so digits in faction names are untouched.
    -- Capped bars with only a label have no pair and retain their original text.
    local prefix, current, separator, maximum, suffix = text:match("^(.-)(%d+)(%s*/%s*)(%d+)(.-)$")
    local value, total = tonumber(current), tonumber(maximum)
    if not value or not total or total <= 0 then return end
    if state.isReputation then
        local remaining = 100 * (1 - SQOL.clamp01(value / total))
        suffix = suffix .. string.format(" · %.1f%% left", remaining)
        local status = GetReputationStatus()
        if type(status) == "string" and status ~= "" then
            suffix = suffix .. " · " .. status
        end
    end
    if not state.font then
        state.font, state.size, state.flags = fs:GetFont()
    end
    if state.font then
        local flags = state.flags or ""
        if not flags:find("OUTLINE", 1, true) then
            flags = flags == "" and "OUTLINE" or flags .. ",OUTLINE"
        end
        fs:SetFont(state.font, state.size, flags)
    end
    fs:SetText("|cffffffff" .. prefix .. SQOL.GetProgressColor(value / total)
        .. current .. "|cffffffff" .. separator .. maximum .. suffix .. "|r")
end

local function Attach(bar, isReputation)
    if not bar or hooked[bar] or not bar.SetBarText then return end
    if bar.IsForbidden and bar:IsForbidden() then return end
    if not bar.OverlayFrame or not bar.OverlayFrame.Text then return end
    hooked[bar] = { isReputation = isReputation }
    hooksecurefunc(bar, "SetBarText", Apply)
    Apply(bar, bar.OverlayFrame.Text:GetText())
end

function SQOL.RefreshStatusBarProgress()
    local manager = StatusTrackingBarManager
    local enums = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if manager and enums then
        -- Current Retail has one set of bars per container; older layouts keep
        -- their bars directly on the manager.
        local function AttachBars(bars)
            if bars then
                Attach(bars[enums.Experience])
                Attach(bars[enums.Reputation], true)
            end
        end
        AttachBars(manager.bars)
        for _, container in ipairs(manager.barContainers or {}) do
            AttachBars(container.bars)
        end
    end
    for bar, state in pairs(hooked) do
        if state.text then Apply(bar, state.text) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    SQOL.RefreshStatusBarProgress()
end)
