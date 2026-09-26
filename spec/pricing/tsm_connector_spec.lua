local C = require("spec.support.connectors")

describe("Pricing: TSM connector", function()
    local ns

    after_each(C.cleanup)

    local function boot(data, valid)
        C.tsm(data, valid or {})
        ns = C.boot({}, { C.TSM })
    end

    it("registers as the tsm source and uses the configured source per role", function()
        boot({
            DBMarket = { ["i:1"] = 500, ["i:2589"] = 1 },
            Destroy = { ["i:1"] = 300 },
            ["(DBRegionSaleRate)*1000"] = { ["i:1"] = 420 },
        })
        assert.same({ 500, "tsm" }, { ns.Price.Get("i:1", "market") })
        assert.equals(300, (ns.Price.Get("i:1", "destroy")))
        assert.equals(0.42, (ns.Price.Get("i:1", "saleRate")))
    end)

    it("follows changed source strings", function()
        boot({ DBMarket = { ["i:1"] = 500 }, DBRecent = { ["i:1"] = 450 } })
        ns.Price.Config().tsm.market = "DBRecent"
        ns.Price.Invalidate()
        assert.equals(450, (ns.Price.Get("i:1", "market")))
    end)

    it("falls back to the base key for gear variants", function()
        boot({ DBMarket = { ["i:212072"] = 777 } })
        assert.equals(777, (ns.Price.Get("i:212072::1:6652", "market")))
    end)

    it("survives TSM errors", function()
        boot({})
        _G.TSM_API.GetCustomPriceValue = function() error("TSM exploded") end
        assert.is_nil(ns.Price.Get("i:1", "market"))
        assert.equals(0, #WoWMock.errors)
    end)

    it("reports missing app data and validates source strings", function()
        boot({}, { DBMarket = true })
        local src = ns.Price.GetSource("tsm")
        assert.truthy(src:Status().note:find("app data", 1, true))
        assert.is_true(src.ValidateSource("DBMarket"))
        assert.is_false(src.ValidateSource("nonsense"))
        assert.same({ "DBMarket", "DBRecent", "DBRegionSaleRate", "Destroy" }, src.KnownSources())
    end)

    it("unregisters when the module is disabled", function()
        boot({ DBMarket = { ["i:1"] = 500 } })
        ns.Modules.SetEnabled("Goblinomics_Connector_TSM", false)
        assert.is_nil(ns.Price.GetSource("tsm"))
        assert.is_nil(ns.Price.Get("i:1", "market"))
    end)
end)
