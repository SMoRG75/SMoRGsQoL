local ADDON_NAME, SQOL = ...
local L = SQOL.L

------------------------------------------------------------
-- Wowhead links
-- Like Leatrix Plus' "Show Wowhead links": a selectable Wowhead link for
-- the quest in the quest log (on the world map in Retail and WoW Forever,
-- in the quest log window in Classic) and for the selected achievement.
-- Hover the link and press CTRL+C to copy it.
--
-- The "Show web link" key binding (Bindings.xml, no default key) works
-- with or without the option, like Leatrix Plus' binding. It pops up a
-- copyable link for what the mouse is over: an item, spell, aura, quest,
-- achievement or currency, an NPC, a battle pet, a player's armory page
-- (Retail), or else a Wowhead search for the tooltip's first line.
------------------------------------------------------------

-- Wowhead's language codes by client locale; English has none.
local SQOL_WOWHEAD_LANGUAGES = {
    deDE = "de", esES = "es", esMX = "mx", frFR = "fr", itIT = "it",
    ptBR = "pt", ruRU = "ru", koKR = "ko", zhCN = "cn", zhTW = "tw",
}

-- Leatrix Plus' armory pages fix these realm names by hand; the rest
-- follow the rules in SQOL_RealmSlug.
local SQOL_REALM_SLUGS = {
    Area52 = "Area-52",
    ["Chantséternels"] = "Chants-Éternels",
    ["ConfrérieduThorium"] = "Confrérie-du-Thorium",
    ConseildesOmbres = "Conseil-des-Ombres",
    CultedelaRivenoire = "Culte-de-la-Rive-noire",
    DerRatvonDalaran = "Der-Rat-von-Dalaran",
    DieewigeWacht = "Die-ewige-Wacht",
    ["FestungderStürme"] = "Festung-der-Stürme",
    KultderVerdammten = "Kult-der-Verdammten",
    ["LaCroisadeécarlate"] = "La-Croisade-Écarlate",
    ["MarécagedeZangar"] = "Marécage-de-Zangar",
    ["Pozzodell'Eternità"] = "Pozzo-dellEternità",
    Templenoir = "Temple-noir",
    VanCleef = "Vancleef",
    ZirkeldesCenarius = "Zirkel-des-Cenarius",
    ["СвежевательДуш"] = "Свежеватель-Душ",
    ["СтражСмерти"] = "Страж-Смерти",
    ["Ревущийфьорд"] = "Ревущий-фьорд",
    ["ТкачСмерти"] = "Ткач-Смерти",
    ["Борейскаятундра"] = "Борейская-тундра",
    ["Ясеневыйлес"] = "Ясеневый-лес",
    ["ПиратскаяБухта"] = "Пиратская-Бухта",
    ["ВечнаяПесня"] = "Вечная-Песня",
    ["ЧерныйШрам"] = "Черный-Шрам",
    ["ВестникРока"] = "Вестник-Рока",
}

-- worldofwarcraft.com language paths; English in Europe is en-gb.
local SQOL_ARMORY_LANGUAGES = {
    deDE = "de-de", esES = "es-es", esMX = "es-mx", frFR = "fr-fr", itIT = "it-it",
    ptBR = "pt-br", ruRU = "ru-ru", koKR = "ko-kr", zhTW = "zh-tw",
}
local SQOL_ARMORY_REGIONS = { "us", "kr", "eu", "tw" } -- by GetCurrentRegion()

-- Tooltip data types (Enum.TooltipDataType, the same in every client).
local SQOL_TOOLTIP_KINDS = {
    [0] = "item", [1] = "spell", [5] = "currency", [7] = "spell",
    [12] = "achievement", [19] = "item", [23] = "quest",
}

-- Hyperlink types that Wowhead has pages for.
local SQOL_LINK_KINDS = {
    item = "item", spell = "spell", enchant = "spell", quest = "quest",
    achievement = "achievement", currency = "currency",
}

local mapBox, achievementBox
local mapHooked, achievementHooked = false, false
local tooltipRecords = {}
local eventFrame = CreateFrame("Frame")

