local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: purchase prices", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, wns, lns

    before_each(function()
        ns, wns, lns = load_workshop({ ledger = true, before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", schematic = { reagentSlotSchematics = {
                { reagentType = 1, dataSlotIndex = 1, quantityRequired = 3, reagents = { { itemID = 11 } } } } } }
            WoWMock.recipes[120] = { name = "Elixir", profession = "Alchemy", schematic = { reagentSlotSchematics = {
                { reagentType = 1, dataSlotIndex = 1, quantityRequired = 2, reagents = { { itemID = 502 } } } } } }
            WoWMock.recipes[300] = { name = "Prospecting", profession = "Jewelcrafting", isSalvage = true,
                schematic = { quantityMax = 5, reagentSlotSchematics = {} } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100, ["i:900"] = 1000, ["i:951"] = 9000 } }))
    end)

    local function buy(key, qty, total, category, sub)
        lns.Store.Add({ time = WoWMock.now, char = "xLN-Blackrock", category = category or "AH", sub = sub or "purchase",
            amount = -total, itemKey = key, quantity = qty })
    end

    local function prospect(n)
        local crafts = {}
        for i = 1, n do crafts[i] = { S.result({ id = 951 }) } end
        S.craft(300, {}, crafts, { call = function() C_TradeSkillUI.CraftSalvage(300, n, { itemID = 900 }, {}) end })
    end

    it("uses what was paid for bought reagents and the market price for the rest", function()
        buy("i:900", 7, 5600)                          -- 800 each on the auction house
        prospect(2)                                    -- 10 ore: 7 bought + 3 at market
        local crafts = GoblinomicsWorkshopDB.crafts
        assert.equals(4000, crafts[1].cost)            -- 5 x 800
        assert.equals(2 * 800 + 3 * 1000, crafts[2].cost)
        local line = crafts[2].reagents[1]
        assert.equals(2, line[5])                      -- two of them from purchases
    end)

    it("shares purchase lots between crafts and salvage and ignores lots older than 14 days", function()
        buy("i:11", 3, 150)
        S.craft(100, {}, { { S.result({ id = 502 }) } })      -- takes the 3 bought herbs
        assert.equals(150, GoblinomicsWorkshopDB.crafts[1].cost)
        buy("i:900", 5, 2500)
        WoWMock.advance(15 * 86400)
        prospect(1)
        assert.equals(5000, GoblinomicsWorkshopDB.crafts[2].cost)   -- expired: market price
    end)

    it("takes vendor purchases once the item is attached to the booking", function()
        local tx = lns.Store.Add({ time = WoWMock.now, char = "xLN-Blackrock", category = "Vendor", sub = "buy",
            amount = -60 })
        lns.Store.Update(tx, { itemKey = "i:11", quantity = 3 })
        S.craft(100, {}, { { S.result({ id = 502 }) } })
        assert.equals(60, GoblinomicsWorkshopDB.crafts[1].cost)
    end)

    it("uses crafted intermediates at their craft cost and removes them from the open stock", function()
        S.craft(100, {}, { { S.result({ id = 502, qty = 2 }) } })   -- 300 for 2 = 150 each
        S.craft(120, {}, { { S.result({ id = 503 }) } })            -- uses both
        assert.equals(300, GoblinomicsWorkshopDB.crafts[2].cost)
        assert.equals(2, GoblinomicsWorkshopDB.crafts[2].reagents[1][6])
        for _, lot in ipairs(wns.Lots.Open()) do assert.are_not.equal("i:502", lot.key) end
    end)

    it("removes resold reagents from the purchase lots", function()
        buy("i:11", 3, 150)
        ns.Bus.Emit("LEDGER_AH_EVENT", { kind = "sale", itemKey = "i:11", quantity = 3, amount = 600, net = 570 })
        S.craft(100, {}, { { S.result({ id = 502 }) } })
        assert.equals(300, GoblinomicsWorkshopDB.crafts[1].cost)
    end)

    it("recomputes stored crafts once from the ledger history", function()
        -- a craft stored with the old market-price rule
        prospect(1)
        local r = GoblinomicsWorkshopDB.crafts[1]
        assert.equals(5000, r.cost)
        -- the purchase that happened before (booked in the ledger), then the sale of the gem
        lns.Store.Add({ time = r.time - 60, char = "xLN-Blackrock", category = "AH", sub = "purchase", amount = -2000,
            itemKey = "i:900", quantity = 5 })
        lns.Store.Add({ time = r.time + 60, char = "xLN-Blackrock", category = "AH", sub = "sale", amount = 8000,
            itemKey = "i:951", quantity = 1 })
        GoblinomicsWorkshopDB.recomputed = nil
        assert.is_true(wns.Recompute.Needed())
        assert.is_true(wns.Recompute.Run())
        assert.equals(2000, r.cost)
        local m = GoblinomicsWorkshopDB.matches
        assert.equals(1, #m)
        assert.equals(6000, m[1].revenue - m[1].cost)
        assert.is_false(wns.Recompute.Needed())
    end)
end)
