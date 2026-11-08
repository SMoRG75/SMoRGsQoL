local _, SQOL = ...
local L = SQOL.L

------------------------------------------------------------
-- New WoW Forever quests
-- WoW Forever keeps the original quests under their old IDs (well below
-- 30000), while the quests written for Forever were numbered from the same
-- pool as Retail at the time (The Great Outdoors 96606, Reading Room 97234).
-- A quest from SQOL_FOREVER_NEW_QUEST_MIN_ID up counts as new. The bound
-- sits above every older quest Forever might reuse (revamped holiday quests
-- and the like) and below anything made while Forever was in development.
--
-- New quests get a small blue star on their quest icon: in the NPC's quest
-- list (gossip and greeting windows), next to the title of the quest text,
-- on the quest log's map pin and on the world map's "!" pins of quests you
-- can pick up, whose tooltips also say "New in WoW Forever". (The "!" above
-- the quest giver in the game world is drawn by the game engine; addons
-- can't change it.) The star is a separate texture, so the
-- titles and Blizzard's layouts (which measure the title text) stay as they
-- are. The Retail and Classic clients never show it.
------------------------------------------------------------
local SQOL_FOREVER_NEW_QUEST_MIN_ID = 80000
SQOL.FOREVER_NEW_QUEST_MIN_ID = SQOL_FOREVER_NEW_QUEST_MIN_ID

local BADGE_SIZE = 12
local BADGE_ATLAS = "PetJournal-FavoritesIcon"
local BADGE_FILE = "Interface\\Common\\FavoritesIcon"

-- True for a quest that was added in WoW Forever.
function SQOL.IsNewForeverQuest(questID)
    if not SQOL.CanUseValue(questID) then return false end
    questID = tonumber(questID)
    return questID ~= nil and questID >= SQOL_FOREVER_NEW_QUEST_MIN_ID
end

local function SQOL_ForeverQuestsEnabled()
    return SQOL.IsForever and SQOL.DB and SQOL.DB.MarkForeverQuests and true or false
end

-- Badges are kept here instead of on Blizzard's frames, so their tables get
-- no addon-written keys.
local badges = setmetatable({}, { __mode = "k" })

local function SQOL_CreateBadge(owner, size, levelOffset)
    local holder = CreateFrame("Frame", nil, owner)
    holder:SetSize(size or BADGE_SIZE, size or BADGE_SIZE)
    if holder.SetFrameLevel and owner.GetFrameLevel then
        -- Above the quest log's map pin, which is a sibling of the title button.
        holder:SetFrameLevel((owner:GetFrameLevel() or 0) + (levelOffset or 20))
    end
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(holder)
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BADGE_ATLAS)
    if atlasInfo and tex.SetAtlas then
        tex:SetAtlas(BADGE_ATLAS)
    else
        tex:SetTexture(BADGE_FILE)
    end
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    tex:SetVertexColor(0.35, 0.85, 1)
    holder:Hide()
    badges[owner] = holder
    return holder
end

-- Shows the star on owner for a new quest (anchor sets its position) and
-- hides it for any other quest, or when the option is off.
local function SQOL_SetBadge(owner, questID, anchor, size, levelOffset)
    if not owner then return end
    local badge = badges[owner]
    if not (SQOL_ForeverQuestsEnabled() and SQOL.IsNewForeverQuest(questID)) then
        if badge then badge:Hide() end
        return
    end
    badge = badge or SQOL_CreateBadge(owner, size, levelOffset)
    badge:ClearAllPoints()
    anchor(badge)
    badge:Show()
end

-- Top right corner of a quest list button's "!" / "?" icon.
local function SQOL_BadgeOnIcon(button, questID)
    local icon = button and button.Icon
    if not icon then return end
    SQOL_SetBadge(button, questID, function(badge)
        badge:SetPoint("CENTER", icon, "TOPRIGHT", -2, -2)
    end)
end

