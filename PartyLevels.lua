local ADDON_NAME, SQOL = ...

------------------------------------------------------------
-- Party member level
-- The default (non-raid-style) party frames never show a level,
-- which is annoying in 5-man instances. Add a small level label
-- to each visible party member frame.
------------------------------------------------------------
SQOL._partyLevelTexts = SQOL._partyLevelTexts or {}
SQOL._partyFramesHooked = SQOL._partyFramesHooked or {}

local PARTY_MEMBER_COUNT = 4

local function SQOL_GetPartyMemberFrame(i)
    local partyFrame = rawget(_G, "PartyFrame")
    if partyFrame then
        -- Retail (10.0+): PartyFrame.MemberFrame1 .. MemberFrame4
        local ok, mf = pcall(function() return partyFrame["MemberFrame" .. i] end)
        if ok and mf then return mf end
    end
    -- Legacy global name, just in case.
    return rawget(_G, "PartyMemberFrame" .. i)
end

local function SQOL_GetPartyMemberUnit(frame, i)
    if frame then
        local ok, u = pcall(function() return frame.unit or frame.unitToken end)
        if ok and type(u) == "string" and u ~= "" then
            return u
        end
    end
    return "party" .. i
end

local function SQOL_GetPartyMemberNameFS(frame, i)
    if frame then
        local ok, n = pcall(function() return frame.name or frame.Name end)
        if ok and n and n.GetObjectType and n:GetObjectType() == "FontString" then
            return n
        end
    end
    local g = rawget(_G, "PartyMemberFrame" .. i .. "Name")
    if g and g.GetObjectType and g:GetObjectType() == "FontString" then
        return g
    end
    return nil
end

local function SQOL_EnsurePartyLevelText(i, frame)
    local fs = SQOL._partyLevelTexts[i]
    if fs then return fs end

    fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetDrawLayer("OVERLAY", 7)
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end

    -- Prefer sitting just after the member's name; fall back to the
    -- frame's top-left if the name FontString can't be located.
    local nameFS = SQOL_GetPartyMemberNameFS(frame, i)
    if nameFS then
        fs:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
    else
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 45, -6)
    end

    SQOL._partyLevelTexts[i] = fs
    return fs
end

local function SQOL_UpdatePartyMemberLevel(i)
    local existing = SQOL._partyLevelTexts[i]

    if not (SQOL.DB and SQOL.DB.ShowPartyLevel) then
        if existing then existing:Hide() end
        return
    end

    local frame = SQOL_GetPartyMemberFrame(i)
    if not frame then
        if existing then existing:Hide() end
        return
    end

    local unit = SQOL_GetPartyMemberUnit(frame, i)
    if not UnitExists(unit) then
        if existing then existing:Hide() end
        return
    end

    local fs = SQOL_EnsurePartyLevelText(i, frame)
    local level = UnitLevel(unit)
    if type(level) == "number" and level > 0 then
        fs:SetText("|cffffd100" .. level .. "|r")
        fs:Show()
    elseif level == -1 then
        -- Level unknown to the client (e.g. much higher level / out of range).
        fs:SetText("|cffff2020??|r")
        fs:Show()
    else
        fs:SetText("")
        fs:Hide()
    end
end

------------------------------------------------------------
-- Raid-style party frames (CompactUnitFrame) don't show a level
-- either. Decorate the compact party member frames the same way.
-- Restricted to party units so real raid/arena frames are left alone.
------------------------------------------------------------
local RAID_PARTY_MEMBER_COUNT = 5

local function SQOL_IsCompactPartyMemberFrame(frame)
    if not frame then return false end

    -- Nameplates (ForbiddenNamePlate*) also flow through
    -- CompactUnitFrame_UpdateName. They are forbidden/tainted frames, and
    -- touching them (even frame:GetName()) throws a taint error. Bail out.
    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end

    local ok, name = pcall(function() return frame.GetName and frame:GetName() end)
    if ok and type(name) == "string" and name:find("CompactPartyFrame") then
        return true
    end

    -- Fallback: only decorate player / party units so we never touch
    -- real raid frames, arena frames, boss frames, etc.
    local ok, unit = pcall(function() return frame.unit end)
    if ok and type(unit) == "string" then
        if unit == "player" or unit:match("^party[1-9]$") then
            return true
        end
    end
    return false
