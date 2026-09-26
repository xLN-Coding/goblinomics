describe("Core/Util/Money", function()
    local Money

    before_each(function()
        Money = load_core().Money
    end)

    it("splits copper", function()
        assert.same({ 12, 34, 56 }, { Money.Split(123456) })
        assert.same({ 0, 0, 5 }, { Money.Split(-5) })
    end)

    it("formats with letters", function()
        local text = Money.Format(123456, { icons = false })
        assert.truthy(text:find("^12|cffffd100g|r 34|cffc7c7cfs|r 56|cffeda55fc|r$"))
        assert.truthy(Money.Format(0, { icons = false }):find("^0"))
    end)

    it("groups thousands of gold", function()
        assert.truthy(Money.Format(12345670000, { icons = false }):find("^1,234,567"))
    end)

    it("abbreviates large amounts", function()
        assert.truthy(Money.Format(14300000000, { abbreviate = true, icons = false }):find("^1.43M"))
        assert.truthy(Money.Format(123450000, { abbreviate = true, icons = false }):find("^12.3K"))
        assert.truthy(Money.Format(9500000, { abbreviate = true, icons = false }):find("^950"))
    end)

    it("adds sign and colour", function()
        local loss = Money.Format(-100, { icons = false, color = true })
        assert.truthy(loss:find("^|cffd9463e%-1"))
        local gain = Money.Format(100, { icons = false, color = true, sign = true })
        assert.truthy(gain:find("^|cff3fbf3f%+1"))
    end)

    it("uses coin icons by default", function()
        assert.truthy(Money.Format(10000):find("UI%-GoldIcon"))
    end)
end)
