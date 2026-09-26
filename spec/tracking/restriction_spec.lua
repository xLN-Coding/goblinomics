local collect = require("spec.support.collect")

local LINCLOTH = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"

describe("Tracking: restricted mode", function()
    local ns, got
    local T = Enum.AddOnRestrictionType

    local function restrict(name, on)
        WoWMock.restricted[T[name]] = on or nil
        WoWMock.fire("ADDON_RESTRICTION_STATE_CHANGED", T[name], on and 2 or 0)
    end

    before_each(function()
        ns = load_core({ login = true, money = 10000 })
        WoWMock.bags[0] = { numSlots = 2, [1] = { itemID = 2589, hyperlink = LINCLOTH, stackCount = 1 } }
        got = collect(ns, { "MONEY_DELTA", "LOOT_RECEIVED", "ITEMS_DELTA", "RESTRICTED_ENTER", "RESTRICTED_LEAVE" })
        WoWMock.flush()
    end)

    it("enters on activation of ChallengeMode and emits nothing else while active", function()
        restrict("ChallengeMode", true)
        assert.is_true(ns.Restriction.IsActive())
        assert.equals("challenge", got.RESTRICTED_ENTER[1].kind)
        WoWMock.set_money(15000)
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. LINCLOTH .. "x2.")
        WoWMock.bags[0][1].stackCount = 3
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        assert.equals(0, #got.MONEY_DELTA)
        assert.equals(0, #got.LOOT_RECEIVED)
        assert.equals(0, #got.ITEMS_DELTA)
    end)

    it("leaves only after Combat lifted and replays the buffer in order", function()
        restrict("ChallengeMode", true)
        restrict("Combat", true)
        WoWMock.set_money(15000)
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. LINCLOTH .. "x2.")
        WoWMock.bags[0][1].stackCount = 3
        WoWMock.fire("BAG_UPDATE", 0)
        restrict("ChallengeMode", false)
        assert.is_true(ns.Restriction.IsActive())
        restrict("Combat", false)
        assert.is_false(ns.Restriction.IsActive())
        WoWMock.flush()
        assert.equals(5000, got.MONEY_DELTA[1].amount)
        assert.equals("challenge", got.MONEY_DELTA[1].restricted)
        assert.equals(2, got.LOOT_RECEIVED[1].quantity)
        assert.equals(0, #got.ITEMS_DELTA) -- the two looted items were claimed
        local leave = got.RESTRICTED_LEAVE[1]
        assert.equals("challenge", leave.kind)
        assert.equals(2, leave.buffered)
        assert.equals(0, leave.secret)
    end)

    it("counts secret payloads and reconciles money and bags afterwards", function()
        restrict("Encounter", true)
        local secretMoney, secretMsg = { "m" }, "secret loot"
        WoWMock.set_secret(secretMoney)
        WoWMock.set_secret(secretMsg)
        WoWMock.money = secretMoney
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("CHAT_MSG_LOOT", secretMsg)
        WoWMock.bags[0][1].stackCount = 4
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.set_money(12000)
        restrict("Encounter", false)
        WoWMock.flush()
        assert.equals(2, got.RESTRICTED_LEAVE[1].secret)
        assert.equals(2000, got.MONEY_DELTA[1].amount)
        assert.is_true(got.MONEY_DELTA[1].reconciled)
        assert.equals(3, got.ITEMS_DELTA[1].changes[1].delta)
        assert.equals("encounter", got.ITEMS_DELTA[1].restricted)
    end)

    it("enters immediately on the ENCOUNTER_START hint and leaves on ENCOUNTER_END", function()
        WoWMock.fire("ENCOUNTER_START", 1, "Boss", 16, 20)
        assert.is_true(ns.Restriction.IsActive())
        assert.equals("encounter", got.RESTRICTED_ENTER[1].kind)
        WoWMock.fire("ENCOUNTER_END", 1, "Boss", 16, 20, 1)
        WoWMock.flush()
        assert.is_false(ns.Restriction.IsActive())
        assert.equals(1, #got.RESTRICTED_LEAVE)
    end)

    it("ignores the Map restriction and Combat alone", function()
        restrict("Map", true)
        restrict("Combat", true)
        assert.is_false(ns.Restriction.IsActive())
    end)

    it("falls back to summed reconciliation on buffer overflow", function()
        restrict("ChallengeMode", true)
        for i = 1, 600 do
            WoWMock.set_money(10000 + i)
            WoWMock.fire("PLAYER_MONEY")
        end
        restrict("ChallengeMode", false)
        WoWMock.flush()
        local leave = got.RESTRICTED_LEAVE[1]
        assert.is_true(leave.overflow)
        local sum = 0
        for _, p in ipairs(got.MONEY_DELTA) do sum = sum + p.amount end
        assert.equals(600, sum)
    end)

    it("drops ordinary chat output while restricted", function()
        restrict("ChallengeMode", true)
        ns.Print("hello")
        assert.equals(0, #WoWMock.chat)
        ns.Print("forced", true)
        assert.equals(1, #WoWMock.chat)
    end)
end)