------------------------------------------------------------
-- URLs
------------------------------------------------------------

-- Retail uses a language subdomain (de.wowhead.com). The other clients
-- have their own section with the language after it (wowhead.com/classic/de).
function SQOL.WowheadBase()
    local language = SQOL_WOWHEAD_LANGUAGES[SQOL.Locale]
    local section
    if SQOL.IsForever then
        section = "forever"
    elseif SQOL.IsClassicEra then
        section = "classic"
    elseif SQOL.IsClassicTBC then
        section = "tbc"
    elseif SQOL.IsClassic then
        section = "mop-classic" -- the only other Classic client so far
    end
    if not section then
        return "https://" .. (language and language .. "." or "") .. "wowhead.com"
    end
    if language == "mx" then language = "es" end
    return "https://wowhead.com/" .. section .. (language and "/" .. language or "")
end

function SQOL.WowheadURL(kind, id)
    return SQOL.WowheadBase() .. "/" .. kind .. "=" .. tostring(id)
end

local function SQOL_URLEncode(text)
    return (text:gsub("[^%w%-%._~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

local function SQOL_StripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- A plain number or numeric string from an API, or nil (secret values too).
local function SQOL_ID(value)
    if value == nil or not SQOL.CanUseValue(value) then return nil end
    local id = tonumber(value)
    if id and id > 0 then return id end
end

local function SQOL_Text(value)
    if type(value) == "string" and SQOL.CanUseValue(value) and value ~= "" then
        return value
    end
end

local function SQOL_Returns(ok, ...)
    if ok then return ... end
end

-- Calls an API that may be missing or may error; returns nothing then.
local function SQOL_Call(fn, ...)
    if type(fn) ~= "function" then return end
    return SQOL_Returns(pcall(fn, ...))
end

------------------------------------------------------------
-- Link boxes (quest log and achievements)
------------------------------------------------------------
local function SQOL_LinkBox_OnEnter(self)
    self:HighlightText()
    self:SetFocus()
    if self.title and GameTooltip then
        GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_TOP", 0, 10)
        GameTooltip:SetText(self.title .. "|n" .. L["Press CTRL+C to copy."], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end
end

local function SQOL_LinkBox_OnLeave(self)
    self:HighlightText(0, 0)
    self:ClearFocus()
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
        GameTooltip:Hide()
    end
end

-- The text can be selected and copied but not changed.
local function SQOL_LinkBox_OnTextChanged(self, userInput)
    if userInput and self.url then
        self:SetText(self.url)
        self:HighlightText()
    end
end

local function SQOL_CreateLinkBox(parent, fontObject)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(16)
    box:SetFontObject(fontObject)
    box:SetAutoFocus(false)
    box:SetBlinkSpeed(0)
    -- The box has focus only while the mouse is over it, and then needs the
    -- keyboard: without it CTRL+C reaches the game's key bindings (C opens
    -- the character window, seen in Retail).
    box:EnableKeyboard(true)
    box:SetScript("OnEnter", SQOL_LinkBox_OnEnter)
    box:SetScript("OnLeave", SQOL_LinkBox_OnLeave)
    box:SetScript("OnTextChanged", SQOL_LinkBox_OnTextChanged)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box.measure = box:CreateFontString(nil, "ARTWORK", fontObject)
    box.measure:Hide()
    box:Hide()
    return box
end

-- Shows the URL for kind=id, or hides the box when there is nothing to link.
local function SQOL_LinkBox_Set(box, kind, id, title)
    if not box then return end
    id = SQOL_ID(id)
    if not (SQOL.DB and SQOL.DB.ShowWowheadLinks and id) then
        box.url = nil
        box:Hide()
        if box.OnHidden then box.OnHidden() end
        return
    end
    box.url = SQOL.WowheadURL(kind, id)
    box.title = SQOL_Text(title)
    box:SetText(box.url)
    box.measure:SetText(box.url)
    box:SetWidth(box.measure:GetStringWidth() + 10)
    box:Show()
    if box.OnShown then box.OnShown() end
end

------------------------------------------------------------
-- Quest log
------------------------------------------------------------
local function SQOL_QuestTitle(questID)
    local questLog = rawget(_G, "C_QuestLog")
    return questLog and SQOL_Call(questLog.GetTitleForQuestID, questID)
end

-- Retail and WoW Forever: the quest open in the world map's quest details,
-- or else the super-tracked quest.
local function SQOL_UpdateMapQuest()
    if not mapBox then return end
    local questID
    local questMap = rawget(_G, "QuestMapFrame")
    local details = questMap and questMap.DetailsFrame
    if details and details.IsShown and details:IsShown() then
        questID = SQOL_Call(rawget(_G, "QuestMapFrame_GetDetailQuestID"))
    end
    if not SQOL_ID(questID) then
        local superTrack = rawget(_G, "C_SuperTrack")
        questID = superTrack and SQOL_Call(superTrack.GetSuperTrackedQuestID)
    end
    SQOL_LinkBox_Set(mapBox, "quest", questID, SQOL_ID(questID) and SQOL_QuestTitle(questID))
end

-- Classic: the quest selected in the quest log window.
local function SQOL_UpdateQuestLogEntry(index)
    if not mapBox then return end
    index = index or SQOL_Call(rawget(_G, "GetQuestLogSelection"))
    local title, isHeader, questID
    if SQOL_ID(index) then
        local results = { SQOL_Call(rawget(_G, "GetQuestLogTitle"), index) }
        title, isHeader, questID = results[1], results[4], results[8]
    end
    if isHeader then questID = nil end
    SQOL_LinkBox_Set(mapBox, "quest", questID, title)
end

-- The link takes the place of the frame's title while it is shown.
local function SQOL_TitleSwap(title)
    return function() if title then title:Hide() end end,
        function() if title then title:Show() end end
end

local function SQOL_HookQuestLog()
    if mapHooked then return true end
    local worldMap = rawget(_G, "WorldMapFrame")
    local questLog = rawget(_G, "QuestLogFrame")

    if not SQOL.IsClassic and worldMap and type(rawget(_G, "QuestMapFrame_ShowQuestDetails")) == "function" then
        mapBox = SQOL_CreateLinkBox(worldMap.BorderFrame or worldMap, "GameFontNormal")
        mapBox:SetFrameLevel(501)
        mapBox:SetPoint("TOPLEFT", 100, -4)
        mapBox.tooltipAnchor = "ANCHOR_BOTTOM"
        local title = rawget(_G, "WorldMapFrameTitleText")
        mapBox.OnShown, mapBox.OnHidden = SQOL_TitleSwap(title)
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", SQOL_UpdateMapQuest)
        if type(rawget(_G, "QuestMapFrame_CloseQuestDetails")) == "function" then
            hooksecurefunc("QuestMapFrame_CloseQuestDetails", SQOL_UpdateMapQuest)
        end
        pcall(eventFrame.RegisterEvent, eventFrame, "SUPER_TRACKING_CHANGED")
        mapBox.Update = SQOL_UpdateMapQuest
    elseif questLog and type(rawget(_G, "SelectQuestLogEntry")) == "function" then
        mapBox = SQOL_CreateLinkBox(questLog, "GameFontNormal")
        mapBox.tooltipAnchor = "ANCHOR_BOTTOM"
        local title = rawget(_G, "QuestLogTitleText")
        if title then
            mapBox:SetPoint("CENTER", title, "CENTER", 0, 0)
        else
            mapBox:SetPoint("TOP", 0, -14)
        end
        mapBox.OnShown, mapBox.OnHidden = SQOL_TitleSwap(title)
        hooksecurefunc("SelectQuestLogEntry", SQOL_UpdateQuestLogEntry)
        questLog:HookScript("OnShow", function() SQOL_UpdateQuestLogEntry() end)
        mapBox.Update = function() SQOL_UpdateQuestLogEntry() end
    else
        return false
    end
    mapHooked = true
    return true
end

------------------------------------------------------------
-- Achievements
------------------------------------------------------------
local function SQOL_ShowAchievement(_, achievementID)
    local name = SQOL_ID(achievementID) and select(2, SQOL_Call(rawget(_G, "GetAchievementInfo"), achievementID))
    SQOL_LinkBox_Set(achievementBox, "achievement", achievementID, name)
end

local function SQOL_HideAchievement()
    SQOL_LinkBox_Set(achievementBox, "achievement", nil)
end

-- Retail and Forever share AchievementTemplateMixin; Mists Classic uses
-- the older AchievementButton_DisplayObjectives. Both run for the
-- achievement that is opened in the list.
local function SQOL_HookAchievements()
    if achievementHooked then return true end
    local frame = rawget(_G, "AchievementFrame")
    local mixin = rawget(_G, "AchievementTemplateMixin")
    local hasMixin = type(mixin) == "table" and type(mixin.DisplayObjectives) == "function"
    local hasButton = type(rawget(_G, "AchievementButton_DisplayObjectives")) == "function"
    if not frame or not (hasMixin or hasButton) then return false end

    achievementBox = SQOL_CreateLinkBox(frame, "GameFontNormalSmall")
    achievementBox:SetPoint("BOTTOMRIGHT", -50, 1)
    achievementBox:SetJustifyH("RIGHT")
    if hasMixin then
        hooksecurefunc(mixin, "DisplayObjectives", SQOL_ShowAchievement)
    else
        hooksecurefunc("AchievementButton_DisplayObjectives", SQOL_ShowAchievement)
    end
    for _, name in ipairs({ "AchievementFrameComparisonTab_OnClick", "AchievementFrameAchievements_ClearSelection" }) do
        if type(rawget(_G, name)) == "function" then
            hooksecurefunc(name, SQOL_HideAchievement)
        end
    end
    achievementHooked = true
    return true
end

------------------------------------------------------------
-- Option
------------------------------------------------------------
-- The hooks are installed whether the option is on or not (they hide the
-- boxes while it is off): achievement buttons copy the mixin's functions
-- when they are created, so a later hook would miss them until a reload.
function SQOL.WowheadLinks_OnOptionChanged()
    SQOL_HookQuestLog()
    SQOL_HookAchievements()
    if mapBox then
        mapBox.Update()
    end
    if not (SQOL.DB and SQOL.DB.ShowWowheadLinks) then
        SQOL_HideAchievement()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event)
    if not SQOL.DB then return end
    if event == "SUPER_TRACKING_CHANGED" then
        SQOL_UpdateMapQuest()
        return
    end
    -- Blizzard_AchievementUI (and in some clients the world map) load on demand.
    SQOL_HookAchievements()
    if not mapHooked and SQOL_HookQuestLog() then
        mapBox.Update()
    end
end)

