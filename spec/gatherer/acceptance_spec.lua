-- M5 acceptance: a gathering session, a dungeon run and a raid with a boss encounter produce the
-- correct sums; the summary follows the session format.
local fake = require("spec.support.sources")

local HERB = "|cffffffff|Hitem:210796::::::::80:::::|h[Mycobloom]|h|r"
local ORE = "|cffffffff|Hitem:210930::::::::80:::::|h[Bismuth]|h|r"
local GREY = "|cff9d9d9d|Hitem:5000::::::::80:::::|h[Broken Tooth]|h|r"
local RARE = "|cff0070dd|Hitem:6000::::::::80:::::|h[Rare Pet]|h|r"

local ns, pns, Session, Farms

local function money(delta)
    WoWMock.set_money(WoWMock.money + delta)
    WoWMock.fire("PLAYER_MONEY")
end

local function loot(link, qty, guid)
    WoWMock.loot = { { link = link, sources = { guid or "Creature-0-1", qty } } }
    WoWMock.fire("LOOT_READY")
    local line = qty > 1 and ("You receive loot: " .. link .. "x" .. qty .. ".") or ("You receive loot: " .. link .. ".")
    WoWMock.fire("CHAT_MSG_LOOT", line, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, WoWMock.player.guid)
    WoWMock.fire("LOOT_CLOSED")
end

local function restrict(name, on)
    local T = Enum.AddOnRestrictionType
    WoWMock.restricted[T[name]] = on or nil
    WoWMock.fire("ADDON_RESTRICTION_STATE_CHANGED", T[name], on and 2 or 0)
end

before_each(function()
    ns, pns = load_gatherer()
    Session, Farms = pns.Session, pns.Farms
    ns.Price.RegisterSource(fake("tsm", 10, {
        market = { ["i:210796"] = 1000000, ["i:210930"] = 500000, ["i:6000"] = 90000000 },
        saleRate = { ["i:210796"] = 0.5, ["i:210930"] = 0.4, ["i:6000"] = 0.01 },
    }))
    WoWMock.items[5000] = { name = "Broken Tooth", sellPrice = 2500 }
    WoWMock.items[210796] = { name = "Mycobloom" }
    WoWMock.items[210930] = { name = "Bismuth" }
    WoWMock.items[6000] = { name = "Rare Pet" }
end)

describe("M5 acceptance", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("gathering session: node loot with quantities, pauses do not count", function()
        local farm = Farms.Create({ name = "Herbs", category = "gathering", expectedHighlights = { "i:210796" } })
        Session.Start(farm.id)
        loot(HERB, 5, "GameObject-0-1")
        WoWMock.advance(600)
        loot(HERB, 3, "GameObject-0-2")
        loot(ORE, 2, "GameObject-0-3")
        Session.Pause()
        WoWMock.advance(900)
        Session.Resume()
        WoWMock.advance(300)
        local summary = Session.Stop()
        assert.equals(900, summary.duration)
        assert.equals(8, summary.items["i:210796"])
        assert.equals(2, summary.items["i:210930"])
        assert.equals(9000000, summary.market)          -- 8 x 100g + 2 x 50g
        assert.equals(0, summary.rawGold)
        assert.equals(9000000, summary.total)
        assert.equals(36000000, summary.gph)            -- 900g in 15 minutes
        assert.equals(1, Farms.Stats(farm.id).runs)
        assert.is_nil(Session.Active())
    end)

    it("dungeon run: mob loot, raw gold, vendor trash and prorated repair", function()
        -- learn the repair rate at a merchant: 20 missing points cost 20s
        WoWMock.durability[1] = { 80, 100 }
        WoWMock.repairCost = 2000
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.Merchant)
        WoWMock.durability[1] = { 100, 100 }
        WoWMock.fire("UPDATE_INVENTORY_DURABILITY")
        WoWMock.advance(10)

        local farm = Farms.Create({ name = "Dungeon", category = "dungeon" })
        Session.Start(farm.id)
        -- gold with the loot window open
        WoWMock.loot = {}
        WoWMock.fire("LOOT_READY"); money(15000); WoWMock.fire("LOOT_CLOSED")
        WoWMock.advance(5)
        loot(GREY, 4)
        loot(ORE, 1)
        WoWMock.advance(5)
        -- autoloot: chat line after the money
        money(5000); WoWMock.fire("CHAT_MSG_MONEY", "You loot 50 Silver")
        WoWMock.durability[1] = { 90, 100 }
        WoWMock.fire("UPDATE_INVENTORY_DURABILITY")
        WoWMock.advance(1790)
        local summary = Session.Stop()
        assert.equals(1800, summary.duration)
        assert.equals(20000, summary.rawGold)
        assert.equals(10000, summary.vendor)            -- 4 x 25s
        assert.equals(500000, summary.market)
        assert.equals(1000, summary.repair)             -- 10 points x 1s
        assert.equals(500000 + 20000 + 10000 - 1000, summary.total)
        assert.equals(20000, summary.realized)
    end)

    it("raid boss encounter: loot and gold arrive through the restricted replay", function()
        local farm = Farms.Create({ name = "Old raid", category = "raid" })
        Session.Start(farm.id)
        restrict("Encounter", true)
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. ORE .. "x3.", nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, WoWMock.player.guid)
        money(40000)
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. RARE .. ".", nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, WoWMock.player.guid)
        assert.same({}, Session.Active().items)
        restrict("Encounter", false)
        WoWMock.flush()
        WoWMock.advance(1200)
        local summary = Session.Stop()
        assert.equals(3, summary.items["i:210930"])
        assert.equals(1, summary.items["i:6000"])
        assert.equals(1500000, summary.market)
        assert.equals(40000, summary.rawGold)
        assert.equals(90000000, summary.speculative)    -- separate line
        assert.equals(1540000, summary.total)           -- speculative not in total
    end)

    it("summary follows the session format", function()
        local farm = Farms.Create({ name = "Herbalism - Zone X", category = "gathering" })
        Session.Start(farm.id)
        loot(HERB, 482, "GameObject-0-1")
        loot(ORE, 217, "GameObject-0-2")
        WoWMock.fire("LOOT_READY"); money(72300000); WoWMock.fire("LOOT_CLOSED")
        WoWMock.advance(5538)
        local summary = Session.Stop()
        local v = Session.SummaryValuation(summary)
        local text = pns.Valuation.Text({ farmName = summary.farmName, duration = summary.duration, valuation = v })
        local lines = {}
        for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
        assert.equals("Farm: Herbalism - Zone X", lines[1])
        assert.equals("Duration: 01:32:18", lines[2])
        assert.equals("Items: Mycobloom 482 \194\183 Bismuth 217", lines[3])
        assert.equals("Market Value: 59,050g", lines[4])
        assert.equals("Raw Gold: 7,230g", lines[5])
        assert.equals("Vendor: 0g", lines[6])
        assert.equals(("\226\148\128"):rep(16), lines[7])
        assert.equals("Total: 66,280g", lines[8])
        assert.equals("GPH: 43,086g", lines[9])
        assert.equals("Realized: 7,230g", lines[10])
    end)
end)
