local fake = require("spec.support.sources")

describe("Core: speculative item marks", function()
    local ns, values

    before_each(function()
        ns = load_core({ login = true, money = 1 })
        values = { market = { ["i:1"] = 100000, ["i:2"] = 100000 }, saleRate = { ["i:1"] = 0.01, ["i:2"] = 0.5 } }
        ns.Price.RegisterSource(fake("tsm", 10, values))
    end)

    after_each(function() assert.same({}, WoWMock.errors) end)

    it("recognises speculative items from links, IDs and keys", function()
        assert.is_true(ns.ItemMarks.IsSpeculative("|cffffffff|Hitem:1::::::::80:::::|h[A]|h|r"))
        assert.is_true(ns.ItemMarks.IsSpeculative(1))
        assert.is_true(ns.ItemMarks.IsSpeculative("i:1"))
        assert.is_false(ns.ItemMarks.IsSpeculative("i:2"))
        assert.is_false(ns.ItemMarks.IsSpeculative(nil))
    end)

    it("returns an inline logo only for speculative items", function()
        assert.equals(" " .. ns.ItemMarks.INLINE, ns.ItemMarks.Inline("i:1"))
        assert.equals("", ns.ItemMarks.Inline("i:2"))
    end)

    it("shows the corner marker on an icon frame for speculative items", function()
        local row = CreateFrame("Button")
        row.icon = row:CreateTexture()
        ns.ItemMarks.Attach(row, row.icon)
        ns.ItemMarks.Update(row, "i:1")
        assert.is_true(row.goblinomicsSpecMark:IsShown())
        ns.ItemMarks.Update(row, "i:2")
        assert.is_false(row.goblinomicsSpecMark:IsShown())
    end)

    it("marks item buttons of bags unless the setting is off", function()
        local button = CreateFrame("ItemButton")
        button.icon = button:CreateTexture()
        ns.ItemMarks.OnQuality(button, 1, "|cffffffff|Hitem:1::::::::80:::::|h[A]|h|r")
        assert.is_true(button.goblinomicsSpecMark:IsShown())
        ns.ItemMarks.OnQuality(button, 1, nil)   -- empty slot
        assert.is_false(button.goblinomicsSpecMark:IsShown())
        GoblinomicsDB.settings.ui.markSpeculative = false
        ns.ItemMarks.OnQuality(button, 1, 1)
        assert.is_false(button.goblinomicsSpecMark:IsShown())
    end)

    it("re-evaluates after the price service invalidates", function()
        assert.is_true(ns.ItemMarks.IsSpeculative("i:1"))
        values.saleRate["i:1"] = 0.6
        ns.Price.Invalidate()
        assert.is_false(ns.ItemMarks.IsSpeculative("i:1"))
    end)
end)
