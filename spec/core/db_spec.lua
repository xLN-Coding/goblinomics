describe("Core/DB", function()
    local ns

    before_each(function()
        ns = load_core()
        _G.GoblinomicsTestDB = nil
    end)

    it("starts a fresh SavedVariable at the current schema without running migrations", function()
        local ran = false
        local db = ns.DB:Namespace("T", "GoblinomicsTestDB", { version = 3, migrations = { [2] = function() ran = true end } })
        assert.is_true(db.ok)
        assert.equals(3, GoblinomicsTestDB._schema)
        assert.is_false(ran)
    end)

    it("merges defaults into settings and char tables", function()
        _G.GoblinomicsTestDB = { settings = { a = 7, nested = { y = 2 } } }
        local db = ns.DB:Namespace("T", "GoblinomicsTestDB", {
            defaults = { a = 1, b = 2, nested = { x = 1 } }, charDefaults = { window = { scale = 1 } },
        })
        assert.equals(7, db.settings.a)
        assert.equals(2, db.settings.b)
        assert.same({ x = 1, y = 2 }, db.settings.nested)
        db:BindChar("xLN-Blackrock")
        assert.equals(1, db.char.window.scale)
    end)

    it("runs pending migrations in order", function()
        _G.GoblinomicsTestDB = { _schema = 1, settings = {}, old = 5 }
        local order = {}
        local db = ns.DB:Namespace("T", "GoblinomicsTestDB", {
            version = 3,
            migrations = {
                [2] = function(root) order[#order + 1] = 2; root.new = root.old * 2; root.old = nil end,
                [3] = function(root) order[#order + 1] = 3; root.new = root.new + 1 end,
            },
        })
        assert.is_true(db.ok)
        assert.same({ 2, 3 }, order)
        assert.equals(11, GoblinomicsTestDB.new)
        assert.equals(3, GoblinomicsTestDB._schema)
    end)

    it("stops at the last good version when a migration fails and retries next session", function()
        _G.GoblinomicsTestDB = { _schema = 1, settings = {} }
        local spec = { version = 3, migrations = { [2] = function() end, [3] = function() error("bad data") end } }
        local db = ns.DB:Namespace("T", "GoblinomicsTestDB", spec)
        assert.is_false(db.ok)
        assert.equals(2, GoblinomicsTestDB._schema)
        assert.equals(1, #WoWMock.errors)
        local saved = GoblinomicsTestDB
        ns = load_core()
        _G.GoblinomicsTestDB = saved
        spec.migrations[3] = function(root) root.fixed = true end
        db = ns.DB:Namespace("T", "GoblinomicsTestDB", spec)
        assert.is_true(db.ok)
        assert.is_true(GoblinomicsTestDB.fixed)
    end)

    it("refuses data from a newer schema", function()
        _G.GoblinomicsTestDB = { _schema = 9, settings = {} }
        local db = ns.DB:Namespace("T", "GoblinomicsTestDB", { version = 2 })
        assert.is_false(db.ok)
    end)

    it("strips defaults from copies at logout and leaves free keys alone", function()
        local db = ns.DB:Namespace("T", "GoblinomicsTestDB", {
            defaults = { a = 1, nested = { x = 1 } }, charDefaults = { seen = 0 },
        })
        db:BindChar("xLN-Blackrock")
        db.settings.nested.x = 2
        db.char.seen = 0
        db.root.data = { 1, 2, 3 }
        local live = db.settings
        ns.DB.OnLogout()
        assert.is_nil(GoblinomicsTestDB.settings.a)
        assert.same({ x = 2 }, GoblinomicsTestDB.settings.nested)
        assert.is_nil(GoblinomicsTestDB.chars["xLN-Blackrock"].seen)
        assert.same({ 1, 2, 3 }, GoblinomicsTestDB.data)
        assert.equals(1, live.a) -- live table untouched
    end)

    it("module with a failed migration stays disabled", function()
        _G.GoblinomicsTestDB = { _schema = 1, settings = {} }
        local m = ns.API.RegisterModule("Goblinomics_Test", {
            apiVersion = 1,
            db = { sv = "GoblinomicsTestDB", version = 2, migrations = { [2] = function() error("x") end } },
        })
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        WoWMock.fire("ADDON_LOADED", "Goblinomics_Test")
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        assert.equals("failed", m.state)
    end)
end)
