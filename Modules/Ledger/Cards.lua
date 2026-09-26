if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Ledger/Cards.lua
-- Dashboard cards of the Ledger: net income of the period (large, with income,
-- expenses, net bars per day and the current gold and wealth; replaced the raw
-- gold delta, which needed daily gold values that did not exist yet), top gold
-- source, most expensive expense,
-- calendar heatmap of the daily net income, records & streaks, auction house
-- figures and a live feed of the latest bookings. One pass over the raw bookings
-- (90 days) and the daily aggregates (older) per period, cached until the
-- ledger changes. Transfers are neutral and never count.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local Cards = {}
ns.LedgerCards = Cards

local API = ns.API
local L = API.L
local FEED = 8

local ledger
local cache = {}        -- days -> data
local allDays           -- dayKey -> net over all time (records)

local function DayKey(t) return date("%Y-%m-%d", t) end

local function Invalidate()
    wipe(cache)
    allDays = nil
end
Cards.Invalidate = Invalidate

local function SourceLabel(category, tag)
    if tag and tag ~= "" then return tag end
    return ns.CategoryName(category)
end

--- Everything the cards need for a period (cached).
function Cards.Data(context)
    local data = cache[context.days]
    if data and data.from == context.from then return data end
    local root = ledger.db.root
    local F = ns.Store.F
    local fromKey = DayKey(context.from)
    data = { from = context.from, days = {}, sources = {}, expenseByCategory = {}, income = 0, expense = 0 }
    local sources = {}
    local function Day(key)
        local d = data.days[key]
        if not d then
            d = { income = 0, expense = 0 }
            data.days[key] = d
        end
        return d
    end
    local function Add(key, category, tag, amount)
        if category == "Transfer" then return end
        local d = Day(key)
        if amount >= 0 then
            d.income = d.income + amount
            data.income = data.income + amount
            local label = SourceLabel(category, tag)
            sources[label] = (sources[label] or 0) + amount
        else
            d.expense = d.expense + amount
            data.expense = data.expense + amount
            data.expenseByCategory[category] = (data.expenseByCategory[category] or 0) + amount
        end
    end
    for key, list in pairs(root.tx) do
        if key >= fromKey then
            for _, tx in ipairs(list) do
                Add(key, tx[F.CAT], tx[F.TAG], tx[F.AMT])
                if tx[F.CAT] ~= "Transfer" and tx[F.AMT] < 0
                    and (not data.topExpense or tx[F.AMT] < data.topExpense.amount) then
                    data.topExpense = ns.Store.Decode(tx, key)
                end
            end
        end
    end
    for key, byChar in pairs(root.daily) do
        if key >= fromKey then
            for _, cells in pairs(byChar) do
                for cell, sum in pairs(cells) do
                    local category, tag = cell:match("^([^|]*)|(.*)$")
                    Add(key, category, tag, sum.amount)
                end
            end
        end
    end
    for label, amount in pairs(sources) do data.sources[#data.sources + 1] = { label = label, amount = amount } end
    table.sort(data.sources, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.label < b.label
    end)
    local worst
    for category, amount in pairs(data.expenseByCategory) do
        if not worst or amount < worst.amount then worst = { category = category, amount = amount } end
    end
    data.topExpenseCategory = worst
    cache[context.days] = data
    return data
end

--- Net per day of the period in at most `maxBars` buckets (oldest first):
-- { { from, to, income, expense, net } }; long periods group several days.
function Cards.NetBuckets(context, maxBars)
    local data = Cards.Data(context)
    local size = math.max(1, math.ceil(context.days / (maxBars or 60)))
    local list = {}
    for i = 0, context.days - 1 do
        local t = context.from + i * 86400 + 3600
        local d = data.days[DayKey(t)]
        local b = list[math.floor(i / size) + 1]
        if not b then
            b = { from = t, to = t, income = 0, expense = 0, net = 0 }
            list[#list + 1] = b
        end
        b.to = t
        if d then
            b.income, b.expense = b.income + d.income, b.expense + d.expense
            b.net = b.income + b.expense
        end
    end
    return list
end

--- Wealth now and its change since the start of the period (Vault), or nil.
function Cards.Wealth(context)
    if not API.Vault or not API.Vault:Current() then return nil end
    local current = API.Vault:Current()
    local fromKey = DayKey(context.from)
    local before, beforeKey, inside, insideKey
    for key, h in pairs(API.Vault:History()) do
        if h.wealth then
            if key < fromKey then
                if not beforeKey or key > beforeKey then before, beforeKey = h, key end
            elseif not insideKey or key < insideKey then
                inside, insideKey = h, key
            end
        end
    end
    local start = before or inside
    return { gold = current.gold, wealth = current.wealth, speculative = current.speculative,
        change = start and (current.wealth - start.wealth) or nil }
end

--- Net per day over all time (raw and aggregated), cached.
function Cards.AllDays()
    if allDays then return allDays end
    local root = ledger.db.root
    local F = ns.Store.F
    allDays = {}
    for key, list in pairs(root.tx) do
        local net = 0
        for _, tx in ipairs(list) do
            if tx[F.CAT] ~= "Transfer" then net = net + tx[F.AMT] end
        end
        allDays[key] = (allDays[key] or 0) + net
    end
    for key, byChar in pairs(root.daily) do
        local net = 0
        for _, cells in pairs(byChar) do
            for cell, sum in pairs(cells) do
                if not cell:match("^Transfer|") then net = net + sum.amount end
            end
        end
        allDays[key] = (allDays[key] or 0) + net
    end
    return allDays
end

--- { bestDay = { key, net }, streak, highestWealth = { key, wealth } }
function Cards.Records()
    local days = Cards.AllDays()
    local best
    for key, net in pairs(days) do
        if not best or net > best.net then best = { key = key, net = net } end
    end
    -- consecutive days with a positive net up to today (today may still be empty)
    local streak, t = 0, time()
    if (days[DayKey(t)] or 0) <= 0 then t = t - 86400 end
    while (days[DayKey(t)] or 0) > 0 do
        streak = streak + 1
        t = t - 86400
    end
    local highest
    if API.Vault then
        for key, h in pairs(API.Vault:History()) do
            if h.wealth and (not highest or h.wealth > highest.wealth) then highest = { key = key, wealth = h.wealth } end
        end
    end
    return { bestDay = best, streak = streak, highestWealth = highest }
end

--- Heatmap cells: weeks x 7 (Monday first) ending with the current week.
-- Returns { weeks, cells = { { key, net, column, row, future } }, maxAbs }
function Cards.Heatmap(context)
    local weeks = math.min(53, math.max(4, math.ceil(context.days / 7)))
    local days = Cards.AllDays()
    local today = time()
    local weekday = (tonumber(date("%w", today)) + 6) % 7      -- 0 = Monday
    local lastMonday = today - weekday * 86400
    local first = lastMonday - (weeks - 1) * 7 * 86400
    local cells, maxAbs = {}, 0
    for column = 0, weeks - 1 do
        for row = 0, 6 do
            local t = first + (column * 7 + row) * 86400
            local key = DayKey(t)
            local future = key > DayKey(today)
            local net = not future and (days[key] or 0) or 0
            if math.abs(net) > maxAbs then maxAbs = math.abs(net) end
            cells[#cells + 1] = { key = key, net = net, column = column, row = row, future = future, time = t }
        end
    end
    return { weeks = weeks, cells = cells, maxAbs = maxAbs }
end

--- Auction house figures in the period.
function Cards.Auctions(context)
    local a = { sold = 0, revenue = 0, expired = 0, cancelled = 0, deposits = 0, purchases = 0, spent = 0 }
    for _, e in ipairs(ledger.db.root.ah.events) do
        if e[1] >= context.from then
            local kind = e[2]
            if kind == "sale" then
                a.sold, a.revenue = a.sold + 1, a.revenue + (e[5] or 0)
            elseif kind == "expired" then
                a.expired, a.deposits = a.expired + 1, a.deposits + (e[6] or 0)
            elseif kind == "cancelled" then
                a.cancelled, a.deposits = a.cancelled + 1, a.deposits + (e[6] or 0)
            elseif kind == "purchase" then
                a.purchases, a.spent = a.purchases + 1, a.spent + (e[5] or 0)
            end
        end
    end
    local attempts = a.sold + a.expired + a.cancelled
    a.saleRate = attempts > 0 and a.sold / attempts or nil
    return a
end

--- Latest bookings of all characters (newest first).
function Cards.Feed(n)
    local root = ledger.db.root
    local keys = {}
    for key in pairs(root.tx) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return a > b end)
    local list = {}
    for _, key in ipairs(keys) do
        local txs = root.tx[key]
        for i = #txs, 1, -1 do
            list[#list + 1] = ns.Store.Decode(txs[i], key)
            if #list >= (n or FEED) then return list end
        end
    end
    return list
end

-- Cards ------------------------------------------------------------------------------
local function Fmt(copper, opts)
    opts = opts or {}
    opts.abbreviate = true
    return API.Money.Format(copper or 0, opts)
end

local function ShortName(charKey) return charKey and (charKey:match("^([^%-]+)") or charKey) or "-" end

local function ItemText(key)
    if not key then return nil end
    local id = tonumber(key:match("^i:(%d+)"))
    local name, link
    if id then name, link = C_Item.GetItemInfo(id) end
    return (link or name or key) .. API.ItemMarks:Inline(key)
end

local function Bars(f, n, top)
    local Theme = API.Theme
    local C = Theme.colors
    local rows = {}
    for i = 1, n do
        local y = top - (i - 1) * 18
        local r = {}
        r.bar = f:CreateTexture(nil, "BACKGROUND")
        r.bar:SetColorTexture(unpack(C.accentSoft))
        r.bar:SetPoint("TOPLEFT", 12, y + 1)
        r.bar:SetHeight(16)
        r.name = Theme.Text(f, "small", C.text)
        r.name:SetPoint("TOPLEFT", 16, y - 1)
        r.name:SetPoint("RIGHT", f, "RIGHT", -74, 0)
        r.name:SetWordWrap(false)
        r.value = Theme.Text(f, "small", C.text)
        r.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y - 1)
        r.value:SetJustifyH("RIGHT")
        rows[i] = r
    end
    return rows
end

local function Width(f, fallback)
    local w = f.GetWidth and f:GetWidth() or 0
    if not w or w <= 0 then w = fallback end
    return w
end

local EVENTS = { "LEDGER_CHANGED" }

local function DateText(t) return ns.API.Format:Date(t) end

local function RegisterCards()
    local Theme = API.Theme
    local C = Theme.colors

    API.UI:RegisterWidget({
        id = "ledger.net", order = 10, size = "twothirds", height = 120, events = { "LEDGER_CHANGED", "NETWORTH_UPDATED" },
        title = function() return L["Net income"] end,
        build = function(f)
            -- the bars take the right part of the card (about 40 %), the text stays left of them
            f.bars = API.Widgets.BarChart(f, { width = 200, height = 70, gap = 1,
                series = { { key = "plus", color = C.accent }, { key = "minus", color = C.loss } },
                tooltip = function(bar)
                    local b = bar.bucket
                    local title = b.from == b.to and DateText(b.from) or (DateText(b.from) .. " - " .. DateText(b.to))
                    return title, { L["Income"] .. ": " .. Fmt(b.income, { color = true }),
                        L["Expenses"] .. ": " .. Fmt(b.expense, { color = true }),
                        L["Net"] .. ": " .. Fmt(b.net, { color = true, sign = true }) }
                end })
            f.bars:SetPoint("TOPRIGHT", -12, -32)
            f.bars:SetPoint("BOTTOMRIGHT", -12, 12)
            f.net = Theme.Text(f, 24, C.text)
            f.net:SetPoint("TOPLEFT", 12, -28)
            f.net:SetWordWrap(false)
            f.period = Theme.Text(f, "caption", C.textDim)
            f.period:SetPoint("TOPLEFT", 12, -56)
            f.flows = Theme.Text(f, "small", C.text)
            f.flows:SetPoint("TOPLEFT", 12, -72)
            f.wealth = Theme.Text(f, "small", C.textDim)
            f.wealth:SetPoint("BOTTOMLEFT", 12, 12)
            for _, fs in ipairs({ f.net, f.period, f.flows, f.wealth }) do
                fs:SetPoint("RIGHT", f.bars, "LEFT", -12, 0)
                fs:SetWordWrap(false)
            end
            local function Fit(self)
                self.bars:SetWidth(math.floor(math.max(90, math.min(260, (Width(self, 480) - 20) * 0.4))))
            end
            f:HookScript("OnSizeChanged", Fit)
            Fit(f)
        end,
        refresh = function(f, context)
            local data = Cards.Data(context)
            local net = data.income + data.expense
            f.net:SetText(Fmt(net, { color = true, sign = true }))
            f.period:SetText(context.days == 1 and L["today"] or API.Lf("in the last %d days", context.days))
            f.flows:SetText(("%s |cff%s%s|r    %s |cff%s%s|r"):format(L["Income"], API.Money.GAIN_COLOR, Fmt(data.income),
                L["Expenses"], API.Money.LOSS_COLOR, Fmt(-data.expense)))
            -- the wealth has its own card (Vault); here only the gold on hand
            local w = Cards.Wealth(context)
            f.wealth:SetText(w and (L["Gold"] .. " " .. Fmt(w.gold)) or "")
            local bars = {}
            for i, b in ipairs(Cards.NetBuckets(context, 60)) do
                bars[i] = { bucket = b, values = { plus = math.max(0, b.net), minus = math.min(0, b.net) } }
            end
            f.bars:SetData(bars)
        end,
    })

    API.UI:RegisterWidget({
        id = "ledger.source", order = 20, size = "third", height = 160, events = EVENTS,
        title = function() return L["Top gold source"] end,
        build = function(f)
            f.name = Theme.Text(f, "title", C.gold)
            f.name:SetPoint("TOPLEFT", 12, -28)
            f.name:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f.name:SetWordWrap(false)
            f.amount = Theme.Text(f, "small", C.textDim)
            f.amount:SetPoint("TOPLEFT", 12, -48)
            f.rows = Bars(f, 3, -74)
        end,
        refresh = function(f, context)
            local data = Cards.Data(context)
            local top = data.sources[1]
            f.name:SetText(top and top.label or L["No income yet"])
            f.amount:SetText(top and API.Lf("%s  (%d%% of the income)", Fmt(top.amount),
                math.floor(top.amount / math.max(1, data.income) * 100 + 0.5)) or "")
            local width = Width(f, 200) - 24
            for i, row in ipairs(f.rows) do
                local s = data.sources[i]
                row.name:SetText(s and s.label or "")
                row.value:SetText(s and Fmt(s.amount) or "")
                row.bar:SetShown(s ~= nil)
                if s then row.bar:SetWidth(math.max(2, width * s.amount / math.max(1, top.amount))) end
            end
        end,
    })

    API.UI:RegisterWidget({
        id = "ledger.expense", order = 21, size = "third", height = 160, events = EVENTS,
        title = function() return L["Most expensive"] end,
        build = function(f)
            f.amount = Theme.Text(f, 18, C.loss)
            f.amount:SetPoint("TOPLEFT", 12, -28)
            f.what = Theme.Text(f, "small", C.text)
            f.what:SetPoint("TOPLEFT", 12, -54)
            f.what:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f.what:SetWordWrap(false)
            f.when = Theme.Text(f, "caption", C.textDim)
            f.when:SetPoint("TOPLEFT", 12, -72)
            f.catLabel = Theme.Text(f, "caption", C.textDim)
            f.catLabel:SetPoint("TOPLEFT", 12, -104)
            f.catLabel:SetText(L["Most expensive category"]:upper())
            f.category = Theme.Text(f, "body", C.text)
            f.category:SetPoint("TOPLEFT", 12, -120)
            f.categoryAmount = Theme.Text(f, "body", C.loss)
            f.categoryAmount:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -120)
            f.categoryAmount:SetJustifyH("RIGHT")
        end,
        refresh = function(f, context)
            local data = Cards.Data(context)
            local e = data.topExpense
            f.amount:SetText(e and Fmt(e.amount) or "-")
            f.what:SetText(e and ((e.itemKey and ItemText(e.itemKey) or ns.BookingLabel(e.category, e.sub))
                .. (e.quantity and e.quantity > 1 and (" x" .. e.quantity) or "")) or L["No expenses in this period."])
            f.when:SetText(e and (ns.API.Format:Date(e.time, "stamp") .. "  " .. ShortName(e.char)) or "")
            local c = data.topExpenseCategory
            f.category:SetText(c and ns.CategoryName(c.category) or "-")
            f.categoryAmount:SetText(c and Fmt(c.amount) or "")
        end,
    })

    API.UI:RegisterWidget({
        id = "ledger.heatmap", order = 30, size = "twothirds", height = 140, events = EVENTS,
        title = function() return L["Daily net income"] end,
        build = function(f)
            f.cells = {}
            f.legend = Theme.Text(f, "caption", C.textDim)
            f.legend:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
            f.legend:SetJustifyH("RIGHT")
        end,
        refresh = function(f, context)
            local map = Cards.Heatmap(context)
            -- cells fill the card: wide cells for a few weeks, narrow ones for a year
            local S = Theme.space
            local width = Width(f, 420) - 2 * S.PAD
            local height = (f.GetHeight and f:GetHeight() or 0)
            if not height or height <= 0 then height = 140 end
            local gap = map.weeks > 26 and 1 or 2
            local cellW = math.max(3, math.floor((width - (map.weeks - 1) * gap) / map.weeks))
            local cellH = math.max(6, math.floor((height + S.CARD_BODY_Y - S.PAD - 6 * gap) / 7))
            for i, cell in ipairs(map.cells) do
                local b = f.cells[i]
                if not b then
                    b = CreateFrame("Frame", nil, f)
                    b.tex = b:CreateTexture(nil, "ARTWORK")
                    b.tex:SetAllPoints()
                    b:EnableMouse(true)
                    b:SetScript("OnEnter", function(self)
                        API.Widgets.ShowTooltip(self, API.Format:Date(self.cell.time, "full"),
                            { Fmt(self.cell.net, { color = true, sign = true }) })
                    end)
                    b:SetScript("OnLeave", API.Widgets.HideTooltip)
                    f.cells[i] = b
                end
                b.cell = cell
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", S.PAD + cell.column * (cellW + gap), S.CARD_BODY_Y - cell.row * (cellH + gap))
                b:SetSize(cellW, cellH)
                local alpha = map.maxAbs > 0 and (0.25 + 0.75 * math.abs(cell.net) / map.maxAbs) or 0.25
                if cell.future then
                    b.tex:SetColorTexture(0, 0, 0, 0)
                elseif cell.net > 0 then
                    b.tex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], alpha)
                elseif cell.net < 0 then
                    b.tex:SetColorTexture(C.loss[1], C.loss[2], C.loss[3], alpha)
                else
                    b.tex:SetColorTexture(unpack(C.trackSoft))
                end
                b:Show()
            end
            for i = #map.cells + 1, #f.cells do f.cells[i]:Hide() end
            f.legend:SetText(API.Lf("%d weeks", map.weeks))
        end,
    })

    API.UI:RegisterWidget({
        id = "ledger.records", order = 31, size = "third", height = 140, events = { "LEDGER_CHANGED", "NETWORTH_UPDATED" },
        title = function() return L["Records & streaks"] end,
        build = function(f)
            local function Line(y, label)
                local l = Theme.Text(f, "caption", C.textDim)
                l:SetPoint("TOPLEFT", 12, y)
                l:SetText(label:upper())
                local v = Theme.Text(f, "body", C.text)
                v:SetPoint("TOPLEFT", 12, y - 13)
                v:SetPoint("RIGHT", f, "RIGHT", -12, 0)
                v:SetWordWrap(false)
                return v
            end
            f.best = Line(-28, L["Best day"])
            f.streak = Line(-66, L["Streak of plus days"])
            f.highest = Line(-104, L["Highest wealth"])
        end,
        refresh = function(f)
            local r = Cards.Records()
            f.best:SetText(r.bestDay and (Fmt(r.bestDay.net, { color = true, sign = true }) .. "  " .. CODE.dim
                .. r.bestDay.key .. "|r") or "-")
            f.streak:SetText(API.Lf("%d days", r.streak))
            f.highest:SetText(r.highestWealth and (Fmt(r.highestWealth.wealth) .. "  " .. CODE.dim .. r.highestWealth.key
                .. "|r") or "-")
        end,
    })

    API.UI:RegisterWidget({
        id = "ledger.auctions", order = 42, size = "quarter", height = 120, events = EVENTS,
        title = function() return L["Auction house"] end,
        build = function(f)
            f.revenue = Theme.Text(f, 16, C.gold)
            f.revenue:SetPoint("TOPLEFT", 12, -28)
            f.lines = Theme.Text(f, "caption", C.textDim)
            f.lines:SetPoint("TOPLEFT", 12, -52)
            f.lines:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f.lines:SetJustifyH("LEFT")
        end,
        refresh = function(f, context)
            local a = Cards.Auctions(context)
            f.revenue:SetText(Fmt(a.revenue))
            f.lines:SetText(table.concat({
                API.Lf("%d sales", a.sold),
                API.Lf("Sale rate %s", a.saleRate and ("%d%%"):format(math.floor(a.saleRate * 100 + 0.5)) or "-"),
                API.Lf("%d expired, %d cancelled", a.expired, a.cancelled),
                API.Lf("Lost deposits %s", Fmt(a.deposits)),
            }, "\n"))
        end,
    })

    API.UI:RegisterWidget({
        id = "ledger.feed", order = 50, size = "full", height = 28 + FEED * 18 + 10, events = { "LEDGER_TRANSACTION", "LEDGER_CHANGED" },
        title = function() return L["Latest bookings"] end,
        build = function(f)
            f.rows = {}
            for i = 1, FEED do
                local y = -28 - (i - 1) * 18
                local r = {}
                r.time = Theme.Text(f, "small", C.textDim)
                r.time:SetPoint("TOPLEFT", 12, y)
                r.time:SetWidth(80)
                r.char = Theme.Text(f, "small", C.text)
                r.char:SetPoint("TOPLEFT", 94, y)
                r.char:SetWidth(90)
                r.char:SetWordWrap(false)
                r.kind = Theme.Text(f, "small", C.textDim)
                r.kind:SetPoint("TOPLEFT", 188, y)
                r.kind:SetWidth(130)
                r.kind:SetWordWrap(false)
                r.amount = Theme.Text(f, "small", C.text)
                r.amount:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y)
                r.amount:SetJustifyH("RIGHT")
                r.item = Theme.Text(f, "small", C.text)
                r.item:SetPoint("TOPLEFT", 322, y)
                r.item:SetPoint("RIGHT", r.amount, "LEFT", -12, 0)
                r.item:SetWordWrap(false)
                f.rows[i] = r
            end
        end,
        refresh = function(f)
            local list = Cards.Feed(FEED)
            for i, r in ipairs(f.rows) do
                local e = list[i]
                r.time:SetText(e and ns.API.Format:Date(e.time, "stamp") or "")
                r.char:SetText(e and ShortName(e.char) or "")
                r.kind:SetText(e and ns.BookingLabel(e.category, e.sub) or "")
                r.item:SetText(e and (e.itemKey and ItemText(e.itemKey) or (e.note or "")) or "")
                local transfer = e and e.category == "Transfer"
                r.amount:SetText(e and (transfer and (CODE.dim .. Fmt(e.amount) .. "|r")
                    or Fmt(e.amount, { color = true, sign = true })) or "")
            end
        end,
    })
end

function Cards.Enable(module)
    ledger = module
    module:On("LEDGER_CHANGED", Invalidate)
    RegisterCards()
end
