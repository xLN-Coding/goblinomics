describe("Ledger: trade popup", function()
    local ns, lns, opened

    before_each(function()
        ns, lns = load_ledger()
        opened = {}
        lns.TradePopup.Open = function(item) opened[#opened + 1] = item end
        lns.TradePopup.IsOpen = function() return false end
    end)

    local function trade(amount)
        WoWMock.fire("TRADE_SHOW")
        WoWMock.trade.moneyIn = amount
        WoWMock.fire("TRADE_MONEY_CHANGED")
        WoWMock.set_money(WoWMock.money + amount)
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
        WoWMock.fire("TRADE_CLOSED")
    end

    it("opens after a trade with gold and applies category, tag and memory", function()
        trade(20000)
        assert.equals(1, #opened)
        assert.equals("Trader", opened[1].partner)
        lns.TradePopup.Apply(opened[1], "Mail", " Boosting ", true)
        local row = lns.Store.Query({})[1]
        assert.same({ "Mail", "Boosting" }, { row.category, row.tag })
        assert.same({ "Mail", "Boosting", true }, { lns.TradePopup.Defaults("Trader") })
        lns.TradePopup.Apply(opened[1], "Other", "", false)
        assert.same({ "Other", nil, false }, { lns.TradePopup.Defaults("Trader") })
    end)

    it("waits while in combat", function()
        WoWMock.combat = true
        trade(500)
        assert.equals(0, #opened)
        assert.equals(1, lns.TradePopup.Queued())
        WoWMock.combat = false
        WoWMock.fire("PLAYER_REGEN_ENABLED")
        assert.equals(1, #opened)
    end)

    it("does not open for trades without gold", function()
        WoWMock.fire("TRADE_SHOW")
        WoWMock.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
        assert.equals(0, #opened)
        local _ = ns
    end)
end)
