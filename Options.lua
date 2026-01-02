------------------------------------------------------------
-- SMoRGsQoL - Settings (Interface -> AddOns)
-- Retail-only (11.2.7+). Uses the Settings API.
-- Slash commands are kept as-is in SMoRGsQoL.lua.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"
SQOL = SQOL or {}

------------------------------------------------------------
-- Defaults button safety
--
-- The Blizzard "Defaults" button can offer "reset all settings".
-- To avoid accidents, we replace that button with a SQoL-only reset
-- that runs:
--   SQOL.Init(true)
--   SQOL.SyncAllSettingsObjects()
------------------------------------------------------------

local function SQOL_ResetOnlyThisAddon()
    if SQOL and SQOL.Init then
        SQOL.Init(true)
    end
    if SQOL and SQOL.SyncAllSettingsObjects then
        SQOL.SyncAllSettingsObjects()
    end
end

local function SQOL_GetButtonText(btn)
    if not btn then return nil end
    if type(btn.GetText) == "function" then
        local t = btn:GetText()
        if type(t) == "string" and t ~= "" then
            return t
        end
    end
    if btn.Text and type(btn.Text.GetText) == "function" then
        local t = btn.Text:GetText()
        if type(t) == "string" and t ~= "" then
            return t
        end
    end
    return nil
end

local function SQOL_FindDefaultsButtonUnder(root)
    if not root or type(root.GetChildren) ~= "function" then
        return nil
    end

    local defaultsLabel = _G["DEFAULTS"] or "Defaults"
    local resetLabel = _G["RESET_TO_DEFAULTS"] or "Reset to Defaults"

    local wanted = {
        [defaultsLabel] = true,
        [resetLabel] = true,
        ["Defaults"] = true,
        ["Reset to Defaults"] = true,
    }

    local stack = { root }
    local guard = 0

    while #stack > 0 and guard < 5000 do
        guard = guard + 1
        local f = table.remove(stack)

        local children = { f:GetChildren() }
        for i = 1, #children do
            local c = children[i]
            if c and type(c.GetObjectType) == "function" then
                if c:GetObjectType() == "Button" then
                    local text = SQOL_GetButtonText(c)
                    if text and wanted[text] then
                        return c
                    end
                end
                if type(c.GetChildren) == "function" then
                    table.insert(stack, c)
                end
            end
        end
    end

    return nil
end

local function SQOL_InstallDefaultsButtonReplacement()
    if SQOL._defaultsReplacementInstalled then
        return
    end

    if not SettingsPanel or not CreateFrame or not C_Timer then
        return
    end

    local blizzBtn = SQOL_FindDefaultsButtonUnder(SettingsPanel)
    if not blizzBtn then
        return
    end

    -- Create a replacement button in the exact same spot.
    local parent = blizzBtn:GetParent() or SettingsPanel
    local repl = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    repl:SetAllPoints(blizzBtn)
    repl:SetText("SQoL Defaults")
    repl:SetScript("OnClick", SQOL_ResetOnlyThisAddon)

    -- Simple tooltip (optional).
    repl:HookScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Reset only SMoRG's QoL settings.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    repl:HookScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Permanently hide/disable Blizzard's global Defaults button to prevent mishaps.
    blizzBtn:Hide()
    if type(blizzBtn.Disable) == "function" then
        blizzBtn:Disable()
    end

    -- Keep it hidden if Blizzard shows it again.
    repl._sqolTicker = C_Timer.NewTicker(0.5, function()
        if blizzBtn and blizzBtn.IsShown and blizzBtn:IsShown() then
            blizzBtn:Hide()
            if type(blizzBtn.Disable) == "function" then
                blizzBtn:Disable()
            end
        end
    end)

    SQOL._defaultsReplacementInstalled = true
    SQOL._defaultsReplacementButton = repl
end

local function SQOL_TryHookSettingsPanel()
    if SQOL._defaultsReplacementHooked then
        return
    end
    if not SettingsPanel or type(SettingsPanel.HookScript) ~= "function" then
        return
    end

    SQOL._defaultsReplacementHooked = true
    SettingsPanel:HookScript("OnShow", function()
        SQOL_InstallDefaultsButtonReplacement()
    end)

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, SQOL_InstallDefaultsButtonReplacement)
    else
        SQOL_InstallDefaultsButtonReplacement()
    end
end

local function SQOL_ScheduleDefaultsButtonReplacement()
    SQOL_TryHookSettingsPanel()
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

    local category = Settings.RegisterVerticalLayoutCategory("SMoRG's QoL")
    Settings.RegisterAddOnCategory(category)

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
    AddCheckbox("HideDoneAchievements", "Hide completed achievements", "Achievement UI will default to showing incomplete achievements only.")
    AddCheckbox("RepWatch", "Auto-watch reputation gains", "When a faction reputation changes, automatically switch your watched faction to the one that changed.")
    AddCheckbox("ShowNameplateObjectives", "Show objective counts on nameplates", "Show quest objective counts (e.g., 0/10) above relevant nameplates.")
    AddCheckbox("ShowIlvlSpd", "Show iLvl + Speed on PlayerFrame", "Adds an iLvl and movement speed line to your PlayerFrame.")
    AddCheckbox("DamageTextFont", "Custom damage text font", "Use the TrashHand damage text font for floating combat text.")
    AddCheckbox("CursorShakeHighlight", "Highlight cursor on shake", "Highlight the cursor when you shake the mouse.")
    AddCheckbox("DebugTrack", "Debug tracking", "Print verbose debug information (for troubleshooting).")

    SQOL_ScheduleDefaultsButtonReplacement()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" then
        SQOL_CreateSettingsCategory()
        SQOL_TryHookSettingsPanel()
    elseif event == "ADDON_LOADED" and addonName == "Blizzard_Settings" then
        SQOL_TryHookSettingsPanel()
    end
end)
