------------------------------------------------------------
-- SMoRGsQoL - Localization
-- The English text is the key: L["Show minimap button"]. A key without a
-- translation returns itself, so English is always the fallback.
-- Each locale file fills in SQOL.L only when it matches the client locale.
-- Keep color codes (|cff...|r) and format specifiers (%s, %d) in translations.
------------------------------------------------------------

local _, SQOL = ...

SQOL.Locale = type(GetLocale) == "function" and GetLocale() or "enUS"

SQOL.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
