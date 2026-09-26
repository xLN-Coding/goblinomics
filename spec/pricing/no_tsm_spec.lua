-- M2 acceptance: without TSM everything runs over Auctionator or the vendor price,
-- and the gaps are marked.
local C = require("spec.support.connectors")

describe("Pricing without TSM", function()
    after_each(C.cleanup)

    it("values items from Auctionator and the vendor price and marks the missing sale rate", function()
        C.auctionator({ ["id:2589"] = 500 }, {})
        local ns = C.boot({}, { C.AUC })
        WoWMock.items[2589] = { sellPrice = 10 }
        WoWMock.items[3000] = { sellPrice = 70 }
        assert.is_nil(ns.Price.GetSource("tsm"))

        local r = ns.Value.Evaluate("i:2589", { quantity = 2 })
        assert.equals("auctionator", r.sources.market)
        assert.equals(500, r.unit)
        assert.equals("market", r.tier)
        assert.is_true(r.gaps.saleRate)

        local vendorOnly = ns.Value.Evaluate("i:3000")
        assert.same({ "vendor", "vendor", 70 }, { vendorOnly.rule, vendorOnly.tier, vendorOnly.unit })
    end)

    it("falls back to the vendor price when no market source is installed", function()
        local ns = load_core({ login = true, money = 1 })
        WoWMock.items[5] = { sellPrice = 33 }
        local r = ns.Value.Evaluate("i:5")
        assert.same({ 33, "vendor" }, { r.unit, r.rule })
        assert.is_true(r.gaps.market)
    end)

    it("prefers TSM when both are installed and Auctionator when configured", function()
        C.tsm({ DBMarket = { ["i:1"] = 900 } }, {})
        C.auctionator({ ["id:1"] = 800 }, {})
        local ns = C.boot({}, { C.TSM, C.AUC })
        assert.equals("tsm", select(2, ns.Price.Get("i:1", "market")))
        ns.Price.SetPreferred("auctionator")
        assert.equals("auctionator", select(2, ns.Price.Get("i:1", "market")))
    end)
end)
