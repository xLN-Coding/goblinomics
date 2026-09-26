-- Every settings section builds on the form kit without errors and reports its height.
describe("UI: settings sections", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local function builds(ns, id)
        local spec = ns.UI.GetSettings(id)
        assert.is_table(spec, id)
        local height = spec.build(CreateFrame("Frame"), 0)
        assert.is_true(type(height) == "number" and height > 60, id)
    end

    it("builds General and Prices", function()
        local ns = load_core({ login = true })
        builds(ns, "core")
        builds(ns, "pricing")
    end)

    it("builds Vault", function() builds((load_vault()), "vault") end)

    it("builds Ledger, Workshop and Import", function()
        local ns = load_import()
        builds(ns, "ledger")
        builds(ns, "workshop")
        builds(ns, "import")
    end)

    it("builds Gatherer", function() builds((load_gatherer()), "gatherer") end)

    it("builds Account link", function() builds((load_link()), "link") end)
end)
