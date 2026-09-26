describe("Ledger UI logic", function()
    local ns, lns

    before_each(function()
        ns, lns = load_ledger()
        local S = lns.Store
        S.Add({ time = WoWMock.now, char = "xLN-Blackrock", category = "Vendor", sub = "sell", amount = 100, itemKey = "i:1" })
        S.Add({ time = WoWMock.now + 1, char = "xLN-Blackrock", category = "Mail", sub = "in", amount = 500, tag = "Boosting" })
        S.Add({ time = WoWMock.now + 2, char = "xLN-Blackrock", category = "Transfer", sub = "warbank", amount = -900 })
        S.Add({ time = WoWMock.now - 86400, char = "xLN-Blackrock", category = "Repair", sub = "repair", amount = -40 })
    end)

    it("groups by day with sums excluding transfers, collapsed by default", function()
        local data = lns.LedgerUI.BuildData(lns.Store.Query({}))
        assert.equals(2, #data)
        assert.equals("group", data[1].kind)
        assert.equals(600, data[1].sum)
        assert.equals(-40, data[2].sum)
    end)

    it("registers the tab, the dashboard cards and the settings section", function()
        assert.is_table(ns.UI.GetTab("ledger"))
        local widgets = {}
        for _, w in ipairs(ns.UI.SortedWidgets()) do widgets[w.id] = true end
        for _, id in ipairs({ "ledger.source", "ledger.expense", "ledger.heatmap", "ledger.records", "ledger.auctions",
            "ledger.feed" }) do
            assert.is_true(widgets[id])
        end
        local sections = {}
        for _, s in ipairs(ns.UI.SortedSettings()) do sections[#sections + 1] = s.id end
        assert.same({ "core", "pricing", "ledger" }, sections)
    end)
end)
