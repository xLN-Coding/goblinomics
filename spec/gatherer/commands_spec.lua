describe("Gatherer: /gob farm", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, pns, printed

    before_each(function()
        ns, pns = load_gatherer()
        printed = {}
        ns.Print = function(msg) printed[#printed + 1] = msg end
        pns.HUD.Refresh = function() end
        pns.Summary.Show = function(summary) printed[#printed + 1] = summary end
    end)

    local function run(arg)
        SlashCmdList.GOBLINOMICS("farm " .. arg)
        WoWMock.flush()
    end

    it("starts a session for a named farm, pauses, resumes and stops it", function()
        local farm = pns.Farms.Create({ name = "Herbs" })
        run("start herbs")
        assert.equals(farm.id, pns.Session.Active().farmId)
        run("pause")
        assert.is_false(pns.Session.IsRunning())
        run("pause")
        assert.is_true(pns.Session.IsRunning())
        run("stop")
        assert.is_nil(pns.Session.Active())
        assert.equals(farm.id, printed[#printed].farmId)
    end)

    it("starts an ad-hoc session without a name and rejects unknown farms", function()
        run("start Nope")
        assert.is_nil(pns.Session.Active())
        assert.equals("No farm named Nope.", printed[1])
        run("start")
        assert.is_nil(pns.Session.Active().farmId)
        run("start")
        assert.equals("A session is already active.", printed[#printed])
    end)
end)
