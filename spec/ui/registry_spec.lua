describe("Core/UI registries", function()
    local ns

    before_each(function()
        ns = load_core({ login = true })
    end)

    it("registers the core tabs without creating frames", function()
        local before = #WoWMock.frames
        ns.UI.RegisterTab({ id = "vault", title = "Vault", order = 10, build = function() end })
        ns.UI.RegisterWidget({ id = "networth", order = 1, build = function() end })
        ns.UI.RegisterSettings({ id = "vault", title = "Vault", order = 10, build = function() return 0 end })
        assert.equals(before, #WoWMock.frames)
        assert.is_false(ns.UI.IsShown())
    end)

    it("sorts tabs by order with bottom tabs last", function()
        ns.UI.RegisterTab({ id = "ledger", title = "Ledger", order = 20 })
        ns.UI.RegisterTab({ id = "vault", title = "Vault", order = 10 })
        local ids = {}
        for _, spec in ipairs(ns.UI.SortedTabs()) do ids[#ids + 1] = spec.id end
        assert.same({ "dashboard", "vault", "ledger", "settings" }, ids)
    end)

    it("replaces a tab registered under the same id", function()
        ns.UI.RegisterTab({ id = "insights", title = "Insights", loadAddon = "Goblinomics_Insights" })
        local build = function() end
        ns.UI.RegisterTab({ id = "insights", title = "Insights", build = build })
        assert.equals(build, ns.UI.GetTab("insights").build)
    end)

    it("translates core tab titles at display time", function()
        assert.equals("Settings", ns.UI.Title(ns.UI.GetTab("settings")))
        ns.Locale.Activate("deDE")
        assert.equals("Einstellungen", ns.UI.Title(ns.UI.GetTab("settings")))
    end)

    it("validates ids", function()
        assert.has_error(function() ns.UI.RegisterTab({ title = "x" }) end)
        assert.has_error(function() ns.UI.RegisterWidget("x") end)
    end)

    it("exposes a colon-style public API", function()
        ns.API.UI:RegisterTab({ id = "gatherer", title = "Gatherer", order = 30 })
        assert.is_table(ns.UI.GetTab("gatherer"))
    end)
end)
