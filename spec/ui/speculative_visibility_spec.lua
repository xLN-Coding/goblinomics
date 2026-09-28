-- Speculative items need a sale rate, which only TSM provides: without such a source the
-- tab, the settings and the summary parts are hidden, and they appear when TSM registers.
local fake = require("spec.support.sources")

describe("UI: speculative items only with a sale rate source", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local function ids(list)
        local set = {}
        for _, spec in ipairs(list) do set[spec.id] = true end
        return set
    end

    local function shows(text)
        for _, frame in ipairs(WoWMock.frames) do
            if frame._text == text then return true end
        end
        return false
    end

    it("knows whether a role is provided", function()
        local ns = load_core({ login = true })
        assert.is_false(ns.API.Price:HasRole("saleRate"))
        ns.Price.RegisterSource(fake("auctionator", 20, { market = {} }))
        assert.is_true(ns.API.Price:HasRole("market"))
        assert.is_false(ns.API.Price:HasRole("saleRate"))
        ns.Price.RegisterSource(fake("tsm", 10, { market = {}, saleRate = {} }))
        assert.is_true(ns.API.Price:HasRole("saleRate"))
        ns.Price.UnregisterSource("tsm")
        assert.is_false(ns.API.Price:HasRole("saleRate"))
    end)

    it("shows the speculative tab only while a sale rate source is registered", function()
        local ns = load_vault()
        local refreshed = 0
        ns.UI.OnModuleTabs = function() refreshed = refreshed + 1 end
        assert.is_nil(ids(ns.UI.SortedTabs()).speculative)
        ns.Price.RegisterSource(fake("auctionator", 20, { market = {} }))
        assert.equals(0, refreshed)                                   -- nothing changed for the UI
        ns.Price.RegisterSource(fake("tsm", 10, { market = {}, saleRate = {} }))
        assert.equals(1, refreshed)
        assert.is_true(ids(ns.UI.SortedTabs()).speculative)
        ns.Price.UnregisterSource("tsm")
        assert.equals(2, refreshed)
        assert.is_nil(ids(ns.UI.SortedTabs()).speculative)
    end)

    it("leaves the speculative threshold out of the price settings without TSM and rebuilds them", function()
        local ns = load_vault()
        ns.UI.GetTab("settings").build(CreateFrame("Frame"))
        ns.UI.SelectSettings("pricing")
        assert.is_false(shows("Speculative below sale rate"))
        ns.Price.RegisterSource(fake("tsm", 10, { market = {}, saleRate = {} }, {
            KnownSources = function() return {} end, ValidateSource = function() return true end }))
        assert.is_true(shows("Speculative below sale rate"))
    end)

    it("hides an entry whose visible() fails", function()
        local ns = load_core({ login = true })
        ns.UI.RegisterTab({ id = "broken", title = "Broken", build = function() end,
            visible = function() error("boom") end })
        assert.is_nil(ids(ns.UI.SortedTabs()).broken)
        for i = #WoWMock.errors, 1, -1 do WoWMock.errors[i] = nil end
    end)
end)
