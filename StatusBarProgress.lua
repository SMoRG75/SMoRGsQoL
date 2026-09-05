-- Color only the current value in Blizzard's XP/reputation text. Let Blizzard
-- calculate renown, friendship, paragon and capped values and own bar visuals.
local _, SQOL = ...
local hooked = {}

local function IsReadable(value)
    return not issecretvalue or not issecretvalue(value)
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

local function Attach(bar)
    if not bar or hooked[bar] or not bar.SetBarText then return end
    if bar.IsForbidden and bar:IsForbidden() then return end
    if not bar.OverlayFrame or not bar.OverlayFrame.Text then return end
    hooked[bar] = {}
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
                Attach(bars[enums.Reputation])
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
