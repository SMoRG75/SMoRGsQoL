------------------------------------------------------------
-- Adventure Recap: event-driven, per-character session totals.
-- Only QUEST_TURNED_IN counts a quest; ready objectives never do.
------------------------------------------------------------
local _, SQOL = ...
local L = SQOL.L
local initialized, clockStarted, recapDB, window, view
local recentLines, lineOrder = {}, {}
local refreshWindow

local function usableNumber(value)
    return SQOL.CanUseValue(value) and type(value) == "number"
        and value == value and value >= 0 and value < math.huge
end

local function now()
    return GetTime()
end

local function newSession()
    return { quests = 0, worldQuests = 0, reputation = 0, elapsed = 0,
        factions = {}, seenQuests = {} }
end

local function validSession(session)
    return type(session) == "table" and usableNumber(session.quests)
        and usableNumber(session.worldQuests) and session.worldQuests <= session.quests
        and usableNumber(session.reputation) and usableNumber(session.elapsed)
        and type(session.factions) == "table" and type(session.seenQuests) == "table"
end

local function checkpoint()
    if clockStarted then
        local timestamp = now()
        recapDB.current.elapsed = recapDB.current.elapsed + math.max(0, timestamp - clockStarted)
        clockStarted = timestamp
    end
end

local function tracking()
    return initialized and SQOL.DB and SQOL.DB.AdventureRecap and recapDB.current
end

local function changed()
    checkpoint()
    if refreshWindow then refreshWindow() end
end

function SQOL.Recap_EnteringWorld(_, isReloadingUI)
    -- Zone changes also fire this event. Only the first event after loading
    -- decides whether to resume the saved session or archive it.
    if initialized then return end
    initialized = true
    if type(SQOL_RecapDB) ~= "table" or SQOL_RecapDB.version ~= 1 then
        SQOL_RecapDB = { version = 1 }
    end
    recapDB = SQOL_RecapDB
    if not validSession(recapDB.current) then recapDB.current = nil end
    if not validSession(recapDB.last) then recapDB.last = nil end
    if isReloadingUI ~= true and recapDB.current then
        recapDB.last = recapDB.current
        -- The previous session needs totals, not its duplicate-event markers.
        recapDB.last.seenQuests = {}
        recapDB.current = nil
    end
    SQOL.Recap_OnOptionChanged()
end

function SQOL.Recap_OnOptionChanged()
    if not initialized then return end
    checkpoint()
    clockStarted = nil
    if SQOL.DB and SQOL.DB.AdventureRecap then
        recapDB.current = recapDB.current or newSession()
        clockStarted = now()
    end
    if refreshWindow then refreshWindow() end
end

function SQOL.Recap_Save()
    if initialized then checkpoint() end
end

function SQOL.Recap_QuestAccepted(questID)
    if not tracking() or not usableNumber(questID) or questID <= 0 then return end
    -- A newly accepted repeatable quest may be completed again this session.
    recapDB.current.seenQuests[questID] = nil
end

local function isWorldQuest(questID)
    local query = C_QuestLog and C_QuestLog.IsWorldQuest
    if type(query) ~= "function" then query = rawget(_G, "QuestUtils_IsQuestWorldQuest") end
    if type(query) ~= "function" then return nil end
    local ok, result = pcall(query, questID)
    if ok and SQOL.CanUseValue(result) and type(result) == "boolean" then return result end
end

function SQOL.Recap_QuestTurnedIn(questID)
    if not tracking() or not usableNumber(questID) or questID <= 0 then return end
    local session = recapDB.current
    if session.seenQuests[questID] then return end
    session.seenQuests[questID] = true
    session.quests = session.quests + 1
    local world = isWorldQuest(questID)
    if world == true then
        session.worldQuests = session.worldQuests + 1
    elseif world == nil then
        session.worldQuestsIncomplete = true
    end
    changed()
end

