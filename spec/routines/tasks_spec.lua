-- Tasks are learned from the game, pinned by the user and done until the next reset.
local fake = require("spec.support.sources")

describe("Routines: tasks and learned quests", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, rns, T
    local ME = "xLN-Blackrock"
    local ORE = "|cffffffff|Hitem:210930::::::::80:::::|h[Ore]|h|r"

    before_each(function()
        ns, rns = load_routines({ before = function()
            WoWMock.quests[500] = { title = "Weekly: Ore for the Forge", frequency = 2 }
            WoWMock.quests[501] = { title = "Daily: Herbs", frequency = 1 }
            WoWMock.quests[502] = { title = "Story quest", frequency = 0 }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:210930"] = 1000 } }))
        T = rns.Tasks
    end)

    local function root() return GoblinomicsRoutinesDB end

    it("learns daily and weekly quests when accepted, not other quests", function()
        WoWMock.fire("QUEST_ACCEPTED", 500)
        WoWMock.fire("QUEST_ACCEPTED", 501)
        WoWMock.fire("QUEST_ACCEPTED", 502)
        assert.equals("weekly", T.Get("q:500").frequency)
        assert.equals("Weekly: Ore for the Forge", T.Get("q:500").name)
        assert.equals("daily", T.Get("q:501").frequency)
        assert.is_nil(T.Get("q:502"))
        assert.equals(3, #T.Suggestions())                           -- plus the delve preset
        assert.equals(0, #T.Routine(ME))
    end)

    it("measures reward and time at turn-in and marks the quest done until the reset", function()
        WoWMock.fire("QUEST_ACCEPTED", 500)
        T.Pin("q:500", true)
        WoWMock.advance(6 * 60)
        WoWMock.currentQuest = 500
        WoWMock.questReward = { money = 50000, items = { { ORE, 5 } } }
        WoWMock.fire("QUEST_COMPLETE")
        WoWMock.fire("QUEST_TURNED_IN", 500, 0, 50000)
        local task = T.Get("q:500")
        assert.equals(55000, task.measured.value)                    -- gold plus 5 ore at 10 silver
        assert.equals(6, task.measured.minutes)
        local routine = T.Routine(ME)
        assert.equals(1, #routine)
        assert.is_true(routine[1].done)
        assert.equals(WoWMock.now + 3 * 86400, routine[1].resetAt)
        WoWMock.advance(3 * 86400 + 1)
        assert.is_false(T.Routine(ME)[1].done)                        -- open again after the weekly reset
    end)

    it("estimates value and duration: manual wins over measured, measured over the default", function()
        local t = T.Learn({ id = "q:9", kind = "quest", name = "Q" })
        local value, minutes, vs, ms = T.Estimate(t)
        assert.same({ 0, 10, "none", "default" }, { value, minutes, vs, ms })
        T.Measure(t, 10000, 4)
        T.Measure(t, 20000, 6)
        value, minutes = T.Estimate(t)
        assert.equals(15000, value)
        assert.equals(5, minutes)
        T.Edit("q:9", { value = 30000, duration = 3 })
        value, minutes, vs, ms = T.Estimate(t)
        assert.same({ 30000, 3, "manual", "manual" }, { value, minutes, vs, ms })
        assert.equals(10000, T.PerMinute(t))
    end)

    it("checks the quest flags at login and sorts the routine open first, then by gold per minute", function()
        T.Learn({ id = "q:500", kind = "quest", ref = 500, frequency = "weekly", name = "A" }).pinned = true
        T.Learn({ id = "q:501", kind = "quest", ref = 501, frequency = "daily", name = "B" }).pinned = true
        T.Learn({ id = "q:503", kind = "quest", ref = 503, frequency = "weekly", name = "C" }).pinned = true
        T.Get("q:501").value, T.Get("q:503").value = 60000, 10000
        WoWMock.quests[500].completed = true
        rns.Learn.CheckFlags()
        local names = {}
        for _, e in ipairs(T.Routine(ME)) do names[#names + 1] = e.task.name end
        assert.same({ "B", "C", "A" }, names)
        assert.equals(WoWMock.now + 3 * 86400, root().chars[ME].done["q:500"].resetAt)   -- weekly
        local value, minutes, open = T.Totals(T.Routine(ME))
        assert.same({ 70000, 20, 2 }, { value, minutes, open })
    end)

    it("knows instances and world bosses from the saved data, also for other characters", function()
        WoWMock.savedInstances = { { name = "Voidspire", mapID = 2900, difficulty = 15, reset = 86400,
            difficultyName = "Heroic", isRaid = true, numEncounters = 6, encounterProgress = 6 } }
        WoWMock.worldBosses = { { name = "Gorak", id = 3001, reset = 86400 } }
        WoWMock.fire("UPDATE_INSTANCE_INFO")
        local raid, boss = T.Get("i:2900:15"), T.Get("wb:3001")
        assert.equals("Voidspire (Heroic)", raid.name)
        assert.is_true((T.State(raid, ME)))
        assert.is_true((T.State(boss, ME)))
        root().chars["Alt-Blackrock"] = { name = "Alt", lockouts = { { mapID = 2900, difficultyID = 15, progress = 2,
            encounters = 6, resetAt = WoWMock.now + 100 } } }
        local done, detail = T.State(raid, "Alt-Blackrock")
        assert.is_false(done)
        assert.equals("2/6", detail)
        raid.pinned = true
        local overview = T.Overview()
        assert.equals(1, overview[1].open)                            -- only Alt can still run it
        assert.equals(2, overview[1].count)
        T.Hide("i:2900:15", true)
        assert.equals(0, #T.Overview())
    end)
end)
