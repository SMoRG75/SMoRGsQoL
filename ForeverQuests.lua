local _, SQOL = ...

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
-- and on the quest log's map pin. The star is a separate texture, so the
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

local function SQOL_CreateBadge(owner)
    local holder = CreateFrame("Frame", nil, owner)
    holder:SetSize(BADGE_SIZE, BADGE_SIZE)
    if holder.SetFrameLevel and owner.GetFrameLevel then
        -- Above the quest log's map pin, which is a sibling of the title button.
        holder:SetFrameLevel((owner:GetFrameLevel() or 0) + 20)
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
local function SQOL_SetBadge(owner, questID, anchor)
    if not owner then return end
    local badge = badges[owner]
    if not (SQOL_ForeverQuestsEnabled() and SQOL.IsNewForeverQuest(questID)) then
        if badge then badge:Hide() end
        return
    end
    badge = badge or SQOL_CreateBadge(owner)
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
-- Hooks and option
------------------------------------------------------------
local hooked = {}

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
end

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
end

-- The mixins are hooked as early as possible, before any gossip button exists.
SQOL_HookForeverQuests()