------------------------------------------------------------
-- Gossip window (quest givers with gossip options)
------------------------------------------------------------
local function SQOL_GossipButtonQuestID(button)
    if type(button.GetElementData) ~= "function" then return nil end
    local ok, data = pcall(button.GetElementData, button)
    if not ok or type(data) ~= "table" or type(data.info) ~= "table" then return nil end
    local buttonType = data.buttonType
    if buttonType ~= rawget(_G, "GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST")
        and buttonType ~= rawget(_G, "GOSSIP_BUTTON_TYPE_ACTIVE_QUEST") then
        return nil
    end
    return data.info.questID
end

local function SQOL_UpdateGossip()
    local gossip = rawget(_G, "GossipFrame")
    local scrollBox = gossip and gossip.GreetingPanel and gossip.GreetingPanel.ScrollBox
    if not scrollBox or type(scrollBox.GetFrames) ~= "function" then return end
    for _, button in ipairs(scrollBox:GetFrames() or {}) do
        local questID = SQOL_GossipButtonQuestID(button)
        if questID or badges[button] then
            SQOL_BadgeOnIcon(button, questID)
        end
    end
end

------------------------------------------------------------
-- Quest greeting window (quest givers without gossip)
------------------------------------------------------------
local function SQOL_UpdateGreeting()
    local panel = rawget(_G, "QuestFrameGreetingPanel")
    local pool = panel and panel.titleButtonPool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    for button in pool:EnumerateActive() do
        local id, questID = button:GetID(), nil
        if button.isActive == 1 then
            if type(GetActiveQuestID) == "function" then
                questID = GetActiveQuestID(id)
            end
        elseif type(GetAvailableQuestInfo) == "function" then
            questID = select(5, GetAvailableQuestInfo(id))
        end
        SQOL_BadgeOnIcon(button, questID)
    end
end

