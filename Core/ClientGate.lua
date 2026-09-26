-- Core/ClientGate.lua
-- Pre-12.1 client failsafe. MUST stay the FIRST file in the core TOC.
--
-- Goblinomics targets WoW Midnight (12.1+) exclusively. On an older client every
-- other file of the suite returns at its first line, so no SavedVariables are read
-- or written and a downgrade restores the addon with settings untouched.
--
-- Fail-open by design: if the interface number cannot be read, the suite runs
-- normally. On 12.1+ this file is two comparisons and exits; no globals, no frames.

local iface = select(4, GetBuildInfo())
if type(iface) ~= "number" then return end
if iface >= 120100 then return end

GOBLINOMICS_CLIENT_BLOCKED = true

local notice = CreateFrame("Frame")
notice:RegisterEvent("PLAYER_LOGIN")
notice:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    print("|cff3fbf3fGoblinomics|r: this version requires World of Warcraft 12.1 or newer. The addon stays disabled.")
end)
