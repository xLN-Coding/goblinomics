if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/WorkshopRecipes.lua
-- "Recipes" view of the Workshop: every crafted recipe of the filter in one
-- sortable table (crafts, average cost and revenue, realized profit, margin,
-- concentration value per point) with a search box. "+" expands a recipe into
-- its quality tiers; a click opens the recipe details, shift-click links the
-- item. The numbers come from Stats.Recipes, the same as everywhere else.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local Recipes = {}
ns.WorkshopRecipes = Recipes

--- Margin in percent of the sold cost, nil without sales.
local function Margin(r)
    if not r.soldCost or r.soldCost <= 0 then return nil end
    return r.profit / r.soldCost * 100
end
Recipes.Margin = Margin

local function Name(r)
    if r.output then
        local id = tonumber(r.output:match("^i:(%d+)"))
        local name = id and C_Item.GetItemInfo(id)
        if name then return name end
    end
    return r.name or ""
end

-- Sort values per column; nil sorts last in both directions.
local SORT = {
    name = function(r) return Name(r):lower() end,
    profession = function(r) return (r.profession or ""):lower() end,
    crafts = function(r) return r.crafts end,
    cost = function(r) return r.unitCost end,
    revenue = function(r) return r.unitRevenue end,
    profit = function(r) return r.profit end,
    margin = function(r) return Margin(r) end,
    conc = function(r) return r.conc end,
}

