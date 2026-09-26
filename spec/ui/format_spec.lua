describe("UI: language formats", function()
    local ns
    before_each(function() ns = load_core({ boot = true }) end)

    it("formats in English by default", function()
        local F = ns.Format
        assert.equals("25%", F.Percent(0.25))
        assert.equals("12.5", F.Number(12.5, 1))
        local t = os.time({ year = 2026, month = 9, day = 26, hour = 12 })
        assert.equals("09/26", F.Date(t))
        assert.equals("09/26/2026", F.Date(t, "long"))
        assert.equals("09/26", F.Day("2026-09-26"))
        assert.equals("12.3K", ns.Money.Format(123000000, { abbreviate = true, icons = false }):match("^[%d%.,]+K"))
    end)

    it("uses the German decimal comma, percent space and date order", function()
        ns.Locale.Activate("deDE")
        local F = ns.Format
        assert.equals("25 %", F.Percent(0.25))
        assert.equals("12,5", F.Number(12.5, 1))
        assert.equals("26.09.", F.Day("2026-09-26"))
        assert.equals("26.09.2026", F.Day("2026-09-26", "long"))
        assert.truthy(ns.Money.Format(123000000, { abbreviate = true, icons = false }):find("12,3K", 1, true))
        assert.equals("2,5K", ns.Charts.AxisLabel(2500 * 10000))
    end)
end)
