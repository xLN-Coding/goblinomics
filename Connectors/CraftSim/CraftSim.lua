if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Connectors/CraftSim/CraftSim.lua
-- CraftSim connector: after every craft call CraftSim fires
-- CRAFTSIM_CRAFT_RECIPE_DATA_PREPARED(recipeData) (public CraftSimAPI:RegisterEvents).
-- The connector forwards CraftSim's cost per craft (priceData.craftingCosts)
-- and expected cost per item as CRAFT_COST_ESTIMATE on the Goblinomics bus.
-- Workshop stores the cost per craft for comparison and uses the per-item
-- estimate only when no reagent has a price of its own. Workshop works without it.
local ADDON_NAME = ...

if type(CraftSimAPI) ~= "table" or type(CraftSimAPI.RegisterEvents) ~= "function" then return end
local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API then return end

local Connector = API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "CraftSim Connector",
    description = function() return API.L["Craft costs from CraftSim."] end,
})

local listener = {}
local registered = false

function listener:CRAFTSIM_CRAFT_RECIPE_DATA_PREPARED(recipeData)
    if not (Connector:IsEnabled() and type(recipeData) == "table") then return end
    local price = type(recipeData.priceData) == "table" and recipeData.priceData or {}
    local perCraft = tonumber(price.craftingCosts)
    local perItem = tonumber(price.expectedCostsPerItem)
    if type(recipeData.recipeID) ~= "number" or (not perCraft and not perItem) then return end
    API.Emit("CRAFT_COST_ESTIMATE", {
        recipeID = recipeData.recipeID, perCraft = perCraft, perItem = perItem, source = "craftsim",
    })
end

function Connector:OnEnable()
    if registered then return end
    registered = true
    local ok, err = pcall(CraftSimAPI.RegisterEvents, CraftSimAPI, listener, { "CRAFTSIM_CRAFT_RECIPE_DATA_PREPARED" })
    if not ok then
        registered = false
        API.Print("CraftSim: " .. tostring(err))
    end
end

-- for specs
Connector.listener = listener
