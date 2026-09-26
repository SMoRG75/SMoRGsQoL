------------------------------------------------------------
-- SMoRGsQoL - Options popup
-- A standalone, movable window opened from the LDB launcher, the addon
-- compartment, the minimap button or /sqol config. It is built from
-- SQOL.OptionSections, so it always matches the Settings panel, and every
-- change goes through SQOL.SetOption like the slash commands do.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"

local POPUP_NAME = "SQOL_OptionsPopup"
local ICON = "Interface\\AddOns\\SMoRGsQoL\\smorgsqol.png"

local COLUMN_WIDTH = 290
local COLUMN_GAP = 20
local PADDING_X = 18
local CONTENT_TOP = 72     -- below the title bar, portrait and subtitle
local FOOTER_HEIGHT = 44
local HEADER_HEIGHT = 24
local ROW_HEIGHT = 26
local SECTION_GAP = 12

local popup
local controls = {}        -- every control has :Refresh()

------------------------------------------------------------
-- Controls
------------------------------------------------------------
local function SQOL_Popup_ShowTooltip(owner, option)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(option.label, 1, 1, 1)
    GameTooltip:AddLine(option.tooltip, nil, nil, nil, true)
    GameTooltip:Show()
end

local function SQOL_Popup_HideTooltip()
    GameTooltip:Hide()
end

local function SQOL_Popup_PlayCheckboxSound(checked)
    if type(PlaySound) ~= "function" or not SOUNDKIT then return end
    local sound = checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
    if sound then PlaySound(sound) end
end

local function SQOL_Popup_CreateCheckbox(parent, option)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)

    local label = checkbox.Text or checkbox.text
    if not label then
        label = checkbox:CreateFontString(nil, "ARTWORK")
        label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    end
    label:SetFontObject("GameFontHighlight")
    label:SetText(option.label)
    -- Let the label toggle the checkbox too.
    checkbox:SetHitRectInsets(0, -math.min(COLUMN_WIDTH - 30, (label:GetStringWidth() or 0) + 6), 0, 0)

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        SQOL_Popup_PlayCheckboxSound(checked)
        SQOL.SetOption(option.key, checked)
    end)
    checkbox:SetScript("OnEnter", function(self) SQOL_Popup_ShowTooltip(self, option) end)
    checkbox:SetScript("OnLeave", SQOL_Popup_HideTooltip)

    function checkbox:Refresh()
        self:SetChecked(SQOL.DB and SQOL.DB[option.key] and true or false)
    end
    return checkbox
end

local function SQOL_Popup_ValueLabel(option, value)
    for _, entry in ipairs(option.values) do
        if entry.value == value then
            return entry.label
        end
    end
    return tostring(value)
end

