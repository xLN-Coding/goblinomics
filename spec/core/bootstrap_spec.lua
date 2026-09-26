describe("Core bootstrap and lifecycle", function()
    it("exposes exactly one global table with API v1", function()
        local ns = load_core()
        assert.is_table(Goblinomics)
        assert.equals(1, Goblinomics.API_VERSION)
        assert.equals(ns.API, Goblinomics.API.v1)
        assert.is_function(ns.API.RegisterModule)
    end)

    it("reports 'dev' while the packager placeholder is unreplaced", function()
        load_core()
        assert.equals("dev", Goblinomics.VERSION)
    end)

    it("moves the Prospector module setting and tab to Gatherer (schema 2)", function()
        local ns = load_core({ boot = true, db = { _schema = 1,
            settings = { modules = { Goblinomics_Prospector = { enabled = false } } },
            chars = { ["xLN-Blackrock"] = { lastTab = "prospector" } } } })
        assert.same({ enabled = false }, ns.coreDB.settings.modules.Goblinomics_Gatherer)
        assert.is_nil(ns.coreDB.settings.modules.Goblinomics_Prospector)
        assert.equals("gatherer", GoblinomicsDB.chars["xLN-Blackrock"].lastTab)
    end)

    it("creates the core namespace with defaults and a stable account id at ADDON_LOADED", function()
        local ns = load_core({ boot = true })
        assert.is_table(GoblinomicsDB)
        assert.equals(3, GoblinomicsDB._schema)
        assert.equals("auto", ns.coreDB.settings.locale)
        assert.is_false(ns.coreDB.settings.minimap.hide)
        local id = GoblinomicsDB.account.id
        assert.is_string(id)
        -- second session keeps the id
        local saved = GoblinomicsDB
        WoWMock.reset()
        local ns2 = {}
        _G.GoblinomicsDB = saved
        for _, file in ipairs(toc_files("Goblinomics.toc")) do
            if not file:match("^Libs/") then load_addon_file(file, "Goblinomics", ns2) end
        end
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        assert.equals(id, GoblinomicsDB.account.id)
    end)

    it("records the character at PLAYER_LOGIN", function()
        local ns = load_core({ login = true })
        local c = GoblinomicsDB.chars["xLN-Blackrock"]
        assert.is_table(c)
        assert.equals(c, ns.coreDB.char)
        assert.equals("WARRIOR", c.class)
        assert.equals("Horde", c.faction)
    end)

    it("stores the last reliable money (not the 0 read at logout) and strips defaults", function()
        load_core({ login = true, money = 100000 })
        WoWMock.set_money(123456)
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("PLAYER_LEAVING_WORLD")
        WoWMock.set_money(0)
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("PLAYER_LOGOUT")
        assert.equals(123456, GoblinomicsDB.chars["xLN-Blackrock"].money)
        assert.is_nil(GoblinomicsDB.settings.locale)
        assert.is_nil(GoblinomicsDB.settings.minimap)
    end)

    it("keeps non-default settings through logout", function()
        local ns = load_core({ login = true })
        ns.coreDB.settings.locale = "deDE"
        WoWMock.fire("PLAYER_LOGOUT")
        assert.equals("deDE", GoblinomicsDB.settings.locale)
    end)

    it("registers only the lifecycle events at load", function()
        local ns = load_core()
        local registered = {}
        for _, r in ipairs(ns.Events.ListRegistered()) do registered[r.event] = true end
        assert.same({ ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true }, registered)
        assert.equals(0, #WoWMock.timers)
    end)

    describe("slash commands", function()
        it("registers /gob and /goblinomics and defers the work one tick", function()
            local ns = load_core({ login = true })
            assert.equals("/gob", SLASH_GOBLINOMICS1)
            assert.equals("/goblinomics", SLASH_GOBLINOMICS2)
            SlashCmdList.GOBLINOMICS("status")
            assert.equals(0, #WoWMock.chat)
            WoWMock.flush()
            assert.truthy(WoWMock.chat[1]:find("Version dev", 1, true))
            assert.is_table(ns.EntryPoints)
        end)

        it("lists registered modules in /gob status", function()
            local ns = load_core()
            ns.API.RegisterModule("Goblinomics_Vault", { apiVersion = 1, name = "Vault" })
            WoWMock.fire("ADDON_LOADED", "Goblinomics")
            WoWMock.fire("ADDON_LOADED", "Goblinomics_Vault")
            WoWMock.loggedIn = true
            WoWMock.fire("PLAYER_LOGIN")
            ns.EntryPoints.HandleSlash("status")
            local found = false
            for _, line in ipairs(WoWMock.chat) do
                if line:find("Registered modules (1): Vault", 1, true) then found = true end
            end
            assert.is_true(found)
        end)

        it("prints help for unknown commands", function()
            local ns = load_core({ login = true })
            ns.EntryPoints.HandleSlash("nonsense")
            assert.truthy(WoWMock.chat[1]:find("/gob", 1, true))
        end)
    end)
end)
