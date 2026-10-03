-- Named price sources of a provider (e.g. TSM's DBRecent) through API.Price:Query.
local fake = require("spec.support.sources")

describe("Price: named sources", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("asks providers that know named sources and returns the first value", function()
        local ns = load_core({ login = true })
        local plain = fake("auctionator", 20, { market = { ["i:1"] = 10 } })
        local tsm = fake("tsm", 10, { market = { ["i:1"] = 12 } })
        function tsm:Query(key, name) return name == "DBRecent" and key == "i:1" and 9 or nil end
        ns.Price.RegisterSource(plain)
        assert.is_nil(ns.API.Price:Query("i:1", "DBRecent"))
        ns.Price.RegisterSource(tsm)
        assert.same({ 9, "tsm" }, { ns.API.Price:Query("i:1", "DBRecent") })
        assert.is_nil(ns.API.Price:Query("i:1", "DBHistorical"))
        assert.is_nil(ns.API.Price:Query(nil, "DBRecent"))
    end)
end)
