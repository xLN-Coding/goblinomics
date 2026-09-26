-- M9: a switched-off module disappears from the whole UI at once and comes back when switched on.
describe("UI: switched-off modules are hidden", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local function ids(list)
        local set = {}
        for _, spec in ipairs(list) do set[spec.id] = true end
        return set
    end

    it("hides tab, card and settings of the Gatherer and brings them back", function()
        local ns = load_gatherer()
        local id = "Goblinomics_Gatherer"
        assert.equals(id, ns.UI.GetTab("gatherer").module)
        assert.is_true(ids(ns.UI.SortedTabs()).gatherer)
        assert.is_true(ids(ns.UI.SortedWidgets())["gatherer.farming"])
        assert.is_true(ids(ns.UI.SortedSettings()).gatherer)
        ns.Modules.SetEnabled(id, false)
        assert.is_nil(ids(ns.UI.SortedTabs()).gatherer)
        assert.is_nil(ids(ns.UI.SortedWidgets())["gatherer.farming"])
        assert.is_nil(ids(ns.UI.SortedSettings()).gatherer)
        ns.Modules.SetEnabled(id, true)
        assert.is_true(ids(ns.UI.SortedTabs()).gatherer)
        assert.is_true(ids(ns.UI.SortedSettings()).gatherer)
    end)

    it("hides the Jealousmeter panel and the Vault tooltip lines", function()
        local ns = load_vault()
        assert.is_table(ns.UI.GetSidePanel())
        ns.Modules.SetEnabled("Goblinomics_Vault", false)
        assert.is_nil(ns.UI.GetSidePanel())
        GameTooltip:SetOwner(UIParent)
        ns.UI.FillTooltipProviders(GameTooltip)
        assert.equals(0, #GameTooltip.lines)
    end)

    it("falls back to General in the settings and to the dashboard in the window", function()
        local ns = load_gatherer()
        ns.UI.GetTab("settings").build(CreateFrame("Frame"))
        ns.UI.SelectSettings("gatherer")
        assert.equals("gatherer", ns.UI.settingsPage.selected)
        ns.Modules.SetEnabled("Goblinomics_Gatherer", false)
        assert.equals("core", ns.UI.settingsPage.selected)
        ns.UI.SelectSettings("gatherer")
        assert.equals("core", ns.UI.settingsPage.selected)
    end)

    it("hides the demand-loaded placeholders of switched-off modules", function()
        local ns = load_core({ login = true })
        ns.UI.RegisterSettings({ id = "import", title = "Import", module = "Goblinomics_Import", build = function() return 1 end })
        assert.is_true(ids(ns.UI.SortedSettings()).import)
        ns.Modules.SetEnabled("Goblinomics_Import", false)
        assert.is_nil(ids(ns.UI.SortedSettings()).import)
    end)
end)
