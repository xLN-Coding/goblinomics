local collect = require("spec.support.collect")
local LINK = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"
local SWORD = "|cffa335ee|Hitem:500::::::::80:::::|h[Sword]|h|r"

describe("Core bags: bound counts and snapshot", function()
    local ns

    before_each(function()
        ns = load_core({ login = true, money = 1 })
        WoWMock.bags[0] = {
            numSlots = 3,
            [1] = { itemID = 2589, hyperlink = LINK, stackCount = 20 },
            [2] = { itemID = 500, hyperlink = SWORD, stackCount = 1, isBound = true },
        }
        collect(ns, { "ITEMS_DELTA" })
        WoWMock.flush()
    end)

    it("reports items, bound units and links", function()
        local snap = ns.API.Bags:Snapshot()
        assert.same({ ["i:2589"] = 20, ["i:500"] = 1 }, snap.items)
        assert.same({ ["i:500"] = 1 }, snap.bound)
        assert.equals(SWORD, snap.links["i:500"])
    end)

    it("tracks items that become bound and bound items that leave", function()
        WoWMock.bags[0][1].isBound = true
        WoWMock.bags[0][2] = nil
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        local snap = ns.Bags.Snapshot()
        assert.same({ ["i:2589"] = 20 }, snap.bound)
        assert.is_nil(snap.items["i:500"])
    end)

    it("returns a copy", function()
        local snap = ns.Bags.Snapshot()
        snap.items["i:2589"] = 0
        assert.equals(20, ns.Bags.Snapshot().items["i:2589"])
    end)

    it("has no snapshot before the baseline", function()
        ns = load_core({ login = true, money = 1 })
        assert.is_nil(ns.Bags.Snapshot())
    end)
end)
