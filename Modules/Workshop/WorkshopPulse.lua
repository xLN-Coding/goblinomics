if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/WorkshopPulse.lua
-- "Market" view of the Workshop (Market Pulse): one header row (search and "add item"
-- on the left, source filter and "only warnings" on the right) and a sortable table of
-- your products: warning mark, item, source, stock, market price, trend (sparkline of
-- the own daily prices plus percent), your sale rate and average sale price. A click
-- opens the details: a larger price chart, TSM's values and your auction house figures.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local View = {}
ns.WorkshopPulse = View

local L = ns.L
local state = { search = "", source = "all", onlyWarnings = false, sort = "trend", reverse = false }
View.state = state

local WARN = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t"

local function Money(copper) return copper and ns.API.Money.Format(math.floor(copper + 0.5), { abbreviate = true }) or "-" end

local function ItemName(key)
    local id = tonumber(key:match("^i:(%d+)"))
    local name, link = nil, nil
    if id then name, link = C_Item.GetItemInfo(id) end
    return name or key, link
end

--- "Craft", "Farm", "Craft, Farm" or "Added".
function View.SourceText(row)
    local parts = {}
    if row.craft then parts[#parts + 1] = L["Craft"] end
    if row.farm then parts[#parts + 1] = L["Farm"] end
    if #parts == 0 and row.manual then parts[1] = L["Added"] end
    return table.concat(parts, ", ")
end

function View.TrendText(trend)
    if not trend then return CODE.dim .. "-|r" end
    local pct = trend * 100
    local color = pct <= -0.5 and CODE.bad or (pct >= 0.5 and CODE.good or CODE.dim)
    return ("%s%+.0f%%|r"):format(color, pct)
end

local SORT = {
    name = function(r) return ItemName(r.key):lower() end,
    stock = function(r) return r.stock end,
    market = function(r) return r.market end,
    trend = function(r) return r.trend end,
    rate = function(r) return r.saleRate end,
    avg = function(r) return r.averagePrice end,
}

--- Rows after search, source filter, "only warnings" and sorting.
function View.Filter(rows, opts)
    opts = opts or state
    local search = strtrim(opts.search or ""):lower()
    local out = {}
    for _, r in ipairs(rows) do
        local okSource = opts.source == "all" or (opts.source == "craft" and r.craft) or (opts.source == "farm" and r.farm)
        local okSearch = search == "" or ItemName(r.key):lower():find(search, 1, true)
        if okSource and okSearch and (not opts.onlyWarnings or r.warning) then out[#out + 1] = r end
    end
    local key = SORT[opts.sort] and opts.sort or "trend"
    local get, textual = SORT[key], key == "name"
    table.sort(out, function(a, b)
        local x, y = get(a), get(b)
        if x == y then return a.key < b.key end
        if x == nil then return false end
        if y == nil then return true end
        local less
        if textual or key == "trend" then less = x < y else less = x > y end
        if opts.reverse then return not less end
        return less
    end)
    return out
end

-- Details dialog ---------------------------------------------------------------------------
local detail

local function BuildDetail()
    local API = ns.API
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    local d
    d = W.Dialog({ title = L["Market"], width = 560, height = 470, name = "GoblinomicsWorkshopPulse", buttons = {
        { text = L["Hide from the board"], width = 170, onClick = function()
            ns.Pulse.Hide(d.row.key, true)
            d:Hide()
        end },
        { text = L["Close"], primary = true, onClick = function() d:Hide() end },
    } })
    d.icon = d.body:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(32, 32)
    d.icon:SetPoint("TOPLEFT", 0, 0)
    d.name = Theme.Text(d.body, "page", C.text)
    d.name:SetPoint("TOPLEFT", 40, -1)
    d.name:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
    d.name:SetWordWrap(false)
    d.sub = Theme.Text(d.body, "small", C.textDim)
    d.sub:SetPoint("TOPLEFT", 40, -19)
    d.chart = API.Charts.TimeChart(d.body, { height = 150, empty = L["The price chart fills up day by day."],
        series = { { kind = "line", key = "price", color = C.gold } } })
    d.chart:SetPoint("TOPLEFT", 0, -(32 + S.GAP))
    d.chart:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
    d.left = Theme.Text(d.body, "small", C.text)
    d.left:SetPoint("TOPLEFT", 0, -(32 + S.GAP + 150 + S.GAP))
    d.left:SetWidth(250)
    d.left:SetJustifyH("LEFT")
    d.right = Theme.Text(d.body, "small", C.text)
    d.right:SetPoint("TOPLEFT", 266, -(32 + S.GAP + 150 + S.GAP))
    d.right:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
    d.right:SetJustifyH("LEFT")
    return d
end

--- Text lines of the details: TSM values (left) and your auction house figures (right).
function View.DetailLines(row)
    local API = ns.API
    local left = { CODE.dim .. L["Prices"]:upper() .. "|r" }
    for _, e in ipairs({ { "DBRecent", L["Latest scan"] }, { "DBMarket", L["14 days"] }, { "DBHistorical", L["60 days"] },
        { "DBRegionMarketAvg", L["Region"] } }) do
        local v = API.Price:Query(row.key, e[1])
        if v then left[#left + 1] = e[2] .. ": " .. Money(v) end
    end
    if #left == 1 then left[#left + 1] = L["Market"] .. ": " .. Money(row.market) end
    left[#left + 1] = L["Trend"] .. ": " .. View.TrendText(row.trend)
        .. (row.trendSource == "history" and (" " .. CODE.dim .. L["(own prices)"] .. "|r") or "")
    local right = { CODE.dim .. L["Your auctions (30 days)"]:upper() .. "|r" }
    local ah = API.Ledger and API.Ledger.AuctionStats and API.Ledger:AuctionStats(row.key, 30)
    if ah then
        right[#right + 1] = API.Lf("Posted %d, sold %d, expired %d, cancelled %d", ah.posted, ah.sold, ah.expired,
            ah.cancelled)
        right[#right + 1] = L["Sale rate"] .. ": " .. (ah.saleRate and API.Format:Percent(ah.saleRate) or "-")
        right[#right + 1] = L["Avg sale price"] .. ": " .. Money(ah.averagePrice)
        right[#right + 1] = L["Revenue"] .. ": " .. Money(ah.revenue)
        right[#right + 1] = L["Lost deposits"] .. ": " .. Money(ah.depositLost)
        if ah.lastSale then right[#right + 1] = L["Last sale"] .. ": " .. API.Format:Date(ah.lastSale, "stamp") end
    else
        right[#right + 1] = L["No auctions of this item yet."]
    end
    return left, right
end

function View.OpenDetail(row)
    detail = detail or BuildDetail()
    detail.row = row
    local name, link = ItemName(row.key)
    local id = tonumber(row.key:match("^i:(%d+)"))
    detail.icon:SetTexture(id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400)
    detail.name:SetText(link or name)
    detail.sub:SetText(View.SourceText(row) .. (row.stock and ("  \194\183  " .. ns.API.Lf("%d in stock", row.stock)) or ""))
    local data = {}
    for _, v in ipairs(ns.Pulse.History(row.key, 60)) do data[#data + 1] = { values = { price = v or nil } } end
    local any = false
    for _, p in ipairs(data) do if p.values.price then any = true end end
    detail.chart:SetData(any and data or {})
    local left, right = View.DetailLines(row)
    detail.left:SetText(table.concat(left, "\n"))
    detail.right:SetText(table.concat(right, "\n"))
    detail:Show()
end

function View.Detail() return detail end

-- Add item -----------------------------------------------------------------------------------
--- Item key from a link or an item ID typed in, or nil.
function View.ParseItem(text)
    text = strtrim(text or "")
    local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
    return id and ("i:" .. id) or nil
end

-- View -------------------------------------------------------------------------------------------
function View.Build(parent)
    local API = ns.API
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetAllPoints(parent)
    local refresh = function() ns.WorkshopUI.Refresh() end

    -- one header row: search and "add item" left, source and "only warnings" right
    local search = W.EditBox(f, { width = 160, tooltip = L["Search item"],
        get = function() return state.search end,
        set = function(text) state.search = text; refresh(); return true end })
    search:SetPoint("TOPLEFT", 0, 0)
    search:HookScript("OnTextChanged", function(self, userInput)
        if userInput then state.search = self:GetText(); refresh() end
    end)
    local add = W.EditBox(f, { width = 150, tooltip = L["Add an item: shift-click it or type its item ID, then Enter."],
        get = function() return "" end,
        set = function(text)
            local key = View.ParseItem(text)
            if not key then return false, L["Shift-click an item or type an item ID."] end
            ns.Pulse.Add(key)
            return true
        end })
    add:SetPoint("LEFT", search, "RIGHT", S.SM, 0)
    page.add = add
    local hint = Theme.Text(f, "small", C.textDim)
    hint:SetPoint("LEFT", add, "RIGHT", S.SM, 0)
    hint:SetText(L["+ item"])
    local only = W.Checkbox(f, L["Only warnings"], function() return state.onlyWarnings end, function(on)
        state.onlyWarnings = on
        refresh()
    end, { width = 140 })
    only:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -1)
    local source = W.Dropdown(f, function() return {
        { value = "all", label = L["All sources"] }, { value = "craft", label = L["Crafted"] },
        { value = "farm", label = L["Farmed"] },
    } end, function() return state.source end, function(v) state.source = v; refresh() end, { size = "S" })
    source:SetPoint("RIGHT", only, "LEFT", -S.GAP, 0)

    local columns = W.Columns({
        { key = "warn", label = "", width = 16 },
        { key = "name", label = L["Item"], sortable = true },
        { key = "source", label = L["Source"], width = 56 },
        { key = "stock", label = L["Stock"], width = 56, align = "RIGHT", sortable = true },
        { key = "market", label = L["Market"], width = 64, align = "RIGHT", sortable = true },
        { key = "trend", label = L["Trend"], width = 104, align = "RIGHT", sortable = true },
        { key = "rate", label = L["Sale rate"], width = 60, align = "RIGHT", sortable = true },
        { key = "avg", label = L["Avg sale"], width = 64, align = "RIGHT", sortable = true },
    }, {
        onSort = function(key)
            if state.sort == key then state.reverse = not state.reverse else state.sort, state.reverse = key, false end
            refresh()
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
            row.spark = W.LineChart(row, { width = 52, height = 14, thickness = 1 })
            row.spark:SetPoint("LEFT", row.cells.trend, "LEFT", 0, 0)
            row:SetScript("OnClick", function(self)
                local _, link = ItemName(self.data.key)
                if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                    HandleModifiedItemClick(link)
                    return
                end
                View.OpenDetail(self.data)
            end)
            row:SetScript("OnEnter", function(self)
                local _, link = ItemName(self.data.key)
                if link then W.ShowItemTooltip(self, link) end
            end)
            row:SetScript("OnLeave", W.HideTooltip)
        end
        row.data = data
        local c = row.cells
        local name, link = ItemName(data.key)
        c.warn:SetText(data.warning and WARN or "")
        c.name:SetText(link or name)
        c.source:SetText(Theme.Colorize(View.SourceText(data), C.textDim))
        c.stock:SetText(data.stock and API.Money.Group(data.stock) or "-")
        c.market:SetText(Money(data.market))
        c.trend:SetText(View.TrendText(data.trend))
        local values = {}
        for _, v in ipairs(data.spark or {}) do if v then values[#values + 1] = v end end
        row.spark:SetShown(#values >= 2)
        if #values >= 2 then
            row.spark:SetColor(data.trend and data.trend < 0 and C.loss or C.accent)
            row.spark:SetData(values)
        end
        c.rate:SetText(data.saleRate and API.Format:Percent(data.saleRate) or CODE.dim .. "-|r")
        c.avg:SetText(Money(data.averagePrice))
    end

    page.list = W.ScrollList(f, { rowHeight = S.ROW, init = InitRow })
    page.list.box:SetPoint("TOPLEFT", 0, headerY - S.HEADER_H - S.XS)
    page.list.box:SetPoint("BOTTOMRIGHT", 0, 0)
    page.empty = W.EmptyState(page.list.box, L["No products yet: craft or farm something, or add an item."])
    page.columns = columns

    function page.Refresh()
        local rows = View.Filter(ns.Pulse.Rows())
        page.rows = rows
        columns:RefreshHeader()
        page.list:SetData(rows)
        page.empty:SetShown(#rows == 0)
    end
    return page
end

function View.Enable()
    ns.WorkshopUI.AddView({ id = "market", noPeriod = true, label = function() return L["Market"] end,
        build = function(parent) return View.Build(parent) end })
end