end

local function SQOL_EnsureCompactLevelText(frame)
    local fs = frame.SQOL_LevelText
    if fs then return fs end

    fs = frame:CreateFontString(nil, "OVERLAY")
    local font = rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
    -- Outlined so it stays legible over the health bar.
    pcall(fs.SetFont, fs, font, 10, "OUTLINE")
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    fs:SetDrawLayer("OVERLAY", 7)
    -- Bottom-left corner keeps clear of the centered name and the
    -- role / leader / ready-check icons that live near the top.
    fs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)

    frame.SQOL_LevelText = fs
    return fs
end

local function SQOL_UpdateCompactPartyFrameLevel(frame)
    if not SQOL_IsCompactPartyMemberFrame(frame) then
        return
    end

    if not (SQOL.DB and SQOL.DB.ShowPartyLevel) then
        if frame.SQOL_LevelText then frame.SQOL_LevelText:Hide() end
        return
    end

    local ok, unit = pcall(function() return frame.unit end)
    if not ok or type(unit) ~= "string"
        or not UnitExists(unit) or not UnitIsPlayer(unit) then
        if frame.SQOL_LevelText then frame.SQOL_LevelText:Hide() end
        return
    end

    local fs = SQOL_EnsureCompactLevelText(frame)
    local level = UnitLevel(unit)
    if type(level) == "number" and level > 0 then
        fs:SetText("|cffffd100" .. level .. "|r")
        fs:Show()
    elseif level == -1 then
        fs:SetText("|cffff2020??|r")
        fs:Show()
    else
        fs:SetText("")
        fs:Hide()
    end
end

local function SQOL_UpdateAllCompactPartyFrameLevels()
    for i = 1, RAID_PARTY_MEMBER_COUNT do
        local frame = rawget(_G, "CompactPartyFrameMember" .. i)
        if frame then
            SQOL_UpdateCompactPartyFrameLevel(frame)
        end
    end
end

-- Hook Blizzard's compact frame refresh so we re-apply whenever a
-- raid-style frame is set up, re-sorted, or reassigned to a new unit.
local function SQOL_HookCompactPartyFrames()
    if SQOL._compactHooked then return end
    local fn = rawget(_G, "CompactUnitFrame_UpdateName")
    if type(fn) ~= "function" or type(hooksecurefunc) ~= "function" then
        return
    end
    SQOL._compactHooked = true
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if not (SQOL.DB and SQOL.DB.ShowPartyLevel) then return end
        SQOL_UpdateCompactPartyFrameLevel(frame)
    end)
end

function SQOL.UpdateAllPartyMemberLevels()
    for i = 1, PARTY_MEMBER_COUNT do
        SQOL_UpdatePartyMemberLevel(i)
    end
    SQOL_UpdateAllCompactPartyFrameLevels()
end

local function SQOL_HookPartyMemberFrames()
    for i = 1, PARTY_MEMBER_COUNT do
        local frame = SQOL_GetPartyMemberFrame(i)
        if frame and not SQOL._partyFramesHooked[i] and frame.HookScript then
            SQOL._partyFramesHooked[i] = true
            frame:HookScript("OnShow", function()
                SQOL_UpdatePartyMemberLevel(i)
            end)
        end
    end
end

-- Public entry point used on login / roster changes.
function SQOL.RefreshPartyMemberLevels()
    -- The compact hook checks the DB flag itself, so it's safe to
    -- install once regardless of the current toggle state.
    SQOL_HookCompactPartyFrames()

    if not (SQOL.DB and SQOL.DB.ShowPartyLevel) then
        SQOL.UpdateAllPartyMemberLevels() -- hides any leftover texts
        return
    end
    SQOL_HookPartyMemberFrames()
    SQOL.UpdateAllPartyMemberLevels()
    -- Party members' levels aren't always known the instant they join;
    -- give the client a moment and refresh once more.
    C_Timer.After(0.5, SQOL.UpdateAllPartyMemberLevels)
end

