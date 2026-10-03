-- The items behind a character's (or the warband bank's) wealth: same rules as the
-- networth, so they add up to the row; the Vault tab expands a row into them.
local fake = require("spec.support.sources")

describe("Vault: items per character", function()
    local ns, vns

    local NOW = 1700000000
    local HOUR = 3600

    before_each(function()
        ns, vns = load_vault()
        ns.Price.RegisterSource(fake("tsm", 10, {
            market = { ["i:1"] = 10000, ["i:3"] = 100000, ["i:5"] = 40000 },
            vendor = { ["i:9"] = 500 },
        }))
        for k in pairs(vns.VaultUI.expanded) do vns.VaultUI.expanded[k] = nil end
        for k in pairs(vns.VaultUI.showAll) do vns.VaultUI.showAll[k] = nil end
    end)

    after_each(function() assert.same({}, WoWMock.errors) end)

    local function root()
        return {
            chars = {
                ["Main-Realm"] = { name = "Main", class = "WARRIOR", gold = 100, locations = {
                    bags = { seenAt = NOW - HOUR, items = { ["i:1"] = 2, ["i:3"] = 2, ["i:5"] = 3, ["i:9"] = 4 },
                        bound = { ["i:5"] = 1 } },
                    bank = { seenAt = NOW - 10 * 86400, items = { ["i:1"] = 5 } },
                    auctions = { seenAt = NOW - HOUR, items = { ["i:3"] = 1 } },
                    equipment = { seenAt = NOW - HOUR, items = { ["i:3"] = 1 }, bound = { ["i:3"] = 1 } },
                } },
                ["Alt-Realm"] = { name = "Alt", locations = {
                    mail = { items = { ["i:3"] = 9 } },                     -- never seen: not counted
                } },
            },
            warband = { seenAt = NOW - HOUR, items = { ["i:5"] = 2, ["i:3"] = 1 }, bound = { ["i:3"] = 1 } },
        }
    end

    it("lists a character's items with quantity, value and locations, most valuable first", function()
        local h = vns.Holdings.Collect(root(), {}, NOW, "Main-Realm")
        local keys = {}
        for _, e in ipairs(h.items) do keys[#keys + 1] = e.key end
        assert.same({ "i:3", "i:5", "i:1", "i:9" }, keys)
        local rare = h.items[1]
        assert.equals(3, rare.quantity)                            -- bags 2 + auction 1, no equipment
        assert.equals(300000, rare.value)
        assert.equals("bags", rare.locations[1].location)
        assert.equals("auctions", rare.locations[2].location)
        assert.equals(2, h.items[2].quantity)                      -- one of three is bound
        local cloth = h.items[3]
        assert.equals(7, cloth.quantity)
        local bank
        for _, loc in ipairs(cloth.locations) do if loc.location == "bank" then bank = loc end end
        assert.equals("stale", bank.state)
        assert.equals(5, bank.quantity)
        assert.equals(2000, h.items[4].value)                      -- vendor price
        assert.same({}, vns.Holdings.Collect(root(), {}, NOW, "Alt-Realm").items)
        assert.same({}, vns.Holdings.Collect(root(), {}, NOW, "Nobody-Realm").items)
    end)

    it("adds up to the networth of every character and of the warband bank", function()
        local r = root()
        local net = vns.Networth.Compute(r, {}, NOW)
        for charKey, c in pairs(net.chars) do
            assert.equals(c.items + c.auctions, vns.Holdings.Collect(r, {}, NOW, charKey).value)
        end
        local w = vns.Holdings.Collect(r, {}, NOW, "warband")
        assert.equals(net.warband.items, w.value)
        assert.equals(1, #w.items)                                 -- the bound one is left out
        assert.equals("warband", w.items[1].locations[1].location)
    end)

    it("expands an owner row into its items, a loading row or a more row", function()
        local VUI = vns.VaultUI
        local h = { items = {} }
        for i = 1, 53 do h.items[i] = { key = "i:" .. i, quantity = 1, value = 100 - i, locations = {} } end
        local function owners() return { { key = "Main-Realm" }, { key = "warband", warband = {} } } end
        assert.equals(2, #VUI.BuildRows(owners(), function() return h end))
        VUI.expanded["Main-Realm"] = true
        local rows = VUI.BuildRows(owners(), function() return nil end)
        assert.equals("loading", rows[2].kind)
        rows = VUI.BuildRows(owners(), function(k) return k == "Main-Realm" and h or nil end)
        assert.equals(1 + 50 + 1 + 1, #rows)
        assert.equals("item", rows[2].kind)
        assert.equals("more", rows[52].kind)
        assert.equals(3, rows[52].count)
        assert.equals(49 + 48 + 47, rows[52].value)
        assert.equals("owner", rows[53].kind)
        VUI.showAll["Main-Realm"] = true
        assert.equals(1 + 53 + 1, #VUI.BuildRows(owners(), function(k) return k == "Main-Realm" and h or nil end))
        VUI.expanded.warband = true
        rows = VUI.BuildRows(owners(), function(k) return k == "warband" and { items = {} } or nil end)
        assert.equals("loading", rows[2].kind)
        assert.equals("empty", rows[4].kind)
    end)

    it("builds the tab, expands a character on click and shows its items", function()
        GoblinomicsVaultDB.chars = root().chars
        GoblinomicsVaultDB.warband = root().warband
        vns.Networth.Schedule()
        WoWMock.flush()
        WoWMock.advance(3)
        WoWMock.flush()
        local tab = ns.UI.GetTab("vault")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        WoWMock.flush()
        vns.VaultUI.expanded["Main-Realm"] = true
        vns.Holdings.Run("Main-Realm")
        WoWMock.flush()
        assert.is_table(vns.Holdings.Get("Main-Realm"))
        assert.equals(4, #vns.Holdings.Get("Main-Realm").items)
        tab.onShow()
        WoWMock.flush()
        tab.onHide()
    end)

    it("counts an item's tradable stock over all characters and the warband bank", function()
        local r = root()
        -- Main: bags 2, auctions 1 (equipment left out); Alt: mail 9; warband: its one unit is bound
        assert.equals(12, vns.Vault.ItemCount(r, "i:3"))
        assert.equals(4, vns.Vault.ItemCount(r, "i:5"))              -- bags 3 with 1 bound, warband 2
        assert.equals(0, vns.Vault.ItemCount(r, "i:404"))
    end)
end)
