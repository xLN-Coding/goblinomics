-- M8: imports from other addons land in the Ledger without duplicates and can be undone.
describe("Ledger: import without duplicates", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, lns, booked

    local function own(offset, category, sub, amount, extra)
        local e = { time = WoWMock.now + offset, char = "xLN-Blackrock", category = category, sub = sub, amount = amount }
        for k, v in pairs(extra or {}) do e[k] = v end
        return lns.Store.Add(e)
    end

    local function entry(offset, category, sub, amount, extra)
        local e = { time = WoWMock.now + offset, char = "xLN-Blackrock", category = category, sub = sub, amount = amount }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end

    before_each(function()
        ns, lns = load_ledger()
        own(-3600, "AH", "sale", 9500, { itemKey = "i:1", quantity = 5 })
        own(-1800, "Repair", "repair", -4000)
        booked = {}
        ns.Bus.On("LEDGER_TRANSACTION", function(_, p) booked[#booked + 1] = p end, "Spec")
    end)

    it("recognises own bookings within the window and imports the rest in time order", function()
        local batch = { source = "tsm:1", entries = {
            entry(-3600 + 120, "AH", "sale", 9975, { itemKey = "i:1", quantity = 5 }),    -- gross in TSM
            entry(-1800 - 200, "Repair", "repair", -4000),
            entry(-86400, "AH", "purchase", -7000, { itemKey = "i:2", quantity = 10 }),
            entry(-7200, "Crafting", "commission", 50000),
        }, events = {
            { time = WoWMock.now - 86400, kind = "purchase", itemKey = "i:2", quantity = 10, amount = 7000 },
        } }
        local preview = ns.API.Ledger:Import(batch, true)
        assert.equals(2, preview.added)
        assert.equals(2, preview.duplicates)
        assert.equals(1, preview.categories.AH.new)
        assert.equals(1, preview.categories.AH.duplicates)
        assert.equals(0, #booked)

        local result = ns.API.Ledger:Import(batch)
        assert.equals(2, result.added)
        assert.equals(1, result.events)
        assert.equals(2, #booked)
        assert.is_true(booked[1].imported)
        local rows = lns.Store.Query({})
        assert.equals(4, #rows)
        local day = os.date("%Y-%m-%d", WoWMock.now)
        local list = GoblinomicsLedgerDB.tx[day]
        for i = 2, #list do assert.is_true(list[i - 1][1] <= list[i][1]) end
        assert.equals("tsm:1", booked[1].source)
    end)

    it("imports nothing twice, not even from a second source", function()
        local batch = { source = "tsm:1", entries = { entry(-86400, "AH", "purchase", -7000, { itemKey = "i:2", quantity = 10 }) },
            events = { { time = WoWMock.now - 86400, kind = "purchase", itemKey = "i:2", quantity = 10, amount = 7000 } } }
        ns.API.Ledger:Import(batch)
        batch.source = "jnl:1"
        batch.entries[1].time = batch.entries[1].time + 60
        local again = ns.API.Ledger:Import(batch)
        assert.equals(0, again.added)
        assert.equals(1, again.duplicates)
        assert.equals(0, again.events)
    end)

    it("never merges imported bookings and removes a whole import", function()
        ns.API.Ledger:Import({ source = "tsm:2", entries = {
            entry(-500, "Mail", "in", 100), entry(-490, "Mail", "in", 200) } })
        own(-480, "Mail", "in", 300)
        assert.equals(5, #lns.Store.Query({}))
        local removed = ns.API.Ledger:RemoveImport("tsm:2")
        assert.equals(2, removed)
        assert.equals(3, #lns.Store.Query({}))
    end)
end)
