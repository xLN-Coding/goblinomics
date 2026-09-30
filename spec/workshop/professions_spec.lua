-- Concentration and recipe cooldowns across characters: read once, then computed.
describe("Workshop: concentration and cooldowns", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local wns, P

    local function install()
        WoWMock.childProfessions = {
            { professionID = 2900, professionName = "Midnight Alchemy", parentProfessionID = 171,
                parentProfessionName = "Alchemy", expansionName = "Midnight" },
            { professionID = 2823, professionName = "Khaz Algar Alchemy", parentProfessionID = 171,
                parentProfessionName = "Alchemy", expansionName = "The War Within" },
        }
        WoWMock.concentrationIDs = { [2900] = 3100, [2823] = 3050 }
        WoWMock.childSkillLine = 2900
        WoWMock.recipeIDs = { 700, 701, 702, 703 }
        WoWMock.currencies = { [3100] = { quantity = 400, maxQuantity = 1000, rechargingCycleDurationMS = 360000,
            rechargingAmountPerCycle = 1 } }
        WoWMock.recipes[700] = { name = "Transmute: Ore" }
        WoWMock.recipes[701] = { name = "Transmute: Herbs" }
        WoWMock.recipes[702] = { name = "Potion" }
        WoWMock.recipes[703] = { name = "Experimental Flask" }
    end

    before_each(function()
        local _
        _, wns = load_workshop({ before = install })
        P = wns.Professions
    end)

    local function char() return GoblinomicsWorkshopDB.chars["xLN-Blackrock"] end

    it("computes the current concentration and when it is full from one reading", function()
        local p = { amount = 400, max = 1000, cycleSec = 360, perCycle = 1, readAt = 1000 }
        assert.equals(400, P.Current(p, 1000))
        assert.equals(400, P.Current(p, 1359))
        assert.equals(401, P.Current(p, 1360))
        assert.equals(1000, P.Current(p, 1000 + 1000 * 360))
        assert.equals(1000 + 600 * 360, P.FullAt(p))
        assert.equals(1000 + 500 * 360, P.FullAt(p, 900))
        assert.equals(1000, P.FullAt({ amount = 1000, max = 1000, cycleSec = 360, readAt = 1000 }))
        assert.equals(1000 + 300 * 360, P.FullAt({ amount = 400, max = 1000, cycleSec = 360, perCycle = 2, readAt = 1000 }))
        assert.is_nil(P.Current(nil, 0))
    end)

    it("reads only the current expansion's line from the profession window", function()
        WoWMock.fire("TRADE_SKILL_SHOW")
        WoWMock.advance(1)
        WoWMock.flush()
        local lines = char().professions
        assert.is_table(lines[2900])
        assert.is_nil(lines[2823])
        assert.equals("Alchemy", lines[2900].name)
        assert.equals(400, lines[2900].amount)
        assert.equals(360, lines[2900].cycleSec)
        assert.equals(WoWMock.now, lines[2900].readAt)
    end)

    it("reads the stored currencies again at login without a window", function()
        char().professions = { [2900] = { name = "Alchemy", currencyID = 3100, amount = 10, readAt = 1 } }
        WoWMock.currencies[3100].quantity = 777
        P.ReadStored()
        assert.equals(777, char().professions[2900].amount)
        WoWMock.currencies[3100].quantity = 780
        WoWMock.fire("CURRENCY_DISPLAY_UPDATE", 3100)
        assert.equals(780, char().professions[2900].amount)
    end)

    it("finds cooldown recipes, groups shared cooldowns and counts charges", function()
        WoWMock.recipeCooldowns[700] = { 3600, true, 0, 0 }
        WoWMock.recipeCooldowns[701] = { 3600, true, 0, 0 }
        WoWMock.recipeCooldowns[703] = { 1800, false, 1, 3 }
        WoWMock.spellCharges[703] = { cooldownDuration = 7200 }
        WoWMock.fire("TRADE_SKILL_SHOW")
        WoWMock.advance(1)
        WoWMock.flush()
        local list = char().cooldowns
        assert.is_table(list[700])
        assert.is_nil(list[702])
        assert.equals(3, list[703].maxCharges)
        local e = P.Overview(GoblinomicsWorkshopDB, {}, WoWMock.now)[1]
        assert.equals(2, #e.cooldowns)                              -- the two transmutes are one entry
        local transmute, flask
        for _, c in ipairs(e.cooldowns) do if c.maxCharges then flask = c else transmute = c end end
        assert.equals(2, transmute.count)
        assert.equals(WoWMock.now + 3600, transmute.readyAt)
        assert.equals(1, flask.charges)
        assert.equals(WoWMock.now + 1800 + 7200, flask.fullAt)
        local charges = P.CooldownState(list[703], WoWMock.now + 1800 + 10)
        assert.equals(2, charges)
    end)

    it("leaves cooldowns alone while they are secret", function()
        WoWMock.recipeCooldowns[700] = { 3600, true, 0, 0 }
        WoWMock.cooldownsSecret = true
        assert.is_false(P.ReadCooldown(700))
        WoWMock.cooldownsSecret = false
        assert.is_true(P.ReadCooldown(700))
    end)

    it("lists characters by the first due entry and leaves hidden ones out", function()
        local now = 100000
        local root = { chars = {
            ["Main-Realm"] = { name = "Main", professions = { [1] = { name = "Alchemy", amount = 900, max = 1000,
                cycleSec = 360, readAt = now } } },
            ["Alt-Realm"] = { name = "Alt", professions = { [2] = { name = "Smithing", amount = 999, max = 1000,
                cycleSec = 360, readAt = now } } },
            ["Bank-Realm"] = { name = "Bank" },
        } }
        local list = P.Overview(root, {}, now)
        assert.same({ "Alt-Realm", "Main-Realm" }, { list[1].key, list[2].key })
        assert.equals(now + 360, list[1].dueAt)
        list = P.Overview(root, { professionsHidden = { ["Alt-Realm"] = true } }, now)
        assert.equals(1, #list)
        local due = P.Due(root, { concentrationThreshold = 950 }, now)
        assert.equals("Alt-Realm", due[1].char)                      -- already above the threshold
        assert.equals(now, due[1].at)
        assert.equals(now + 50 * 360, due[2].at)
    end)
end)
