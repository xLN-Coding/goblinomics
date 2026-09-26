if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Insights/Insights.lua
-- Insights (load on demand, M7): the deeper view behind the dashboard: wealth
-- history, income and expenses per day, top sources and expenses, the cash flow
-- (sources -> characters & warband bank -> expenses, warband bank, kept) and
-- daily/weekly reports. Reads the other modules through their public APIs
-- (API.Vault, API.Ledger, API.Workshop, API.Gatherer). The tab spec is
-- registered at load time so the core's placeholder is replaced before the
-- page is built (UI.EnsureTabLoaded loads this addon on the first click).
local ADDON_NAME, ns = ...

local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API then return end
ns.API = API
ns.L = API.L

local Insights = API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "Insights",
    description = function() return API.L["History, cash flow and reports; loads when opened."] end,
    order = 60,
    db = {
        sv = "GoblinomicsInsightsDB",
        version = 1,
        defaults = { days = 30 },
        charDefaults = {},
    },
})
ns.Insights = Insights

function Insights:OnEnable()
    if ns.Data then ns.Data.Enable(self) end
end

function Insights:OnDisable()
    if ns.Data then ns.Data.Invalidate() end
end
