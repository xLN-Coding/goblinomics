describe("Core: dashboard", function()
    local ns

    before_each(function()
        ns = load_core({ login = true, money = 1 })
    end)

    after_each(function() assert.same({}, WoWMock.errors) end)

    it("lays out cards in rows by size", function()
        local specs = { { size = "twothirds", height = 100 }, { size = "third", height = 80 }, { size = "quarter" },
            { size = "quarter" }, { size = "half" }, { size = "full", height = 50 } }
        local placed, height = ns.Dashboard.Layout(specs, 290)
        assert.equals(0, placed[1].x)
        assert.equals(190, math.floor(placed[1].width + 0.5))     -- 2/3 of (290 + 10) - 10
        assert.equals(200, math.floor(placed[2].x + 0.5))
        assert.equals(110, placed[3].y)                             -- new row below the tallest card
        assert.equals(110, placed[5].y)                             -- quarter + quarter + half fit one row
        assert.equals(240, placed[6].y)
        assert.equals(290, placed[6].width)
        assert.equals(290, height)
    end)

    it("gives the period as context: today and the last days", function()
        local today = ns.Dashboard.Context(1)
        local d = os.date("*t", WoWMock.now)
        assert.equals(os.time({ year = d.year, month = d.month, day = d.day, hour = 0 }), today.from)
        local week = ns.Dashboard.Context(7)
        assert.equals(7, week.days)
        assert.equals(6, math.floor((today.from - week.from) / 86400 + 0.5))
    end)

    it("builds registered cards, refreshes them with the period and on their events", function()
        local calls = {}
        ns.UI.RegisterWidget({ id = "test.card", order = 1, size = "half", title = "Test", events = { "TEST_EVENT" },
            build = function(frame) frame.built = true end,
            refresh = function(_, context) calls[#calls + 1] = context.days end })
        local tab = ns.UI.GetTab("dashboard")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        assert.equals(7, calls[#calls])
        ns.coreDB.settings.ui.dashboardDays = 30
        ns.Dashboard.Refresh()
        assert.equals(30, calls[#calls])
        local n = #calls
        ns.Bus.Emit("TEST_EVENT", {})
        ns.Bus.Emit("TEST_EVENT", {})
        WoWMock.advance(0.3)
        assert.equals(n + 1, #calls)                                -- debounced
        tab.onHide()
        ns.Bus.Emit("TEST_EVENT", {})
        WoWMock.advance(0.3)
        assert.equals(n + 1, #calls)
        assert.is_table(ns.Perf.Get("Core.Dashboard", "build"))
    end)
end)
