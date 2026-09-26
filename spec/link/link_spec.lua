-- M8 acceptance: two accounts give one networth.
describe("Link: several accounts", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local function account(money)
        local core, lns, vns = load_link({ money = money })
        WoWMock.advance(5)
        WoWMock.flush()
        return core, lns, vns
    end

    it("round-trips the string and rejects foreign text", function()
        local _, lns = account(500000)
        local text = lns.Link.Export()
        assert.equals("GOB1:", text:sub(1, 5))
        local snap = lns.Link.Decode(text)
        assert.equals(500000, snap.chars["xLN-Blackrock"].gold)
        assert.is_nil(lns.Link.Decode("hello"))
        assert.same({ false, "format" }, { lns.Link.Import("GOB1:!!!") })
        assert.same({ false, "own" }, { lns.Link.Import(text) })
    end)

    it("adds the other account to the wealth and its history, the newest state wins", function()
        local _, a = account(500000)
        GoblinomicsVaultDB.history["2026-09-01"] = { wealth = 400000 }
        local fromA = a.Link.Export()
        WoWMock.reset()
        local _, b, vb = account(2000000)
        local own = vb.Networth.Get().wealth
        GoblinomicsVaultDB.history["2026-09-01"] = { wealth = 1000000 }
        assert.is_true(b.Link.Import(fromA))
        WoWMock.advance(5)
        WoWMock.flush()
        local r = vb.Networth.Get()
        assert.equals(own + 500000, r.wealth)
        assert.equals(500000, r.remote.wealth)
        assert.equals(1400000, GoblinomicsVaultDB.history["2026-09-01"].wealth)
        -- B's export passes on only its own wealth
        local snapB = b.Link.Decode(b.Link.Export())
        assert.equals(1000000, snapB.history["2026-09-01"])
        -- an older string does not replace the newer one; removing takes the account out again
        local older = b.Link.Decode(fromA)
        older.seenAt = older.seenAt - 100
        assert.same({ false, "older" }, { b.Link.Import(b.Link.Encode(older)) })
        local id = older.account
        assert.equals(1, #b.API.Vault:Remotes())
        b.API.Vault:RemoveRemote(id)
        assert.equals(1000000, GoblinomicsVaultDB.history["2026-09-01"].wealth)
        assert.equals(0, #b.API.Vault:Remotes())
    end)

    it("builds the settings section and imports from it", function()
        local core, lns = account(100)
        local height = core.UI.GetSettings("link").build(CreateFrame("Frame"), 0)
        assert.is_true(height > 100)
        assert.is_false(lns.LinkUI.Import("nonsense"))
        assert.truthy(lns.LinkUI.section.status:GetText():find("link string", 1, true))
    end)
end)
