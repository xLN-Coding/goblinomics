local collect = require("spec.support.collect")

describe("Tracking: money", function()
    local ns, got

    before_each(function()
        ns = load_core({ boot = true, money = 50000 })
        WoWMock.warband = 100000
        WoWMock.loggedIn = true
        WoWMock.fire("PLAYER_LOGIN")
        got = collect(ns, { "MONEY_DELTA" })
    end)

    it("takes a baseline without emitting and then emits deltas with context", function()
        assert.equals(0, #got.MONEY_DELTA)
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
        WoWMock.set_money(62345)
        WoWMock.fire("PLAYER_MONEY")
        local p = got.MONEY_DELTA[1]
        assert.equals("player", p.scope)
        assert.equals(12345, p.amount)
        assert.equals(62345, p.total)
        assert.is_true(p.context.merchant)
        assert.is_false(p.restricted)
    end)

    it("re-reads a zero balance after login before accepting it", function()
        ns = load_core({ login = true })
        WoWMock.set_money(0)
        got = collect(ns, { "MONEY_DELTA" })
        WoWMock.set_money(70000)
        WoWMock.advance(1)
        WoWMock.set_money(80000)
        WoWMock.fire("PLAYER_MONEY")
        assert.equals(1, #got.MONEY_DELTA)
        assert.equals(10000, got.MONEY_DELTA[1].amount)
    end)

    it("tracks warband money", function()
        WoWMock.warband = 90000
        WoWMock.fire("ACCOUNT_MONEY")
        local p = got.MONEY_DELTA[1]
        assert.equals("warband", p.scope)
        assert.equals(-10000, p.amount)
    end)

    it("ignores warband money without the account inventory lock", function()
        WoWMock.warbandAccess = false
        WoWMock.warband = 1
        WoWMock.fire("ACCOUNT_MONEY")
        assert.equals(0, #got.MONEY_DELTA)
    end)

    it("skips secret readings and carries the delta with the next plain one", function()
        local secret = { "secret money" }
        WoWMock.set_secret(secret)
        WoWMock.money = secret
        WoWMock.fire("PLAYER_MONEY")
        assert.equals(0, #got.MONEY_DELTA)
        WoWMock.set_money(60000)
        WoWMock.fire("PLAYER_MONEY")
        assert.equals(10000, got.MONEY_DELTA[1].amount)
    end)

    it("stops tracking when the last subscriber leaves", function()
        ns.Bus.Off("MONEY_DELTA", "Spec")
        ns.Bus.OffAll("Core.LDB")
        assert.is_false(ns.Bus.IsServiceActive("money"))
        local registered = {}
        for _, r in ipairs(ns.Events.ListRegistered()) do registered[r.event] = true end
        assert.is_nil(registered.PLAYER_MONEY)
    end)

    it("ignores the 0 the client reports while leaving the world", function()
        WoWMock.fire("PLAYER_LEAVING_WORLD")
        WoWMock.set_money(0)
        WoWMock.fire("PLAYER_MONEY")
        assert.equals(0, #got.MONEY_DELTA)
        assert.equals(50000, ns.API.PlayerMoney())
        WoWMock.fire("PLAYER_ENTERING_WORLD")
        WoWMock.set_money(60000)
        WoWMock.fire("PLAYER_MONEY")
        assert.equals(10000, got.MONEY_DELTA[1].amount)
    end)
end)
