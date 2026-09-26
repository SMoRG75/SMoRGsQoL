------------------------------------------------------------
-- SMoRGsQoL - Launchers
-- LibDataBroker launcher (Bazooka, Titan Panel, ChocolateBar...), an optional
-- LibDBIcon minimap button, and Blizzard's addon compartment menu (the TOC
-- names the SMoRGsQoL_OnAddonCompartment* globals below).
-- Left-click opens the options popup, right-click Blizzard's Settings panel.
------------------------------------------------------------

local ADDON_NAME, SQOL = ...
ADDON_NAME = ADDON_NAME or "SMoRGsQoL"

local ICON = "Interface\\AddOns\\SMoRGsQoL\\smorgsqol.png"
local LibStub = rawget(_G, "LibStub")
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function SQOL_Launcher_OnClick(button)
    if button == "RightButton" then
        SQOL.OpenBlizzardSettings()
    else
        SQOL.OptionsPopup_Toggle()
    end
end

-- Title, how many features are on, and the click hints.
function SQOL.Launcher_AddTooltip(tooltip)
    tooltip:AddLine("SMoRG's QoL")

    local enabled, total = 0, 0
    SQOL.ForEachOption(function(_, option)
        if option.kind ~= "dropdown" and option.key ~= "DebugTrack" and option.key ~= "ShowMinimapButton" then
            total = total + 1
            if SQOL.DB and SQOL.DB[option.key] then
                enabled = enabled + 1
            end
        end
    end)
    tooltip:AddLine(string.format("%d of %d features enabled", enabled, total), 1, 1, 1)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffeda55fLeft-click|r to open options", 0.2, 1, 0.2)
    tooltip:AddLine("|cffeda55fRight-click|r to open Blizzard Settings", 0.2, 1, 0.2)
end

local dataObject = LDB and LDB:NewDataObject(ADDON_NAME, {
    type = "launcher",
    label = "SMoRG's QoL",
    icon = ICON,
    OnClick = function(_, button) SQOL_Launcher_OnClick(button) end,
    OnTooltipShow = function(tooltip) SQOL.Launcher_AddTooltip(tooltip) end,
})

------------------------------------------------------------
-- Minimap button
------------------------------------------------------------
-- LibDBIcon keeps its position and hidden flag in SQOL_DB.MinimapIcon;
-- ShowMinimapButton is the setting shown to the user.
function SQOL.UpdateMinimapButton()
    if not (LDBIcon and dataObject and SQOL.DB) then return end

    if type(SQOL.DB.MinimapIcon) ~= "table" then
        SQOL.DB.MinimapIcon = {}
    end
    local iconDB = SQOL.DB.MinimapIcon
    iconDB.hide = not SQOL.DB.ShowMinimapButton

    if LDBIcon:IsRegistered(ADDON_NAME) then
        -- After /sqol reset, SQOL_DB is a new table; point LibDBIcon at it.
        LDBIcon:Refresh(ADDON_NAME, iconDB)
    else
        LDBIcon:Register(ADDON_NAME, dataObject, iconDB)
    end

    if iconDB.hide then
        LDBIcon:Hide(ADDON_NAME)
    else
        LDBIcon:Show(ADDON_NAME)
    end
end

------------------------------------------------------------
-- Addon compartment (named in SMoRGsQoL.toc)
------------------------------------------------------------
function SMoRGsQoL_OnAddonCompartmentClick(_, buttonName)
    SQOL_Launcher_OnClick(buttonName)
end

function SMoRGsQoL_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    SQOL.Launcher_AddTooltip(GameTooltip)
    GameTooltip:Show()
end

function SMoRGsQoL_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    SQOL.UpdateMinimapButton()
end)
