local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: concentration value", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local wns

    before_each(function()
        local ns
        ns, wns = load_workshop({ before = function()
            WoWMock.recipes[110] = { name = "Flask", profession = "Alchemy", qualityItemIDs = { 511, 512 },
                schematic = { reagentSlotSchematics = {} } }
            WoWMock.recipes[200] = { name = "Sword", profession = "Blacksmithing", qualityIDs = { 7, 8 },
                outputs = { [7] = S.link(601, "Sword") }, schematic = { reagentSlotSchematics = {} } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:511"] = 4000, ["i:512"] = 9000,
            ["i:601"] = 100000, ["i:602"] = 250000 } }))
    end)

    it("values the quality gain per concentration point and averages it per profession", function()
        S.craft(110, {}, {
            { S.result({ id = 512, quality = 2, conc = 50 }) },            -- 5,000 gain / 50 = 100 per point
            { S.result({ id = 512, quality = 2, qty = 2, conc = 50 }) },   -- 10,000 / 50 = 200 per point
            { S.result({ id = 511, quality = 1 }) },                       -- no concentration
        })
        local crafts = GoblinomicsWorkshopDB.crafts
        assert.equals(100, wns.Concentration.PerPoint(crafts[1]))
        assert.equals(200, wns.Concentration.PerPoint(crafts[2]))
        assert.is_nil(wns.Concentration.PerPoint(crafts[3]))
        local alchemy = wns.Concentration.ByProfession().Alchemy
        assert.equals(150, alchemy.value)
        assert.equals(2, alchemy.crafts)
        assert.equals(100, alchemy.points)
    end)

    it("finds the quality below of gear through the output data", function()
        S.craft(200, {}, { { S.result({ id = 602, quality = 2, conc = 300 }) } })
        assert.equals(500, wns.Concentration.PerPoint(GoblinomicsWorkshopDB.crafts[1]))
    end)

    it("only averages crafts inside the window", function()
        S.craft(110, {}, { { S.result({ id = 512, quality = 2, conc = 50 }) } })
        WoWMock.advance(31 * 86400)
        assert.is_nil(wns.Concentration.ByProfession().Alchemy)
    end)
end)
