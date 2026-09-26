describe("UI: theme tokens", function()
    local ns
    before_each(function() ns = load_core() end)

    it("has spacing, type roles and the audit colours", function()
        local T = ns.Theme
        assert.equals(12, T.space.PAD)
        assert.equals(22, T.space.ROW)
        assert.equals(10, T.SIZE.caption)
        assert.equals(24, T.SIZE.hero)
        for _, key in ipairs({ "lossSoft", "hover", "zebra", "neutral", "teal", "blue", "brass", "overlay" }) do
            assert.is_table(T.colors[key], key)
        end
        assert.equals(T.colors.accent, T.colors.gain)
        assert.equals(8, #T.palette)
    end)

    it("turns colours into hex and coloured text", function()
        local T = ns.Theme
        assert.equals("3fbf3f", T.Hex(T.colors.accent))
        assert.equals("d9463e", T.Hex(T.colors.loss))
        assert.equals("|cff3fbf3fok|r", T.Colorize("ok", T.colors.accent))
        assert.equals(T.Hex(T.colors.accent), ns.Money.GAIN_COLOR)
    end)

    it("accepts role names for text sizes", function()
        local fs = ns.Theme.Text(CreateFrame("Frame"), "caption", ns.Theme.colors.textDim)
        assert.is_table(fs)
    end)
end)
