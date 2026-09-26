-- M1 acceptance criterion 1: a dummy module registers and receives deltas with context.
local LINCLOTH = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"

describe("M1 acceptance: dummy module", function()
    it("registers and receives money, loot and item deltas with context", function()
        local ns = load_core()
        local received = {}
        local m = ns.API.RegisterModule("Goblinomics_Dummy", { apiVersion = 1 })
        function m:OnEnable()
            self:On("MONEY_DELTA", function(e, p) received[#received + 1] = { e, p } end)
            self:On("LOOT_RECEIVED", function(e, p) received[#received + 1] = { e, p } end)
            self:On("ITEMS_DELTA", function(e, p) received[#received + 1] = { e, p } end)
        end
        WoWMock.set_money(1000)
        WoWMock.bags[0] = { numSlots = 2 }
        WoWMock.fire("ADDON_LOADED", "Goblinomics")
        WoWMock.fire("ADDON_LOADED", "Goblinomics_Dummy")
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        WoWMock.flush()

        WoWMock.loot = { { link = LINCLOTH, sources = { "Creature-0-1", 1 } } }
        WoWMock.fire("LOOT_READY")
        WoWMock.set_money(1500)
        WoWMock.fire("CHAT_MSG_MONEY", "You loot 5 Silver")
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. LINCLOTH .. ".")
        WoWMock.fire("LOOT_CLOSED")
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
        WoWMock.bags[0][1] = { itemID = 2589, hyperlink = LINCLOTH, stackCount = 1 }
        WoWMock.bags[0][2] = { itemID = 1000, hyperlink = "|Hitem:1000|h[Bought]|h", stackCount = 1 }
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()

        assert.equals("MONEY_DELTA", received[1][1])
        assert.equals(500, received[1][2].amount)
        assert.is_true(received[1][2].context.loot)
        assert.is_true(received[1][2].context.marks.lootMoney)
        assert.equals("LOOT_RECEIVED", received[2][1])
        assert.equals("creature", received[2][2].source.kind)
        assert.equals("ITEMS_DELTA", received[3][1])
        assert.same({ { itemKey = "i:1000", link = "|Hitem:1000|h[Bought]|h", delta = 1 } }, received[3][2].changes)
        assert.is_true(received[3][2].context.merchant)
    end)
end)
