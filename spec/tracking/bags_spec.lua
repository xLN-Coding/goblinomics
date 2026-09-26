local collect = require("spec.support.collect")

local LINCLOTH = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"
local POTION = "|cffffffff|Hitem:1000::::::::80:::::|h[Potion]|h|r"

local function item(id, link, count)
    return { itemID = id, hyperlink = link, stackCount = count }
end

describe("Tracking: bags", function()
    local ns, got

    before_each(function()
        ns = load_core({ login = true })
        WoWMock.bags[0] = { numSlots = 4, [1] = item(2589, LINCLOTH, 10), [2] = item(1000, POTION, 3) }
        got = collect(ns, { "ITEMS_DELTA", "LOOT_RECEIVED" })
        WoWMock.flush()
    end)

    it("takes a baseline without emitting", function()
        assert.is_true(ns.Bags.HasBaseline())
        assert.equals(10, ns.Bags.GetCount("i:2589"))
        assert.equals(0, #got.ITEMS_DELTA)
    end)

    it("scans dirty bags in the next frame and emits deltas with context", function()
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
        WoWMock.bags[0][2] = nil
        WoWMock.fire("BAG_UPDATE", 0)
        assert.equals(0, #got.ITEMS_DELTA)
        WoWMock.flush()
        local p = got.ITEMS_DELTA[1]
        assert.same({ { itemKey = "i:1000", link = POTION, delta = -3 } }, p.changes)
        assert.is_true(p.context.merchant)
    end)

    it("nets looted items against loot claims", function()
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. LINCLOTH .. "x5.")
        WoWMock.bags[0][1] = item(2589, LINCLOTH, 17)
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        assert.equals(1, #got.LOOT_RECEIVED)
        assert.same({ { itemKey = "i:2589", link = LINCLOTH, delta = 2 } }, got.ITEMS_DELTA[1].changes)
    end)

    it("retries slots whose item info is not loaded yet", function()
        WoWMock.bags[0][3] = { stackCount = 1 } -- no itemID yet
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        assert.equals(0, #got.ITEMS_DELTA)
        WoWMock.bags[0][3] = item(2589, LINCLOTH, 1)
        WoWMock.advance(0.5)
        WoWMock.flush()
        assert.same({ { itemKey = "i:2589", link = LINCLOTH, delta = 1 } }, got.ITEMS_DELTA[1].changes)
    end)

    it("waits for combat to end", function()
        WoWMock.combat = true
        WoWMock.bags[0][2] = item(1000, POTION, 2)
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        assert.equals(0, #got.ITEMS_DELTA)
        WoWMock.combat = false
        WoWMock.fire("PLAYER_REGEN_ENABLED")
        WoWMock.flush()
        assert.equals(-1, got.ITEMS_DELTA[1].changes[1].delta)
    end)

    it("ignores bank and warband bags", function()
        WoWMock.fire("BAG_UPDATE", Enum.BagIndex.AccountBankTab_1)
        WoWMock.flush()
        assert.equals(0, #got.ITEMS_DELTA)
    end)

    it("reports removed slots when a bag shrinks", function()
        WoWMock.bags[0].numSlots = 1
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        assert.equals(-3, got.ITEMS_DELTA[1].changes[1].delta)
    end)
end)
