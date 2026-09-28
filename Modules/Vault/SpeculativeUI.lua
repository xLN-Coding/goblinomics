if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/SpeculativeUI.lua
-- Main-window tab "Speculative items": every speculative item with icon
-- (logo marker), link, total quantity, value and sale rate, sorted by value;
-- a click expands where it lies (character and location, or the warband bank)
-- with quantity and value per place. Hover shows the item tooltip, shift-click
-- links it. Filters: character (or the warband bank), location, item name,
-- minimum value; the column heads sort (a second click reverses); totals
-- follow the filtered places.
-- Recomputed when the tab opens and after inventory scans.
local _, ns = ...

local SUI = {}
ns.SpeculativeUI = SUI

local API = ns.API
local L = API.L
local OWNER = "Goblinomics_Vault.Speculative"
local ROW_H = API.Theme.space.ROW

local tab = {}
local expanded = {}
local ALL = "all"
local WARBAND = "warband"
local filter = { char = ALL, location = ALL, search = "", minGold = 0, sort = "value", reverse = false }
SUI.filter = filter

local function Money(copper) return API.Money.Format(copper, { abbreviate = true }) end

local function LocationName(id)
    if id == "bags" then return L["Bags"] end
    if id == "bank" then return L["Bank"] end
    if id == "mail" then return L["Mail"] end
    if id == "auctions" then return L["Auctions"] end
    if id == "warband" then return L["Warband bank"] end
    return id
end

--- "1.2%" or "-"
function SUI.SaleRate(rate)
    if type(rate) ~= "number" then return "-" end
    return API.Format:Percent(rate, 1)
end

local function ItemLink(key)
    local id = tonumber(key:match("^i:(%d+)"))
    if not id then return nil end
    local name, link = C_Item.GetItemInfo(id)
    return link, name
end

local function ItemName(key)
    local id = tonumber(key:match("^i:(%d+)"))
    local name = id and C_Item.GetItemInfo(id)
    return name or key
end

local SORTS = {
    value = function(a, b) return a.value > b.value end,
    quantity = function(a, b) return a.quantity > b.quantity end,
    rate = function(a, b) return (a.saleRate or 1) < (b.saleRate or 1) end,
    name = function(a, b) return ItemName(a.key):lower() < ItemName(b.key):lower() end,
}

