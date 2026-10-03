local fake = require("spec.support.sources")

describe("Vault: speculative items", function()
    local ns, vns

    local NOW = 1700000000
    local HOUR = 3600

    before_each(function()
        ns, vns = load_vault()
        ns.Price.Config().speculativeMinValue = 0   -- test prices are far below 1000 gold
        ns.Price.RegisterSource(fake("tsm", 10, {
            market = { ["i:1"] = 10000, ["i:3"] = 100000, ["i:5"] = 40000 },
            saleRate = { ["i:1"] = 0.5, ["i:3"] = 0.012, ["i:5"] = 0.02 },
        }))
    end)

    after_each(function() assert.same({}, WoWMock.errors) end)

    local function root()
        return {
            chars = {
                ["Main-Realm"] = { name = "Main", class = "WARRIOR", locations = {
                    bags = { seenAt = NOW - HOUR, items = { ["i:1"] = 2, ["i:3"] = 2, ["i:5"] = 3 }, bound = { ["i:5"] = 1 } },
                    auctions = { seenAt = NOW - HOUR, items = { ["i:3"] = 1 } },
                    equipment = { seenAt = NOW - HOUR, items = { ["i:3"] = 1 } },
                } },
                ["Alt-Realm"] = { name = "Alt", locations = {
                    bank = { seenAt = NOW - 10 * 86400, items = { ["i:3"] = 4 } },
                } },
            },
            warband = { seenAt = NOW - HOUR, items = { ["i:5"] = 1 } },
        }
    end

    it("lists speculative items with places, quantities, values and sale rate", function()
        local r = vns.Speculative.Collect(root(), {}, NOW)
        assert.equals(2, #r.items)
        local rare = r.items[1]
        assert.equals("i:3", rare.key)
        assert.equals(7, rare.quantity)                 -- bags 2 + auction 1 + Alt bank 4, no equipment
        assert.equals(700000, rare.value)
        assert.equals(0.012, rare.saleRate)
        assert.equals("tsm", rare.source)
        assert.equals("Alt-Realm", rare.locations[1].char)
        assert.equals("bank", rare.locations[1].location)
        assert.equals("stale", rare.locations[1].state)
        local other = r.items[2]
        assert.equals(3, other.quantity)                -- 2 tradable in bags + 1 in the warband bank
        local warband
        for _, p in ipairs(other.locations) do if p.location == "warband" then warband = p end end
        assert.is_nil(warband.char)
        assert.equals(10, r.quantity)
        assert.equals(820000, r.value)
    end)

    it("formats sale rates and expands an item into its places", function()
        assert.equals("1.2%", vns.SpeculativeUI.SaleRate(0.012))
        assert.equals("-", vns.SpeculativeUI.SaleRate(nil))
        local r = vns.Speculative.Collect(root(), {}, NOW)
        assert.equals(2, #vns.SpeculativeUI.BuildRows(r.items))
    end)

    describe("filters", function()
        local SUI, r

        before_each(function()
            SUI = vns.SpeculativeUI
            WoWMock.items[3] = { name = "Rare Pet Cage" }
            WoWMock.items[5] = { name = "Old Gem" }
            r = vns.Speculative.Collect(root(), {}, NOW)
        end)

        local function apply(f)
            local base = { char = "all", location = "all", search = "", minGold = 0, sort = "value" }
            for k, v in pairs(f) do base[k] = v end
            return SUI.Apply(r, base)
        end

        it("filters by character and recomputes the totals from its places", function()
            local items, quantity, value = apply({ char = "Alt-Realm" })
            assert.equals(1, #items)
            assert.equals(4, items[1].quantity)
            assert.equals(4, quantity)
            assert.equals(400000, value)
        end)

        it("filters the warband bank and locations", function()
            local items = apply({ char = "warband" })
            assert.equals(1, #items)
            assert.equals("i:5", items[1].key)
            items = apply({ location = "auctions" })
            assert.equals(1, #items)
            assert.equals(1, items[1].quantity)
        end)

        it("filters by name and minimum value", function()
            assert.equals("i:5", apply({ search = "gem" })[1].key)
            assert.equals(0, #apply({ search = "nothing" }))
            local items = apply({ minGold = 50 })     -- i:3 is worth 70 g, i:5 12 g
            assert.equals(1, #items)
            assert.equals("i:3", items[1].key)
        end)

        it("sorts by value, quantity, sale rate and name", function()
            assert.equals("i:3", apply({ sort = "value" })[1].key)
            assert.equals("i:3", apply({ sort = "quantity" })[1].key)
            assert.equals("i:3", apply({ sort = "rate" })[1].key)   -- 1.2 % before 2 %
            assert.equals("i:5", apply({ sort = "name" })[1].key)   -- Old Gem before Rare Pet Cage
        end)

        it("offers the characters that hold speculative items plus the warband bank", function()
            local labels = {}
            for _, c in ipairs(SUI.CharacterChoices(r)) do labels[#labels + 1] = c.label end
            assert.same({ "All characters", "Alt", "Main", "Warband bank" }, labels)
        end)
    end)

    it("registers the tab and builds it without errors", function()
        local tab = ns.UI.GetTab("speculative")
        assert.is_table(tab)
        GoblinomicsVaultDB.chars = root().chars
        GoblinomicsVaultDB.warband = root().warband
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        WoWMock.flush()
        assert.equals(2, #vns.Speculative.Get().items)
        tab.onHide()
    end)
end)