local function SQOL_Popup_CreateDropdown(parent, option)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(COLUMN_WIDTH, ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) SQOL_Popup_ShowTooltip(self, option) end)
    row:SetScript("OnLeave", SQOL_Popup_HideTooltip)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetText(option.label)

    -- Blizzard's menu dropdown (11.0+); fall back to a button that cycles the values.
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    if ok and dropdown and type(dropdown.SetupMenu) == "function" then
        dropdown:SetWidth(150)
        dropdown:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        dropdown:SetupMenu(function(_, rootDescription)
            for _, entry in ipairs(option.values) do
                rootDescription:CreateRadio(entry.label,
                    function() return SQOL.DB and SQOL.DB[option.key] == entry.value end,
                    function() SQOL.SetOption(option.key, entry.value) end)
            end
        end)
        function row:Refresh()
            dropdown:GenerateMenu()
        end
    else
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(150, 22)
        button:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        button:SetScript("OnClick", function()
            local current = SQOL.DB and SQOL.DB[option.key]
            local index = 1
            for i, entry in ipairs(option.values) do
                if entry.value == current then index = i end
            end
            SQOL.SetOption(option.key, option.values[index % #option.values + 1].value)
        end)
        function row:Refresh()
            button:SetText(SQOL_Popup_ValueLabel(option, SQOL.DB and SQOL.DB[option.key]))
        end
    end
    return row
end

local function SQOL_Popup_CreateSectionHeader(parent, title)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetText(title)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.3)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    line:SetWidth(COLUMN_WIDTH - 10)
    return header
end

------------------------------------------------------------
-- Layout
------------------------------------------------------------
-- Collect the available options per section, then split the sections into
-- two columns (in order) so the columns are as even as possible.
local function SQOL_Popup_GetSections()
    local sections, bySection = {}, {}
    SQOL.ForEachOption(function(section, option)
        local entry = bySection[section]
        if not entry then
            entry = { title = section.title, options = {} }
            bySection[section] = entry
            sections[#sections + 1] = entry
        end
        entry.options[#entry.options + 1] = option
    end)
    for _, section in ipairs(sections) do
        section.height = HEADER_HEIGHT + #section.options * ROW_HEIGHT + SECTION_GAP
    end
    return sections
end

local function SQOL_Popup_SplitColumns(sections)
    local total = 0
    for _, section in ipairs(sections) do total = total + section.height end

    local bestSplit, bestHeight, left = #sections, total, 0
    for i, section in ipairs(sections) do
        left = left + section.height
        local height = math.max(left, total - left)
        if height < bestHeight then
            bestSplit, bestHeight = i, height
        end
    end
    return bestSplit, bestHeight
end

local function SQOL_Popup_BuildContent(frame)
    local sections = SQOL_Popup_GetSections()
    local split, columnHeight = SQOL_Popup_SplitColumns(sections)

    local y = { -CONTENT_TOP, -CONTENT_TOP }
    for i, section in ipairs(sections) do
        local column = (i <= split) and 1 or 2
        local x = PADDING_X + (column - 1) * (COLUMN_WIDTH + COLUMN_GAP)

        local header = SQOL_Popup_CreateSectionHeader(frame, section.title)
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y[column])
        y[column] = y[column] - HEADER_HEIGHT

        for _, option in ipairs(section.options) do
            local control
            if option.kind == "dropdown" then
                control = SQOL_Popup_CreateDropdown(frame, option)
                control:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y[column])
            else
                control = SQOL_Popup_CreateCheckbox(frame, option)
                control:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y[column] - 1)
            end
            control.option = option
            controls[#controls + 1] = control
            y[column] = y[column] - ROW_HEIGHT
        end
        y[column] = y[column] - SECTION_GAP
    end

    frame:SetSize(PADDING_X * 2 + COLUMN_WIDTH * 2 + COLUMN_GAP, CONTENT_TOP + columnHeight + FOOTER_HEIGHT)
end

------------------------------------------------------------
-- Window
------------------------------------------------------------
local function SQOL_Popup_GetVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    local ok, version = pcall(getMetadata, ADDON_NAME, "Version")
    return ok and type(version) == "string" and version or "?"
end

local function SQOL_Popup_SavePosition(frame)
    if not SQOL.DB then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    SQOL.DB.PopupPosition = { point, relativePoint, x, y }
end

local function SQOL_Popup_RestorePosition(frame)
    frame:ClearAllPoints()
    local pos = SQOL.DB and SQOL.DB.PopupPosition
    if type(pos) == "table" and pos[1] then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

-- The portrait frame gives the Blizzard look (title bar, close button, round icon);
-- fall back to simpler templates if a client lacks it.
local function SQOL_Popup_CreateFrame()
    for _, template in ipairs({ "PortraitFrameTemplate", "BasicFrameTemplateWithInset" }) do
        local ok, frame = pcall(CreateFrame, "Frame", POPUP_NAME, UIParent, template)
        if ok and frame then
            return frame
        end
    end
    return CreateFrame("Frame", POPUP_NAME, UIParent, "BackdropTemplate")
end

local function SQOL_Popup_Create()
    local frame = SQOL_Popup_CreateFrame()
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SQOL_Popup_SavePosition(self)
    end)

    local title = "SMoRG's QoL"
    if type(frame.SetTitle) == "function" then
        frame:SetTitle(title)
    elseif frame.TitleText then
        frame.TitleText:SetText(title)
    else
        local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", frame, "TOP", 0, -8)
        titleText:SetText(title)
    end
    if type(frame.SetPortraitToAsset) == "function" then
        frame:SetPortraitToAsset(ICON)
    end
    if frame.SetBackdrop and not frame.CloseButton then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    end

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -36)
    subtitle:SetText("Quality-of-life tweaks. Changes apply immediately.")

    SQOL_Popup_BuildContent(frame)

    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING_X, 16)
    version:SetText("v" .. SQOL_Popup_GetVersion() .. "  ·  /sqol help")

    local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsButton:SetSize(160, 22)
    settingsButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING_X, 12)
    settingsButton:SetText("Blizzard Settings")
    settingsButton:SetScript("OnClick", function()
        frame:Hide()
        SQOL.OpenBlizzardSettings()
    end)

    frame:SetScript("OnShow", function()
        for _, control in ipairs(controls) do
            control:Refresh()
        end
    end)

    -- Close with Escape.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, POPUP_NAME)
    end
    return frame
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function SQOL.OptionsPopup_Toggle()
    if not SQOL.DB then return end
    if not popup then
        popup = SQOL_Popup_Create()
    end
    if popup:IsShown() then
        popup:Hide()
    else
        SQOL_Popup_RestorePosition(popup)
        popup:Show()
    end
end

-- Keep the window in sync when options change elsewhere (slash commands, Settings panel).
function SQOL.OptionsPopup_Refresh()
    if not popup or not popup:IsShown() then return end
    for _, control in ipairs(controls) do
        control:Refresh()
    end
end
