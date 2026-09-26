describe("Ledger: dashboard cards", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, lns, C

    local function book(offsetDays, category, amount, extra)
        local e = { time = WoWMock.now + offsetDays * 86400, char = "xLN-Blackrock", category = category, sub = "x",
            amount = amount }
        for k, v in pairs(extra or {}) do e[k] = v end
        return lns.Store.Add(e)
    end

    before_each(function()
        ns, lns = load_ledger()
        C = lns.LedgerCards
        book(0, "AH", 50000, { sub = "sale" })
        book(0, "Mail", 90000, { tag = "Boosting" })
        book(-1, "AH", 30000, { sub = "sale" })
        book(-1, "Repair", -4000)
        book(-2, "AH", -25000, { sub = "purchase", itemKey = "i:2589", quantity = 20 })
        book(-2, "Transfer", -900000)
        book(-20, "Quest", 10000)
    end)

    it("finds the top gold sources (tags first) and the most expensive expense", function()
        local data = C.Data(ns.Dashboard.Context(7))
        assert.equals("Boosting", data.sources[1].label)
        assert.equals(90000, data.sources[1].amount)
        assert.equals("Auction House", data.sources[2].label)
        assert.equals(80000, data.sources[2].amount)
        assert.equals(-25000, data.topExpense.amount)           -- transfers never count
        assert.equals("i:2589", data.topExpense.itemKey)
        assert.equals("AH", data.topExpenseCategory.category)
        assert.equals(170000, data.income)
    end)

    it("includes daily aggregates for long periods", function()
        lns.Retention.Aggregate(GoblinomicsLedgerDB, os.date("%Y-%m-%d", WoWMock.now - 20 * 86400))
        local data = C.Data(ns.Dashboard.Context(30))
        assert.equals(180000, data.income)
    end)

    it("builds a heatmap of whole weeks ending with the current week", function()
        local map = C.Heatmap(ns.Dashboard.Context(30))
        assert.equals(5, map.weeks)
        assert.equals(35, #map.cells)
        assert.equals(0, map.cells[1].row)                       -- Monday first
        local today = os.date("%Y-%m-%d", WoWMock.now)
        local found
        for _, cell in ipairs(map.cells) do if cell.key == today then found = cell end end
        assert.equals(140000, found.net)
        assert.equals(4, C.Heatmap(ns.Dashboard.Context(1)).weeks)
        assert.equals(53, C.Heatmap(ns.Dashboard.Context(365)).weeks)
    end)

    it("reports the best day and the streak of plus days", function()
        local r = C.Records()
        assert.equals(140000, r.bestDay.net)
        assert.equals(2, r.streak)                               -- today and yesterday; the day before is negative
    end)

    it("sums auction house figures and lists the latest bookings", function()
        lns.AuctionLog.Post("i:1", 1, 100)
        lns.AuctionLog.Sale("i:1", "X", 1, 5000, 4750)
        lns.AuctionLog.Expired("i:1", 1)
        local a = C.Auctions(ns.Dashboard.Context(7))
        assert.equals(1, a.sold)
        assert.equals(5000, a.revenue)
        assert.equals(0.5, a.saleRate)
        local feed = C.Feed(3)
        assert.equals(3, #feed)
        assert.equals("Boosting", feed[1].tag)
    end)

    it("sums the net income per day and groups long periods", function()
        local ctx = ns.Dashboard.Context(7)
        local data = C.Data(ctx)
        assert.equals(50000 + 90000 + 30000, data.income)
        assert.equals(-4000 - 25000, data.expense)
        local buckets = C.NetBuckets(ctx, 60)
        assert.equals(7, #buckets)
        assert.equals(140000, buckets[7].net)
        assert.equals(26000, buckets[6].net)
        assert.equals(-25000, buckets[5].net)
        local long = C.NetBuckets(ns.Dashboard.Context(365), 60)
        assert.equals(53, #long)                     -- 7 days per bar
        local total = 0
        for _, b in ipairs(long) do total = total + b.net end
        assert.equals(50000 + 90000 + 30000 - 4000 - 25000 + 10000, total)
    end)

    it("builds all ledger cards on the dashboard", function()
        local tab = ns.UI.GetTab("dashboard")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        assert.equals(7, #ns.Dashboard.State().cards)
        tab.onHide()
    end)
end)
