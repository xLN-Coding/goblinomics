describe("Vault UI registration", function()
    it("registers the tab, the dashboard cards and the settings section without frames", function()
        local ns = load_vault()
        assert.is_table(ns.UI.GetTab("vault"))
        local ids = {}
        for _, w in ipairs(ns.UI.SortedWidgets()) do ids[#ids + 1] = w.id end
        assert.same({ "vault.wealth", "vault.gallywix", "vault.chars", "vault.goals" }, ids)
        local sections = {}
        for _, s in ipairs(ns.UI.SortedSettings()) do sections[#sections + 1] = s.id end
        assert.same({ "core", "pricing", "vault" }, sections)
        assert.is_false(ns.UI.IsShown())
    end)

    it("shows the data freshness in the header logo tooltip", function()
        local ns, vns = load_vault()
        WoWMock.flush(); WoWMock.advance(3); WoWMock.flush()
        assert.is_table(vns.Networth.Get())
        _G.GameTooltip.lines = {}
        ns.UI.FillHeaderTooltip(GameTooltip)
        assert.truthy(table.concat(GameTooltip.lines, "\n"):find("Data freshness=", 1, true))
    end)
end)
