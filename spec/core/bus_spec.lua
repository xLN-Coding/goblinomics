describe("Core/Bus", function()
    local ns

    before_each(function()
        ns = load_core()
    end)

    it("delivers (event, payload) to subscribers and times them per owner", function()
        local got
        ns.Bus.On("SOMETHING", function(e, p) got = { e, p } end, "Tester")
        ns.Bus.Emit("SOMETHING", { x = 1 })
        assert.equals("SOMETHING", got[1])
        assert.equals(1, got[2].x)
        assert.equals(1, ns.Perf.Get("Tester", "bus:SOMETHING").count)
    end)

    it("requires an owner", function()
        assert.has_error(function() ns.Bus.On("X", function() end) end)
    end)

    it("starts a service with its dependencies on first use and stops it with the last", function()
        local log = {}
        ns.Bus.DefineService("base", { start = function() log[#log + 1] = "base+" end, stop = function() log[#log + 1] = "base-" end })
        ns.Bus.DefineService("svc", {
            deps = { "base" }, events = { "SVC_EVENT" },
            start = function() log[#log + 1] = "svc+" end, stop = function() log[#log + 1] = "svc-" end,
        })
        ns.Bus.On("SVC_EVENT", function() end, "A")
        ns.Bus.On("SVC_EVENT", function() end, "B")
        assert.same({ "base+", "svc+" }, log)
        ns.Bus.Off("SVC_EVENT", "A")
        assert.equals(2, #log)
        ns.Bus.OffAll("B")
        assert.same({ "base+", "svc+", "svc-", "base-" }, log)
        assert.equals(0, ns.Bus.CountSubscriptions())
    end)

    it("drops core events while the restricted mode is active", function()
        local got = 0
        ns.Bus.On("MONEY_DELTA", function() got = got + 1 end, "A")
        ns.Restriction = { IsActive = function() return true end }
        ns.Bus.Emit("MONEY_DELTA", {})
        assert.equals(0, got)
        ns.Bus.Emit("CUSTOM_MODULE_EVENT", {})
        assert.equals(1, ns.Bus.DroppedCount())
    end)
end)
