-- Concentration and recipe cooldowns across characters: read once, then computed.
describe("Workshop: concentration and cooldowns", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, wns, P

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

        ns, wns = load_workshop({ before = install })
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

    it("shows the view in the Workshop and the dashboard card, filtered and foldable", function()
        local root = GoblinomicsWorkshopDB
        root.chars["Alt-Realm"] = { name = "Alt", class = "MAGE", professions = { [2901] = { name = "Blacksmithing",
            amount = 990, max = 1000, cycleSec = 360, readAt = WoWMock.now } },
            cooldowns = { [700] = { name = "Transmute: Ore", readyAt = WoWMock.now - 5 } } }
        char().professions = { [2900] = { name = "Alchemy", amount = 100, max = 1000, cycleSec = 360, readAt = WoWMock.now } }
        local V = wns.WorkshopProfessions
        local overview = P.Overview(root, {}, WoWMock.now)
        local rows = V.Rows(overview, {})
        assert.same({ "char", "profession", "cooldown", "char", "profession" },
            { rows[1].kind, rows[2].kind, rows[3].kind, rows[4].kind, rows[5].kind })
        assert.equals("Alt-Realm", rows[1].entry.key)                 -- the transmute is ready
        assert.equals(3, #V.Rows(overview, { char = "Alt-Realm" }))
        assert.equals(2, #V.Rows(overview, { profession = "Blacksmithing" }))   -- no cooldowns under a profession filter
        assert.equals(2, #V.Rows(overview, { profession = "Alchemy" }))
        V.collapsed["Alt-Realm"] = true
        assert.equals(3, #V.Rows(overview, {}))
        V.collapsed["Alt-Realm"] = nil

        local tab = ns.UI.GetTab("workshop")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        wns.WorkshopUI.Show("professions")
        assert.equals(5, #wns.WorkshopUI.CurrentPage().rows)
        WoWMock.advance(61)
        WoWMock.flush()
        tab.onHide()

        local card
        for _, w in ipairs(ns.UI.SortedWidgets()) do if w.id == "workshop.concentration" then card = w end end
        assert.is_table(card)
        local f = CreateFrame("Frame")
        card.build(f)
        card.refresh(f, {})
        assert.is_truthy(f.lines[1].left:GetText():find("Alt"))
    end)

    it("toasts once when an entry becomes due, prints due entries at login and fills the tooltip", function()
        local toasts = {}
        ns.Toast.Show = function(spec) toasts[#toasts + 1] = spec end
        local root = GoblinomicsWorkshopDB
        local N = wns.ProfessionNotices
        root.chars["Alt-Realm"] = { name = "Alt", professions = { [2901] = { name = "Blacksmithing", amount = 1000,
            max = 1000, cycleSec = 360, readAt = WoWMock.now } } }
        char().professions = { [2900] = { name = "Alchemy", amount = 998, max = 1000, cycleSec = 360, readAt = WoWMock.now } }
        local line = N.LoginLine(root, root.settings, WoWMock.now)
        assert.is_truthy(line:find("Alt %(Blacksmithing%)"))
        assert.is_falsy(line:find("Alchemy"))
        local left, right = N.TooltipText(root, root.settings, WoWMock.now)
        assert.equals("Concentration & cooldowns", left)
        assert.is_truthy(right:find("1 ready"))
        assert.is_truthy(right:find("next in 12m"))
        -- the login marks what is due already; only the Alchemy becomes due later
        for k in pairs(WoWMock.chat) do WoWMock.chat[k] = nil end
        WoWMock.advance(7)
        WoWMock.flush()
        assert.is_truthy(WoWMock.chat[1] and WoWMock.chat[1]:find("Blacksmithing"))
        assert.equals(0, #toasts)
        WoWMock.advance(2 * 360)
        WoWMock.flush()
        assert.equals(1, #toasts)
        assert.is_truthy(toasts[1].text:find("Alchemy"))
        N.Check()
        assert.equals(1, #toasts)                                     -- once per due time
        root.settings.notifyTooltip = false
        GameTooltip:SetOwner(UIParent)
        ns.UI.FillTooltipProviders(GameTooltip)
        for _, l in ipairs(GameTooltip.lines) do assert.is_falsy(tostring(l.left or l[1] or ""):find("Concentration")) end
        assert.is_nil(N.LoginLine({ chars = {} }, {}, WoWMock.now))
    end)

    it("builds the settings with the threshold, the notice switches and the characters", function()
        char().professions = { [2900] = { name = "Alchemy", amount = 1, readAt = 1 } }
        local section
        for _, s in ipairs(ns.UI.SortedSettings()) do if s.id == "workshop" then section = s end end
        assert.is_true(section.build(CreateFrame("Frame"), 0) > 200)
    end)
end)
