-- UI kit building blocks: card, segmented, columns, dialog, empty state, icon and nav buttons.
describe("UI: components", function()
    local ns, W
    before_each(function()
        ns = load_core({ login = true })
        W = ns.Widgets
    end)
    after_each(function() assert.same({}, WoWMock.errors) end)

    it("builds cards with a grey upper-case caption", function()
        local card = W.Card(CreateFrame("Frame"), "Wealth")
        assert.equals("WEALTH", card.title:GetText())
        assert.is_table(card.body)
    end)

    it("selects in a segmented control", function()
        local value = 7
        local seg = W.Segmented(CreateFrame("Frame"), { { value = 1, label = "1" }, { value = 7, label = "7" } },
            function() return value end, function(v) value = v end)
        assert.is_true(seg.buttons[2].selected)
        seg.buttons[1]:GetScript("OnClick")(seg.buttons[1], "LeftButton")
        assert.equals(1, value)
        assert.is_true(seg.buttons[1].selected)
        assert.is_false(seg.buttons[2].selected)
    end)

    it("lines up header and row cells and sorts by a head", function()
        local sorted
        local cols = W.Columns({ { key = "name", label = "Name" }, { key = "value", label = "Value", width = 80,
            align = "RIGHT", sortable = true } }, { onSort = function(k) sorted = k end, sortKey = function() return sorted end })
        local header = cols:Header(CreateFrame("Frame"))
        assert.equals("VALUE", header.cells[2].label:GetText())
        header.cells[2]:GetScript("OnClick")(header.cells[2])
        assert.equals("value", sorted)
        local cells = cols:Cells(CreateFrame("Frame"))
        assert.is_table(cells.name)
        assert.is_table(cells.value)
    end)

    it("keeps the sort mark inside its own head, never over the neighbour", function()
        local key = "value"
        local cols = W.Columns({ { key = "name", label = "Name", sortable = true, width = 120 },
            { key = "value", label = "Value", width = 80, align = "RIGHT", sortable = true } },
            { onSort = function() end, sortKey = function() return key end })
        local header = cols:Header(CreateFrame("Frame"))
        local right = header.cells[2]
        local p = right.chevron._points[#right.chevron._points]
        assert.same({ "RIGHT", right, "RIGHT", 0, 0 }, p)                -- at its own right edge
        local lp = right.label._points[#right.label._points]
        assert.equals(-9, lp[2])                                          -- the sorted text makes room
        key = "name"
        cols:RefreshHeader()
        lp = right.label._points[#right.label._points]
        assert.equals(0, lp[2])                                           -- unsorted: flush with its values
        local left = header.cells[1]
        p = left.chevron._points[#left.chevron._points]
        assert.equals(left, p[2])
        assert.is_true(p[4] >= 0 and p[4] <= 120 - 9)                     -- inside the column
    end)

    it("builds dialogs with a close button and a button row", function()
        local clicked
        local d = W.Dialog({ title = "Goals", buttons = { { text = "Close", primary = true, onClick = function() clicked = true end } } })
        assert.equals("Goals", d.title:GetText())
        d:Show()
        d.close:GetScript("OnClick")(d.close, "LeftButton")
        assert.is_false(d:IsShown())
        d.buttons[1]:GetScript("OnClick")(d.buttons[1], "LeftButton")
        assert.is_true(clicked)
        local label = d:Row("Name", CreateFrame("Frame"), -10)
        assert.equals("Name", label:GetText())
    end)

    it("greys out disabled buttons and marks navigation rows", function()
        local b = W.Button(CreateFrame("Frame"), "OK")
        b:SetEnabled(false)
        assert.is_true(b.disabled)
        local nav = W.NavButton(CreateFrame("Frame"), "General")
        nav:SetSelected(true)
        assert.is_true(nav.selected)
        local empty = W.EmptyState(CreateFrame("Frame"), "Nothing", "Hint")
        assert.equals("Nothing", empty.text:GetText())
        local icon = W.IconButton(CreateFrame("Frame"), "next")
        assert.is_table(icon.icon)
    end)

    it("opens dropdown submenus", function()
        local drop = W.Dropdown(CreateFrame("Frame"), function()
            return { { value = "a", label = "A" }, { label = "Group", children = { { value = "b", label = "B" } } } }
        end, function() return "b" end, function() end, { size = "M" })
        assert.equals("B", drop.label:GetText())
    end)

    it("confirms through the shared dialog look", function()
        local confirmed, cancelled
        W.Confirm({ title = "Delete", text = "Sure?", onConfirm = function() confirmed = true end,
            onCancel = function() cancelled = true end })
        local d = _G.GoblinomicsConfirmDialog
        assert.equals("Delete", d.title:GetText())
        d.confirm:GetScript("OnClick")(d.confirm, "LeftButton")
        d:GetScript("OnHide")(d)                                  -- the client fires OnHide on Hide
        assert.is_true(confirmed)
        assert.is_nil(cancelled)
    end)
end)