------------------------------------------------------------
-- Quest text (offered quests, and the quest log's details)
------------------------------------------------------------
local function SQOL_UpdateQuestInfo()
    local header = rawget(_G, "QuestInfoTitleHeader")
    local infoFrame = rawget(_G, "QuestInfoFrame")
    if not header or not infoFrame then return end

    local questID
    if infoFrame.questLog then
        questID = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    elseif type(GetQuestID) == "function" then
        questID = GetQuestID()
    end
    if not header:IsShown() then questID = nil end

    SQOL_SetBadge(infoFrame, questID, function(badge)
        -- After the last letter of a one-line title, else past its right edge.
        local textWidth = header:GetStringWidth() or 0
        local boxWidth = header:GetWidth() or 0
        if textWidth > 0 and textWidth < boxWidth then
            badge:SetPoint("LEFT", header, "TOPLEFT", textWidth + 4, -(BADGE_SIZE / 2) - 1)
        else
            badge:SetPoint("TOPLEFT", header, "TOPRIGHT", 2, 0)
        end
    end)
end

------------------------------------------------------------
-- Quest log (world map side panel)
------------------------------------------------------------
local function SQOL_UpdateQuestLog()
    local scroll = rawget(_G, "QuestScrollFrame")
    local pool = scroll and scroll.titleFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    for button in pool:EnumerateActive() do
        SQOL_SetBadge(button, button.questID, function(badge)
            -- The map pin sits at TOPLEFT (6, -4); the star goes on its top right corner.
            badge:SetPoint("CENTER", button, "TOPLEFT", 24, -5)
        end)
    end
end

------------------------------------------------------------
-- World map: the "!" pins of quests you can pick up
------------------------------------------------------------
local function SQOL_BadgeOnMapPin(pin, questID)
    local icon = pin and pin.Texture
    if not icon then return end
    SQOL_SetBadge(pin, questID, function(badge)
        badge:SetPoint("CENTER", icon, "TOPRIGHT", -3, -3)
    end, 10, 1)
end

-- Pins of quests in your quest log (the "..." and "?" buttons).
local function SQOL_BadgeOnQuestPin(pin)
    local questID = pin.questID
    if type(pin.GetQuestID) == "function" then
        local ok, id = pcall(pin.GetQuestID, pin)
        if ok then questID = id end
    end
    local icon = pin.Display or pin
    SQOL_SetBadge(pin, questID, function(badge)
        badge:SetPoint("CENTER", icon, "TOPRIGHT", -4, -4)
    end, 10, 1)
end

local function SQOL_UpdateQuestPins()
    local map = rawget(_G, "WorldMapFrame")
    if not map or type(map.EnumeratePinsByTemplate) ~= "function" then return end
    for pin in map:EnumeratePinsByTemplate("QuestPinTemplate") do
        SQOL_BadgeOnQuestPin(pin)
    end
end

local function SQOL_UpdateMapPins()
    local map = rawget(_G, "WorldMapFrame")
    if not map or type(map.EnumeratePinsByTemplate) ~= "function" then return end
    for pin in map:EnumeratePinsByTemplate("QuestOfferPinTemplate") do
        SQOL_BadgeOnMapPin(pin, pin.questID)
    end
    SQOL_UpdateQuestPins()
end

-- Blizzard's map quest tooltips announce themselves, quest offers with
-- TaskPOI.TooltipShown (poi, questID) and your quests with
-- MapCanvas.QuestPin.OnEnter (pin, questID); a new quest gets a line.
local function SQOL_OnMapTooltipShown(_, _, questID)
    if not (SQOL_ForeverQuestsEnabled() and SQOL.IsNewForeverQuest(questID)) then return end
    local tooltip = rawget(_G, "GameTooltip")
    if not tooltip or not tooltip:IsShown() then return end
    tooltip:AddLine(L["New in WoW Forever"], 0.35, 0.85, 1)
    tooltip:Show()
end

------------------------------------------------------------
-- Objective tracker: the "..." and "?" buttons before quest titles
------------------------------------------------------------
-- Blocks add their button in OnLayout while the module lays out, so the
-- stars are set once the module's EndLayout has run. Only reads the blocks;
-- nothing here asks the tracker to update (that would taint it).
local SQOL_TRACKER_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

local function SQOL_UpdateTrackerModule(module)
    if type(module) ~= "table" or type(module.usedBlocks) ~= "table" then return end
    for _, blocks in pairs(module.usedBlocks) do
        if type(blocks) == "table" then
            for _, block in pairs(blocks) do
                local button = type(block) == "table" and block.poiButton
                if button then
                    SQOL_SetBadge(button, block.poiQuestID or block.id, function(badge)
                        badge:SetPoint("CENTER", button, "TOPRIGHT", -4, -4)
                    end, 10, 1)
                end
            end
        end
    end
end

local function SQOL_UpdateTracker()
    for _, name in ipairs(SQOL_TRACKER_MODULES) do
        SQOL_UpdateTrackerModule(rawget(_G, name))
    end
end

------------------------------------------------------------
-- Hooks and option
------------------------------------------------------------
local hooked = {}
local questPinsPending = false

local function SQOL_HookForeverQuests()
    if not SQOL.IsForever then return end

    local gossip = rawget(_G, "GossipFrame")
    if not hooked.gossip and gossip and type(gossip.Update) == "function" then
        hooked.gossip = true
        hooksecurefunc(gossip, "Update", SQOL_UpdateGossip)
    end
    -- Buttons the gossip list reuses while scrolling run Setup without Update.
    -- Hooking the mixins works for the buttons created after this (all of
    -- them: the list makes its buttons the first time a quest giver opens).
    for _, name in ipairs({ "GossipAvailableQuestButtonMixin", "GossipActiveQuestButtonMixin" }) do
        local mixin = rawget(_G, name)
        if not hooked[name] and type(mixin) == "table" and type(mixin.Setup) == "function" then
            hooked[name] = true
            hooksecurefunc(mixin, "Setup", function(button, questInfo)
                SQOL_BadgeOnIcon(button, type(questInfo) == "table" and questInfo.questID or nil)
            end)
        end
    end

    local greeting = rawget(_G, "QuestFrameGreetingPanel")
    if not hooked.greeting and greeting and greeting.HookScript then
        hooked.greeting = true
        greeting:HookScript("OnShow", SQOL_UpdateGreeting)
    end

    if not hooked.questInfo and type(rawget(_G, "QuestInfo_Display")) == "function" then
        hooked.questInfo = true
        hooksecurefunc("QuestInfo_Display", SQOL_UpdateQuestInfo)
    end

    if not hooked.questLog and type(rawget(_G, "QuestLogQuests_Update")) == "function" then
        hooked.questLog = true
        hooksecurefunc("QuestLogQuests_Update", SQOL_UpdateQuestLog)
    end

    -- The world map may load on demand. Every pin, new or reused from the
    -- pool, goes through the map's AcquirePin; the hook can't see the pin it
    -- returns, so it looks the pin up by the quest it was given.
    local map = rawget(_G, "WorldMapFrame")
    if not hooked.mapPins and type(map) == "table" and type(map.AcquirePin) == "function"
        and type(map.EnumeratePinsByTemplate) == "function" then
        hooked.mapPins = true
        hooksecurefunc(map, "AcquirePin", function(self, template, questOffer)
            if template == "QuestPinTemplate" then
                -- Your quests' pins get their quest right after AcquirePin;
                -- star them all once the map has placed them, next frame.
                if not questPinsPending and SQOL_ForeverQuestsEnabled() then
                    questPinsPending = true
                    C_Timer.After(0, function()
                        questPinsPending = false
                        SQOL_UpdateQuestPins()
                    end)
                end
                return
            end
            if template ~= "QuestOfferPinTemplate" or type(questOffer) ~= "table" then return end
            for pin in self:EnumeratePinsByTemplate(template) do
                if pin.questID == questOffer.questID then
                    SQOL_BadgeOnMapPin(pin, pin.questID)
                end
            end
        end)
    end

    for _, name in ipairs(SQOL_TRACKER_MODULES) do
        local module = rawget(_G, name)
        if not hooked[name] and type(module) == "table" and type(module.EndLayout) == "function" then
            hooked[name] = true
            hooksecurefunc(module, "EndLayout", SQOL_UpdateTrackerModule)
        end
    end

    local registry = rawget(_G, "EventRegistry")
    if not hooked.mapTooltip and type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        hooked.mapTooltip = true
        registry:RegisterCallback("TaskPOI.TooltipShown", SQOL_OnMapTooltipShown, hooked)
        registry:RegisterCallback("MapCanvas.QuestPin.OnEnter", SQOL_OnMapTooltipShown, hooked)
    end
end

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(_, _, addonName)
    if addonName == "Blizzard_SharedMapDataProviders" or addonName == "Blizzard_WorldMap"
        or addonName == "Blizzard_ObjectiveTracker" then
        SQOL_HookForeverQuests()
    end
end)

-- Hooks are installed either way (they hide the stars while the option is
-- off); refreshing redraws what is on screen now.
function SQOL.ForeverQuests_OnOptionChanged()
    SQOL_HookForeverQuests()
    if not SQOL.IsForever then return end
    if not SQOL_ForeverQuestsEnabled() then
        for _, badge in pairs(badges) do badge:Hide() end
        return
    end
    SQOL_UpdateGossip()
    SQOL_UpdateGreeting()
    local infoFrame = rawget(_G, "QuestInfoFrame")
    if infoFrame and infoFrame.IsVisible and infoFrame:IsVisible() then
        SQOL_UpdateQuestInfo()
    end
    SQOL_UpdateQuestLog()
    SQOL_UpdateMapPins()
    SQOL_UpdateTracker()
end

-- The mixins are hooked as early as possible, before any gossip button exists.
SQOL_HookForeverQuests()
