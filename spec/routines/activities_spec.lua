-- Great Vault delves, patron orders, the Workshop's concentration and cooldowns, and
-- values measured by the Gatherer.
local fake = require("spec.support.sources")

describe("Routines: activities", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, rns, T
    local ME = "xLN-Blackrock"
    local HERB = "|cffffffff|Hitem:210800::::::::80:::::|h[Herb]|h|r"

    before_each(function()
        ns, rns = load_routines()
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:210800"] = 2000 } }))
        T = rns.Tasks
    end)

    it("reads the Great Vault's world row as the delve task, done at the top threshold", function()
        WoWMock.vaultWorld = { { progress = 3, threshold = 1 }, { progress = 3, threshold = 4 },
            { progress = 3, threshold = 8 } }
        rns.Activities.ReadVault()
        local task = T.Get("delve:vault")
        assert.equals("delve", task.kind)
        local done, detail, resetAt = T.State(task, ME)
        assert.is_false(done)
        assert.equals("3/8", detail)
        assert.equals(WoWMock.now + 3 * 86400, resetAt)
        WoWMock.vaultWorld[3].progress = 8
        rns.Activities.ReadVault()
        assert.is_true((T.State(task, ME)))
        WoWMock.vaultWorld = {}                                       -- nothing read in the new week yet
        WoWMock.advance(3 * 86400 + 1)
        assert.is_false((T.State(task, ME)))                          -- a new week
    end)

    it("reads patron orders at the crafting table and counts fulfilled ones down", function()
        WoWMock.baseProfession = { professionName = "Alchemy" }
        WoWMock.crafterOrders = {
            { orderType = 3, tipAmount = 10000, expirationTime = WoWMock.now + 7200,
                npcOrderRewards = { { itemLink = HERB, count = 5 } } },
            { orderType = 3, tipAmount = 5000, expirationTime = WoWMock.now + 3600, npcOrderRewards = {} },
            { orderType = 0, tipAmount = 99999 },                     -- a public order: not a patron order
        }
        rns.Activities.ReadPatronOrders()
        local task = T.Get("patron:Alchemy")
        assert.equals("Patron orders (Alchemy)", task.name)
        assert.equals(25000, task.measured.value)                     -- tips plus 5 herbs at 20 silver
        local done, detail, resetAt = T.State(task, ME)
        assert.is_false(done)
        assert.equals("2", detail)
        assert.equals(WoWMock.now + 3600, resetAt)
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 1)
        WoWMock.fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 2)
        assert.is_true((T.State(task, ME)))
    end)

    it("takes concentration and cooldowns from the Workshop and values concentration", function()
        local now = WoWMock.now
        ns.API.Workshop = {
            Due = function() return {
                { char = ME, kind = "concentration", label = "Alchemy", lineID = 2900, at = now - 10 },
                { char = ME, kind = "cooldown", label = "Transmute: Ore", recipeID = 700, at = now + 3600 },
            } end,
            ConcentrationValue = function() return { Alchemy = { value = 50 } } end,
        }
        rns.Activities.LearnProfessions()
        local conc, cd = T.Get("prof:c:2900"), T.Get("prof:r:700")
        assert.equals("Use concentration (Alchemy)", conc.name)
        local done, detail = T.State(conc, ME)
        assert.is_false(done)                                         -- full: something to do
        assert.equals("ready", detail)
        done, detail = T.State(cd, ME)
        assert.is_true(done)                                          -- not ready yet
        assert.equals("in 1h 0m", detail)
        GoblinomicsRoutinesDB.chars["Alt-Blackrock"] = { name = "Alt" }
        assert.is_true((T.State(cd, "Alt-Blackrock")))                -- the alt does not have it
        assert.equals(50000, (T.Estimate(conc)))                      -- 1000 points at 50 copper
        ns.API.Workshop = nil
    end)

    it("values instances by the Gatherer's runs there", function()
        ns.API.Gatherer = { InstanceStats = function(_, mapID)
            return mapID == 2900 and { runs = 3, value = 90000, minutes = 30 } or nil
        end }
        local raid = T.Learn({ id = "i:2900:15", kind = "instance", ref = { mapID = 2900, difficultyID = 15 } })
        local value, minutes, vs, ms = T.Estimate(raid)
        assert.same({ 90000, 30, "measured", "measured" }, { value, minutes, vs, ms })
        assert.equals(3000, T.PerMinute(raid))
        ns.API.Gatherer = nil
        value, minutes, vs = T.Estimate(raid)
        assert.same({ 0, 30, "none" }, { value, minutes, vs })          -- the default duration of instances
    end)
end)
