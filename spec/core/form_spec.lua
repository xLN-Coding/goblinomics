describe("Core: settings forms", function()
    local ns

    before_each(function() ns = load_core({ login = true, money = 1 }) end)
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("stacks rows in cards and returns the height", function()
        local form = ns.Form.New(CreateFrame("Frame"), -10)
        local card = form:Group("Display", "Intro")
        local value = false
        local toggle = form:Toggle({ label = "Minimap", description = "Shows the button", get = function() return value end,
            set = function(v) value = v end })
        form:Select({ label = "Language", choices = function() return { { value = "a", label = "A" } } end,
            get = function() return "a" end, set = function() end })
        local second = form:Group("Numbers")
        local n = 3
        local number = form:Number({ label = "Days", get = function() return n end, set = function(v) n = v end, min = 1 })
        form:Custom(40, function(frame) frame.built = true end)
        local height = form:Finish()
        -- card 1: 54 (title and intro) + 52 (row with explanation) + 34 (row) + 10 padding
        assert.equals(2, #form.cards)
        assert.equals(card, form.cards[1])
        assert.equals(second, form.cards[2])
        assert.equals(toggle.control, toggle.control)
        assert.is_true(height > 54 + 52 + 34 + 32 + 34 + 52)
        -- the number field validates and converts
        local box = number.control
        box:SetText("7")
        box:GetScript("OnEnterPressed")(box)
        assert.equals(7, n)
        box:SetText("0")
        box:GetScript("OnEnterPressed")(box)
        assert.equals(7, n)
        -- the toggle writes through
        toggle.control:GetScript("OnClick")(toggle.control)
        assert.is_true(value)
    end)

    it("lays out button rows and notes", function()
        local clicked
        local form = ns.Form.New(CreateFrame("Frame"), 0)
        form:Group("Actions")
        local row = form:Buttons({ label = "Export", buttons = { { text = "A", onClick = function() clicked = "a" end },
            { text = "B", width = 80 } } })
        assert.equals(2, #row.control.buttons)
        row.control.buttons[1]:GetScript("OnClick")(row.control.buttons[1], "LeftButton")
        assert.equals("a", clicked)
        local note = form:Note("Hint", nil, 2)
        assert.equals("Hint", note.text:GetText())
        assert.is_true(form:Finish() > 0)
    end)
end)
