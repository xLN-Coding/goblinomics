describe("Ledger: store", function()
    local ns, lns, S

    before_each(function()
        ns, lns = load_ledger()
        S = lns.Store
    end)

    local function add(e)
        e.char = e.char or "xLN-Blackrock"
        return S.Add(e)
    end

    it("stores compact transactions per day with a character index", function()
        local tx = add({ time = WoWMock.now, category = "Vendor", sub = "sell", amount = 500, itemKey = "i:1", quantity = 2 })
        local day = os.date("%Y-%m-%d", WoWMock.now)
        assert.equals(tx, GoblinomicsLedgerDB.tx[day][1])
        assert.equals(1, tx[S.F.CHAR])
        assert.same({ "xLN-Blackrock" }, GoblinomicsLedgerDB.charIndex)
    end)

    it("merges item-less bookings of the same kind within 60 s", function()
        add({ time = WoWMock.now, category = "Loot", sub = "money", amount = 10 })
        local tx = add({ time = WoWMock.now + 30, category = "Loot", sub = "money", amount = 15 })
        assert.equals(25, tx[S.F.AMT])
        assert.equals(2, tx[S.F.COUNT])
        add({ time = WoWMock.now + 200, category = "Loot", sub = "money", amount = 5 })
        add({ time = WoWMock.now + 210, category = "Vendor", sub = "sell", amount = 5, itemKey = "i:1" })
        local day = os.date("%Y-%m-%d", WoWMock.now)
        assert.equals(3, #GoblinomicsLedgerDB.tx[day])
    end)

    it("does not merge across signs, tags or characters", function()
        add({ time = WoWMock.now, category = "Mail", sub = "in", amount = 10 })
        add({ time = WoWMock.now, category = "Mail", sub = "in", amount = -10 })
        add({ time = WoWMock.now, category = "Mail", sub = "in", amount = 10, tag = "Boosting" })
        add({ time = WoWMock.now, category = "Mail", sub = "in", amount = 10, char = "Alt-Blackrock" })
        assert.equals(4, #GoblinomicsLedgerDB.tx[os.date("%Y-%m-%d", WoWMock.now)])
    end)

    it("emits LEDGER_TRANSACTION and a debounced LEDGER_CHANGED", function()
        local got, changed = {}, 0
        ns.Bus.On("LEDGER_TRANSACTION", function(_, p) got[#got + 1] = p end, "Spec")
        ns.Bus.On("LEDGER_CHANGED", function() changed = changed + 1 end, "Spec")
        add({ time = WoWMock.now, category = "Quest", sub = "reward", amount = 100 })
        add({ time = WoWMock.now, category = "Repair", sub = "repair", amount = -100 })
        assert.equals("Quest", got[1].category)
        WoWMock.advance(0.5)
        assert.equals(1, changed)
    end)

    it("queries with filters, newest first, and totals without transfers", function()
        add({ time = WoWMock.now - 86400, category = "Vendor", sub = "sell", amount = 100, itemKey = "i:1" })
        add({ time = WoWMock.now, category = "Repair", sub = "repair", amount = -40 })
        add({ time = WoWMock.now + 1, category = "Transfer", sub = "warbank", amount = -1000 })
        add({ time = WoWMock.now + 2, category = "Mail", sub = "in", amount = 500, tag = "Boosting" })
        local rows = S.Query({})
        assert.equals(4, #rows)
        assert.equals("Mail", rows[1].category)
        assert.same({ 600, -40, 560 }, { S.Totals(rows) })
        assert.equals(1, #S.Query({ tag = "Boosting" }))
        assert.equals(3, #S.Query({ from = WoWMock.now - 10 }))
        assert.same({ "Boosting" }, S.Tags())
    end)

    it("updates category and tag of a stored transaction", function()
        local tx = add({ time = WoWMock.now, category = "Other", sub = "trade", amount = 5000, note = "Gallywix" })
        S.Update(tx, { category = "Mail", tag = "Boosting" })
        local row = S.Query({})[1]
        assert.same({ "Mail", "Boosting" }, { row.category, row.tag })
    end)
end)
