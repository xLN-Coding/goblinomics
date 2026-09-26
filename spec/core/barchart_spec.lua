describe("Core: bar chart", function()
    local ns
    local SERIES = { { key = "a", color = { 0, 1, 0, 1 } }, { key = "b", color = { 1, 1, 0, 1 } } }

    before_each(function()
        ns = load_core({ login = true, money = 1 })
    end)

    after_each(function() assert.same({}, WoWMock.errors) end)

    it("stacks positive values above and negative values below the zero line", function()
        local layout = ns.Widgets.BarChartLayout({
            { values = { a = 60, b = 20 } },
            { values = { a = -20, b = 10 } },
        }, SERIES, 102, 100, 2)
        assert.equals(50, layout.barWidth)
        assert.equals(20, layout.baseline)           -- 20 negative of 100 total range
        local first = layout.bars[1].segments
        assert.same({ key = "a", y = 20, height = 60 }, first[1])
        assert.same({ key = "b", y = 80, height = 20 }, first[2])
        local second = layout.bars[2].segments
        assert.same({ key = "a", y = 0, height = 20 }, second[1])
        assert.equals(52, layout.bars[2].x)
    end)

    it("handles empty data and all-zero values", function()
        assert.same({}, ns.Widgets.BarChartLayout({}, SERIES, 100, 50).bars)
        local layout = ns.Widgets.BarChartLayout({ { values = {} } }, SERIES, 100, 50)
        assert.equals(0, layout.baseline)
        assert.same({}, layout.bars[1].segments)
    end)

    it("builds bars with tooltips", function()
        local chart = ns.Widgets.BarChart(CreateFrame("Frame"), { width = 200, height = 80, series = SERIES,
            tooltip = function(bar) return bar.label, {} end })
        chart:SetData({ { label = "Mon", values = { a = 5 } }, { label = "Tue", values = { b = 3 } } })
        assert.equals(2, #chart.layout.bars)
    end)
end)
