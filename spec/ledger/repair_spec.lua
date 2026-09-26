-- Schema 2 repair: auction sales that "open all" booked as Mail before the
-- classifier fix are split back into AH/sale bookings (in-game finding, M7).
describe("Ledger: repair of merged mail bookings", function()
    local lns

    before_each(function() lns = select(2, load_ledger()) end)

    local function root(tx, events, deposits)
        return { tx = { ["2026-09-25"] = tx }, ah = { events = events, deposits = deposits or {} } }
    end

    it("splits a Mail booking into the logged sales and keeps other mail gold", function()
        local r = root({
            { 1000, 1, "AH", "sale", 9500, "i:1", 5, nil, "Buyer" },
            { 1001, 1, "Mail", "in", 9500 + 1900 + 50 + 5000, nil, nil, nil, nil, 3 },
        }, {
            { 1000, "sale", "i:1", 5, 10000, 0, "Linen" },   -- already booked
            { 1000, "sale", "i:2", 1, 2000, 0, "Silk" },
            { 1000, "sale", "i:3", 2, 10000, 0, "Wool" },
        }, { ["i:2"] = 50 })
        assert.equals(1, lns.Repair.MergedMail(r))
        local list = r.tx["2026-09-25"]
        assert.equals(4, #list)
        assert.same({ "AH", "sale", 1900 + 50, "i:2" }, { list[2][3], list[2][4], list[2][5], list[2][6] })
        assert.same({ "AH", "sale", 9500, "i:3" }, { list[3][3], list[3][4], list[3][5], list[3][6] })
        assert.same({ "Mail", "in", 5000 }, { list[4][3], list[4][4], list[4][5] })
        local total = 0
        for i = 2, 4 do total = total + list[i][5] end
        assert.equals(9500 + 1900 + 50 + 5000, total)
    end)

    it("spreads a small rest over the sales and leaves mail with a sender alone", function()
        local r = root({
            { 2000, 1, "Mail", "in", 9530 },
            { 2000, 1, "Mail", "in", 700, nil, nil, nil, "Friend" },
        }, { { 1990, "sale", "i:3", 2, 10000, 0, "Wool" } })
        assert.equals(1, lns.Repair.MergedMail(r))
        local list = r.tx["2026-09-25"]
        assert.same({ "AH", "sale", 9530 }, { list[1][3], list[1][4], list[1][5] })
        assert.same({ "Mail", "in", 700 }, { list[2][3], list[2][4], list[2][5] })
    end)

    it("runs as the schema 2 migration", function()
        assert.equals(2, GoblinomicsLedgerDB._schema)
    end)
end)
