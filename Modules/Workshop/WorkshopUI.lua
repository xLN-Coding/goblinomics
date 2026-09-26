if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/WorkshopUI.lua
-- Workshop tab, master-detail:
--   left   a slim list: Summary, Orders, Salvage, then the recipes by realized
--          profit; "+" expands a recipe into its quality tiers
--   right  the page for the selection (WorkshopSummary, WorkshopDetail)
-- Filters on top: period, profession, character. Shared helpers for the pages
-- live here (money, item labels, quality marks, small stat blocks). Plus the
-- "Workshop" settings section and the dashboard card.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local UI = {}
ns.WorkshopUI = UI

local OWNER = "Goblinomics_Workshop.Tab"
local ROW_H = 22
local LIST_W = 250
local ALL = "all"

local API, L
local module
local tab = {}
local state = { period = 30, profession = ALL, char = ALL, expanded = {}, selected = { kind = "summary" } }
UI.state = state

-- Helpers shared by the pages --------------------------------------------------------
local function Money(copper, opts)
    if copper == nil then return "-" end
    opts = opts or {}
    opts.abbreviate = true
    return API.Money.Format(math.floor(copper + 0.5), opts)
end
UI.Money = Money

function UI.ShortName(charKey) return charKey and (charKey:match("^([^%-]+)") or charKey) or "-" end

function UI.QualityMark(q, size)
    if not q or q == 0 then return "" end
    if CreateAtlasMarkup then
        return CreateAtlasMarkup("Professions-Icon-Quality-Tier" .. q .. "-Small", size or 16, size or 16)
    end
    return "Q" .. q
end

--- label (link or name with the speculative logo), link, itemID
function UI.ItemLabel(key)
    local id = key and tonumber(key:match("^i:(%d+)"))
    local name, link
    if id then name, link = C_Item.GetItemInfo(id) end
    return (link or name or key or "?") .. (key and API.ItemMarks:Inline(key) or ""), link, id
end

function UI.ItemIcon(key)
    local id = key and tonumber(key:match("^i:(%d+)"))
    return id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400
end

--- Small stat block: dim label above a value; returns the value fontstring.
function UI.Stat(parent, x, y, label, width)
    local Theme = API.Theme
    local l = Theme.Text(parent, 10, Theme.colors.textDim)
    l:SetPoint("TOPLEFT", x, y)
    l:SetText(label:upper())
    local v = Theme.Text(parent, "title", Theme.colors.text)
    v:SetPoint("TOPLEFT", x, y - 13)
    if width then v:SetWidth(width) end
    v:SetWordWrap(false)
    return v
end

function UI.Section(parent, text, x, y)
    local Theme = API.Theme
    local fs = Theme.Text(parent, "caption", Theme.colors.textDim)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text:upper())
    return fs
end

