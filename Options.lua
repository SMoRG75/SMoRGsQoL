------------------------------------------------------------
-- SMoRGsQoL - Settings (Interface -> AddOns)
-- Retail (11.2.7+) and WoW Forever. Uses the Settings API.
-- Slash commands are kept as-is in SMoRGsQoL.lua.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"
SQOL = SQOL or {}
local L = SQOL.L

------------------------------------------------------------
-- Option list, shared by the Settings panel and the options popup
------------------------------------------------------------
-- kind defaults to "checkbox"; "dropdown" entries list their values.
-- An entry with isAvailable is left out when it returns false.
SQOL.OptionSections = {
    {
        title = L["Quests"],
        options = {
            { key = "AdventureRecap", label = L["Adventure Recap"],
              tooltip = L["Record quests, reputation gains and playtime per character. Open with /sqol recap. Reload continues the session; a new login starts another. No automatic popups."] },
            { key = "AutoTrack", label = L["Auto-track newly accepted quests"],
              tooltip = L["Automatically track newly accepted quests in the objective tracker."] },
            { key = "ColorProgress", label = L["Color quest progress"],
              tooltip = L["Colorize quest and scenario progress messages, the current count of quest objectives in the objective tracker, and quest objective counts on nameplates (red → yellow → green)."] },
            { key = "SmartQuestRadar", label = L["Smart Quest Radar"],
              tooltip = L["Mark relevant nameplates with a quest icon and up to three unfinished objectives. Uses readable tooltip data for your active quests. Replaces objective counts while enabled; unavailable data is hidden."] },
            { key = "ShowNameplateObjectives", label = L["Show objective counts on nameplates"],
              tooltip = L["Show quest objective counts (e.g., 0/10) above relevant nameplates."] },
            { key = "QuestCompleteSound", label = L["Quest completion sound"],
              tooltip = L["Play a sound when a quest is ready to turn in (or done for bonus/world quests)."] },
            { key = "QuestObjectiveSound", label = L["Quest objective completion sound"],
              tooltip = L["Play a worker voice line when one objective is completed but the quest is not yet done."] },
            { key = "QuestSoundProfile", label = L["Quest sound profile"], kind = "dropdown",
              tooltip = L["Choose the worker voice used for objective and full quest completion."],
              values = {
                  { value = "Horde", label = SQOL.QuestSoundProfiles.Horde.label },
                  { value = "Alliance", label = SQOL.QuestSoundProfiles.Alliance.label },
              } },
        },
    },
    {
        title = L["Character"],
        options = {
            { key = "ShowItemLevel", label = L["Show item level on PlayerFrame"],
              tooltip = L["Show your equipped item level on the player frame, independently of movement speed."] },
            { key = "ShowMovementSpeed", label = L["Show movement speed on PlayerFrame"],
              tooltip = L["Show movement speed on the player frame, independently of item level."] },
        },
    },
    {
        title = L["Reputation & XP"],
        options = {
            { key = "ColorStatusBarProgress", label = L["Color XP/reputation numbers"],
              tooltip = L["Colorize the current XP/reputation number (red → yellow → green), with outlined text. Reputation also shows the percentage remaining and current standing after the total. Labels and maximum values stay white; bar colors stay unchanged. Independent of quest progress colors."] },
            { key = "RepWatch", label = L["Auto-watch reputation gains"],
              tooltip = L["When a faction reputation changes, automatically switch your watched faction to the one that changed."] },
            { key = "RepMemory", label = L["Return to preferred reputation"],
              tooltip = L["Save your watched faction with /sqol repfocus. With auto-watch enabled, return to it after 10 seconds without new reputation gains. Changing the watched faction cancels the pending return. Saved per character."] },
            { key = "ShowRepGains", label = L["Floating reputation gains"],
              tooltip = L["Show reputation gains as simple green text near your character that floats upward and fades out. Independent of auto-watch."] },
        },
    },
    {
        title = L["Group"],
        options = {
            { key = "ShowReadyCheckTimer", label = L["Ready check countdown timer"],
              tooltip = L["Show a live countdown on the ready check popup for how long until it expires."] },
            { key = "ShowLFGProposalTimer", label = L["LFG queue pop countdown timer"],
              tooltip = L["Show a live countdown on the group finder queue pop for how long you have left to accept (40 seconds)."] },
            { key = "ShowPartyLevel", label = L["Show party member levels"],
              tooltip = L["Show each party member's level on the party frames (both default and raid-style), handy in 5-man instances."] },
        },
    },
    {
        title = L["Interface"],
        options = {
            { key = "ShowTooltipTarget", label = L["Show target in unit tooltips"],
              tooltip = L["Add a \"Target:\" line to unit tooltips showing who the unit is targeting: class-colored for players, reaction-colored for NPCs, and a red \"You\" when it is you. Updates live while you hover."] },
            { key = "ShowRangeIndicator", label = L["Range icon and distance for your target"],
              tooltip = L["On your target's nameplate, where Blizzard's soft target sword icon sits (or next to the target frame portrait without a nameplate), show the distance to an attackable target in yards (e.g. \"8-30 yd\", from the range of the abilities on your action bars), and a pulsing icon when none of your offensive abilities can reach it. Uses the same range check that tints action buttons red, so it follows forms and bonus bars. While enabled, Blizzard's soft target sword icon (SoftTargetIconEnemy) is turned off; it is turned back on when you disable this."] },
            { key = "DamageTextFont", label = L["Custom damage text font"],
              tooltip = L["Use the TrashHand damage text font for floating combat text. Restart the game client after changing this; the font is only loaded when the game starts."] },
            { key = "CursorShakeHighlight", label = L["Highlight cursor on shake"],
              tooltip = L["Highlight the cursor when you shake the mouse."] },
            { key = "HideDoneAchievements", label = L["Hide completed achievements"],
              tooltip = L["Achievement UI will default to showing incomplete achievements only."],
              isAvailable = function() return SQOL.IsAchievementFilterSupported() end },
            { key = "ShowMinimapButton", label = L["Show minimap button"],
              tooltip = L["Show a SMoRG's QoL button on the minimap. The addon is also available from the addon compartment menu and from LibDataBroker displays such as Bazooka or Titan Panel."] },
            { key = "ShowSplash", label = L["Show splash on login"],
              tooltip = L["Show the status splash message when you log in."] },
        },
    },
    {
        title = L["Advanced"],
        options = {
            { key = "DebugTrack", label = L["Debug tracking"],
              tooltip = L["Print verbose debug information (for troubleshooting)."] },
        },
    },
}

