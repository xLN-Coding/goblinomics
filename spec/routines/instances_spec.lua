-- Routines reads lockouts and world bosses of every character and takes over the Gatherer's old data.
describe("Routines: instances and world bosses", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("stores world bosses of the week with their reset", function()
        local _, rns = load_routines({ before = function()
            WoWMock.worldBosses = { { name = "Gorak", id = 3001, reset = 86400 } }
        end })
        WoWMock.fire("UPDATE_INSTANCE_INFO")
        local c = GoblinomicsRoutinesDB.chars["xLN-Blackrock"]
        assert.equals("Gorak", c.worldBosses[1].name)
        assert.equals(WoWMock.now + 86400, c.worldBosses[1].resetAt)
        assert.is_table(rns.Instances.All()["xLN-Blackrock"])
        assert.is_table(Goblinomics.API.v1.Routines:Lockouts()["xLN-Blackrock"])
    end)

    it("takes over lockouts the Gatherer stored before, once and only for unknown characters", function()
        local root = { chars = { ["Main-Realm"] = { lockoutsScanned = 5, lockouts = { { name = "Mine" } } } } }
        local gatherer = { chars = {
            ["Main-Realm"] = { lockoutsScanned = 1, lockouts = { { name = "Old" } } },
            ["Alt-Realm"] = { lockoutsScanned = 2, level = 80, class = "MAGE", lockouts = { { name = "Raid" } } },
            ["New-Realm"] = { level = 10 },
        } }
        local _, rns = load_routines()
        assert.equals(1, rns.Instances.Migrate(root, gatherer))
        assert.equals("Mine", root.chars["Main-Realm"].lockouts[1].name)
        assert.equals("Raid", root.chars["Alt-Realm"].lockouts[1].name)
        assert.equals("MAGE", root.chars["Alt-Realm"].class)
        assert.is_nil(root.chars["New-Realm"])
        assert.equals(0, rns.Instances.Migrate(root, nil))
    end)

    it("knows the next weekly and daily reset", function()
        local _, rns = load_routines()
        assert.equals(WoWMock.now + 3 * 86400, rns.Routines.WeeklyResetAt())
        assert.equals(WoWMock.now + 8 * 3600, rns.Routines.DailyResetAt())
    end)
end)
