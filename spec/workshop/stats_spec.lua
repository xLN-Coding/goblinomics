local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: stats for the new views", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, wns

    before_each(function()
        ns, wns = load_workshop({ before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", qualityItemIDs = { 501, 502 },
                schematic = { reagentSlotSchematics = {
                    { reagentType = 1, dataSlotIndex = 1, quantityRequired = 3, reagents = { { itemID = 11 } } },
                    { reagentType = 1, dataSlotIndex = 2, quantityRequired = 1, reagents = { { itemID = 12 } } } } } }
            WoWMock.recipes[110] = { name = "Flask", profession = "Alchemy", qualityItemIDs = { 511, 512 },
                schematic = { reagentSlotSchematics = {} } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100, ["i:12"] = 200, ["i:501"] = 400,
            ["i:502"] = 900, ["i:511"] = 1000, ["i:512"] = 3000 } }))
        WoWMock.claimedOrder = { orderID = 9, customerName = "C", tipAmount = 5000, consortiumCut = 500, reagents = {} }
    end)

    it("sums profit per day for sales and orders", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2 }) } })          -- cost 500
        wns.Lots.Sell("i:502", 1, 1500)                                       -- +1,000 today
        WoWMock.advance(86400)
        S.craft(100, {}, { { S.result({ id = 502, quality = 2 }) } }, { orderID = 9 })
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 9)          -- 4,500 - 500
        local days = wns.Stats.Daily(7)
        assert.equals(7, #days)
        assert.equals(4000, days[7].orders)
        assert.equals(0, days[7].sales)
        assert.equals(1000, days[6].sales)
        assert.equals(1000, days[6].total)
    end)

    it("compares the window with the period before it", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2, qty = 2 }) } })  -- cost 500 for 2
        wns.Lots.Sell("i:502", 1, 1250)                                       -- +1,000 in the old week
        WoWMock.advance(8 * 86400)
        wns.Lots.Sell("i:502", 1, 2250)                                       -- +2,000 now
        local c = wns.Stats.Compare({ from = WoWMock.now - 7 * 86400 })
        assert.equals(2000, c.current.total)
        assert.equals(1000, c.previous.total)
        assert.equals(100, c.change)
        assert.is_nil(wns.Stats.Compare({}).previous)
    end)

    it("values the open stock at the current market price", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2, qty = 2 }) } })
        local stock = wns.Stats.OpenStock({})
        assert.equals(2, stock.qty)
        assert.equals(500, stock.cost)
        assert.equals(1800, stock.value)
    end)

    it("details a recipe: reagents per craft, history, quality filter and margin", function()
        S.craft(100, {}, {
            { S.result({ id = 502, quality = 2, returned = { { 11, 1 } } }) },   -- cost 400 (saved 100)
            { S.result({ id = 501, quality = 1 }) },                             -- cost 500
        })
        wns.Lots.Sell("i:502", 1, 1200)
        local d = wns.Stats.RecipeDetail(100, {})
        assert.equals(2, d.crafts)
        assert.equals("i:11", d.reagents[1].key)
        assert.equals(3, d.reagents[1].perCraft)
        assert.equals(250, d.reagents[1].costPerCraft)       -- the returned item was not consumed
        assert.equals(500 / 900, d.reagents[1].share)
        assert.equals(50, d.savedPerCraft)
        assert.equals(3, #d.history)
        assert.equals("sale", d.history[1].kind)
        assert.equals(800, d.history[1].profit)
        assert.equals(200, d.margin)                     -- 800 profit on 400 cost
        local q2 = wns.Stats.RecipeDetail(100, {}, 2)
        assert.equals(1, q2.crafts)
        assert.equals(2, q2.row.quality)
        assert.equals(2, #q2.history)
    end)

    it("ranks recipes by concentration value per point", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2, conc = 50 }) } })   -- 500 gain / 50 = 10
        S.craft(110, {}, { { S.result({ id = 512, quality = 2, conc = 100 }) } })  -- 2,000 / 100 = 20
        local list = wns.Concentration.ByRecipe()
        assert.equals(110, list[1].recipe)
        assert.equals(20, list[1].value)
        assert.equals(10, list[2].value)
        assert.equals(10, wns.Concentration.ForRecipe(100).value)
    end)
end)
