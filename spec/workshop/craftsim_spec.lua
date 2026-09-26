local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: CraftSim connector", function()
    after_each(function()
        assert.same({}, WoWMock.errors)
        _G.CraftSimAPI = nil
    end)

    local ns, registered

    local function loadConnector()
        registered = {}
        _G.CraftSimAPI = { RegisterEvents = function(_, tbl, events) registered[#registered + 1] = { tbl, events } end }
        local cns = {}
        for _, file in ipairs(toc_files("Connectors/CraftSim/Goblinomics_Connector_CraftSim.toc", "Connectors/CraftSim/")) do
            load_addon_file(file, "Goblinomics_Connector_CraftSim", cns)
        end
        WoWMock.fire("ADDON_LOADED", "Goblinomics_Connector_CraftSim")
    end

    before_each(function()
        ns = select(1, load_workshop({ before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", schematic = { reagentSlotSchematics = {
                { reagentType = 1, dataSlotIndex = 1, quantityRequired = 3, reagents = { { itemID = 11 } } } } } }
            loadConnector()
        end }))
        WoWMock.flush()
    end)

    local function fireCraftSim(recipeID, perCraft, perItem)
        local listener = registered[1][1]
        listener:CRAFTSIM_CRAFT_RECIPE_DATA_PREPARED({ recipeID = recipeID,
            priceData = { craftingCosts = perCraft, expectedCostsPerItem = perItem } })
    end

    it("registers for CraftSim's craft event and stores its cost for comparison", function()
        assert.same({ "CRAFTSIM_CRAFT_RECIPE_DATA_PREPARED" }, registered[1][2])
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100 } }))
        S.craft(100, {}, { { S.result({ id = 502 }) }, { S.result({ id = 502 }) } }, { call = function()
            C_TradeSkillUI.CraftRecipe(100, 2, {})
            fireCraftSim(100, 320, 320)
        end })
        local crafts = GoblinomicsWorkshopDB.crafts
        assert.equals(300, crafts[1].cost)          -- own reagent prices stay primary
        assert.equals(320, crafts[1].craftSimCost)
    end)

    it("falls back to CraftSim's estimate when no reagent has a price", function()
        S.craft(100, {}, { { S.result({ id = 502, qty = 2 }) } }, { call = function()
            fireCraftSim(100, 500, 250)             -- CraftSim's hook ran first
            C_TradeSkillUI.CraftRecipe(100, 1, {})
        end })
        local r = GoblinomicsWorkshopDB.crafts[1]
        assert.equals(500, r.cost)
        assert.equals("craftsim", r.costSource)
    end)
end)
