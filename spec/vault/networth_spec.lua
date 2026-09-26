-- M3 acceptance: a known inventory with known prices yields exactly the expected tiers.
local fake = require("spec.support.sources")

describe("Vault: networth", function()
    local ns, vns, values

    local NOW = 1700000000
    local HOUR = 3600

    before_each(function()
        ns, vns = load_vault({ login = false })
        values = {
            market = { ["i:1"] = 10000, ["i:2"] = 5000, ["i:3"] = 100000 },
            saleRate = { ["i:1"] = 0.5, ["i:2"] = 0.1, ["i:3"] = 0.01 },
            destroy = { ["i:9"] = 2000 },
        }
        ns.Price.RegisterSource(fake("tsm", 10, values))
        WoWMock.items[4] = { sellPrice = 300 }
        WoWMock.items[9] = { sellPrice = 100 }
    end)

    local function root()
        return {
            chars = {
                ["Main-Realm"] = {
                    name = "Main", class = "WARRIOR", gold = 1000000,
                    locations = {
                        bags = { seenAt = NOW - HOUR, items = { ["i:1"] = 2, ["i:4"] = 10, ["i:9"] = 1 }, bound = { ["i:9"] = 1 } },
                        mail = { seenAt = NOW - HOUR, items = { ["i:2"] = 4 }, money = 50000 },
                        auctions = { seenAt = NOW - HOUR, items = { ["i:1"] = 3 } },
                        equipment = { seenAt = NOW - HOUR, items = { ["i:9"] = 1 } },
                    },
                },
                ["Alt-Realm"] = {
                    name = "Alt", gold = 20000,
                    locations = { bank = { seenAt = NOW - 10 * 86400, items = { ["i:3"] = 1 } } },
                },
            },
            warband = { gold = 3000000, seenAt = NOW - HOUR, items = { ["i:2"] = 2 }, bound = {} },
        }
    end

    it("computes one wealth figure: gold, auctions and sellable items, speculative separately", function()
        local r = vns.Networth.Compute(root(), {}, NOW)
        -- gold: 1,000,000 + 20,000 + 3,000,000 + mail 50,000
        assert.equals(4070000, r.gold)
        assert.equals(30000, r.auctions)                 -- i:1 x3
        -- items: i:1 x2 = 20,000; vendor-only i:4 x10 = 3,000; mail i:2 x4 = 20,000;
        -- alt bank i:3 = 100,000 (speculative); warband i:2 x2 = 10,000; bound i:9 and equipment not counted
        assert.equals(153000, r.items)
        assert.equals(100000, r.speculative)
        assert.equals(4070000 + 30000 + 153000, r.wealth)
    end)

    it("breaks the result down per character and for the warband", function()
        local r = vns.Networth.Compute(root(), {}, NOW)
        local main = r.chars["Main-Realm"]
        assert.equals(1050000, main.gold)
        assert.equals(43000, main.items)
        assert.equals(1050000 + 43000 + 30000, main.wealth)
        assert.equals(3000000, r.warband.gold)
        assert.equals(3010000, r.warband.wealth)
    end)

    it("leaves out bound items in mail (warbound) and every equipped item", function()
        local data = root()
        data.chars["Main-Realm"].locations.mail.bound = { ["i:2"] = 4 }
        data.chars["Main-Realm"].locations.equipment.items["i:1"] = 1
        local r = vns.Networth.Compute(data, {}, NOW)
        assert.equals(133000, r.items)
    end)

    it("counts stale locations, reports never-seen ones and lowers the confidence", function()
        local r = vns.Networth.Compute(root(), {}, NOW)
        local alt = r.chars["Alt-Realm"]
        assert.equals("stale", alt.locations.bank.state)
        assert.equals(100000, alt.locations.bank.value)
        assert.equals("never", alt.locations.bags.state)
        assert.equals(0, alt.locations.bags.value)
        assert.is_true(r.confidence < 1 and r.confidence > 0)
    end)

    it("runs as a job, emits NETWORTH_UPDATED and records the daily value", function()
        local got
        ns.Bus.On("NETWORTH_UPDATED", function(_, p) got = p end, "Spec")
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        WoWMock.advance(2)
        WoWMock.flush()
        assert.is_table(got)
        assert.equals(got, vns.Networth.Get())
        vns.Networth.RecordDay()
        local day = GoblinomicsVaultDB.history[os.date("%Y-%m-%d", WoWMock.now)]
        assert.equals(got.wealth, day.wealth)
        assert.equals(got.chars["xLN-Blackrock"].gold, day.chars["xLN-Blackrock"].gold)
    end)

    it("records the daily value at logout", function()
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        WoWMock.fire("PLAYER_LOGOUT")
        assert.is_table(GoblinomicsVaultDB.history[os.date("%Y-%m-%d", WoWMock.now)])
    end)

    it("migrates the old daily tiers to one wealth figure", function()
        local _, v2 = load_vault({ before = function()
            _G.GoblinomicsVaultDB = { _schema = 1, history = {
                ["2026-09-20"] = { liquid = 1, market = 500, speculative = 20, total = 900 },
            } }
        end })
        assert.is_table(v2)
        local day = GoblinomicsVaultDB.history["2026-09-20"]
        assert.equals(500, day.wealth)
        assert.equals(20, day.speculative)
        assert.is_nil(day.market)
        assert.is_nil(day.total)
    end)
end)