------------------------------------------------------------
-- Copy popup
------------------------------------------------------------
local popup

local function SQOL_GetPopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "SQOL_WebLinkPopup", UIParent)
    popup:SetSize(700, 110)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    popup:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then self:Hide() end
    end)
    local background = popup:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    local box = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -12)
    box:SetSize(672, 24)
    box:SetFontObject("GameFontNormalLarge")
    box:SetTextColor(1, 1, 1, 1)
    box:SetBlinkSpeed(0)
    box:SetAutoFocus(true)
    box:SetScript("OnEscapePressed", function() popup:Hide() end)
    box:SetScript("OnEnterPressed", box.HighlightText)
    box:SetScript("OnMouseUp", box.HighlightText)
    box:SetScript("OnTextChanged", SQOL_LinkBox_OnTextChanged)
    -- Closes itself once the link has been copied.
    box:SetScript("OnKeyDown", function(_, key)
        local copy = type(IsControlKeyDown) == "function" and IsControlKeyDown()
            or type(IsMetaKeyDown) == "function" and IsMetaKeyDown()
        if key == "C" and copy then
            C_Timer.After(0.1, function() popup:Hide() end)
        end
    end)
    popup.box = box

    popup.label = popup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    popup.label:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -52)
    popup.label:SetWidth(676)
    popup.label:SetJustifyH("LEFT")
    popup.label:SetWordWrap(false)

    local copyHint = popup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    copyHint:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -82)
    copyHint:SetText(L["Press CTRL+C to copy."])
    local closeHint = popup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    closeHint:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -82)
    closeHint:SetText(L["Right-click to close."])

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "SQOL_WebLinkPopup")
    end
    return popup