function SQOL.Recap_ReputationMessage(message, lineID)
    if not tracking() then return end
    -- A chat line ID distinguishes duplicate deliveries from two legitimate
    -- identical gains. Keep only a small in-memory window of IDs.
    if usableNumber(lineID) and lineID > 0 then
        if recentLines[lineID] then return end
        recentLines[lineID] = true
        lineOrder[#lineOrder + 1] = lineID
        if #lineOrder > 128 then recentLines[table.remove(lineOrder, 1)] = nil end
    end
    local session = recapDB.current
    if not SQOL.CanUseValue(message) or type(message) ~= "string" then
        session.reputationIncomplete = true
        changed()
        return
    end
    local ok, name, amount, increased = pcall(SQOL.Rep_ParseMessage, message)
    if not ok or not SQOL.CanUseValue(name) or not SQOL.CanUseValue(amount)
        or not SQOL.CanUseValue(increased) then
        session.reputationIncomplete = true
    elseif increased == false then
        return -- This counter records gains, not net reputation.
    elseif increased ~= true or type(name) ~= "string" or name == ""
        or not usableNumber(amount) then
        session.reputationIncomplete = true
    elseif amount > 0 then
        session.reputation = session.reputation + amount
        local previous = session.factions[name]
        session.factions[name] = (usableNumber(previous) and previous or 0) + amount
    end
    changed()
end

-- Returns a detached summary so previews and callers cannot mutate saved data.
function SQOL.Recap_GetSummary(previous)
    if not initialized then return nil end
    local session = previous and recapDB.last or (not previous and recapDB.current)
    if not session then return nil end
    local elapsed = session.elapsed
    if not previous and clockStarted then elapsed = elapsed + math.max(0, now() - clockStarted) end
    local topName, topAmount
    if not session.reputationIncomplete then
        for name, amount in pairs(session.factions) do
            if type(name) == "string" and usableNumber(amount) and amount > 0
                and (not topAmount or amount > topAmount or (amount == topAmount and name < topName)) then
                topName, topAmount = name, amount
            end
        end
    end
    return { quests = session.quests, worldQuests = session.worldQuests,
        reputation = session.reputation, elapsed = elapsed,
        reputationIncomplete = session.reputationIncomplete,
        worldQuestsIncomplete = session.worldQuestsIncomplete,
        topFaction = topName, topAmount = topAmount }
end

local function duration(seconds)
    local minutes = math.floor(seconds / 60)
    return string.format(L["%dh %dm"], math.floor(minutes / 60), minutes % 60)
end

local function number(value)
    if type(BreakUpLargeNumbers) == "function" then return BreakUpLargeNumbers(value) end
    return string.format("%.0f", value)
end

local function text(parent, template, x, y, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY", template)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetSize(width, height)
    label:SetJustifyH("LEFT")
    return label
end

local function button(parent, label, x, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 16)
    control:SetSize(144, 26)
    control:SetText(label)
    control:SetScript("OnClick", callback)
    return control
end

local function createWindow()
    local frame = CreateFrame("Frame", "SQOL_AdventureRecap", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(500, 472)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0.025, 0.045, 0.04, 0.97)
    frame:SetBackdropBorderColor(0.28, 0.60, 0.43, 1)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        recapDB.position = { point, relativePoint, x, y }
    end)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    local title = text(frame, "GameFontNormalLarge", 24, -22, 440, 28)
    title:SetText(L["Your Adventure"])
    frame.subtitle = text(frame, "GameFontHighlightSmall", 24, -54, 452, 32)
    frame.values = {}
    local labels = { L["Quests completed"], L["World quests (included)"],
        L["Reputation gained"], L["Session time"] }
    for i, label in ipairs(labels) do
        local x = 24 + ((i - 1) % 2) * 232
        local y = -98 - math.floor((i - 1) / 2) * 90
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        background:SetSize(220, 78)
        background:SetColorTexture(0.10, 0.22, 0.16, 0.7)
        local caption = text(frame, "GameFontHighlightSmall", x + 12, y - 10, 196, 24)
        caption:SetText(label)
        local value = text(frame, "GameFontNormalLarge", x + 12, y - 38, 196, 28)
        value:SetTextColor(0.45, 1, 0.66)
        frame.values[i] = value
    end
    frame.highlights = text(frame, "GameFontHighlight", 24, -286, 452, 60)
    frame.notice = text(frame, "GameFontHighlightSmall", 24, -354, 452, 66)
    frame.notice:SetTextColor(0.85, 0.80, 0.65)
    button(frame, L["Current session"], 24, function() SQOL.Recap_Command("") end)
    button(frame, L["Previous session"], 178, function() SQOL.Recap_Command("last") end)
    button(frame, L["Preview"], 332, function() SQOL.Recap_Command("test") end)
    -- Update the clock once per second only while the live recap is visible.
    -- Tracking itself has no timers or OnUpdate handler.
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.refreshElapsed = (self.refreshElapsed or 0) + elapsed
        if self.refreshElapsed >= 1 then
            self.refreshElapsed = 0
            if view == "current" then refreshWindow() end
        end
    end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "SQOL_AdventureRecap")
    end
    return frame
