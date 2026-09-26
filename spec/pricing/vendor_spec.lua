describe("Pricing: vendor source", function()
    local ns

    before_each(function()
        ns = load_core({ login = true, money = 1 })
    end)

    it("returns the merchant sell price", function()
        WoWMock.items[2589] = { sellPrice = 13 }
        assert.same({ 13, "vendor" }, { ns.Price.Get("i:2589", "vendor") })
    end)

    it("treats a sell price of 0 as no value", function()
        WoWMock.items[5] = { sellPrice = 0 }
        assert.is_nil(ns.Price.Get("i:5", "vendor"))
    end)

    it("uses the exact variant for keys with bonus ids", function()
        WoWMock.items["item:212072::::::::::::1:6652"] = { sellPrice = 999 }
        WoWMock.items[212072] = { sellPrice = 1 }
        assert.equals(999, (ns.Price.Get("i:212072::1:6652", "vendor")))
    end)

    it("requests missing item data and invalidates when it arrives", function()
        local value, _, pending = ns.Price.Get("i:77", "vendor")
        assert.is_nil(value)
        assert.is_true(pending)
        assert.same({ 77 }, WoWMock.itemRequests)
        WoWMock.items[77] = { sellPrice = 40 }
        WoWMock.fire("ITEM_DATA_LOAD_RESULT", 77, true)
        assert.equals(40, (ns.Price.Get("i:77", "vendor")))
        assert.is_false(ns.Events.ListRegistered and (function()
            for _, r in ipairs(ns.Events.ListRegistered()) do
                if r.event == "ITEM_DATA_LOAD_RESULT" then return true end
            end
            return false
        end)())
    end)

    it("has no vendor price for battle pets", function()
        assert.is_nil(ns.Price.Get("p:1234:25:3", "vendor"))
    end)
end)
