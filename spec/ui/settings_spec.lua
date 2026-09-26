-- Settings page: sections on the left, the selected one on the right, built on first use.
describe("UI: settings page", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local function build(ns)
        local tab = ns.UI.GetTab("settings")
        tab.build(CreateFrame("Frame"))
        return ns.UI.settingsPage
    end

    it("lists the sections in order and builds only the selected one", function()
        local ns = load_core({ login = true })
        local built = 0
        ns.UI.RegisterSettings({ id = "zzz", title = "Last", order = 999, build = function() built = built + 1; return 40 end })
        local page = build(ns)
        assert.equals("core", page.selected)
        assert.equals("General", page.buttons[1].label:GetText())
        assert.equals("zzz", page.buttons[#ns.UI.SortedSettings()].id)
        assert.equals(0, built)
        page.buttons[#ns.UI.SortedSettings()]:GetScript("OnClick")(page.buttons[#ns.UI.SortedSettings()])
        assert.equals(1, built)
        assert.equals("Last", page.title:GetText())
        ns.UI.SelectSettings("core")
        ns.UI.SelectSettings("zzz")
        assert.equals(1, built)                              -- kept, not rebuilt
        assert.equals("zzz", ns.coreDB.settings.ui.settingsSection)
    end)

    it("opens the remembered section", function()
        local ns = load_core({ login = true, db = { _schema = 2, settings = { ui = { settingsSection = "pricing" } } } })
        local page = build(ns)
        assert.equals("pricing", page.selected)
        assert.is_true(page.built.pricing.frame:IsShown())
        assert.is_nil(page.built.core)
    end)
end)