--- Rows of the table for the Stats.Recipes rows: search, sort (key, reverse)
-- and quality rows under expanded recipes. conc(recipe) -> value per point or nil.
function Recipes.Rows(recipes, opts, conc)
    opts = opts or {}
    local search = strtrim(opts.search or ""):lower()
    local list = {}
    for _, r in ipairs(recipes) do
        if search == "" or Name(r):lower():find(search, 1, true) or (r.name or ""):lower():find(search, 1, true) then
            local entry = conc and conc(r.recipe)
            r.conc = entry and entry.value or nil
            list[#list + 1] = r
        end
    end
    local key = SORT[opts.sort or "profit"] and (opts.sort or "profit") or "profit"
    local get = SORT[key]
    local textual = key == "name" or key == "profession"
    table.sort(list, function(a, b)
        local va, vb = get(a), get(b)
        if va == vb then return (a.name or "") < (b.name or "") end
        if va == nil then return false end
        if vb == nil then return true end
        local less = textual and va < vb or (not textual and va > vb)
        if opts.reverse then return not less end
        return less
    end)
    local rows = {}
    for _, r in ipairs(list) do
        local expandable = #r.qualityList > 1
        rows[#rows + 1] = { kind = "recipe", recipe = r.recipe, row = r, expandable = expandable }
        if expandable and opts.expanded and opts.expanded[r.recipe] then
            for _, q in ipairs(r.qualityList) do
                rows[#rows + 1] = { kind = "quality", recipe = r.recipe, quality = q.quality, row = q, parent = r }
            end
        end
    end
    return rows
end

function Recipes.Build(parent)
    local API, L, UI = ns.API, ns.L, ns.WorkshopUI
    local Theme, W = API.Theme, API.Widgets
    local C, S = Theme.colors, Theme.space
    local state = UI.state
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetAllPoints(parent)

    local search = W.EditBox(f, {
        width = 200,
        get = function() return state.search end,
        set = function(text) state.search = text; UI.Refresh(); return true end,
        tooltip = L["Search recipe"],
    })
    search:SetPoint("TOPLEFT", 0, 0)
    search:HookScript("OnTextChanged", function(self, userInput)
        if userInput then state.search = self:GetText(); UI.Refresh() end
    end)
    page.search = search
    page.count = Theme.Text(f, "small", C.textDim)
    page.count:SetPoint("LEFT", search, "RIGHT", S.GAP, 0)

    local columns = W.Columns({
        { key = "name", label = L["Recipe"], sortable = true },
        { key = "profession", label = L["Profession"], width = 90, sortable = true },
        { key = "crafts", label = L["Crafts"], width = 44, align = "RIGHT", sortable = true },
        { key = "cost", label = L["Avg cost"], width = 64, align = "RIGHT", sortable = true },
        { key = "revenue", label = L["Avg revenue"], width = 64, align = "RIGHT", sortable = true },
        { key = "profit", label = L["Profit"], width = 76, align = "RIGHT", sortable = true },
        { key = "margin", label = L["Margin"], width = 48, align = "RIGHT", sortable = true },
        { key = "conc", label = L["Conc. value"], width = 64, align = "RIGHT", sortable = true },
    }, {
        onSort = function(key)
            if state.sort == key then state.reverse = not state.reverse else state.sort, state.reverse = key, false end
            UI.Refresh()
        end,
        sortKey = function() return state.sort end,
        sortDesc = function() return not state.reverse end,
    })
    local headerY = -(S.CONTROL_H + S.SM)
    local header = columns:Header(f)
    header:SetPoint("TOPLEFT", 0, headerY)
    header:SetPoint("RIGHT", f, "RIGHT", 0, 0)

    local function InitRow(row, data)
        if not row.cells then
            columns:Cells(row, "body")
            W.RowBackground(row)
            row.toggle = CreateFrame("Button", nil, row)
            row.toggle:SetSize(16, S.ROW)
            row.toggle:SetPoint("LEFT", 0, 0)
            row.toggle.label = Theme.Text(row.toggle, "body", C.textDim)
            row.toggle.label:SetPoint("CENTER")
            row.toggle:SetScript("OnClick", function()
                local d = row.data
                state.expanded[d.recipe] = not state.expanded[d.recipe] or nil
                UI.Refresh()
            end)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.label = Theme.Text(row, "body", C.text)
            row.label:SetWordWrap(false)
            row.label:SetPoint("RIGHT", row.cells.profession, "LEFT", -S.SM, 0)
            row.cells.name:SetText("")
            row:SetScript("OnClick", function(self)
                local d = self.data
                if self.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                    HandleModifiedItemClick(self.link)
                    return
                end
                UI.OpenRecipe(d.recipe, d.quality)
            end)
            row:SetScript("OnEnter", function(self)
                if self.link then W.ShowItemTooltip(self, self.link) end
            end)
            row:SetScript("OnLeave", W.HideTooltip)
        end
        row.data = data
        local r = data.row
        local cells = row.cells
        local quality = data.kind == "quality"
        row.zebra:SetShown(not quality)
        row.toggle:SetShown(data.expandable)
        row.toggle.label:SetText(state.expanded[data.recipe] and "-" or "+")
        row.icon:ClearAllPoints()
        row.label:ClearAllPoints()
        row.label:SetPoint("RIGHT", cells.profession, "LEFT", -S.SM, 0)
        if quality then
            row.icon:Hide()
            row.link = nil
            row.label:SetPoint("LEFT", 38, 0)
            row.label:SetText(UI.QualityMark(r.quality) .. "  " .. L["Quality"] .. " " .. r.quality)
            cells.profession:SetText("")
            cells.crafts:SetText(Theme.Colorize(tostring(r.made), C.textDim))
        else
            row.icon:SetPoint("LEFT", 18, 0)
            row.icon:SetTexture(UI.ItemIcon(r.output))
            row.icon:Show()
            local label, link = UI.ItemLabel(r.output)
            row.link = link
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.label:SetText((r.output and label or (r.name or "?")) .. (r.incomplete and (" " .. CODE.gold .. "*|r") or ""))
            cells.profession:SetText(Theme.Colorize(r.profession or "", C.textDim))
            cells.crafts:SetText(tostring(r.crafts))
        end
        cells.cost:SetText(UI.Money(r.unitCost))
        cells.revenue:SetText(UI.Money(r.unitRevenue))
        cells.profit:SetText(r.sold and r.sold > 0 and UI.Money(r.profit, { color = true, sign = true })
            or Theme.Colorize("-", C.textDim))
        local margin = Margin(r)
        cells.margin:SetText(margin and ("%.0f%%"):format(margin) or Theme.Colorize("-", C.textDim))
        local conc = quality and data.parent.conc or r.conc
        cells.conc:SetText(conc and API.Lf("%s/pt", UI.Money(conc)) or "")
    end

    page.list = W.ScrollList(f, { rowHeight = S.ROW, init = InitRow })
    page.list.box:SetPoint("TOPLEFT", 0, headerY - S.HEADER_H - S.XS)
    page.list.box:SetPoint("BOTTOMRIGHT", 0, 0)
    page.empty = W.EmptyState(page.list.box, L["No crafts in this period."])
    page.columns = columns

    function page.Refresh(filter)
        local recipes = ns.Stats.Recipes(filter)
        local rows = Recipes.Rows(recipes, state, ns.Concentration.ForRecipe)
        page.rows = rows
        local shown = 0
        for _, r in ipairs(rows) do if r.kind == "recipe" then shown = shown + 1 end end
        page.count:SetText(API.Lf("%d of %d recipes", shown, #recipes))
        columns:RefreshHeader()
        page.list:SetData(rows)
        page.empty:SetShown(#rows == 0)
    end
    return page
end
