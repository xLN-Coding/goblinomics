describe("Ledger: retention", function()
    local lns

    before_each(function()
        lns = select(2, load_ledger())
    end)

    it("aggregates days older than 90 days and keeps the totals", function()
        local S = lns.Store
        local old = WoWMock.now - 100 * 86400
        S.Add({ time = old, char = "xLN-Blackrock", category = "Loot", sub = "money", amount = 100 })
        S.Add({ time = old + 120, char = "xLN-Blackrock", category = "Loot", sub = "money", amount = 50 })
        S.Add({ time = old + 300, char = "xLN-Blackrock", category = "Mail", sub = "in", amount = 1000, tag = "Boosting" })
        S.Add({ time = WoWMock.now, char = "xLN-Blackrock", category = "Vendor", sub = "sell", amount = 7, itemKey = "i:1" })
        local before = { S.Totals(S.Query({})) }
        WoWMock.advance(10)
        WoWMock.flush()
        local oldDay = os.date("%Y-%m-%d", old)
        assert.is_nil(GoblinomicsLedgerDB.tx[oldDay])
        assert.same({ amount = 150, count = 2 }, GoblinomicsLedgerDB.daily[oldDay][1]["Loot|"])
        assert.same({ amount = 1000, count = 1 }, GoblinomicsLedgerDB.daily[oldDay][1]["Mail|Boosting"])
        assert.same(before, { S.Totals(S.Query({})) })
        local aggregated = 0
        for _, row in ipairs(S.Query({ tag = "Boosting" })) do
            if row.aggregated then aggregated = aggregated + row.amount end
        end
        assert.equals(1000, aggregated)
    end)
end)
