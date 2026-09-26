------------------------------------------------------------
-- SMoRGsQoL - Settings (Interface -> AddOns)
-- Retail (11.2.7+) and WoW Forever. Uses the Settings API.
-- Slash commands are kept as-is in SMoRGsQoL.lua.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"
SQOL = SQOL or {}

------------------------------------------------------------
-- Option list, shared by the Settings panel and the options popup
------------------------------------------------------------
-- kind defaults to "checkbox"; "dropdown" entries list their values.
-- An entry with isAvailable is left out when it returns false.
SQOL.OptionSections = {
    {
        title = "Quests",
        options = {
            { key = "AutoTrack", label = "Auto-track newly accepted quests",
              tooltip = "Automatically track newly accepted quests in the objective tracker." },
            { key = "ColorProgress", label = "Color quest progress",
              tooltip = "Colorize quest and scenario progress messages, the current count of quest objectives in the objective tracker, and quest objective counts on nameplates (red → yellow → green)." },
            { key = "ShowNameplateObjectives", label = "Show objective counts on nameplates",
              tooltip = "Show quest objective counts (e.g., 0/10) above relevant nameplates." },
            { key = "QuestCompleteSound", label = "Quest completion sound",
              tooltip = "Play a sound when a quest is ready to turn in (or done for bonus/world quests)." },
            { key = "QuestObjectiveSound", label = "Quest objective completion sound",
              tooltip = "Play a worker voice line when one objective is completed but the quest is not yet done." },
            { key = "QuestSoundProfile", label = "Quest sound profile", kind = "dropdown",
              tooltip = "Choose the worker voice used for objective and full quest completion.",
              values = {
                  { value = "Horde", label = SQOL.QuestSoundProfiles.Horde.label },
                  { value = "Alliance", label = SQOL.QuestSoundProfiles.Alliance.label },
              } },
        },
    },
    {
        title = "Character",
        options = {
            { key = "ShowItemLevel", label = "Show item level on PlayerFrame",
              tooltip = "Show your equipped item level on the player frame, independently of movement speed." },
            { key = "ShowMovementSpeed", label = "Show movement speed on PlayerFrame",
              tooltip = "Show movement speed on the player frame, independently of item level." },
        },
    },
    {
        title = "Reputation & XP",
        options = {
            { key = "ColorStatusBarProgress", label = "Color XP/reputation numbers",
              tooltip = "Colorize the current XP/reputation number (red → yellow → green), with outlined text. Reputation also shows the percentage remaining and current standing after the total. Labels and maximum values stay white; bar colors stay unchanged. Independent of quest progress colors." },
            { key = "RepWatch", label = "Auto-watch reputation gains",
              tooltip = "When a faction reputation changes, automatically switch your watched faction to the one that changed." },
            { key = "ShowRepGains", label = "Floating reputation gains",
              tooltip = "Show reputation gains as simple green text near your character that floats upward and fades out. Independent of auto-watch." },
        },
    },
    {
        title = "Group",
        options = {
            { key = "ShowReadyCheckTimer", label = "Ready check countdown timer",
              tooltip = "Show a live countdown on the ready check popup for how long until it expires." },
            { key = "ShowLFGProposalTimer", label = "LFG queue pop countdown timer",
              tooltip = "Show a live countdown on the group finder queue pop for how long you have left to accept (40 seconds)." },
            { key = "ShowPartyLevel", label = "Show party member levels",
              tooltip = "Show each party member's level on the party frames (both default and raid-style), handy in 5-man instances." },
        },
    },
    {
        title = "Interface",
        options = {
            { key = "ShowTooltipTarget", label = "Show target in unit tooltips",
              tooltip = "Add a \"Target:\" line to unit tooltips showing who the unit is targeting: class-colored for players, reaction-colored for NPCs, and a red \"You\" when it is you. Updates live while you hover." },
            { key = "DamageTextFont", label = "Custom damage text font",
              tooltip = "Use the TrashHand damage text font for floating combat text." },
            { key = "CursorShakeHighlight", label = "Highlight cursor on shake",
              tooltip = "Highlight the cursor when you shake the mouse." },
            { key = "HideDoneAchievements", label = "Hide completed achievements",
              tooltip = "Achievement UI will default to showing incomplete achievements only.",
              isAvailable = function() return SQOL.IsAchievementFilterSupported() end },
            { key = "ShowMinimapButton", label = "Show minimap button",
              tooltip = "Show a SMoRG's QoL button on the minimap. The addon is also available from the addon compartment menu and from LibDataBroker displays such as Bazooka or Titan Panel." },
            { key = "ShowSplash", label = "Show splash on login",
              tooltip = "Show the status splash message when you log in." },
        },
    },
    {
        title = "Advanced",
        options = {
            { key = "DebugTrack", label = "Debug tracking",
              tooltip = "Print verbose debug information (for troubleshooting)." },
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
