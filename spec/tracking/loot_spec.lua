local collect = require("spec.support.collect")

local LINCLOTH = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"
local PEACEBLOOM = "|cffffffff|Hitem:2447::::::::80:::::|h[Peacebloom]|h|r"

describe("Tracking: loot", function()
    local ns, got

    before_each(function()
        ns = load_core({ login = true })
        got = collect(ns, { "LOOT_RECEIVED" })
    end)

    local function loot(msg, guid)
        WoWMock.fire("CHAT_MSG_LOOT", msg, "xLN", "", "", "", "", 0, 0, "", 0, 0, guid)
    end

    it("parses multiple before single patterns", function()
        assert.same({ LINCLOTH, 5 }, { ns.Loot.Parse("You receive loot: " .. LINCLOTH .. "x5.") })
        assert.same({ LINCLOTH, 1 }, { ns.Loot.Parse("You receive loot: " .. LINCLOTH .. ".") })
        local link, qty, kind = ns.Loot.Parse("You create: " .. LINCLOTH .. "x2.")
        assert.same({ LINCLOTH, 2, "craft" }, { link, qty, kind })
        assert.equals("bonus", select(3, ns.Loot.Parse("You receive bonus loot: " .. LINCLOTH .. ".")))
        assert.is_nil(ns.Loot.Parse("Gallywix receives loot: " .. LINCLOTH .. "."))
    end)

    it("emits LOOT_RECEIVED with the source from the loot window", function()
        WoWMock.loot = {
            { link = LINCLOTH, sources = { "Creature-0-1-2-3-4-0000", 5 } },
            { link = PEACEBLOOM, sources = { "GameObject-0-1-2-3-4-0000", 1 } },
        }
        WoWMock.fire("LOOT_READY")
        loot("You receive loot: " .. LINCLOTH .. "x5.", "Player-1-0000ABCD")
        loot("You receive loot: " .. PEACEBLOOM .. ".")
        assert.equals(2, #got.LOOT_RECEIVED)
        local p = got.LOOT_RECEIVED[1]
        assert.equals("i:2589", p.itemKey)
        assert.equals(5, p.quantity)
        assert.equals("creature", p.source.kind)
        assert.is_true(p.context.loot)
        assert.equals("object", got.LOOT_RECEIVED[2].source.kind)
    end)

    it("detects fishing and treats pushed items without a window as push", function()
        WoWMock.fishing = true
        WoWMock.loot = { { link = LINCLOTH, sources = { "GameObject-0", 1 } } }
        WoWMock.fire("LOOT_READY")
        loot("You receive loot: " .. LINCLOTH .. ".")
        assert.equals("fishing", got.LOOT_RECEIVED[1].source.kind)
        WoWMock.fire("LOOT_CLOSED")
        WoWMock.advance(10)
        loot("You receive item: " .. PEACEBLOOM .. ".")
        assert.equals("push", got.LOOT_RECEIVED[2].source.kind)
    end)

    it("uses unknown for secret source GUIDs", function()
        local guid = "Creature-secret"
        WoWMock.set_secret(guid)
        assert.equals("unknown", ns.Loot.GuidKind(guid))
    end)

    it("ignores other players' loot by GUID and drops secret messages", function()
        loot("You receive loot: " .. LINCLOTH .. ".", "Player-9-FFFF")
        local secret = "You receive loot: secret."
        WoWMock.set_secret(secret)
        loot(secret)
        assert.equals(0, #got.LOOT_RECEIVED)
        assert.equals(1, ns.Loot.SecretDropped())
    end)

    it("records claims that the bag diff consumes", function()
        loot("You receive loot: " .. LINCLOTH .. "x5.")
        assert.equals(3, ns.Loot.Consume("i:2589", 3))
        assert.equals(2, ns.Loot.Consume("i:2589", 10))
        assert.equals(0, ns.Loot.Consume("i:2589", 1))
    end)
end)
