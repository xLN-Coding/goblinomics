describe("Vault: gold goals", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, vns, G, toasts

    before_each(function()
        ns, vns = load_vault({ money = 3000000 })
        G = vns.Goals
        toasts = {}
        ns.Toast.Show = function(spec) toasts[#toasts + 1] = spec end
        WoWMock.advance(3)
        WoWMock.flush()
    end)

    it("adds goals and measures wealth goals against wealth, purchase goals against gold", function()
        local w = G.Add("wealth", "Ten mil", 6000000)
        local p = G.Add("purchase", "", 2000000)
        assert.equals("Purchase goal", p.name)
        local current, progress = G.Progress(w)
        assert.equals(3000000, current)
        assert.equals(0.5, progress)
        assert.equals(1, select(2, G.Progress(p)))
        assert.is_nil(G.Add("other", "x", 5))
        assert.is_true(G.Remove(p))
    end)

    it("forecasts a wealth goal from the trend of the daily history", function()
        local h = GoblinomicsVaultDB.history
        for i = 0, 9 do h[os.date("%Y-%m-%d", WoWMock.now - i * 86400)] = { wealth = 3000000 - i * 100000 } end
        assert.equals(100000, math.floor(G.Trend() + 0.5))
        local goal = G.Add("wealth", "Goal", 4000000)
        local eta = G.Forecast(goal)
        assert.equals(WoWMock.now + 10 * 86400, eta)
        for k in pairs(h) do h[k] = nil end
        assert.is_nil(G.Forecast(goal))                      -- not enough history
    end)

    it("toasts a reached goal once", function()
        G.Add("purchase", "Mount", 1000000)
        G.Check()
        G.Check()
        assert.equals(1, #toasts)
        assert.equals("Goal reached!", toasts[1].title)
    end)

    it("builds the goals card and the dialog", function()
        G.Add("wealth", "Goal", 6000000)
        local tab = ns.UI.GetTab("dashboard")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        G.OpenDialog()
        assert.is_true(_G.GoblinomicsGoalsDialog:IsShown())
        tab.onHide()
    end)
end)