end

refreshWindow = function()
    if not window or not window:IsShown() then return end
    local summary
    local mode = L["Current session"]
    if view == "test" then
        summary = { quests = 18, worldQuests = 4, reputation = 2450, elapsed = 8100,
            topFaction = "The Nightfallen", topAmount = 1800 }
        mode = L["Preview — sample data"]
    else
        summary = SQOL.Recap_GetSummary(view == "last")
        if view == "last" then mode = L["Previous session"] end
    end
    window.subtitle:SetText("SMoRG's QoL · " .. L["Adventure Recap"] .. "\n" .. mode)
    if not summary then
        for _, value in ipairs(window.values) do value:SetText("—") end
        window.highlights:SetText(view == "last" and L["No previous session recorded."]
            or L["Enable Adventure Recap to start recording this character's session."])
        window.notice:SetText("")
        return
    end
    window.values[1]:SetText(number(summary.quests))
    window.values[2]:SetText(number(summary.worldQuests) .. (summary.worldQuestsIncomplete and "+" or ""))
    window.values[3]:SetText("+" .. number(summary.reputation) .. (summary.reputationIncomplete and "*" or ""))
    window.values[4]:SetText(duration(summary.elapsed))
    local highlights = { string.format(L["%d quests completed this session."], summary.quests) }
    if summary.topFaction then
        highlights[#highlights + 1] = string.format(L["Most active faction: %s (+%d)"], summary.topFaction, summary.topAmount)
    end
    window.highlights:SetText(table.concat(highlights, "\n"))
    local notices = {}
    if view == "current" and not tracking() then notices[#notices + 1] = L["Recording paused."] end
    if summary.reputationIncomplete then
        notices[#notices + 1] = L["* Recorded reputation only; some gains could not be read."]
    end
    if summary.worldQuestsIncomplete then
        notices[#notices + 1] = L["World quest count is a minimum; some quest types could not be identified."]
    end
    window.notice:SetText(table.concat(notices, "\n"))
end

local function showWindow(mode)
    if not initialized then return end
    view = mode
    if not window then window = createWindow() end
    if not window:IsShown() then
        window:ClearAllPoints()
        local pos = recapDB.position
        local points = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
            TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
        if type(pos) == "table" and points[pos[1]] and points[pos[2]]
            and type(pos[3]) == "number" and type(pos[4]) == "number" then
            window:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        end
        window:Show()
    end
    refreshWindow()
end

function SQOL.Recap_Command(command)
    if command == "" or command == "last" or command == "test" then
        showWindow(command == "" and "current" or command)
    elseif command == "reset" then
        if not initialized then return end
        recapDB.current = SQOL.DB.AdventureRecap and newSession() or nil
        clockStarted = recapDB.current and now() or nil
        print("|cff33ff99SQoL:|r " .. L["Current Adventure Recap reset."])
        if refreshWindow then refreshWindow() end
    else
        print("|cff33ff99SQoL:|r /sqol recap [last | reset | test]")
    end
end