end

function SQOL.WebLink_Show(url, label)
    local frame = SQOL_GetPopup()
    frame.box.url = url
    frame.box:SetText(url)
    frame.label:SetText(label or "")
    frame:Show()
    frame.box:SetFocus()
    frame.box:HighlightText()
end

------------------------------------------------------------
-- What the mouse is over
------------------------------------------------------------
local function SQOL_IsMouseOver(frame)
    if not (frame and frame.IsShown and frame:IsShown()) then return false end
    if type(frame.IsMouseMotionFocus) == "function" then
        local ok, focus = pcall(frame.IsMouseMotionFocus, frame)
        if ok then return focus == true end
    end
    return type(frame.IsMouseOver) == "function" and frame:IsMouseOver() and true or false
end

local function SQOL_FirstLine(tooltip)
    local name = tooltip.GetName and tooltip:GetName()
    local line = name and rawget(_G, name .. "TextLeft1")
    return line and SQOL_Text(line:GetText())
end

local function SQOL_Described(kindLabel, name, id)
    return kindLabel .. ": " .. (name or "?") .. " (" .. tostring(id) .. ")"
end

local SQOL_KIND_LABELS = {
    item = L["Item"], spell = L["Spell"], quest = L["Quest"],
    achievement = L["Achievement"], currency = L["Currency"],
}

