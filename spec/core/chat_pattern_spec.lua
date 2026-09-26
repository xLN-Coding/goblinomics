describe("Core/Util/ChatPattern", function()
    local ChatPattern
    local LINK = "|cffffffff|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"

    before_each(function()
        WoWMock.reset()
        local ns = {}
        load_addon_file("Core/Util/ChatPattern.lua", "Goblinomics", ns)
        ChatPattern = ns.ChatPattern
        ChatPattern.ClearCache()
    end)

    it("builds an anchored pattern for a single %s", function()
        local pattern, order, positional = ChatPattern.Build(LOOT_ITEM_SELF)
        assert.equals("^You receive loot: (.-)%.$", pattern)
        assert.same({ 1 }, order)
        assert.is_false(positional)
    end)

    it("matches LOOT_ITEM_SELF and captures the link", function()
        assert.equals(LINK, ChatPattern.Match(LOOT_ITEM_SELF, "You receive loot: " .. LINK .. "."))
    end)

    it("matches LOOT_ITEM_SELF_MULTIPLE with link and count", function()
        local link, count = ChatPattern.Match(LOOT_ITEM_SELF_MULTIPLE, "You receive loot: " .. LINK .. "x5.")
        assert.equals(LINK, link)
        assert.equals("5", count)
    end)

    it("does not confuse an x inside the item name with the count separator", function()
        local waxy = "|cffffffff|Hitem:1::::::::80:::::|h[Box of Wax]|h|r"
        local link, count = ChatPattern.Match(LOOT_ITEM_SELF_MULTIPLE, "You receive loot: " .. waxy .. "x12.")
        assert.equals(waxy, link)
        assert.equals("12", count)
    end)

    it("does not match a different message", function()
        assert.is_nil(ChatPattern.Match(LOOT_ITEM_SELF, "Other player receives loot: " .. LINK .. "."))
        assert.is_nil(ChatPattern.Match(LOOT_ITEM_SELF_MULTIPLE, "You receive loot: " .. LINK .. "."))
    end)

    it("supports the pushed-item variants", function()
        assert.equals(LINK, ChatPattern.Match(LOOT_ITEM_PUSHED_SELF, "You receive item: " .. LINK .. "."))
        local link, count = ChatPattern.Match(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "You receive item: " .. LINK .. "x3.")
        assert.equals(LINK, link)
        assert.equals("3", count)
    end)

    it("returns captures in argument order for positional specifiers", function()
        local fmt = "%2$s receives loot: %1$s."
        local pattern, order, positional = ChatPattern.Build(fmt)
        assert.equals("^(.-) receives loot: (.-)%.$", pattern)
        assert.same({ 2, 1 }, order)
        assert.is_true(positional)
        local item, player = ChatPattern.Match(fmt, "Gallywix receives loot: " .. LINK .. ".")
        assert.equals(LINK, item)
        assert.equals("Gallywix", player)
    end)

    it("escapes Lua magic characters in the surrounding text", function()
        local pattern = ChatPattern.Build("(%s) [%d] costs %d+ gold? yes*")
        assert.equals("^%((.-)%) %[(%d+)%] costs (%d+)%+ gold%? yes%*$", pattern)
        local a, b, c = ChatPattern.Match("(%s) [%d] costs %d+ gold? yes*", "(x) [7] costs 3+ gold? yes*")
        assert.equals("x", a)
        assert.equals("7", b)
        assert.equals("3", c)
    end)

    it("keeps literal percent signs", function()
        local pattern = ChatPattern.Build("%d%% of %s")
        assert.equals("^(%d+)%% of (.-)$", pattern)
        local pct, what = ChatPattern.Match("%d%% of %s", "50% of everything")
        assert.equals("50", pct)
        assert.equals("everything", what)
    end)

    it("unwraps |3-N(%s) declension tokens used by some locales", function()
        local fmt = "Ihr erhaltet Beute: |3-1(%s)."
        assert.equals("^Ihr erhaltet Beute: (.-)%.$", ChatPattern.Build(fmt))
        assert.equals(LINK, ChatPattern.Match(fmt, "Ihr erhaltet Beute: " .. LINK .. "."))
    end)

    it("matches |4singular:plural; tokens loosely", function()
        local fmt = "%d |4Gegenstand:Gegenstaende; erhalten"
        assert.equals("2", ChatPattern.Match(fmt, "2 Gegenstaende erhalten"))
        assert.equals("1", ChatPattern.Match(fmt, "1 Gegenstand erhalten"))
    end)

    it("caches built patterns", function()
        local p1 = ChatPattern.Build(LOOT_ITEM_SELF)
        local p2 = ChatPattern.Build(LOOT_ITEM_SELF)
        assert.equals(p1, p2)
    end)

    it("returns nil for non-string input", function()
        assert.is_nil(ChatPattern.Build(nil))
        assert.is_nil(ChatPattern.Match(LOOT_ITEM_SELF, nil))
        assert.is_nil(ChatPattern.Match(nil, "text"))
    end)
end)
