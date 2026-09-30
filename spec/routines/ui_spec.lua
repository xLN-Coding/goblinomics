-- The Routines tab: list, overview and suggestions, the edit dialog, sharing, card and settings.
describe("Routines: UI", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, rns, T
    local ME = "xLN-Blackrock"

    before_each(function()
        ns, rns = load_routines()
        T = rns.Tasks
    end)

    local function build()
        local tab = ns.UI.GetTab("routines")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        return tab
    end

    it("registers tab, card and settings and switches the views", function()
        local a = T.Learn({ id = "q:1", kind = "quest", ref = 1, name = "Ore", frequency = "weekly" })
        a.pinned, a.value = true, 50000
        T.Learn({ id = "q:2", kind = "quest", ref = 2, name = "Herbs" })
        build()
        local UI = rns.RoutinesUI
        assert.equals(1, #UI.Rows())
        UI.state.view = "suggestions"
        UI.Refresh()
        assert.equals(2, #UI.Rows())                                  -- Herbs and the delve preset
        UI.state.view = "overview"
        UI.Refresh()
        assert.equals(1, #UI.Rows())
        assert.equals(1, UI.Rows()[1].open)
        UI.state.view = "list"
        local ids = {}
        for _, w in ipairs(ns.UI.SortedWidgets()) do ids[w.id] = w end
        local f = CreateFrame("Frame")
        ids["routines.week"].build(f)
        ids["routines.week"].refresh(f, {})
        assert.is_truthy(f.value:GetText())
        local section
        for _, s in ipairs(ns.UI.SortedSettings()) do if s.id == "routines" then section = s end end
        assert.is_true(section.build(CreateFrame("Frame"), 0) > 100)
    end)

    it("edits value, duration and note in the dialog; empty fields go back to measured", function()
        local t = T.Learn({ id = "q:1", kind = "quest", ref = 1, name = "Ore" })
        t.pinned = true
        T.Measure(t, 20000, 5)
        build()
        local UI = rns.RoutinesUI
        UI.OpenEdit(t)
        local d = _G.GoblinomicsRoutinesEdit
        d.value:SetText("12,5")
        d.duration:SetText("4")
        d.note:SetText("Via portal")
        d.buttons[2]:GetScript("OnClick")(d.buttons[2], "LeftButton")
        assert.same({ 125000, 4, "Via portal" }, { t.value, t.duration, t.note })
        UI.OpenEdit(t)
        d.value:SetText("")
        d.duration:SetText("")
        d.buttons[2]:GetScript("OnClick")(d.buttons[2], "LeftButton")
        local value, minutes, vs = T.Estimate(t)
        assert.same({ 20000, 5, "measured" }, { value, minutes, vs })
        d.buttons[1]:GetScript("OnClick")(d.buttons[1], "LeftButton")   -- remove from routine
        assert.is_nil(t.pinned)
    end)

    it("explains a task in its tooltip and prints what is open after login", function()
        local t = T.Learn({ id = "q:1", kind = "quest", ref = 1, name = "Ore", frequency = "weekly" })
        t.pinned, t.value, t.note = true, 30000, "Flight path"
        local title, lines = rns.RoutinesUI.TooltipLines({ task = t, resetAt = WoWMock.now + 3600 }, WoWMock.now)
        assert.equals("Ore", title)
        local text = table.concat(lines, "|")
        assert.is_truthy(text:find("set by you", 1, true))
        assert.is_truthy(text:find("Resets in 1h 0m", 1, true))
        assert.is_truthy(text:find("Flight path", 1, true))
        assert.is_truthy(rns.RoutinesUI.LoginLine(ME):find("1 open", 1, true))
        for k in pairs(WoWMock.chat) do WoWMock.chat[k] = nil end
        WoWMock.advance(9)
        WoWMock.flush()
        local found = false
        for _, line in ipairs(WoWMock.chat) do if line:find("Routines", 1, true) then found = true end end
        assert.is_true(found)
    end)
end)