-- Links and auras the tooltip was given (Classic tooltips carry no
-- tooltip data). Only trusted while the tooltip still shows the same title.
local function SQOL_RecordTooltip(tooltip, kind, id)
    id = SQOL_ID(id)
    if not (kind and id) then
        tooltipRecords[tooltip] = nil
        return
    end
    tooltipRecords[tooltip] = { kind = kind, id = id, title = SQOL_FirstLine(tooltip) }
end

local function SQOL_OnSetHyperlink(tooltip, link)
    if not SQOL_Text(link) then return SQOL_RecordTooltip(tooltip) end
    local linkType, id = link:match("^(%a+):(%d+)")
    if not linkType then
        linkType, id = link:match("|H(%a+):(%d+)")
    end
    SQOL_RecordTooltip(tooltip, SQOL_LINK_KINDS[linkType or ""], id)
end

local function SQOL_AuraSpellID(unit, index, filter)
    local auras = rawget(_G, "C_UnitAuras")
    if auras and type(auras.GetAuraDataByIndex) == "function" then
        local data = SQOL_Call(auras.GetAuraDataByIndex, unit, index, filter)
        if type(data) == "table" then return data.spellId end
    end
    return select(10, SQOL_Call(rawget(_G, "UnitAura"), unit, index, filter))
end

function SQOL.WebLink_HookTooltips()
    if SQOL._webLinkTooltipsHooked then return end
    SQOL._webLinkTooltipsHooked = true
    for _, tooltip in ipairs({ rawget(_G, "GameTooltip"), rawget(_G, "ItemRefTooltip") }) do
        if type(tooltip.SetHyperlink) == "function" then
            hooksecurefunc(tooltip, "SetHyperlink", SQOL_OnSetHyperlink)
        end
    end
    local tooltip = rawget(_G, "GameTooltip")
    local auraMethods = { SetUnitAura = false, SetUnitBuff = "HELPFUL", SetUnitDebuff = "HARMFUL" }
    for method, defaultFilter in pairs(auraMethods) do
        if tooltip and type(tooltip[method]) == "function" then
            hooksecurefunc(tooltip, method, function(self, unit, index, filter)
                if defaultFilter then
                    filter = (filter and defaultFilter .. "|" .. filter) or defaultFilter
                end
                SQOL_RecordTooltip(self, "spell", SQOL_AuraSpellID(unit, index, filter))
            end)
        end
    end
