describe("Core: line chart", function()
    local ns

    before_each(function() ns = load_core({ login = true, money = 1 }) end)
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("scales values between the lowest and the highest point", function()
        local layout = ns.Widgets.LineLayout({ 10, 30, 20 }, 100, 40)
        assert.same({ x = 0, y = 0 }, layout.points[1])
        assert.same({ x = 50, y = 40 }, layout.points[2])
        assert.same({ x = 100, y = 20 }, layout.points[3])
        assert.equals(10, layout.min)
        assert.equals(30, layout.max)
    end)

    it("draws flat series in the middle and handles empty data", function()
        local flat = ns.Widgets.LineLayout({ 5, 5 }, 100, 40)
        assert.equals(20, flat.points[1].y)
        assert.same({}, ns.Widgets.LineLayout({}, 100, 40).points)
        local one = ns.Widgets.LineLayout({ 7 }, 100, 40)
        assert.same({ x = 50, y = 20 }, one.points[1])
    end)

    it("builds lines and one hover area that covers exactly the chart", function()
        local chart = ns.Widgets.LineChart(CreateFrame("Frame"), { width = 100, height = 40,
            tooltip = function(i) return "Day " .. i, {} end })
        chart:SetData({ 1, 3 })
        assert.equals(2, #chart.layout.points)
        -- per-point areas reached past the edge and covered the Insights navigation (M7)
        assert.equals(chart, chart.overlay._allPoints)
        assert.same({}, chart.overlay._points)
        chart:SetData({})
    end)

    it("shows the tooltip of the point nearest to the cursor", function()
        local chart = ns.Widgets.LineChart(CreateFrame("Frame"), { width = 100, height = 40,
            tooltip = function(i) return "Day " .. i, {} end })
        chart:SetData({ 1, 3, 2 })
        chart.GetLeft = function() return 200 end
        chart.GetBottom = function() return 100 end
        WoWMock.cursor.x, WoWMock.cursor.y = 290, 120
        chart.overlay:GetScript("OnEnter")(chart.overlay)
        assert.equals("Day 3", GameTooltip.lines[1])
        assert.equals(2, ns.Widgets.NearestIndex(chart.layout.points, 40))
        assert.is_nil(ns.Widgets.NearestIndex({}, 10))
    end)
end)