--- "Sold crafts x, Crafting orders y (, Salvage z)" with coloured amounts.
function UI.BreakdownText(b, separator)
    local parts = {
        L["Sold crafts"] .. " " .. Money(b.sales, { color = true, sign = true }),
        L["Crafting orders"] .. " " .. Money(b.orders, { color = true, sign = true }),
    }
    if b.salvage ~= 0 then
        parts[#parts + 1] = L["Salvage"] .. " " .. Money(b.salvage, { color = true, sign = true })
    end
    return table.concat(parts, separator or "\n")
end

--- Filter for the stats from the current state.
function UI.Filter()
    return { from = API.Periods:From(state.period), profession = state.profession ~= ALL and state.profession or nil,
        char = state.char ~= ALL and state.char or nil }
end

-- Left list --------------------------------------------------------------------------
--- Rows of the left list for the current filter.
function UI.ListRows()
    local filter = UI.Filter()
    local rows = {}
    local b = ns.Stats.Breakdown(filter)
    rows[#rows + 1] = { kind = "summary", value = b.total }
    rows[#rows + 1] = { kind = "orders", value = b.orders }
    local salvage = ns.Salvage.Rows(filter)
    if #salvage > 0 or b.salvage ~= 0 then rows[#rows + 1] = { kind = "salvage", value = b.salvage } end
    local recipes = ns.Stats.Recipes(filter)
    if #recipes > 0 then rows[#rows + 1] = { kind = "header" } end
    for _, r in ipairs(recipes) do
        rows[#rows + 1] = { kind = "recipe", recipe = r.recipe, row = r, value = r.profit,
            expandable = #r.qualityList > 1 }
        if state.expanded[r.recipe] and #r.qualityList > 1 then
            for _, q in ipairs(r.qualityList) do
                rows[#rows + 1] = { kind = "quality", recipe = r.recipe, quality = q.quality, row = q, value = q.profit }
            end
        end
    end
    return rows
end

local function IsSelected(data)
    local sel = state.selected
    if sel.kind ~= data.kind then return false end
    if data.kind == "recipe" then return sel.recipe == data.recipe end
    if data.kind == "quality" then return sel.recipe == data.recipe and sel.quality == data.quality end
    return true
end

function UI.Select(selection)
    if selection.kind == "quality" then state.expanded[selection.recipe] = true end
    state.selected = selection
    UI.Refresh()
end

local function RowLabel(data)
    if data.kind == "summary" then return L["Summary"], nil end
    if data.kind == "orders" then return L["Crafting orders"], nil end
    if data.kind == "salvage" then return L["Salvage"], nil end
    if data.kind == "header" then return L["Recipes"], nil end
    if data.kind == "quality" then
        return UI.QualityMark(data.quality) .. "  " .. L["Quality"] .. " " .. data.quality, nil
    end
    local r = data.row
    local label = r.output and (UI.ItemLabel(r.output)) or (r.name or "?")
    return label .. (r.incomplete and " " .. CODE.gold .. "*|r" or ""), r.output
end

local function InitListRow(row, data)
    if not row.name then
        local Theme = API.Theme
        API.Widgets.RowBackground(row)
        row.toggle = CreateFrame("Button", nil, row)
        row.toggle:SetSize(16, ROW_H)
        row.toggle:SetPoint("LEFT", 0, 0)
        row.toggle.label = Theme.Text(row.toggle, "body", Theme.colors.textDim)
        row.toggle.label:SetPoint("CENTER")
        row.toggle:SetScript("OnClick", function()
            local d = row.data
            state.expanded[d.recipe] = not state.expanded[d.recipe] or nil
            UI.Refresh()
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.name = Theme.Text(row, "body", Theme.colors.text)
        row.name:SetWordWrap(false)
        row.value = Theme.Text(row, "small", Theme.colors.text)
        row.value:SetPoint("RIGHT", -4, 0)
        row.value:SetJustifyH("RIGHT")
        row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        row:SetScript("OnClick", function(self)
            local d = self.data
            if d.kind == "header" then return end
            if self.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                HandleModifiedItemClick(self.link)
                return
            end
            UI.Select({ kind = d.kind, recipe = d.recipe, quality = d.quality })
        end)
        row:SetScript("OnEnter", function(self)
            if self.link then API.Widgets.ShowItemTooltip(self, self.link) end
        end)
        row:SetScript("OnLeave", API.Widgets.HideTooltip)
    end
    row.data = data
    local C = API.Theme.colors
    local selected = IsSelected(data)
    local header = data.kind == "header"
    row.zebra:SetShown(not header and not selected)
    API.Widgets.MarkSelected(row, selected)
    local label, link = RowLabel(data)
    row.link = link
    row.toggle:SetShown(data.kind == "recipe" and data.expandable)
    row.toggle.label:SetText(state.expanded[data.recipe] and "-" or "+")
    local indent = (data.kind == "quality") and 30 or 16
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", indent, 0)
    row.icon:SetShown(data.kind == "recipe")
    if data.kind == "recipe" then row.icon:SetTexture(UI.ItemIcon(data.row.output)) end
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", data.kind == "recipe" and 38 or (header and 4 or indent), 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.name:SetText(header and label:upper() or label)
    row.name:SetTextColor(unpack(header and C.textDim or C.text))
    row.name:SetFontObject(API.Theme.Font(API.Theme.SIZE[header and "caption" or "body"]))
    row.value:SetText(data.value and Money(data.value, { color = true, sign = true }) or "")
end

-- Right side -------------------------------------------------------------------------
local function Page(kind)
    tab.pages = tab.pages or {}
    local page = tab.pages[kind]
    if page then return page end
    if kind == "summary" then
        page = ns.WorkshopSummary.Build(tab.right)
    elseif kind == "orders" then
        page = ns.WorkshopDetail.BuildOrders(tab.right)
    elseif kind == "salvage" then
        page = ns.WorkshopDetail.BuildSalvage(tab.right)
    else
        page = ns.WorkshopDetail.BuildRecipe(tab.right)
    end
    tab.pages[kind] = page
    return page
end

function UI.Refresh()
    if not tab.list then return end
    local filter = UI.Filter()
    local rows = UI.ListRows()
    -- a recipe that disappeared from the filter falls back to the summary
    local sel = state.selected
    if sel.kind == "recipe" or sel.kind == "quality" then
        local found = false
        for _, r in ipairs(rows) do if IsSelected(r) then found = true end end
        if not found then state.selected = { kind = "summary" } end
    end
    tab.list:SetData(rows)
    local kind = state.selected.kind == "quality" and "recipe" or state.selected.kind
    for k, page in pairs(tab.pages or {}) do page.frame:SetShown(k == kind) end
    local page = Page(kind)
    page.frame:Show()
    page.Refresh(filter, state.selected)
end

function UI.CurrentPage()
    local kind = state.selected.kind == "quality" and "recipe" or state.selected.kind
    return tab.pages and tab.pages[kind]
end

local function Choices(field)
    local seen = {}
    local list = { { value = ALL, label = field == "profession" and L["All professions"] or L["All characters"] } }
    for _, r in ipairs(module.db.root.crafts) do
        local v = field == "profession" and r.profession or r.char
        if v and not seen[v] then
            seen[v] = true
            list[#list + 1] = { value = v, label = field == "profession" and v or UI.ShortName(v) }
        end
    end
    table.sort(list, function(a, b)
        if a.value == ALL then return true end
        if b.value == ALL then return false end
        return a.label < b.label
    end)
    return list
end

local function BuildTab(page)
    local W = API.Widgets
    local Theme = API.Theme
    local S = Theme.space
    local period = API.Periods:Control(page, function() return state.period end, function(value)
        state.period = value
        UI.Refresh()
    end, true)
    period:SetPoint("TOPLEFT", 0, 0)
    local x = -S.GUTTER
    local function dropdown(choices, field)
        local d = W.Dropdown(page, choices, function() return state[field] end, function(value)
            state[field] = value
            UI.Refresh()
        end, { size = "M" })
        d:SetPoint("TOPRIGHT", page, "TOPRIGHT", x, 0)
        x = x - S.DROP_M - S.SM
    end
    dropdown(function() return Choices("char") end, "char")
    dropdown(function() return Choices("profession") end, "profession")

    local listBg = CreateFrame("Frame", nil, page)
    listBg:SetPoint("TOPLEFT", 0, S.CONTENT_TOP)
    listBg:SetPoint("BOTTOMLEFT", 0, 0)
    listBg:SetWidth(LIST_W)
    Theme.Backdrop(listBg, Theme.colors.panel, Theme.colors.border)
    tab.list = W.ScrollList(listBg, { rowHeight = ROW_H, init = InitListRow })
    tab.list.box:SetPoint("TOPLEFT", 2, -2)
    tab.list.box:SetPoint("BOTTOMRIGHT", -16, 2)
    tab.right = CreateFrame("Frame", nil, page)
    tab.right:SetPoint("TOPLEFT", LIST_W + S.MASTER_GAP, S.CONTENT_TOP)
    tab.right:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.Refresh()
end

-- Settings ---------------------------------------------------------------------------
local function BuildSettings(parent, y)
    local settings = module.db.settings
    local form = API.Form.New(parent, y)
    local function number(label, description, field)
        form:Number({ label = label, description = description, min = 1,
            get = function() return settings[field] end,
            set = function(n) settings[field] = n end })
    end
    form:Group(L["Retention"])
    number(L["Keep craft details (days)"], L["Older crafts and sales are kept as totals per recipe."], "retentionDays")
    number(L["Open stock for (days)"],
        L["Crafted items that are not sold after this time leave the open stock; a later sale still counts."], "lotDays")
    number(L["Concentration value over (days)"], L["Period for the gold value of one concentration point."],
        "concentrationDays")
    form:Note(L["Realized profit needs the Ledger module: it reports the auction house sales."])
    return form:Finish()
end

-- Dashboard card ---------------------------------------------------------------------
local function RegisterCard()
    local Theme = API.Theme
    local C = Theme.colors
    API.UI:RegisterWidget({
        id = "workshop.crafting", order = 40, size = "quarter", height = 120,
        events = { "WORKSHOP_CRAFT", "WORKSHOP_MATCH", "WORKSHOP_ORDER" },
        title = function() return L["Crafting"] end,
        build = function(f)
            f.value = Theme.Text(f, 16, C.gold)
            f.value:SetPoint("TOPLEFT", 12, -28)
            f.lines = Theme.Text(f, 10, C.textDim)
            f.lines:SetPoint("TOPLEFT", 12, -52)
            f.lines:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f.lines:SetJustifyH("LEFT")
        end,
        refresh = function(f, context)
            local filter = { from = context.from }
            local b = ns.Stats.Breakdown(filter)
            f.value:SetText(Money(b.total, { color = true, sign = true }))
            local best
            for _, r in ipairs(ns.Stats.Recipes(filter)) do
                if r.sold > 0 then best = r break end
            end
            f.lines:SetText(table.concat({
                L["Sold crafts"] .. " " .. Money(b.sales, { color = true, sign = true }),
                L["Crafting orders"] .. " " .. Money(b.orders, { color = true, sign = true }),
                best and (L["Best"] .. ": " .. (best.output and (UI.ItemLabel(best.output)) or best.name)) or "",
            }, "\n"))
        end,
    })
end

function UI.Enable(m)
    module = m
    API, L = ns.API, ns.L
    API.UI:RegisterTab({
        id = "workshop", title = function() return L["Workshop"] end, order = 40,
        build = BuildTab,
        onShow = function()
            UI.Refresh()
            for _, event in ipairs({ "WORKSHOP_CRAFT", "WORKSHOP_MATCH", "WORKSHOP_ORDER" }) do
                API.On(event, UI.Refresh, OWNER)
            end
        end,
        onHide = function()
            for _, event in ipairs({ "WORKSHOP_CRAFT", "WORKSHOP_MATCH", "WORKSHOP_ORDER" }) do API.Off(event, OWNER) end
        end,
    })
    API.UI:RegisterSettings({ id = "workshop", title = function() return L["Workshop"] end, order = 50,
        build = BuildSettings, description = function() return L["How long craft details and open stock are kept."] end })
    RegisterCard()
end