end

-- Tooltip data (every current client): type and ID of what it shows.
local function SQOL_TooltipData(tooltip)
    if type(tooltip.GetPrimaryTooltipData) ~= "function" then return end
    local data = SQOL_Call(tooltip.GetPrimaryTooltipData, tooltip)
    if type(data) ~= "table" or not SQOL.CanUseValue(data.type) then return end
    local kind = SQOL_TOOLTIP_KINDS[data.type]
    local id = SQOL_ID(data.id)
    if kind and id then return kind, id end
end

-- "Creature-0-1465-0-2105-448-000043F59F": the sixth part is the NPC ID.
local function SQOL_UnitNPCID(unit)
    local guid = SQOL_Call(rawget(_G, "UnitGUID"), unit)
    if not SQOL_Text(guid) then return end
    local unitType, npcID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" then
        return tonumber(npcID)
    end
end

-- Battle pets: Wowhead's NPC page for the species.
local function SQOL_BattlePetNPC(name)
    local journal = rawget(_G, "C_PetJournal")
    if not (journal and SQOL_Text(name)) then return end
    local speciesID = SQOL_Call(journal.FindPetIDByName, name, false)
    if not SQOL_ID(speciesID) then return end
    local creatureID = select(4, SQOL_Call(journal.GetPetInfoBySpeciesID, speciesID))
    return SQOL_ID(creatureID)
end

local function SQOL_RealmSlug(realm)
    local slug = SQOL_REALM_SLUGS[realm]
    if not slug then
        slug = realm:gsub("(%l[of])(%u)", "-%1-%2")    -- CavernsofTime -> Cavernsof-Time
            :gsub("(ofthe)", "-of-the-")                -- ShrineoftheDormantFlame
            :gsub("(%l)(%u)", "%1 %2")                  -- space before capitals
            :gsub(" ", "-"):gsub("'", ""):gsub("[(]", "-"):gsub("[)]", "")
    end
    return slug
end

-- worldofwarcraft.com character page (Retail only; none for zhCN).
local function SQOL_ArmoryLink(unit)
    if SQOL.IsClassic or SQOL.IsForever or SQOL.Locale == "zhCN" then return end
    if SQOL_Call(rawget(_G, "UnitIsPlayer"), unit) ~= true then return end
    local name, realm = SQOL_Call(rawget(_G, "UnitName"), unit)
    name = SQOL_Text(name)
    realm = SQOL_Text(realm) or SQOL_Text(SQOL_Call(rawget(_G, "GetNormalizedRealmName")))
    if not (name and realm) then return end

    local region = SQOL_ARMORY_REGIONS[SQOL_Call(rawget(_G, "GetCurrentRegion")) or 1] or "us"
    local language = SQOL_ARMORY_LANGUAGES[SQOL.Locale] or (region == "eu" and "en-gb" or "en-us")
    local slug = SQOL_RealmSlug(realm)
    local url = "https://worldofwarcraft.com/" .. language .. "/character/" .. region .. "/"
        .. slug:lower() .. "/" .. name:lower()
    return url, L["Player"] .. ": " .. name .. " (" .. slug:gsub("-", " ") .. ")"
end

