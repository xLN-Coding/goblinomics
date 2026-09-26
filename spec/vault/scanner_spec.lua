local LINEN = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"
local SWORD = "|cffa335ee|Hitem:500::::::::80:::::|h[Sword]|h|r"
local HERB = "|cffffffff|Hitem:2447::::::::80:::::|h[Peacebloom]|h|r"

describe("Vault: scanner", function()
    local char, root

    before_each(function()
        load_vault({
            money = 123456,
            before = function()
                WoWMock.bags[0] = { numSlots = 2, [1] = { itemID = 2589, hyperlink = LINEN, stackCount = 20 } }
                WoWMock.equipment[16] = SWORD
                WoWMock.warband = 5000000
            end,
        })
        WoWMock.flush()
        WoWMock.advance(1)
        WoWMock.flush()
        char = GoblinomicsVaultDB.chars["xLN-Blackrock"]
        root = GoblinomicsVaultDB
    end)

    it("records gold, bags and equipment at login", function()
        assert.equals(123456, char.gold)
        assert.same({ ["i:2589"] = 20 }, char.locations.bags.items)
        assert.is_number(char.locations.bags.seenAt)
        assert.same({ ["i:500"] = 1 }, char.locations.equipment.items)
        assert.same({ ["i:500"] = 1 }, char.locations.equipment.bound)
        assert.equals(5000000, root.warband.gold)
    end)

    it("updates bags after ITEMS_DELTA, debounced", function()
        WoWMock.bags[0][2] = { itemID = 2447, hyperlink = HERB, stackCount = 3 }
        WoWMock.fire("BAG_UPDATE", 0)
        WoWMock.flush()
        assert.is_nil(char.locations.bags.items["i:2447"])
        WoWMock.advance(2)
        assert.equals(3, char.locations.bags.items["i:2447"])
    end)

    it("scans bank and warband only while the bank is open", function()
        WoWMock.bags[6] = { numSlots = 2, [1] = { itemID = 2447, hyperlink = HERB, stackCount = 50 } }
        WoWMock.bags[13] = { numSlots = 1, [1] = { itemID = 500, hyperlink = SWORD, stackCount = 1, isBound = true } }
        WoWMock.fire("BAG_UPDATE", 6)
        WoWMock.flush()
        assert.is_nil(char.locations.bank)
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Banker)
        WoWMock.flush()
        assert.same({ ["i:2447"] = 50 }, char.locations.bank.items)
        assert.same({ ["i:500"] = 1 }, root.warband.bound)
        assert.equals("xLN-Blackrock", root.warband.seenBy)
        WoWMock.bags[6][1].stackCount = 40
        WoWMock.fire("BAG_UPDATE", 6)
        WoWMock.advance(0.5)
        WoWMock.flush()
        assert.equals(40, char.locations.bank.items["i:2447"])
    end)

    it("keeps the warband snapshot without the account inventory lock", function()
        WoWMock.warbandAccess = false
        WoWMock.bags[13] = { numSlots = 1, [1] = { itemID = 2447, hyperlink = HERB, stackCount = 9 } }
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Banker)
        WoWMock.flush()
        assert.is_nil(root.warband.items)
    end)

    it("records mail attachments and gold, excluding COD mails", function()
        WoWMock.mail = {
            { money = 10000, items = { { HERB, 5 } } },
            { money = 0, cod = 500, items = { { LINEN, 99 } } },
        }
        WoWMock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
        WoWMock.advance(0.5)
        assert.same({ ["i:2447"] = 5 }, char.locations.mail.items)
        assert.equals(10000, char.locations.mail.money)
    end)

    it("records active auctions and ignores sold ones and WoW tokens", function()
        WoWMock.auctions = {
            { itemLink = HERB, itemID = 2447, quantity = 20, status = 0 },
            { itemLink = LINEN, itemID = 2589, quantity = 5, status = 1 },
            { itemID = 122284, quantity = 1, status = 0 },
        }
        WoWMock.fire("AUCTION_HOUSE_SHOW")
        assert.equals(1, C_AuctionHouse.queried)
        WoWMock.fire("OWNED_AUCTIONS_UPDATED")
        WoWMock.advance(0.5)
        assert.same({ ["i:2447"] = 20 }, char.locations.auctions.items)
    end)

    it("updates gold from MONEY_DELTA", function()
        WoWMock.set_money(200000)
        WoWMock.fire("PLAYER_MONEY")
        assert.equals(200000, char.gold)
    end)

    it("keeps the character's gold at logout although GetMoney() reads 0 then", function()
        WoWMock.fire("PLAYER_LEAVING_WORLD")
        WoWMock.set_money(0)
        WoWMock.fire("PLAYER_MONEY")
        WoWMock.fire("PLAYER_LOGOUT")
        assert.equals(123456, GoblinomicsVaultDB.chars["xLN-Blackrock"].gold)
    end)

    it("waits for the money baseline when GetMoney() reads 0 after login", function()
        load_vault({ money = 0 })
        WoWMock.flush()
        local c = GoblinomicsVaultDB.chars["xLN-Blackrock"]
        assert.is_nil(c.gold)
        WoWMock.set_money(777000)
        WoWMock.advance(1)
        WoWMock.advance(1)
        assert.equals(777000, c.gold)
    end)
end)
