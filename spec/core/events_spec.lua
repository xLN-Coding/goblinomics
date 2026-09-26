describe("Core/Events", function()
    local ns, d

    before_each(function()
        ns = load_core()
        d = ns.Events.NewDispatcher("Test")
    end)

    it("registers the frame on the first handler and unregisters after the last", function()
        local f1, f2 = function() end, function() end
        d:Register("BAG_UPDATE", f1)
        d:Register("BAG_UPDATE", f2)
        assert.is_true(d.frame:IsEventRegistered("BAG_UPDATE"))
        d:Unregister("BAG_UPDATE", f1)
        assert.is_true(d.frame:IsEventRegistered("BAG_UPDATE"))
        d:Unregister("BAG_UPDATE", f2)
        assert.is_false(d.frame:IsEventRegistered("BAG_UPDATE"))
    end)

    it("passes event and arguments to handlers in registration order", function()
        local calls = {}
        d:Register("BAG_UPDATE", function(e, bag) calls[#calls + 1] = "a" .. e .. bag end)
        d:Register("BAG_UPDATE", function(e, bag) calls[#calls + 1] = "b" .. e .. bag end)
        WoWMock.fire("BAG_UPDATE", 3)
        assert.same({ "aBAG_UPDATE3", "bBAG_UPDATE3" }, calls)
    end)

    it("allows removing handlers during dispatch", function()
        local calls = 0
        local second
        local first = function() calls = calls + 1; d:Unregister("X", second) end
        second = function() calls = calls + 10 end
        d:Register("X", first)
        d:Register("X", second)
        WoWMock.fire("X")
        assert.equals(1, calls)
        WoWMock.fire("X")
        assert.equals(2, calls)
    end)

    it("isolates errors and counts them in perf", function()
        local ran = false
        d:Register("X", function() error("boom") end)
        d:Register("X", function() ran = true end)
        WoWMock.fire("X")
        assert.is_true(ran)
        assert.equals(1, #WoWMock.errors)
        local stat = ns.Perf.Get("Test", "X")
        assert.equals(2, stat.count)
        assert.equals(1, stat.errors)
    end)

    it("unregisters everything", function()
        d:Register("A", function() end)
        d:Register("B", function() end)
        d:UnregisterAll()
        assert.is_false(d:IsRegistered("A"))
        assert.is_false(d:IsRegistered("B"))
    end)
end)
