-- M6 acceptance: 20 crafts with quality tiers over three recipes; profit per recipe
-- and quality is traceable; without CraftSim the reagent fallback delivers the costs.
local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("M6 acceptance", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local wns, lns

    local function basic(itemID, qty, slot)
        return { reagentType = 1, dataSlotIndex = slot, quantityRequired = qty, reagents = { { itemID = itemID } } }
    end

    before_each(function()
        local ns
        ns, wns, lns = load_workshop({ ledger = true, before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", qualityItemIDs = { 501, 502 },
                schematic = { reagentSlotSchematics = { basic(11, 3, 1),
                    { reagentType = 1, dataSlotIndex = 2, quantityRequired = 2, reagents = { { itemID = 21 }, { itemID = 22 } } } } } }
            WoWMock.recipes[110] = { name = "Flask", profession = "Alchemy", qualityItemIDs = { 511, 512 },
                schematic = { reagentSlotSchematics = { basic(12, 2, 1),
                    { reagentType = 1, dataSlotIndex = 2, quantityRequired = 1, reagents = { { itemID = 22 } } } } } }
            WoWMock.recipes[120] = { name = "Sword", profession = "Blacksmithing", qualityItemIDs = { 601, 602 },
                schematic = { reagentSlotSchematics = { basic(13, 5, 1) } } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100, ["i:21"] = 1000, ["i:22"] = 2000,
            ["i:12"] = 500, ["i:13"] = 300, ["i:511"] = 4000, ["i:512"] = 9000 } }))
        for _, id in ipairs({ 501, 502 }) do WoWMock.items[id] = { name = "Potion" } end
    end)

    local function potionSeries()
        local q2 = function(qty, extra)
            local f = { id = 502, name = "Potion", qty = qty or 1, quality = 2 }
            for k, v in pairs(extra or {}) do f[k] = v end
            return { S.result(f) }
        end
        local q1 = function() return { S.result({ id = 501, name = "Potion", quality = 1 }) } end
        S.craft(100, { { reagent = { itemID = 21 }, quantity = 2, dataSlotIndex = 2 } }, {
            q2(), q2(), q2(2), q2(1, { returned = { { 21, 1 } } }), q1(), q1(), q2(), q2(),
        })
    end

    local function sell(name, count, bid, consignment)
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
        WoWMock.mail = { { sender = "Auction House", subject = "Auction successful", money = bid - consignment,
            invoice = { type = "seller", itemName = name, player = "Buyer", bid = bid, count = count,
                consignment = consignment } } }
        TakeInboxMoney(1)
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.MailInfo)
    end

    local function byName(rows)
        local map = {}
        for _, r in ipairs(rows) do map[r.name] = r end
        return map
    end

    it("records 20 crafts and yields the profit per recipe and quality", function()
        potionSeries()                                                          -- 8 crafts
        local flask = {}
        for i = 1, 7 do
            flask[i] = { S.result(i <= 3 and { id = 512, quality = 2, conc = 30 } or { id = 511, quality = 1 }) }
        end
        S.craft(110, { { reagent = { itemID = 22 }, quantity = 1, dataSlotIndex = 2 } }, flask)   -- 7 crafts
        local sword = {}
        for i = 1, 5 do sword[i] = { S.result({ id = 601, quality = 1 }) } end
        S.craft(120, {}, sword)                                                  -- 5 crafts

        -- two qualities with the same name on the auction house
        lns.AuctionLog.Post("i:502", 4, 0, S.link(502, "Potion"), 5000)
        lns.AuctionLog.Post("i:501", 2, 0, S.link(501, "Potion"), 3000)
        sell("Potion", 4, 20000, 1000)     -- quality 2, net 19,000
        sell("Potion", 1, 3000, 150)       -- quality 1, net 2,850

        local rows = byName(wns.Stats.Recipes({}))
        local potion, flaskRow, swordRow = rows.Potion, rows.Flask, rows.Sword
        assert.equals(20, potion.crafts + flaskRow.crafts + swordRow.crafts)
        assert.equals(8, potion.crafts)
        assert.equals(9, potion.made)
        assert.equals(7 * 2300 + 1300, potion.cost)          -- resourcefulness returned one reagent
        assert.equals(5, potion.sold)
        assert.equals(21850, potion.revenue)
        assert.equals(9200, potion.soldCost)                  -- 3 crafts (1 + 1 + multicraft 2) + 1 quality 1
        assert.equals(12650, potion.profit)
        local q = {}
        for _, s in ipairs(potion.qualityList) do q[s.quality] = s end
        assert.equals(7, q[2].made)
        assert.equals(12800, q[2].cost)
        assert.equals(12100, q[2].profit)
        assert.equals(550, q[1].profit)
        assert.equals(4, potion.openQty)

        assert.equals(7, flaskRow.crafts)
        assert.equals(21000, flaskRow.cost)
        assert.equals(0, flaskRow.profit)
        assert.equals(5, swordRow.openQty)
        assert.equals(7500, swordRow.openCost)
    end)

    it("delivers costs without CraftSim from reagents and market prices", function()
        assert.is_nil(_G.CraftSimAPI)
        potionSeries()
        local record = GoblinomicsWorkshopDB.crafts[1]
        assert.equals(2300, record.cost)
        assert.is_nil(record.incomplete)
        assert.is_nil(record.costSource)
    end)
end)
