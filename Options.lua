------------------------------------------------------------
-- SMoRGsQoL - Settings (Interface -> AddOns)
-- Retail-only (11.2.7+). Uses the Settings API.
-- Slash commands are kept as-is in SMoRGsQoL.lua.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"
SQOL = SQOL or {}

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

    local category = Settings.RegisterVerticalLayoutCategory("SMoRG's QoL")
    Settings.RegisterAddOnCategory(category)
    SQOL._settingsCategory = category

    local function AddCheckbox(optionKey, optionLabel, tooltip)
        local defaultValue = SQOL.defaults[optionKey]
        if defaultValue == nil then
            defaultValue = false
        end

        local variable = ("%s_%s"):format(ADDON_NAME, optionKey)

        -- 11.0.2+ signature:
        -- Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
        local setting = Settings.RegisterAddOnSetting(
            category,
            variable,
            optionKey,
            SQOL.DB,
            type(defaultValue),
            optionLabel,
            defaultValue
        )

        if SQOL.RegisterSettingObject then
            SQOL.RegisterSettingObject(optionKey, setting)
        end

        local createCheckbox = Settings.CreateCheckBox or Settings.CreateCheckbox
        if type(createCheckbox) == "function" then
            createCheckbox(category, setting, tooltip)
        end

        -- Ensure UI matches saved value without triggering re-entrant callbacks.
        if type(setting.SetValue) == "function" and SQOL.DB[optionKey] ~= nil then
            SQOL._settingsSync = true
            pcall(setting.SetValue, setting, SQOL.DB[optionKey])
            SQOL._settingsSync = false
        end

        -- Apply side-effects + keep slash commands in sync.
        if type(Settings.SetOnValueChangedCallback) == "function" then
            Settings.SetOnValueChangedCallback(variable, function(...)
                if SQOL._settingsSync then return end
                local args = { ... }
                local value = args[#args]
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
    AddCheckbox("QuestCompleteSound", "Quest completion sound", "Play a sound when a quest is ready to turn in (or done for bonus/world quests).")
    AddCheckbox("HideDoneAchievements", "Hide completed achievements", "Achievement UI will default to showing incomplete achievements only.")
    AddCheckbox("RepWatch", "Auto-watch reputation gains", "When a faction reputation changes, automatically switch your watched faction to the one that changed.")
    AddCheckbox("ShowNameplateObjectives", "Show objective counts on nameplates", "Show quest objective counts (e.g., 0/10) above relevant nameplates.")
    AddCheckbox("ShowIlvlSpd", "Show iLvl + Speed on PlayerFrame", "Adds an iLvl and movement speed line to your PlayerFrame.")
    AddCheckbox("Tooltip", "TinyTooltip-style unit tooltips", "Enable TinyTooltip-like styling for unit tooltips (player header lines + health text overlay + target line).")
    AddCheckbox("DamageTextFont", "Custom damage text font", "Use the TrashHand damage text font for floating combat text.")
    AddCheckbox("CursorShakeHighlight", "Highlight cursor on shake", "Highlight the cursor when you shake the mouse.")
    AddCheckbox("DebugTrack", "Debug tracking", "Print verbose debug information (for troubleshooting).")

end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" then
        SQOL_CreateSettingsCategory()
    end
end)
