local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: retention", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("folds old crafts and matches into aggregates that all-time stats include", function()
        local ns, wns = load_workshop({ before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", schematic = { reagentSlotSchematics = {
                { reagentType = 1, dataSlotIndex = 1, quantityRequired = 3, reagents = { { itemID = 11 } } } } } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100 } }))
        S.craft(100, {}, { { S.result({ id = 502, qty = 2 }) } })
        wns.Lots.Sell("i:502", 1, 1000)
        WoWMock.advance(100 * 86400)
        S.craft(100, {}, { { S.result({ id = 502 }) } })
        wns.Retention.Run()
        local root = GoblinomicsWorkshopDB
        assert.equals(1, #root.crafts)
        assert.equals(0, #root.matches)
        assert.equals(1, root.aggregates[100].crafts)
        local row = wns.Stats.Recipes({})[1]
        assert.equals(2, row.crafts)
        assert.equals(3, row.made)
        assert.equals(1000 - 150, row.profit)
        local recent = wns.Stats.Recipes({ from = WoWMock.now - 86400 })[1]
        assert.equals(1, recent.crafts)
    end)
end)
