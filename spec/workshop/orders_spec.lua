local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: crafting orders", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local wns

    before_each(function()
        local ns
        ns, wns = load_workshop({ before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", qualityItemIDs = { 501, 502 },
                schematic = { reagentSlotSchematics = {
                    { reagentType = 1, dataSlotIndex = 1, quantityRequired = 3, reagents = { { itemID = 11 } } },
                    { reagentType = 1, dataSlotIndex = 2, quantityRequired = 2, reagents = { { itemID = 21 }, { itemID = 22 } } },
                } } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100, ["i:21"] = 1000, ["i:700"] = 5000 } }))
        WoWMock.claimedOrder = { orderID = 77, customerName = "Customer", tipAmount = 50000, consortiumCut = 5000,
            npcOrderRewards = { { itemLink = S.link(700, "Reward"), count = 2 } },
            reagents = { { source = 0, reagentInfo = { reagent = { itemID = 11 }, quantity = 3 } } } }
    end)

    it("books commission and rewards against the own reagents, without a lot", function()
        S.craft(100, { { reagent = { itemID = 21 }, quantity = 2, dataSlotIndex = 2 } },
            { { S.result({ id = 502, quality = 2 }) } }, { orderID = 77 })
        assert.equals(0, #GoblinomicsWorkshopDB.lots)
        local o = GoblinomicsWorkshopDB.orders[1]
        assert.equals(2000, o.cost)                    -- the customer supplied reagent 11
        assert.same({ { 11, 3, 0 } }, GoblinomicsWorkshopDB.crafts[1].orderReagents)
        assert.equals("crafted", o.status)
        assert.equals(0, #wns.Orders.List({}))
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 77)
        assert.equals(45000, o.commission)
        assert.equals(10000, o.rewards)
        assert.equals(53000, o.profit)
        assert.equals("Customer", o.customer)
        assert.equals(1, #wns.Orders.List({}))
    end)

    it("ignores failed responses and books orders without a recorded craft", function()
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 3, 77)
        assert.equals(0, #GoblinomicsWorkshopDB.orders)
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 77)
        local o = GoblinomicsWorkshopDB.orders[1]
        assert.equals(45000, o.commission)
        assert.is_true(o.incomplete)
    end)

    it("shows the counted reagents and can count an order without own cost", function()
        S.craft(100, { { reagent = { itemID = 21 }, quantity = 2, dataSlotIndex = 2 } },
            { { S.result({ id = 502, quality = 2 }) } }, { orderID = 77 })
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 77)
        local o = GoblinomicsWorkshopDB.orders[1]
        assert.equals("i:21", wns.Orders.CraftOf(o).reagents[1][1])
        wns.Orders.ClearCost(o)
        assert.equals(0, o.cost)
        assert.equals(55000, o.profit)
        assert.is_true(o.manual)
    end)

    it("counts resourcefulness returns of customer reagents as a pure gain", function()
        S.craft(100, { { reagent = { itemID = 21 }, quantity = 2, dataSlotIndex = 2 } },
            { { S.result({ id = 502, quality = 2, returned = { { 11, 2 } } }) } }, { orderID = 77 })
        local o = GoblinomicsWorkshopDB.orders[1]
        assert.equals(2000 - 200, o.cost)              -- reagent 11 came from the customer, its return is free
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 77)
        assert.equals(45000 + 10000 - 1800, o.profit)
    end)
end)
