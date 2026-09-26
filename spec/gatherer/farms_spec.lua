describe("Gatherer: farms", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local pns, Farms

    before_each(function()
        pns = select(2, load_gatherer())
        Farms = pns.Farms
    end)

    local RAID = { journalID = 1296, mapID = 2769, name = "Liberation of Undermine", isRaid = true }

    it("creates, updates and deletes farms", function()
        local farm = Farms.Create({ name = "  Herbs Zaralek ", category = "gathering",
            expectedHighlights = { "i:1", "i:2", "i:1" } })
        assert.equals("Herbs Zaralek", farm.name)
        assert.equals("gathering", farm.category)
        assert.same({ "i:1", "i:2" }, farm.expectedHighlights)
        assert.equals(farm, Farms.FindByName("herbs zaralek"))

        Farms.Update(farm.id, { category = "nonsense" })
        assert.equals("other", farm.category)

        Farms.Update(farm.id, { category = "raid", instance = RAID })
        assert.equals(2769, farm.instance.mapID)
        Farms.Update(farm.id, { category = "dungeon" })   -- a raid does not fit a dungeon farm
        assert.is_nil(farm.instance)
        Farms.Update(farm.id, { category = "raid", instance = RAID })
        Farms.Update(farm.id, { instance = false })
        assert.is_nil(farm.instance)

        assert.is_true(Farms.Delete(farm.id))
        assert.is_nil(Farms.Get(farm.id))
        assert.is_false(Farms.Delete(farm.id))
    end)

    it("rejects farms without a name", function()
        local farm, err = Farms.Create({ name = "   " })
        assert.is_nil(farm)
        assert.equals("name", err)
    end)

    it("lists farms by name and hands out unique ids", function()
        local b = Farms.Create({ name = "beta" })
        local a = Farms.Create({ name = "Alpha" })
        assert.are_not.equal(a.id, b.id)
        local list = Farms.List()
        assert.equals("Alpha", list[1].name)
        assert.equals("beta", list[2].name)
    end)

    it("computes statistics from the stored summaries", function()
        local farm = Farms.Create({ name = "Ore" })
        Farms.AddSummary({ farmId = farm.id, started = 100, duration = 1800, total = 5000000, gph = 10000000 })
        Farms.AddSummary({ farmId = farm.id, started = 200, duration = 3600, total = 4000000, gph = 4000000 })
        local stats = Farms.Stats(farm.id)
        assert.equals(2, stats.runs)
        assert.equals(10000000, stats.bestGPH)
        assert.equals(200, stats.lastRun)
        assert.equals(6000000, stats.avgGPH)   -- 9,000,000 copper over 1.5 hours
        assert.equals(200, Farms.History(farm.id)[1].started)
    end)

    it("keeps ad-hoc sessions under their own key and drops history with the farm", function()
        Farms.AddSummary({ started = 1, duration = 60, total = 1, gph = 60 })
        assert.equals(1, #Farms.History(nil))
        local farm = Farms.Create({ name = "X" })
        Farms.AddSummary({ farmId = farm.id, started = 1, duration = 60, total = 1, gph = 60 })
        Farms.Delete(farm.id)
        assert.equals(0, #Farms.History(farm.id))
        assert.equals(0, Farms.Stats(farm.id).runs)
    end)

    it("persists farms in the SavedVariable", function()
        Farms.Create({ name = "Saved" })
        local found = false
        for _, farm in pairs(GoblinomicsGathererDB.farms) do
            if farm.name == "Saved" then found = true end
        end
        assert.is_true(found)
    end)

    it("has no Mythic+ category and migrates old Mythic+ farms to dungeons", function()
        assert.is_false(tContains(pns.CATEGORIES, "mythicplus"))
        pns = select(2, load_gatherer({ before = function()
            _G.GoblinomicsGathererDB = { _schema = 1, farms = { f1 = { id = "f1", name = "Keys", category = "mythicplus" } } }
        end }))
        assert.equals("dungeon", pns.Farms.Get("f1").category)
        assert.equals(4, GoblinomicsGathererDB._schema)
    end)

    it("drops expected GPH and duration and turns an instance name into a record", function()
        pns = select(2, load_gatherer({ before = function()
            _G.GoblinomicsGathererDB = { _schema = 3, farms = {
                f1 = { id = "f1", name = "Raid", category = "raid", instance = "Undermine", expectedGPH = 5, expectedMinutes = 9,
                    expectedHighlights = {} },
                f2 = { id = "f2", name = "Herbs", category = "gathering", instance = "Zone", expectedHighlights = {} },
            } }
        end }))
        local raid = pns.Farms.Get("f1")
        assert.same({ name = "Undermine", isRaid = true }, raid.instance)
        assert.is_nil(raid.expectedGPH)
        assert.is_nil(raid.expectedMinutes)
        assert.is_nil(pns.Farms.Get("f2").instance)
    end)

    it("merges old expected items and the farm watchlist into expected highlights", function()
        pns = select(2, load_gatherer({ before = function()
            _G.GoblinomicsGathererDB = { _schema = 2, farms = { f1 = { id = "f1", name = "Herbs", category = "gathering",
                expectedItems = { "i:2", "i:1" }, watchlist = { ["i:1"] = true, ["i:9"] = true, ["i:5"] = true } } } }
        end }))
        local farm = pns.Farms.Get("f1")
        assert.same({ "i:2", "i:1", "i:5", "i:9" }, farm.expectedHighlights)
        assert.is_nil(farm.expectedItems)
        assert.is_nil(farm.watchlist)
    end)
end)