--- Entries with only the places that pass the filter; quantity and value follow
-- those places. Returns items (sorted), total quantity, total value.
function SUI.Apply(result, f)
    f = f or filter
    local items, quantity, value = {}, 0, 0
    local search = strtrim(f.search or ""):lower()
    local minValue = (tonumber(f.minGold) or 0) * 10000
    for _, e in ipairs(result and result.items or {}) do
        if search == "" or ItemName(e.key):lower():find(search, 1, true) then
            local places, q, v = {}, 0, 0
            for _, p in ipairs(e.locations) do
                local charOk = f.char == ALL or (f.char == WARBAND and p.char == nil) or p.char == f.char
                local locationOk = f.location == ALL or p.location == f.location
                if charOk and locationOk then
                    places[#places + 1] = p
                    q, v = q + p.quantity, v + p.value
                end
            end
            if #places > 0 and v >= minValue then
                items[#items + 1] = { key = e.key, quantity = q, value = v, unit = e.unit, saleRate = e.saleRate,
                    source = e.source, locations = places }
                quantity, value = quantity + q, value + v
            end
        end
    end
    local sort = SORTS[f.sort] or SORTS.value
    if f.reverse then
        local base = sort
        sort = function(a, b) return base(b, a) end
    end
    table.sort(items, function(a, b)
        if sort(a, b) then return true end
        if sort(b, a) then return false end
        return a.key < b.key
    end)
    return items, quantity, value
end

--- Characters that hold speculative items: { { value, label } } plus the warband bank.
function SUI.CharacterChoices(result)
    local seen, list = {}, {}
    local warband = false
    for _, e in ipairs(result and result.items or {}) do
        for _, p in ipairs(e.locations) do
            if p.char and not seen[p.char] then
                seen[p.char] = true
                list[#list + 1] = { value = p.char, label = p.name or p.char }
            elseif not p.char then
                warband = true
            end
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    table.insert(list, 1, { value = ALL, label = L["All characters"] })
    if warband then list[#list + 1] = { value = WARBAND, label = L["Warband bank"] } end
    return list
end

--- Flat rows for the list: an item row, followed by its places when expanded.
function SUI.BuildRows(items)
    local rows = {}
    for _, e in ipairs(items or {}) do
        rows[#rows + 1] = { kind = "item", entry = e }
        if expanded[e.key] then
            for _, place in ipairs(e.locations) do rows[#rows + 1] = { kind = "place", place = place, entry = e } end
        end
    end
    return rows
end

--- Sort by a column head; the same head again reverses the order.
function SUI.SortBy(key)
    if filter.sort == key then
        filter.reverse = not filter.reverse
    else
        filter.sort, filter.reverse = key, false
    end
    SUI.Refresh()
end

local columns   -- Widgets.Columns: item (flex), quantity, value, sale rate

local function InitRow(row, data)
    local Theme = API.Theme
    local C = Theme.colors
    if not row.cols then
        row.cols = columns:Cells(row, "body")
        row.cols.item:SetText("")
        row.cols.value:SetTextColor(unpack(C.gold))
        row.cols.qty:SetTextColor(unpack(C.textDim))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 16, 0)
        API.ItemMarks:Attach(row, row.icon, 11)
        row.toggle = Theme.Text(row, "body", C.textDim)
        row.toggle:SetPoint("LEFT", 2, 0)
        row.name = Theme.Text(row, "body", C.text)
        row.name:SetWordWrap(false)
        API.Widgets.RowBackground(row)
        row:SetScript("OnClick", function(self)
            local d = self.data
            local link = ItemLink(d.entry.key)
            if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                HandleModifiedItemClick(link)
                return
            end
            expanded[d.entry.key] = not expanded[d.entry.key] or nil
            SUI.Refresh()
        end)
        row:SetScript("OnEnter", function(self)
            local link = ItemLink(self.data.entry.key)
            if link then API.Widgets.ShowItemTooltip(self, link) end
        end)
        row:SetScript("OnLeave", API.Widgets.HideTooltip)
    end
    row.data = data
    local c = row.cols
    local e = data.entry
    row.name:ClearAllPoints()
    row.name:SetPoint("RIGHT", row.cols.qty, "LEFT", -Theme.space.SM, 0)
    if data.kind == "item" then
        row.zebra:Show()
        row.toggle:SetText(expanded[e.key] and "-" or "+")
        local id = tonumber(e.key:match("^i:(%d+)"))
        row.icon:SetTexture(id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400)
        row.icon:Show()
        API.ItemMarks:Update(row, e.key)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        local link, name = ItemLink(e.key)
        row.name:SetText(link or name or e.key)
        c.qty:SetText(API.Money.Group(e.quantity))
        c.value:SetText(Money(e.value))
        c.rate:SetText(SUI.SaleRate(e.saleRate))
    else
        local p = data.place
        row.zebra:Hide()
        row.toggle:SetText("")
        row.icon:Hide()
        API.ItemMarks:Update(row, nil)
        row.name:SetPoint("LEFT", 44, 0)
        local who
        if p.char then
            local color = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            who = color and ("|c%s%s|r"):format(color.colorStr, p.name) or p.name
            who = who .. "  " .. Theme.Colorize(LocationName(p.location), C.textDim)
        else
            who = LocationName(p.location)
        end
        if p.state == "stale" then who = who .. "  " .. ns.Freshness.Colorize("stale", "(" .. ns.Freshness.Label("stale") .. ")") end
        row.name:SetText(who)
        c.qty:SetText(API.Money.Group(p.quantity))
        c.value:SetText(Money(p.value))
        c.rate:SetText("")
    end
end

function SUI.Refresh()
    if not tab.list then return end
    local result = ns.Speculative.Get()
    if not result then
        tab.summary:SetText(L["Collecting..."])
        tab.list:SetData({})
        return
    end
    local items, quantity, value = SUI.Apply(result)
    local threshold = API.Price.Config().speculativeThreshold or 0.05
    local filtered = #items < #result.items
    local dim = API.Theme.colors.textDim
    tab.summary:SetText(API.Lf("%d items worth %s", quantity, Money(value))
        .. (filtered and ("  " .. API.Theme.Colorize(API.Lf("(filtered, %d of %d items)", #items, #result.items), dim)) or "")
        .. "   " .. API.Theme.Colorize(API.Lf("Sale rate below %s", SUI.SaleRate(threshold)), dim))
    local fromTSM = false
    for _, e in ipairs(result.items) do
        if e.source == "tsm" then fromTSM = true break end
    end
    tab.rateTitle:SetText((fromTSM and L["Sale rate (TSM)"] or L["Sale rate"]):upper())
    columns:RefreshHeader()
    tab.list:SetData(SUI.BuildRows(items))
    tab.empty:Set(#result.items == 0
        and L["No speculative items. Open bank and mailbox once per character to include them."]
        or L["No items match the filter."])
    tab.empty:SetShown(#items == 0)
end

local function BuildFilters(page)
    local W = API.Widgets
    local S = API.Theme.space
    local x = 0
    local function dropdown(width, choices, field, tooltip)
        local d = W.Dropdown(page, choices, function() return filter[field] end, function(v)
            filter[field] = v
            SUI.Refresh()
        end, { width = width, tooltip = tooltip })
        d:SetPoint("TOPLEFT", x, 0)
        x = x + width + S.SM
        return d
    end
    tab.charFilter = dropdown(S.DROP_M, function() return SUI.CharacterChoices(ns.Speculative.Get()) end, "char",
        L["Character"])
    tab.locationFilter = dropdown(S.DROP_M, function()
        local list = { { value = ALL, label = L["All locations"] } }
        for _, id in ipairs({ "bags", "bank", "mail", "auctions", WARBAND }) do
            list[#list + 1] = { value = id, label = LocationName(id) }
        end
        return list
    end, "location", L["Location"])
    local minBox = W.EditBox(page, {
        width = 70,
        get = function() return (filter.minGold or 0) > 0 and tostring(filter.minGold) or "" end,
        set = function(text)
            filter.minGold = tonumber(text) or 0
            SUI.Refresh()
            return true
        end,
        tooltip = L["Minimum value (gold)"], tooltipLines = { L["Only items worth at least this much in total."] },
    })
    minBox:SetNumeric(true)
    minBox:SetPoint("TOPLEFT", x, 0)
    x = x + 70 + S.SM
    local search = W.EditBox(page, {
        width = 100,
        get = function() return filter.search end,
        set = function(text) filter.search = text; SUI.Refresh(); return true end,
        tooltip = L["Search item"],
    })
    search:SetPoint("TOPLEFT", x, 0)
    search:SetPoint("RIGHT", page, "RIGHT", -S.GUTTER, 0)
    search:HookScript("OnTextChanged", function(self, userInput)
        if userInput then filter.search = self:GetText(); SUI.Refresh() end
    end)
    tab.minBox, tab.search = minBox, search
end

local function BuildTab(page)
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    BuildFilters(page)
    -- summary left, hint right, one line under the filters
    tab.summary = Theme.Text(page, "body", C.text)
    tab.summary:SetPoint("TOPLEFT", 0, S.CONTENT_TOP - 2)
    local hint = Theme.Text(page, "caption", C.textDim)
    hint:SetPoint("TOPRIGHT", page, "TOPRIGHT", -S.GUTTER, S.CONTENT_TOP - 4)
    hint:SetJustifyH("RIGHT")
    hint:SetText(L["Click an item to see where it is. Bound items and equipment are not included."])
    tab.summary:SetPoint("RIGHT", hint, "LEFT", -S.GAP, 0)
    tab.summary:SetWordWrap(false)
    columns = W.Columns({
        { key = "item", label = L["Item"], sortable = true, sortKey = "name" },
        { key = "qty", label = L["Qty"], width = 60, align = "RIGHT", sortable = true },
        { key = "value", label = L["Value"], width = 100, align = "RIGHT", sortable = true },
        { key = "rate", label = L["Sale rate"], width = 90, align = "RIGHT", sortable = true },
    }, {
        onSort = function(key)
            SUI.SortBy(({ item = "name", qty = "quantity", value = "value", rate = "rate" })[key])
        end,
        sortKey = function()
            return ({ name = "item", quantity = "qty", value = "value", rate = "rate" })[filter.sort]
        end,
        sortDesc = function()
            local desc = filter.sort == "value" or filter.sort == "quantity"
            if filter.reverse then desc = not desc end
            return desc
        end,
    })
    local top = S.CONTENT_TOP - 24
    local header = columns:Header(page)
    header:SetPoint("TOPLEFT", 0, top)
    header:SetPoint("RIGHT", page, "RIGHT", -S.GUTTER, 0)
    tab.rateTitle = header.cells[4].label
    tab.list = W.ScrollList(page, { rowHeight = ROW_H, init = InitRow })
    tab.list.box:SetPoint("TOPLEFT", 0, top - S.HEADER_H - S.XS)
    tab.list.box:SetPoint("BOTTOMRIGHT", -S.GUTTER, 0)
    tab.empty = W.EmptyState(tab.list.box, L["No speculative items. Open bank and mailbox once per character to include them."])
    SUI.Refresh()
end

local function Recompute()
    ns.Speculative.Run(function() SUI.Refresh() end)
end

function SUI.Enable()
    API.UI:RegisterTab({
        id = "speculative", title = function() return L["Speculative items"] end, order = 15,
        visible = function() return API.Price:HasRole("saleRate") end,   -- only TSM has a sale rate
        build = BuildTab,
        onShow = function()
            SUI.Refresh()
            Recompute()
            API.On("NETWORTH_UPDATED", Recompute, OWNER)
        end,
        onHide = function() API.Off("NETWORTH_UPDATED", OWNER) end,
    })
end
