------------------------------------------------------------
-- SMoRGsQoL - Settings (Interface -> AddOns)
-- Retail (Settings API).
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"
SQOL = SQOL or {}

local function SQOL_CreateSettingsCategory()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        -- Settings UI not available (very old clients)
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

    local title = "SMoRG's QoL"
    local category = Settings.RegisterVerticalLayoutCategory(title)
    Settings.RegisterAddOnCategory(category)
    SQOL.SettingsCategory = category

    local CreateCheckBox = Settings.CreateCheckBox or Settings.CreateCheckbox
    if not CreateCheckBox then
        return
    end

    local function RegisterSetting(categoryObj, optionKey, optionLabel, defaultValue)
        -- We use a namespaced "variable" id for the Settings system callbacks.
        local variable = ("%s_%s"):format(ADDON_NAME, optionKey)

        -- Newer clients (Patch 11.0.2+) use:
        -- Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, type(defaultValue), name, defaultValue)
        local setting
        local ok = pcall(function()
            setting = Settings.RegisterAddOnSetting(
                categoryObj,
                variable,
                optionKey,
                SQOL.DB,
                type(defaultValue),
                optionLabel,
                defaultValue
            )
        end)

        -- Older clients (10.0 - 11.0.1) used:
        -- Settings.RegisterAddOnSetting(category, name, variable, type(defaultValue), defaultValue)
        if not ok or not setting then
            pcall(function()
                setting = Settings.RegisterAddOnSetting(
                    categoryObj,
                    optionLabel,
                    optionKey,
                    type(defaultValue),
                    defaultValue
                )
            end)
        end

        return variable, setting
    end

    local function AddCheckbox(optionKey, optionLabel, tooltip)
        local defaultValue = SQOL.defaults[optionKey]
        if defaultValue == nil then
            defaultValue = false
        end

        local variable, setting = RegisterSetting(category, optionKey, optionLabel, defaultValue)
        if not setting then
            return
        end

        if SQOL.RegisterSettingObject then
            SQOL.RegisterSettingObject(optionKey, setting)
        end

        -- Build UI element.
        CreateCheckBox(category, setting, tooltip)

        -- Ensure UI reflects saved value (and does NOT trigger re-entrant callbacks).
        if type(setting.SetValue) == "function" and SQOL.DB[optionKey] ~= nil then
            SQOL._settingsSync = true
            pcall(setting.SetValue, setting, SQOL.DB[optionKey])
            SQOL._settingsSync = false
        end

        -- Apply side-effects + keep slash commands in sync.
        if Settings and type(Settings.SetOnValueChangedCallback) == "function" then
            Settings.SetOnValueChangedCallback(variable, function(_, _, value)
                if SQOL._settingsSync then return end
                if SQOL.SetOption then
                    SQOL.SetOption(optionKey, value)
                else
                    SQOL.DB[optionKey] = value
                end
            end)
        elseif type(setting.SetValueChangedCallback) == "function" then
            -- Fallback in case Blizzard changes the API again.
            setting:SetValueChangedCallback(function(_, value)
                if SQOL._settingsSync then return end
                if SQOL.SetOption then
                    SQOL.SetOption(optionKey, value)
                else
                    SQOL.DB[optionKey] = value
                end
            end)
        end
    end

    AddCheckbox("AutoTrack", "Auto-track newly accepted quests", "Automatically track newly accepted quests in the objective tracker.")
    AddCheckbox("ShowSplash", "Show splash on login", "Show the status splash message when you log in.")
    AddCheckbox("ColorProgress", "Color progress messages", "Colorize objective count messages (e.g., 3/10) and quest objective progress (red → yellow → green).")
    AddCheckbox("HideDoneAchievements", "Hide completed achievements", "Achievement UI will default to showing incomplete achievements only.")
    AddCheckbox("RepWatch", "Auto-watch reputation gains", "When a faction reputation changes, automatically switch your watched faction to the one that changed.")
    AddCheckbox("ShowIlvlSpd", "Show iLvl + Speed on PlayerFrame", "Adds an iLvl and movement speed line to your PlayerFrame.")
    AddCheckbox("DebugTrack", "Debug tracking", "Print verbose debug information (for troubleshooting).")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    SQOL_CreateSettingsCategory()
end)
