local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: salvage", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local wns

    before_each(function()
        local ns
        ns, wns = load_workshop({ before = function()
            WoWMock.recipes[300] = { name = "Milling", profession = "Inscription", isSalvage = true,
                schematic = { quantityMax = 5, reagentSlotSchematics = {} } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:900"] = 200, ["i:950"] = 900, ["i:951"] = 3000 } }))
    end)

    local function mill(results)
        S.craft(300, {}, results, { call = function()
            C_TradeSkillUI.CraftSalvage(300, #results, { itemID = 900 }, {})
        end })
    end

    it("compares the value of the milled herbs with the yield", function()
        mill({
            { S.result({ id = 950, qty = 2 }) },
            { S.result({ id = 950, qty = 1 }), S.result({ id = 951, qty = 1, op = 7001 }) },
        })
        local rows = wns.Salvage.Rows({})
        assert.equals(1, #rows)
        local row = rows[1]
        assert.equals("i:900", row.input)
        assert.equals(2, row.operations)
        assert.equals(10, row.used)                 -- 5 herbs per milling
        assert.equals(2000, row.cost)
        assert.equals(3 * 900 + 3000, row.yield)
        assert.equals(3700, row.gain)
        assert.same({ ["i:950"] = 3, ["i:951"] = 1 }, row.outputs)
    end)

    it("turns the yield into lots whose sales count for the salvage", function()
        mill({ { S.result({ id = 951, qty = 1 }) } })
        assert.equals(1000, GoblinomicsWorkshopDB.lots[1].unit)
        wns.Lots.Sell("i:951", 1, 2800)
        local row = wns.Salvage.Rows({})[1]
        assert.equals(2800, row.revenue)
        assert.equals(1800, row.profit)
        assert.equals(0, #wns.Stats.Recipes({}))    -- salvage is not a recipe row
        mill({ { S.result({ id = 950, qty = 1 }) } })     -- a second herb row without sales
        assert.equals("i:900", wns.Salvage.Rows({})[1].input)
        assert.equals(2800 - 2000, wns.Salvage.Rows({})[1].profit)   -- cash basis: both operations cost
    end)

    it("counts the cost of unsold yields right away (cash basis)", function()
        mill({ { S.result({ id = 951 }) } })
        assert.equals(-1000, wns.Stats.Breakdown({}).salvage)
        assert.equals(-1000, wns.Salvage.Rows({})[1].profit)
        assert.equals(3000, wns.Salvage.Rows({})[1].openValue)
        wns.Lots.Sell("i:951", 1, 2800)
        assert.equals(1800, wns.Stats.Breakdown({}).salvage)
    end)

    it("credits yields used in a craft to the salvage while the craft carries their cost", function()
        WoWMock.recipes[400] = { name = "Ring", profession = "Jewelcrafting", schematic = { reagentSlotSchematics = {
            { reagentType = 1, dataSlotIndex = 1, quantityRequired = 1, reagents = { { itemID = 951 } } } } } }
        mill({ { S.result({ id = 951 }) } })                        -- cost 1000, gem lot at 1000
        S.craft(400, {}, { { S.result({ id = 960 }) } })            -- uses the gem
        local ring = GoblinomicsWorkshopDB.crafts[2]
        assert.equals(1000, ring.cost)
        assert.equals(1, #GoblinomicsWorkshopDB.transfers)
        local b = wns.Stats.Breakdown({})
        assert.equals(0, b.salvage)                                 -- -1000 cost + 1000 used
        wns.Lots.Sell("i:960", 1, 4000)
        b = wns.Stats.Breakdown({})
        assert.equals(3000, b.sales)
        assert.equals(3000, b.total)                                -- ring revenue minus ore cost
        assert.equals(1000, wns.Salvage.Rows({})[1].transferred)
    end)

    it("shows salvage costs on the day of the operation in the daily chart", function()
        mill({ { S.result({ id = 951 }) } })
        local days = wns.Stats.Daily(14)
        assert.equals(-1000, days[14].salvage)
    end)
end)
