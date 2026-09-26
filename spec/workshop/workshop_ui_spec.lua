local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop UI", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, wns

    before_each(function()
        ns, wns = load_workshop({ before = function()
            WoWMock.recipes[100] = { name = "Potion", profession = "Alchemy", qualityItemIDs = { 501, 502 },
                schematic = { reagentSlotSchematics = {
                    { reagentType = 1, dataSlotIndex = 1, quantityRequired = 3, reagents = { { itemID = 11 } } } } } }
            WoWMock.recipes[110] = { name = "Flask", profession = "Alchemy", qualityItemIDs = { 511, 512 },
                schematic = { reagentSlotSchematics = {} } }
            WoWMock.recipes[300] = { name = "Milling", profession = "Inscription", isSalvage = true,
                schematic = { quantityMax = 5, reagentSlotSchematics = {} } }
        end })
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:11"] = 100, ["i:501"] = 500, ["i:502"] = 900,
            ["i:512"] = 3000, ["i:511"] = 1000 } }))
    end)

    local function build()
        local tab = ns.UI.GetTab("workshop")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        return tab
    end

    it("registers the tab, the settings section and the dashboard tile", function()
        assert.is_table(ns.UI.GetTab("workshop"))
        local sections, widgets = {}, {}
        for _, s in ipairs(ns.UI.SortedSettings()) do sections[#sections + 1] = s.id end
        for _, w in ipairs(ns.UI.SortedWidgets()) do widgets[w.id] = true end
        assert.same({ "core", "pricing", "workshop" }, sections)
        assert.is_true(widgets["workshop.crafting"])
        assert.is_true(ns.UI.SortedSettings()[3].build(CreateFrame("Frame"), 0) > 60)
    end)

    it("lists summary, orders, salvage and the recipes by profit; qualities expand", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2 }) }, { S.result({ id = 501, quality = 1 }) } })
        S.craft(110, {}, { { S.result({ id = 512, quality = 2 }) } })
        wns.Lots.Sell("i:512", 1, 5000)
        S.craft(300, {}, { { S.result({ id = 950 }) } }, { call = function()
            C_TradeSkillUI.CraftSalvage(300, 1, { itemID = 900 }, {})
        end })
        local UI = wns.WorkshopUI
        local kinds = {}
        for _, r in ipairs(UI.ListRows()) do kinds[#kinds + 1] = r.kind end
        assert.same({ "summary", "orders", "salvage", "header", "recipe", "recipe" }, kinds)
        local rows = UI.ListRows()
        assert.equals(110, rows[5].recipe)          -- Flask sold: highest profit first
        assert.is_true(rows[6].expandable)
        UI.state.expanded[100] = true
        assert.equals(8, #UI.ListRows())
    end)

    it("switches the right side with the selection and builds every page", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2, conc = 20 }) }, { S.result({ id = 501, quality = 1 }) } })
        wns.Lots.Sell("i:502", 1, 2000)
        build()
        local UI = wns.WorkshopUI
        assert.equals("summary", UI.state.selected.kind)
        assert.is_true(UI.CurrentPage().frame:IsShown())
        UI.Select({ kind = "recipe", recipe = 100 })
        local page = UI.CurrentPage()
        assert.equals(2, page.detail.crafts)
        assert.equals(3, #page.detail.history)
        UI.Select({ kind = "quality", recipe = 100, quality = 2 })
        assert.equals(page, UI.CurrentPage())
        assert.equals(1, page.detail.crafts)
        UI.Select({ kind = "orders" })
        UI.Select({ kind = "salvage" })
        UI.state.profession = "Tailoring"
        UI.Select({ kind = "recipe", recipe = 100 })
        assert.equals("summary", UI.state.selected.kind)   -- the recipe is not in the filter
    end)
end)
