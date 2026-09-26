if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/WorkshopDetail.lua
-- Compact pages of the Workshop tab:
--   recipe   head, key figures, cost per craft by reagent (share bars,
--            resourcefulness savings), history of crafts and sales; filtered
--            to one quality when a quality row is selected
--   orders   key figures and the fulfilled orders (tooltip: commission,
--            rewards, counted reagents; right-click: count without own cost)
--   salvage  key figures and one row per salvaged item on a cash basis:
--            revenue of sold yields plus the cost share of yields used in
--            crafts, minus all costs of the operations
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local Detail = {}
ns.WorkshopDetail = Detail

local ROW_H = 22
local REAGENT_ROWS = 6

local function Page(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    return { frame = f }
end

-- Generic list columns: a flexible first column, then fixed right-aligned columns
-- (widths in `specs`), through the shared Widgets.Columns so header and rows line up.
local columnSets = {}

local function ColumnSet(specs, titles)
    local set = columnSets[specs]
    if not set then
        local spec = { { key = "c0", label = titles and titles[1] } }
        for i, w in ipairs(specs) do
            spec[#spec + 1] = { key = "c" .. i, width = w, align = "RIGHT", label = titles and titles[i + 1] }
        end
        set = ns.API.Widgets.Columns(spec)
        columnSets[specs] = set
    end
    return set
end

local function Columns(row, specs)
    local cells = ColumnSet(specs):Cells(row)
    local list = {}
    for i = 1, #specs do list[i] = cells["c" .. i] end
    return cells.c0, list
end

local function Highlight(row)
    ns.API.Widgets.RowBackground(row)
    row.zebra:Hide()
end

local function Header(parent, y, specs, titles)
    local S = ns.API.Theme.space
    local set = ColumnSet(specs, titles)
    local h = set:Header(parent)
    for i, cell in ipairs(h.cells) do cell.label:SetText((titles[i] or ""):upper()) end
    h:SetPoint("TOPLEFT", 0, y)
    h:SetPoint("RIGHT", parent, "RIGHT", -S.GUTTER, 0)
    return h
end

-- Recipe --------------------------------------------------------------------------------
local HISTORY_COLS = { 64, 30, 40, 84 }

function Detail.BuildRecipe(parent)
    local API, L, UI = ns.API, ns.L, ns.WorkshopUI
    local Theme, W = API.Theme, API.Widgets
    local C = Theme.colors
    local page = Page(parent)
    local f = page.frame

    page.icon = f:CreateTexture(nil, "ARTWORK")
    page.icon:SetSize(32, 32)
    page.icon:SetPoint("TOPLEFT", 0, 0)
    page.title = Theme.Text(f, "page", C.text)
    page.title:SetPoint("TOPLEFT", 40, -1)
    page.title:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    page.title:SetWordWrap(false)
    page.sub = Theme.Text(f, 11, C.textDim)
    page.sub:SetPoint("TOPLEFT", 40, -19)
    page.stats = {
        profit = UI.Stat(f, 0, -44, L["Profit"], 130),
        crafts = UI.Stat(f, 145, -44, L["Crafts"], 130),
        sold = UI.Stat(f, 290, -44, L["Sold"], 130),
        cost = UI.Stat(f, 0, -78, L["Avg cost"], 130),
        revenue = UI.Stat(f, 145, -78, L["Avg revenue"], 130),
        margin = UI.Stat(f, 290, -78, L["Margin"], 130),
    }

    UI.Section(f, L["Cost per craft"], 0, -116)
    page.reagents = {}
    for i = 1, REAGENT_ROWS do
        local y = -132 - (i - 1) * 18
        local r = {}
        r.bar = f:CreateTexture(nil, "BACKGROUND")
        r.bar:SetColorTexture(unpack(C.accentSoft))
        r.bar:SetPoint("TOPLEFT", 0, y + 1)
        r.bar:SetHeight(16)
        r.name = Theme.Text(f, 11, C.text)
        r.name:SetPoint("TOPLEFT", 4, y - 1)
        r.name:SetPoint("RIGHT", f, "RIGHT", -150, 0)
        r.name:SetWordWrap(false)
        r.qty = Theme.Text(f, 11, C.textDim)
        r.qty:SetPoint("TOPRIGHT", f, "TOPRIGHT", -96, y - 1)
        r.qty:SetJustifyH("RIGHT")
        r.cost = Theme.Text(f, 11, C.text)
        r.cost:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y - 1)
        r.cost:SetJustifyH("RIGHT")
        page.reagents[i] = r
    end
    page.reagentNote = Theme.Text(f, 10, C.textDim)
    page.reagentNote:SetPoint("TOPLEFT", 4, -132 - REAGENT_ROWS * 18 - 2)
    page.reagentNote:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    page.reagentNote:SetJustifyH("LEFT")

    local historyTop = -132 - REAGENT_ROWS * 18 - 22
    UI.Section(f, L["History"], 0, historyTop)
    Header(f, historyTop - 14, HISTORY_COLS, { L["Date"], L["Type"], L["Q"], L["Qty"], L["Amount"] })
    page.history = W.ScrollList(f, { rowHeight = ROW_H, init = function(row, e)
        if not row.first then
            row.first, row.cells = Columns(row, HISTORY_COLS)
            Highlight(row)
        end
        row.first:SetText(ns.API.Format:Date(e.time, "stamp"))
        row.cells[1]:SetText(e.kind == "sale" and (CODE.good .. L["Sale"] .. "|r") or L["Craft"])
        row.cells[2]:SetText(UI.QualityMark(e.quality, 14))
        row.cells[3]:SetText(tostring(e.qty))
        local text = UI.Money(e.amount, { color = true, sign = true })
        if e.profit then text = text .. " " .. CODE.dim .. "(" .. UI.Money(e.profit, { sign = true }) .. ")|r" end
        row.cells[4]:SetText(text)
    end })
    page.history.box:SetPoint("TOPLEFT", 0, historyTop - 32)
    page.history.box:SetPoint("BOTTOMRIGHT", -14, 0)

    function page.Refresh(filter, selection)
        local d = ns.Stats.RecipeDetail(selection.recipe, filter, selection.quality)
        page.detail = d
        local recipeRow
        for _, r in ipairs(ns.Stats.Recipes(filter)) do
            if r.recipe == selection.recipe then recipeRow = r end
        end
        local output = selection.quality and d.row and d.row.key or (recipeRow and recipeRow.output)
        page.icon:SetTexture(UI.ItemIcon(output))
        page.title:SetText((output and (UI.ItemLabel(output)) or (recipeRow and recipeRow.name) or "?")
            .. (selection.quality and ("  " .. UI.QualityMark(selection.quality)) or ""))
        local conc = ns.Concentration.ForRecipe(selection.recipe)
        page.sub:SetText((recipeRow and recipeRow.profession or "")
            .. (conc and ("   " .. CODE.gold .. L["Concentration"] .. " " .. API.Lf("%s/pt", UI.Money(conc.value)) .. "|r")
                or ""))
        local row = d.row or {}
        page.stats.profit:SetText(row.sold and row.sold > 0 and UI.Money(row.profit, { color = true, sign = true }) or "-")
        page.stats.crafts:SetText(tostring(d.crafts) .. (row.made and ("  " .. CODE.dim .. "(" .. API.Lf("%d made", row.made)
            .. ")|r") or ""))
        page.stats.sold:SetText(tostring(row.sold or 0))
        page.stats.cost:SetText(UI.Money(row.unitCost))
        page.stats.revenue:SetText(UI.Money(row.unitRevenue))
        page.stats.margin:SetText(d.margin and ("%.0f%%"):format(d.margin) or "-")

        local width = (f.GetWidth and f:GetWidth()) or 0
        if not width or width <= 0 then width = 420 end
        for i, r in ipairs(page.reagents) do
            local e = d.reagents[i]
            local bought = e and e.qty > 0 and e.purchased / e.qty or 0
            r.name:SetText(e and ((UI.ItemLabel(e.key)) .. (bought > 0 and ("  " .. CODE.dim .. API.Lf("%d%% bought",
                math.floor(bought * 100 + 0.5)) .. "|r") or "")) or "")
            r.qty:SetText(e and ("x" .. (e.perCraft % 1 == 0 and tostring(e.perCraft) or ("%.1f"):format(e.perCraft))) or "")
            r.cost:SetText(e and UI.Money(e.costPerCraft) or "")
            r.bar:SetShown(e ~= nil and e.share > 0)
            if e and e.share > 0 then r.bar:SetWidth(math.max(2, width * e.share)) end
        end
        local notes = {}
        if #d.reagents > REAGENT_ROWS then notes[#notes + 1] = API.Lf("%d more reagents", #d.reagents - REAGENT_ROWS) end
        if d.savedPerCraft > 0 then
            notes[#notes + 1] = API.Lf("Resourcefulness saved %s per craft", UI.Money(d.savedPerCraft))
        end
        if #d.reagents == 0 then notes[#notes + 1] = L["No crafts in this period."] end
        page.reagentNote:SetText(table.concat(notes, "   "))
        page.history:SetData(d.history)
    end
    return page
end

-- Orders --------------------------------------------------------------------------------
local ORDER_COLS = { 76, 76, 76 }

function Detail.BuildOrders(parent)
    local API, L, UI = ns.API, ns.L, ns.WorkshopUI
    local Theme, W = API.Theme, API.Widgets
    local C = Theme.colors
    local page = Page(parent)
    local f = page.frame
    UI.Section(f, L["Crafting orders"], 0, 0)
    page.stats = {
        count = UI.Stat(f, 0, -18, L["Orders"], 80),
        commission = UI.Stat(f, 86, -18, L["Commission"], 80),
        rewards = UI.Stat(f, 172, -18, L["Rewards"], 80),
        cost = UI.Stat(f, 258, -18, L["Own cost"], 80),
        profit = UI.Stat(f, 344, -18, L["Profit"], 80),
    }
    Header(f, -56, ORDER_COLS, { L["Order"], L["Commission"], L["Own cost"], L["Profit"] })
    page.list = W.ScrollList(f, { rowHeight = 32, init = function(row, o)
        if not row.first then
            row.first, row.cells = Columns(row, ORDER_COLS)
            row.first:ClearAllPoints()
            row.first:SetPoint("TOPLEFT", 4, -3)
            row.first:SetPoint("RIGHT", row.cells[1], "LEFT", -6, 0)
            row.sub = Theme.Text(row, 10, C.textDim)
            row.sub:SetPoint("BOTTOMLEFT", 4, 3)
            row.sub:SetPoint("RIGHT", row.cells[1], "LEFT", -6, 0)
            row.sub:SetWordWrap(false)
            Highlight(row)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, button)
                local order = self.data
                if button ~= "RightButton" or order.manual then return end
                W.Confirm({
                    title = L["Own cost"], text = L["Count this order without own reagent cost?"],
                    confirmText = L["OK"], onConfirm = function() ns.Orders.ClearCost(order) end,
                })
            end)
            row:SetScript("OnEnter", function(self)
                local order = self.data
                local lines = {
                    L["Commission"] .. ": " .. UI.Money(order.commission),
                    L["Rewards"] .. ": " .. UI.Money(order.rewards or 0),
                }
                local record = ns.Orders.CraftOf(order)
                if record and (record.saved or 0) > 0 then
                    lines[#lines + 1] = CODE.good .. API.Lf("Resourcefulness: %s returned for free",
                        UI.Money(record.saved)) .. "|r"
                end
                for _, g in ipairs(record and record.reagents or {}) do
                    lines[#lines + 1] = ("%s x%d  %s"):format((UI.ItemLabel(g[1])), g[2], UI.Money(g[8] or g[3] * g[2]))
                end
                if not record or #record.reagents == 0 then lines[#lines + 1] = L["No own reagents counted."] end
                if order.manual then lines[#lines + 1] = CODE.dim .. L["Own cost set to 0 by hand."] .. "|r" end
                lines[#lines + 1] = CODE.dim .. L["Right-click: count without own cost."] .. "|r"
                W.ShowTooltip(self, order.customer or L["Crafting orders"], lines)
            end)
            row:SetScript("OnLeave", W.HideTooltip)
        end
        row.data = o
        row.first:SetText(o.output and (UI.ItemLabel(o.output)) or (o.name or "?"))
        row.sub:SetText(ns.API.Format:Date(o.fulfilledAt or o.time, "stamp") .. "  " .. (o.customer or ""))
        row.cells[1]:SetText(UI.Money((o.commission or 0) + (o.rewards or 0)))
        row.cells[2]:SetText(UI.Money(o.cost, o.cost < 0 and { color = true } or nil)
            .. (o.incomplete and " " .. CODE.gold .. "*|r" or ""))
        row.cells[3]:SetText(UI.Money(o.profit, { color = true, sign = true }))
    end })
    page.list.box:SetPoint("TOPLEFT", 0, -74)
    page.list.box:SetPoint("BOTTOMRIGHT", -14, 0)
    page.empty = W.EmptyState(page.list.box, L["No fulfilled crafting orders in this period."])

    function page.Refresh(filter)
        local orders = ns.Orders.List(filter)
        local commission, rewards, cost, profit = 0, 0, 0, 0
        for _, o in ipairs(orders) do
            commission = commission + (o.commission or 0)
            rewards = rewards + (o.rewards or 0)
            cost = cost + (o.cost or 0)
            profit = profit + (o.profit or 0)
        end
        page.stats.count:SetText(tostring(#orders))
        page.stats.commission:SetText(UI.Money(commission))
        page.stats.rewards:SetText(UI.Money(rewards))
        page.stats.cost:SetText(UI.Money(cost))
        page.stats.profit:SetText(UI.Money(profit, { color = true, sign = true }))
        page.list:SetData(orders)
        page.empty:SetShown(#orders == 0)
    end
    return page
end

-- Salvage -------------------------------------------------------------------------------
local SALVAGE_COLS = { 50, 70, 70, 76 }

function Detail.BuildSalvage(parent)
    local API, L, UI = ns.API, ns.L, ns.WorkshopUI
    local W = API.Widgets
    local page = Page(parent)
    local f = page.frame
    UI.Section(f, L["Salvage"], 0, 0)
    page.stats = {
        ops = UI.Stat(f, 0, -18, L["Operations"], 100),
        cost = UI.Stat(f, 108, -18, L["Cost"], 100),
        sold = UI.Stat(f, 216, -18, L["Income"], 100),
        profit = UI.Stat(f, 324, -18, L["Profit"], 100),
    }
    Header(f, -56, SALVAGE_COLS, { L["Salvaged item"], L["Operations"], L["Cost"], L["Income"], L["Profit"] })
    page.list = W.ScrollList(f, { rowHeight = ROW_H + 2, init = function(row, s)
        if not row.first then
            row.first, row.cells = Columns(row, SALVAGE_COLS)
            Highlight(row)
            row:SetScript("OnEnter", function(self)
                local lines = {}
                for key, qty in pairs(self.data.outputs) do lines[#lines + 1] = (UI.ItemLabel(key)) .. " x" .. qty end
                table.sort(lines)
                local d = self.data
                lines[#lines + 1] = " "
                lines[#lines + 1] = L["Sold"] .. ": " .. UI.Money(d.revenue)
                lines[#lines + 1] = L["Processed further"] .. ": " .. UI.Money(d.transferred)
                lines[#lines + 1] = L["Cost"] .. ": " .. UI.Money(-d.cost, { color = true })
                lines[#lines + 1] = CODE.dim .. L["Unsold yield at market price"] .. ": " .. UI.Money(d.openValue) .. "|r"
                W.ShowTooltip(self, L["Yield"], lines)
            end)
            row:SetScript("OnLeave", W.HideTooltip)
        end
        row.data = s
        row.first:SetText(s.input and (UI.ItemLabel(s.input)) or (s.name or "?"))
        row.cells[1]:SetText(tostring(s.operations))
        row.cells[2]:SetText(UI.Money(s.cost))
        local income = s.revenue + s.transferred
        row.cells[3]:SetText(income > 0 and UI.Money(income) or CODE.dim .. "-|r")
        row.cells[4]:SetText(UI.Money(s.profit, { color = true, sign = true }))
    end })
    page.list.box:SetPoint("TOPLEFT", 0, -74)
    page.list.box:SetPoint("BOTTOMRIGHT", -14, 0)
    page.empty = W.EmptyState(page.list.box, L["No salvage in this period."])

    function page.Refresh(filter)
        local rows = ns.Salvage.Rows(filter)
        local ops, cost, revenue, profit = 0, 0, 0, 0
        for _, s in ipairs(rows) do
            ops, cost = ops + s.operations, cost + s.cost
            revenue, profit = revenue + s.revenue + s.transferred, profit + s.profit
        end
        page.stats.ops:SetText(tostring(ops))
        page.stats.cost:SetText(UI.Money(cost))
        page.stats.sold:SetText(UI.Money(revenue))
        page.stats.profit:SetText(UI.Money(profit, { color = true, sign = true }))
        page.list:SetData(rows)
        page.empty:SetShown(#rows == 0)
    end
    return page
end
