describe("Vault: freshness", function()
    local F
    before_each(function() F = select(2, load_vault()).Freshness end)

    it("classifies by age with the default thresholds", function()
        local now = 1000000
        assert.equals("fresh", F.State(now - 5 * 3600, now))
        assert.equals("aging", F.State(now - 6 * 3600, now))
        assert.equals("aging", F.State(now - 2 * 86400, now))
        assert.equals("stale", F.State(now - 3 * 86400, now))
        assert.equals("never", F.State(nil, now))
    end)

    it("follows custom thresholds", function()
        assert.equals("stale", F.State(0, 3 * 3600, { freshHours = 1, agingDays = 0.1 }))
    end)

    it("labels never-seen locations as not recorded", function()
        assert.equals("not recorded", F.Label("never"))
    end)
end)
