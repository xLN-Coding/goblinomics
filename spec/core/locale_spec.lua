describe("Core/Locale", function()
    local ns

    before_each(function()
        ns = load_core()
    end)

    it("returns the English key when no translation is active", function()
        assert.equals("Registered modules", ns.L["Registered modules"])
    end)

    it("activates the client locale", function()
        WoWMock.locale = "deDE"
        assert.equals("deDE", ns.Locale.Activate("auto"))
        assert.equals("Registrierte Module", ns.L["Registered modules"])
    end)

    it("lets the override win over the client locale", function()
        WoWMock.locale = "enUS"
        ns.Locale.Activate("deDE")
        assert.equals("Registrierte Module", ns.L["Registered modules"])
        ns.Locale.Activate("enUS")
        assert.equals("Registered modules", ns.L["Registered modules"])
    end)

    it("maps enGB and unsupported locales to English", function()
        WoWMock.locale = "enGB"
        assert.equals("enUS", ns.Locale.Activate(nil))
        WoWMock.locale = "koKR"
        assert.equals("enUS", ns.Locale.Activate(nil))
    end)

    it("keeps English for true values and missing keys", function()
        local t = ns.RegisterLocale("deDE")
        t["Keep me"] = true
        ns.Locale.Activate("deDE")
        assert.equals("Keep me", ns.L["Keep me"])
        assert.equals("Not translated", ns.L["Not translated"])
    end)

    it("formats with Lf", function()
        local t = ns.RegisterLocale("deDE")
        t["%d items"] = "%d Gegenstände"
        ns.Locale.Activate("deDE")
        assert.equals("3 Gegenstände", ns.Lf("%d items", 3))
    end)

    it("refuses direct writes to L", function()
        assert.has_error(function() ns.L["x"] = "y" end)
    end)

    it("applies the saved override at ADDON_LOADED", function()
        ns = load_core()
        _G.GoblinomicsDB = { _schema = 1, settings = { locale = "deDE" } }
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        assert.equals("deDE", ns.Locale.GetActive())
    end)

    it("offers and uses a CurseForge language only once it has translations", function()
        local ns = load_core()
        local function has(code)
            for _, c in ipairs(ns.Locale.Choices()) do if c.value == code then return true end end
            return false
        end
        assert.is_true(has("deDE"))
        assert.is_false(has("frFR"))
        WoWMock.locale = "frFR"
        assert.equals("enUS", ns.Locale.Activate("auto"))
        ns.RegisterLocale("frFR")["Settings"] = "Param\195\168tres"
        assert.is_true(has("frFR"))
        assert.equals("frFR", ns.Locale.Activate("auto"))
        assert.equals("Param\195\168tres", ns.L["Settings"])
        assert.equals("Dashboard", ns.L["Dashboard"])                  -- missing strings stay English
    end)
end)