-- Calls func(section, option) for every option available in this client.
function SQOL.ForEachOption(func)
    for _, section in ipairs(SQOL.OptionSections) do
        for _, option in ipairs(section.options) do
            if not option.isAvailable or option.isAvailable() then
                func(section, option)
            end
        end
    end
end

-- Returns the option entry for a DB key, available in this client or not.
function SQOL.GetOption(key)
    for _, section in ipairs(SQOL.OptionSections) do
        for _, option in ipairs(section.options) do
            if option.key == key then
                return option
            end
        end
    end
end

-- Returns the display label of a dropdown value.
function SQOL.GetOptionValueLabel(option, value)
    for _, entry in ipairs(option.values or {}) do
        if entry.value == value then
            return entry.label
        end
    end
    return tostring(value)
end

-- Colored ON/OFF text, or the value label for a dropdown.
function SQOL.GetOptionStateText(option)
    local value = SQOL.DB and SQOL.DB[option.key]
    if option.kind == "dropdown" then
        return "|cffffff00" .. SQOL.GetOptionValueLabel(option, value) .. "|r"
    end
    return value and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r")
end

------------------------------------------------------------
-- Settings category
------------------------------------------------------------

local function SQOL_CreateSettingsCategory()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end

    -- Avoid double-registering.
    if SQOL._settingsCategoryCreated then
        return
    end
    SQOL._settingsCategoryCreated = true

    -- Ensure DB exists.
    if SQOL.Init and not SQOL.DB then
        SQOL.Init(false)
    end
    if not SQOL.DB or not SQOL.defaults then
        return
    end

    local category, layout = Settings.RegisterVerticalLayoutCategory("SMoRG's QoL")
    Settings.RegisterAddOnCategory(category)
    SQOL._settingsCategory = category

    local function RegisterSetting(option)
        local defaultValue = SQOL.defaults[option.key]
        if defaultValue == nil then
            defaultValue = false
        end

        local variable = ("%s_%s"):format(ADDON_NAME, option.key)

        -- 11.0.2+ signature:
        -- Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
        local setting = Settings.RegisterAddOnSetting(
            category,
            variable,
            option.key,
            SQOL.DB,
            type(defaultValue),
            option.label,
            defaultValue
        )

        if SQOL.RegisterSettingObject then
            SQOL.RegisterSettingObject(option.key, setting)
        end
        return setting, variable
    end

    local function BindSetting(option, setting, variable)
        -- Ensure UI matches saved value without triggering re-entrant callbacks.
        if type(setting.SetValue) == "function" and SQOL.DB[option.key] ~= nil then
            SQOL._settingsSync = true
            pcall(setting.SetValue, setting, SQOL.DB[option.key])
            SQOL._settingsSync = false
        end

        -- Apply side-effects + keep slash commands in sync.
        if type(Settings.SetOnValueChangedCallback) == "function" then
            Settings.SetOnValueChangedCallback(variable, function(...)
                if SQOL._settingsSync then return end
                local args = { ... }
                local value = args[#args]
                if SQOL.SetOption then
                    SQOL.SetOption(option.key, value)
                else
                    SQOL.DB[option.key] = value
                end
            end)
        end
    end

    local function AddCheckbox(option)
        local setting, variable = RegisterSetting(option)
        local createCheckbox = Settings.CreateCheckBox or Settings.CreateCheckbox
        if type(createCheckbox) == "function" then
            createCheckbox(category, setting, option.tooltip)
        end
        BindSetting(option, setting, variable)
    end

    local function AddDropdown(option)
        local setting, variable = RegisterSetting(option)
        if type(Settings.CreateDropdown) == "function"
            and type(Settings.CreateControlTextContainer) == "function" then
            local function GetOptions()
                local container = Settings.CreateControlTextContainer()
                for _, value in ipairs(option.values) do
                    container:Add(value.value, value.label)
                end
                return container:GetData()
            end
            Settings.CreateDropdown(category, setting, GetOptions, option.tooltip)
        end
        BindSetting(option, setting, variable)
    end

    local canAddHeaders = layout and type(layout.AddInitializer) == "function"
        and type(CreateSettingsListSectionHeaderInitializer) == "function"
    local lastSection
    SQOL.ForEachOption(function(section, option)
        if section ~= lastSection then
            lastSection = section
            if canAddHeaders then
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.title))
            end
        end
        if option.kind == "dropdown" then
            AddDropdown(option)
        else
            AddCheckbox(option)
        end
    end)
end

-- Opens Blizzard's Settings panel on the SMoRG's QoL page.
function SQOL.OpenBlizzardSettings()
    SQOL_CreateSettingsCategory()
    local category = SQOL._settingsCategory
    if not (category and Settings and type(Settings.OpenToCategory) == "function") then
        return
    end
    local id = type(category.GetID) == "function" and category:GetID() or category.ID
    Settings.OpenToCategory(id)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" then
        SQOL_CreateSettingsCategory()
    end
end)
