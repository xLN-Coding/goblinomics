-- Routines travel as strings; presets arrive as suggestions.
describe("Routines: sharing and presets", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local rns, T

    before_each(function()
        local _
        _, rns = load_routines()
        T = rns.Tasks
    end)

    it("adds the presets as suggestions once", function()
        local task = T.Get("delve:vault")
        assert.equals("preset", task.source)
        assert.is_nil(task.pinned)
        assert.equals(15, select(2, T.Estimate(task)))
        assert.equals(0, rns.Presets.Apply(GoblinomicsRoutinesDB))
    end)

    it("exports pinned tasks and imports them as suggestions on another account", function()
        local q = T.Learn({ id = "q:500", kind = "quest", ref = 500, name = "Ore", frequency = "weekly" })
        q.pinned, q.value, q.duration, q.note = true, 30000, 8, "Take the flight path"
        T.Learn({ id = "q:501", kind = "quest", ref = 501, name = "Not shared" })
        local text = rns.Share.Export()
        assert.is_truthy(text:find("^!GOB:ROUTINE:1!"))
        GoblinomicsRoutinesDB.tasks = {}
        local added, known = rns.Share.Import(text)
        assert.same({ 1, 0 }, { added, known })
        local t = T.Get("q:500")
        assert.equals("imported", t.source)
        assert.is_nil(t.pinned)
        assert.equals("Take the flight path", t.note)
        local value, minutes = T.Estimate(t)
        assert.same({ 30000, 8 }, { value, minutes })
        t.pinned = true
        added, known = rns.Share.Import(text)
        assert.same({ 0, 1 }, { added, known })
        assert.is_true(T.Get("q:500").pinned)                          -- the user's choice stays
    end)

    it("rejects broken strings and invalid fields", function()
        assert.same({ nil, "format" }, { rns.Share.Import("hello") })
        assert.same({ nil, "version" }, { rns.Share.Import("!GOB:ROUTINE:9!abc") })
        assert.same({ nil, "format" }, { rns.Share.Import("!GOB:ROUTINE:1!@@@") })
        assert.is_nil(rns.Share.Clean({ id = "bad id!", kind = "quest" }))
        assert.is_nil(rns.Share.Clean({ id = "q:1", kind = "hack" }))
        local t = rns.Share.Clean({ id = "q:1", kind = "quest", ref = 1, value = -5, duration = 9999,
            name = string.rep("x", 500) })
        assert.same({ nil, nil, nil, 1 }, { t.value, t.duration, t.name, t.ref })
    end)
end)
