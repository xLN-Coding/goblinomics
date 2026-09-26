local fake = require("spec.support.sources")

describe("/gob price", function()
    it("prints prices per role and both valuations, keeping the link's case", function()
        local ns = load_core({ login = true, money = 1 })
        ns.Price.RegisterSource(fake("tsm", 10, {
            market = { ["i:2589"] = 12345 }, saleRate = { ["i:2589"] = 0.5 },
        }))
        WoWMock.items[2589] = { sellPrice = 13 }
        ns.EntryPoints.HandleSlash("price |cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r")
        local out = table.concat(WoWMock.chat, "\n")
        assert.truthy(out:find("i:2589", 1, true))
        assert.truthy(out:find("market: ", 1, true))
        assert.truthy(out:find("(tsm)", 1, true))
        assert.truthy(out:find("saleRate: 0.500", 1, true))
        assert.truthy(out:find("tradable: market, market", 1, true))
        assert.truthy(out:find("bound: vendor, bound", 1, true))
    end)

    it("prints usage without a link", function()
        local ns = load_core({ login = true, money = 1 })
        ns.EntryPoints.HandleSlash("PRICE")
        assert.truthy(WoWMock.chat[1]:find("/gob price", 1, true))
    end)
end)
