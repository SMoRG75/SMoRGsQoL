-- The default font is Alte Haas Grotesk
-- Typeface look like an helvetice printed in an old muller-brockmann book
--Freeware + distributed

FontDamageChanger = CreateFrame("Frame", "FontDamageChanger");
local FDC_FONT = "Interface\\AddOns\\FontDamageChanger\\FONTGOESHERE\\FDCFONT.TTF";
function FontDamageChanger:ApplySystemFonts()
DAMAGE_TEXT_FONT = FDC_FONT;
end
FontDamageChanger:RegisterEvent("ADDON_LOADED");
FontDamageChanger:ApplySystemFonts()