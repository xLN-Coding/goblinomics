describe("Core/Timer and Jobs", function()
    local ns

    before_each(function()
        ns = load_core()
    end)

    it("tracks active timers and cancels by owner", function()
        local ran = {}
        ns.Timer.After(1, function() ran[#ran + 1] = "a" end, "A")
        ns.Timer.After(1, function() ran[#ran + 1] = "b" end, "B")
        assert.equals(2, ns.Timer.ActiveCount())
        ns.Timer.CancelOwner("A")
        WoWMock.advance(1)
        assert.same({ "b" }, ran)
        assert.equals(0, ns.Timer.ActiveCount())
    end)

    it("debounces bursts", function()
        local n = 0
        for _ = 1, 5 do ns.Timer.Debounce("k", 0, function() n = n + 1 end) end
        WoWMock.flush()
        assert.equals(1, n)
    end)

    it("runs a job across frames within the budget", function()
        local steps = 0
        WoWMock.profileStep = 1 -- every debugprofilestop call advances 1 ms
        ns.Jobs.Run("T", "count", function()
            for _ = 1, 10 do
                steps = steps + 1
                ns.Jobs.Yield()
            end
        end)
        assert.equals(1, ns.Jobs.ActiveCount())
        WoWMock.advance(0)
        assert.is_true(steps < 10)
        WoWMock.flush()
        assert.equals(10, steps)
        assert.equals(0, ns.Jobs.ActiveCount())
        assert.equals(0, #WoWMock.timers)
    end)

    it("pauses in combat and resumes on PLAYER_REGEN_ENABLED", function()
        local done = false
        WoWMock.combat = true
        ns.Jobs.Run("T", "j", function() done = true end)
        WoWMock.flush()
        assert.is_false(done)
        WoWMock.combat = false
        WoWMock.fire("PLAYER_REGEN_ENABLED")
        WoWMock.flush()
        assert.is_true(done)
    end)

    it("reports job errors and continues with the next job", function()
        local second = false
        ns.Jobs.Run("T", "bad", function() error("job failed") end)
        ns.Jobs.Run("T", "good", function() second = true end)
        WoWMock.flush()
        assert.is_true(second)
        assert.equals(1, #WoWMock.errors)
    end)

    it("calls onDone and cancels by owner", function()
        local done = false
        ns.Jobs.Run("A", "x", function() end, function() done = true end)
        ns.Jobs.Run("B", "y", function() error("should not run") end)
        ns.Jobs.CancelOwner("B")
        WoWMock.flush()
        assert.is_true(done)
        assert.equals(0, #WoWMock.errors)
    end)
end)
