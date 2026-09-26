describe("Core: sounds", function()
    local ns

    before_each(function()
        ns = load_core({ login = true, money = 1 })
    end)

    after_each(function() assert.same({}, WoWMock.errors) end)

    it("offers none, the available Blizzard kits and every SharedMedia sound", function()
        LibStub("LibSharedMedia-3.0"):Register("sound", "Goblin Cheer", "Interface\\AddOns\\Pack\\cheer.ogg")
        local values = {}
        for _, c in ipairs(ns.Sounds.Choices()) do values[c.value] = c.label end
        assert.equals("None", values.none)
        assert.equals("Epic loot toast", values["kit:UI_EPICLOOT_TOAST"])
        assert.equals("Raid warning", values["kit:RAID_WARNING"])
        assert.is_nil(values["kit:READY_CHECK"])          -- kit missing in this client
        assert.equals("Goblin Cheer", values["lsm:Goblin Cheer"])
        assert.is_nil(values["lsm:None"])
    end)

    it("plays kits and SharedMedia files on the chosen channel", function()
        LibStub("LibSharedMedia-3.0"):Register("sound", "Goblin Cheer", "Interface\\AddOns\\Pack\\cheer.ogg")
        assert.is_true(ns.Sounds.Play("kit:UI_EPICLOOT_TOAST"))
        GoblinomicsDB.settings.sound.channel = "SFX"
        assert.is_true(ns.Sounds.Play("lsm:Goblin Cheer"))
        assert.is_false(ns.Sounds.Play("none"))
        assert.is_false(ns.Sounds.Play("kit:DOES_NOT_EXIST"))
        assert.same({ { 31578, "Master" }, { "Interface\\AddOns\\Pack\\cheer.ogg", "SFX" } }, WoWMock.sounds)
    end)

    it("maps old boolean settings and labels values", function()
        assert.equals("kit:X", ns.Sounds.Resolve(true, "kit:X"))
        assert.equals("kit:X", ns.Sounds.Resolve(nil, "kit:X"))
        assert.equals("none", ns.Sounds.Resolve(false, "kit:X"))
        assert.equals("lsm:A", ns.Sounds.Resolve("lsm:A", "kit:X"))
        assert.equals("Legendary loot toast", ns.Sounds.Label("kit:UI_LEGENDARY_LOOT_TOAST"))
        assert.equals("A", ns.Sounds.Label("lsm:A"))
    end)

    it("builds the sound picker", function()
        local picker = ns.Widgets.SoundPicker(CreateFrame("Frame"), function() return nil end, function() end,
            { default = "kit:UI_EPICLOOT_TOAST" })
        assert.equals("Epic loot toast", picker.dropdown.label:GetText())
    end)
end)
