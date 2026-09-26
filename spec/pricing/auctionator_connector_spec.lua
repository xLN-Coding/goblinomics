local C = require("spec.support.connectors")

describe("Pricing: Auctionator connector", function()
    local ns

    after_each(C.cleanup)

    it("looks up plain items by id and variants by item string", function()
        C.auctionator({ ["id:2589"] = 12, ["item:212072::::::::::::1:6652"] = 5000 }, {})
        ns = C.boot({}, { C.AUC })
        assert.same({ 12, "auctionator" }, { ns.Price.Get("i:2589", "market") })
        assert.equals(5000, (ns.Price.Get("i:212072::1:6652", "market")))
    end)

    it("provides a disenchant value as destroy and no sale rate", function()
        C.auctionator({}, { ["item:212072::::::::::::1:6652"] = 800 })
        ns = C.boot({}, { C.AUC })
        assert.equals(800, (ns.Price.Get("i:212072::1:6652", "destroy")))
        assert.is_nil(ns.Price.Get("i:212072::1:6652", "saleRate"))
    end)

    it("invalidates the cache when new scan data arrives", function()
        local prices = { ["id:1"] = 10 }
        C.auctionator(prices, {})
        ns = C.boot({}, { C.AUC })
        assert.equals(10, (ns.Price.Get("i:1", "market")))
        prices["id:1"] = 20
        Auctionator.FireUpdate()
        assert.equals(20, (ns.Price.Get("i:1", "market")))
    end)

    it("reports missing scan data", function()
        C.auctionator({}, {}, false)
        ns = C.boot({}, { C.AUC })
        assert.truthy(ns.Price.GetSource("auctionator"):Status().note:find("scan", 1, true))
    end)
end)