-- Returns the URL and a description for what the mouse is over.
function SQOL.WebLink_Find()
    -- Battle pet and pet ability tooltips linked in chat or in the pet journal.
    local petTooltip = rawget(_G, "FloatingBattlePetTooltip")
    if SQOL_IsMouseOver(petTooltip) and petTooltip.Name then
        local name = SQOL_Text(petTooltip.Name:GetText())
        local creatureID = SQOL_BattlePetNPC(name)
        if creatureID then
            return SQOL.WowheadURL("npc", creatureID), SQOL_Described(L["Pet"], name, creatureID)
        end
    end
    -- The chat link's tooltip stays open, so it counts only under the mouse.
    local abilityTooltips = {
        { rawget(_G, "FloatingPetBattleAbilityTooltip"), true },
        { rawget(_G, "PetJournalPrimaryAbilityTooltip"), false },
    }
    for _, entry in ipairs(abilityTooltips) do
        local abilityTooltip, needsMouse = entry[1], entry[2]
        if abilityTooltip and abilityTooltip.Name and abilityTooltip:IsShown()
            and (not needsMouse or SQOL_IsMouseOver(abilityTooltip)) then
            local name = SQOL_Text(abilityTooltip.Name:GetText())
            if name then
                return SQOL.WowheadBase() .. "/search?q=" .. SQOL_URLEncode(name),
                    "|cffff0000" .. L["Pet ability"] .. ": " .. name
            end
        end
    end

    local itemRef = rawget(_G, "ItemRefTooltip")
    local tooltip = SQOL_IsMouseOver(itemRef) and itemRef or rawget(_G, "GameTooltip")
    if not (tooltip and tooltip:IsShown()) then return end

    if type(tooltip.GetItem) == "function" then
        local name, link = SQOL_Call(tooltip.GetItem, tooltip)
        link = SQOL_Text(link)
        local itemID = link and SQOL_ID(link:match("item:(%d+)"))
        if itemID then
            return SQOL.WowheadURL("item", itemID), SQOL_Described(L["Item"], link, itemID)
        end
    end
    -- Retail returns name, spellID; older clients had a rank in between.
    if type(tooltip.GetSpell) == "function" then
        local name, second, third = SQOL_Call(tooltip.GetSpell, tooltip)
        local spellID = SQOL_ID(type(second) == "number" and second or third)
        if SQOL_Text(name) and spellID then
            return SQOL.WowheadURL("spell", spellID), SQOL_Described(L["Spell"], name, spellID)
        end
    end

    local title = SQOL_FirstLine(tooltip)
    local kind, id = SQOL_TooltipData(tooltip)
    if not kind then
        local record = tooltipRecords[tooltip]
        if record and title and record.title == title then
            kind, id = record.kind, record.id
        end
    end
    if kind then
        return SQOL.WowheadURL(kind, id), SQOL_Described(SQOL_KIND_LABELS[kind], title, id)
    end

    local npcID = SQOL_UnitNPCID("mouseover")
    if npcID then
        local name = SQOL_Text(SQOL_Call(rawget(_G, "UnitName"), "mouseover"))
        return SQOL.WowheadURL("npc", npcID), SQOL_Described(L["NPC"], name, npcID)
    end
    if not title then return end

    local creatureID = SQOL_BattlePetNPC(title)
    if creatureID then
        return SQOL.WowheadURL("npc", creatureID), SQOL_Described(L["Pet"], title, creatureID)
    end

    -- Players get their armory page in Retail and no link elsewhere.
    local unit = SQOL_Call(rawget(_G, "UnitExists"), "mouseover") and "mouseover"
        or (type(tooltip.GetUnit) == "function" and select(2, SQOL_Call(tooltip.GetUnit, tooltip)))
    if SQOL_Text(unit) and SQOL_Call(rawget(_G, "UnitIsPlayer"), unit) == true then
        return SQOL_ArmoryLink(unit)
    end

    return SQOL.WowheadBase() .. "/search?q=" .. SQOL_URLEncode(SQOL_StripColors(title)),
        "|cffff0000" .. L["Link will search Wowhead"]
end

-- The "Show web link" key binding (Bindings.xml).
function SMoRGsQoL_ShowWebLink()
    local ok, url, label = pcall(SQOL.WebLink_Find)
    if ok and url then
        SQOL.WebLink_Show(url, label)
    elseif not ok then
        SQOL.dprint("Web link failed:", tostring(url))
    end
end

BINDING_HEADER_SMORGSQOL = "SMoRG's QoL"
BINDING_NAME_SMORGSQOL_WEBLINK = L["Show web link"]

SQOL.WebLink_HookTooltips()
