-- M8: settings section "Import" (placeholder in the core, real section from the addon).
describe("Import: settings section", function()
    after_each(function()
        _G.TradeSkillMasterDB = nil
        assert.same({}, WoWMock.errors)
    end)

    it("registers a placeholder that loads the addon", function()
        WoWMock.reset()
        WoWMock.lod.Goblinomics_Import = true
        WoWMock.notLoaded.Goblinomics_Import = true
        local ns = {}
        for _, file in ipairs(toc_files("Goblinomics.toc")) do
            if not file:match("^Libs/") then load_addon_file(file, "Goblinomics", ns) end
        end
        local spec = ns.UI.GetSettings("import")
        assert.is_table(spec)
        spec.build(CreateFrame("Frame"), 0)
        assert.same({ "Goblinomics_Import" }, WoWMock.loadedAddOns)
    end)

    it("previews, imports all and lists the imports", function()
        local core, ins = load_import()
        _G.TradeSkillMasterDB = {
            ["r@Blackrock@internalData@csvExpense"] = "type,amount,otherPlayer,player,time\n"
                .. "Repair Bill,20484,Merchant,xLN," .. (WoWMock.now - 5000) .. "\n"
                .. "Postage,30,Friend,xLN," .. (WoWMock.now - 4000),
        }
        local spec = core.UI.GetSettings("import")
        local height = spec.build(CreateFrame("Frame"), 0)
        assert.is_true(height > 300)
        local UI = ins.ImportUI
        UI.Preview("tsm")
        assert.truthy(UI.section.status:GetText():find("2"))
        assert.equals("1", UI.section.preview[1].new:GetText())
        UI.RunAll()
        WoWMock.flush(10)
        assert.equals(1, #ins.Import.List())
        assert.is_true(UI.section.list[1].undo:IsShown())
        assert.truthy(UI.section.list[1].text:GetText():find("TSM", 1, true))
    end)

    it("opens the settings with /gob import", function()
        local core = load_import()
        local shown
        core.UI.Show = function(id) shown = id end
        core.EntryPoints.HandleSlash("import")
        assert.equals("settings", shown)
    end)
end)
