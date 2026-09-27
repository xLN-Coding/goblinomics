describe("Core: bound items for the wealth", function()
    local ns

    before_each(function()
        ns = load_core({ login = true, money = 1 })
    end)

    it("treats soulbound, warbound and warbound-until-equipped items as bound", function()
        local B = ns.Binding
        assert.is_true(B.IsBound({ itemID = 1, isBound = true }, 0, 1))
        WoWMock.items[2] = { bindType = 8 }                 -- ToBnetAccount
        assert.is_true(B.IsBound({ itemID = 2 }, 0, 2))
        WoWMock.items[3] = { bindType = 2 }                 -- OnEquip
        assert.is_false(B.IsBound({ itemID = 3 }, 0, 3))    -- a normal BoE
        WoWMock.warboundSlots["0:4"] = true
        WoWMock.items[4] = { bindType = 2 }
        assert.is_true(B.IsBound({ itemID = 4 }, 0, 4))     -- warbound until equipped
        assert.is_true(B.IsWarboundType("|cffffffff|Hitem:2::::::::80:::::|h[X]|h|r"))
        assert.is_false(B.IsWarboundType(3))
    end)

    it("uses it in the bag snapshot", function()
        WoWMock.items[2] = { bindType = 7 }
        WoWMock.bags[0] = { numSlots = 2,
            [1] = { itemID = 2, hyperlink = "|cffffffff|Hitem:2::::::::80:::::|h[W]|h|r", stackCount = 3 },
            [2] = { itemID = 5, hyperlink = "|cffffffff|Hitem:5::::::::80:::::|h[F]|h|r", stackCount = 1 } }
        local got = {}
        ns.Bus.On("ITEMS_DELTA", function() end, "spec")
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        WoWMock.advance(1)
        WoWMock.flush()
        local snap = ns.API.Bags.Snapshot()
        got.bound = snap and snap.bound["i:2"]
        assert.equals(3, got.bound)
        assert.is_nil(snap.bound["i:5"])
    end)

    it("reports items without loaded data, requests them and tells the owner once they arrive", function()
        local B = ns.Binding
        local bound, unknown = B.IsBound({ itemID = 6 }, 0, 1)
        assert.is_false(bound)
        assert.equals(6, unknown)
        local got = {}
        B.OnKnown("spec", function(id) got[#got + 1] = id end)
        B.Await("spec", 6)
        B.Await("spec", 6)
        assert.same({ 6 }, WoWMock.itemRequests)
        WoWMock.fire("GET_ITEM_INFO_RECEIVED", 7, true)
        assert.same({}, got)
        WoWMock.items[6] = { bindType = 8 }
        WoWMock.fire("GET_ITEM_INFO_RECEIVED", 6, true)
        assert.same({ 6 }, got)
        assert.is_false(B.IsWaiting(6))
        WoWMock.fire("GET_ITEM_INFO_RECEIVED", 6, true)
        assert.same({ 6 }, got)                                -- only once
        assert.is_true(B.WarboundState(6))
        assert.is_nil(B.WarboundState(99))
    end)

    it("rescans the bags when a bind type arrives later", function()
        WoWMock.bags[0] = { numSlots = 1,
            [1] = { itemID = 6, hyperlink = "|cffffffff|Hitem:6::::::::80:::::|h[W]|h|r", stackCount = 2 } }
        ns.Bus.On("ITEMS_DELTA", function() end, "spec")
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        WoWMock.advance(1)
        WoWMock.flush()
        assert.is_nil(ns.API.Bags.Snapshot().bound["i:6"])
        WoWMock.items[6] = { bindType = 7 }
        WoWMock.fire("GET_ITEM_INFO_RECEIVED", 6, true)
        WoWMock.flush()
        WoWMock.advance(1)
        WoWMock.flush()
        assert.equals(2, ns.API.Bags.Snapshot().bound["i:6"])
    end)
end)
