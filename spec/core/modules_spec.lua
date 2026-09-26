describe("Core/Modules", function()
    local ns, API

    before_each(function()
        ns = load_core()
        API = ns.API
    end)

    local function boot(addons)
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        for _, a in ipairs(addons or {}) do WoWMock.fire("ADDON_LOADED", a) end
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
    end

    it("validates id, spec, api version and duplicates", function()
        assert.has_error(function() API.RegisterModule(nil, { apiVersion = 1 }) end)
        assert.has_error(function() API.RegisterModule("", { apiVersion = 1 }) end)
        assert.has_error(function() API.RegisterModule("X", "spec") end)
        assert.has_error(function() API.RegisterModule("X", { apiVersion = 2 }) end)
        API.RegisterModule("X", { apiVersion = 1 })
        assert.has_error(function() API.RegisterModule("X", { apiVersion = 1 }) end)
    end)

    it("runs OnInit at the module's ADDON_LOADED and OnEnable at PLAYER_LOGIN", function()
        local log = {}
        local m = API.RegisterModule("Goblinomics_Test", {
            apiVersion = 1,
            db = { sv = "GoblinomicsTestDB", defaults = { threshold = 5 }, charDefaults = { seen = 0 } },
        })
        function m:OnInit() log[#log + 1] = "init:" .. self.db.settings.threshold end
        function m:OnEnable() log[#log + 1] = "enable:" .. self.db.char.seen end
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        assert.same({}, log)
        WoWMock.fire("ADDON_LOADED", "Goblinomics_Test")
        assert.same({ "init:5" }, log)
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        assert.same({ "init:5", "enable:0" }, log)
        assert.equals("enabled", m.state)
    end)

    it("enables demand-loaded modules one tick after ADDON_LOADED", function()
        boot()
        local enabled = false
        API.RegisterModule("Goblinomics_Insights", { apiVersion = 1, OnEnable = function() enabled = true end })
        WoWMock.fire("ADDON_LOADED", "Goblinomics_Insights")
        assert.is_false(enabled)
        WoWMock.flush()
        assert.is_true(enabled)
    end)

    it("cleans up events, bus subscriptions, timers and jobs when disabled", function()
        local m = API.RegisterModule("Goblinomics_Test", { apiVersion = 1 })
        local fired, busGot, timerRan = 0, 0, false
        function m:OnEnable()
            self:RegisterEvent("BAG_UPDATE", function() fired = fired + 1 end)
            self:On("SOMETHING", function() busGot = busGot + 1 end)
            self:After(5, function() timerRan = true end)
        end
        boot({ "Goblinomics_Test" })
        WoWMock.fire("BAG_UPDATE", 0)
        ns.Bus.Emit("SOMETHING", {})
        assert.equals(1, fired)
        assert.equals(1, busGot)
        ns.Modules.SetEnabled("Goblinomics_Test", false)
        assert.equals("disabled", m.state)
        assert.same({ enabled = false }, GoblinomicsDB.settings.modules.Goblinomics_Test)
        WoWMock.fire("BAG_UPDATE", 0)
        ns.Bus.Emit("SOMETHING", {})
        WoWMock.advance(10)
        assert.equals(1, fired)
        assert.equals(1, busGot)
        assert.is_false(timerRan)
        ns.Modules.SetEnabled("Goblinomics_Test", true)
        assert.equals("enabled", m.state)
        assert.is_nil(GoblinomicsDB.settings.modules.Goblinomics_Test)
    end)

    it("keeps a module disabled across sessions", function()
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        GoblinomicsDB.settings.modules.Goblinomics_Test = { enabled = false }
        local m = API.RegisterModule("Goblinomics_Test", { apiVersion = 1 })
        WoWMock.fire("ADDON_LOADED", "Goblinomics_Test")
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        assert.equals("disabled", m.state)
    end)

    it("isolates errors in lifecycle callbacks", function()
        local other = false
        API.RegisterModule("A", { apiVersion = 1, addon = "Goblinomics", OnEnable = function() error("broken") end })
        API.RegisterModule("B", { apiVersion = 1, addon = "Goblinomics", OnEnable = function() other = true end })
        boot()
        assert.is_true(other)
        assert.equals(1, #WoWMock.errors)
    end)

    it("refuses RegisterEvent before the module is enabled", function()
        local m = API.RegisterModule("A", { apiVersion = 1 })
        assert.has_error(function() m:RegisterEvent("BAG_UPDATE", function() end) end)
    end)

    it("supports method-name handlers", function()
        local m = API.RegisterModule("A", { apiVersion = 1, addon = "Goblinomics" })
        local got
        function m:BAG_UPDATE(event, bag) got = event .. bag end
        function m:OnEnable() self:RegisterEvent("BAG_UPDATE") end
        boot()
        WoWMock.fire("BAG_UPDATE", 2)
        assert.equals("BAG_UPDATE2", got)
    end)
end)
