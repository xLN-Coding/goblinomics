if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Stats.lua
-- Evaluation per recipe and quality for a time window, profession and
-- character: crafts, items made, costs, sold items, net revenue and realized
-- profit (revenue minus the cost of the sold items), open stock. Crafting
-- orders and salvage have their own lists (Orders, Salvage).
local _, ns = ...

local Stats = {}
ns.Stats = Stats

local module

local function Passes(filter, t, profession, char)
    if filter.from and t < filter.from then return false end
    if filter.to and t >= filter.to then return false end
    if filter.profession and filter.profession ~= profession then return false end
    if filter.char and filter.char ~= char then return false end
    return true
end

local function Quality(row, q)
    q = q or 0
    local s = row.qualities[q]
    if not s then
        s = { quality = q, made = 0, cost = 0, sold = 0, revenue = 0, soldCost = 0, openQty = 0, openCost = 0 }
        row.qualities[q] = s
    end
    return s
end

--- Rows per recipe (sorted by realized profit, then cost) with a quality breakdown.
-- filter = { from = time, to = time (exclusive), profession = name, char = key }
function Stats.Recipes(filter)
    filter = filter or {}
    local root = module.db.root
    local rows, byRecipe = {}, {}
    local function Row(recipe, name, profession)
        local row = byRecipe[recipe]
        if not row then
            row = { recipe = recipe, name = name, profession = profession, crafts = 0, made = 0, cost = 0, sold = 0,
                revenue = 0, soldCost = 0, openQty = 0, openCost = 0, qualities = {} }
            byRecipe[recipe] = row
            rows[#rows + 1] = row
        end
        return row
    end
    for _, r in ipairs(root.crafts) do
        if r.kind ~= "order" and r.kind ~= "salvage" and Passes(filter, r.time, r.profession, r.char) then
            local row = Row(r.recipe, r.name, r.profession)
            row.crafts = row.crafts + r.crafts
            row.cost = row.cost + (r.cost or 0)
            if r.incomplete then row.incomplete = true end
            local made = 0
            for _, o in ipairs(r.outputs) do made = made + o[2] end
            for _, o in ipairs(r.outputs) do
                local q = Quality(row, o[3])
                q.key = q.key or o[1]
                q.made = q.made + o[2]
                q.cost = q.cost + (r.cost or 0) * (made > 0 and o[2] / made or 0)
            end
            row.made = row.made + made
            row.output = row.output or (r.outputs[1] and r.outputs[1][1])
        end
    end
    -- sales count in the window of the sale, also for items crafted earlier
    local meta, salvage = {}, {}
    for _, r in ipairs(root.crafts) do
        meta[r.recipe] = meta[r.recipe] or { r.name, r.profession }
        if r.kind == "salvage" then salvage[r.recipe] = true end
    end
    for recipe, a in pairs(root.aggregates) do meta[recipe] = meta[recipe] or { a.name, a.profession } end
    for _, m in ipairs(root.matches) do
        local info = meta[m.recipe] or {}
        local isSalvage = m.kind == "salvage" or salvage[m.recipe]
        if not isSalvage and (not filter.from or m.time >= filter.from) and (not filter.to or m.time < filter.to)
            and (not filter.profession or filter.profession == info[2])
            and (not filter.char or m.char == nil or m.char == filter.char) then
            local row = byRecipe[m.recipe] or Row(m.recipe, info[1], info[2])
            row.sold = row.sold + m.qty
            row.revenue = row.revenue + m.revenue
            row.soldCost = row.soldCost + m.cost
            local q = Quality(row, m.quality)
            q.sold = q.sold + m.qty
            q.revenue = q.revenue + m.revenue
            q.soldCost = q.soldCost + m.cost
        end
    end
    for _, lot in ipairs(ns.Lots.Open()) do
        local row = byRecipe[lot.recipe]
        if row then
            row.openQty = row.openQty + lot.qty
            row.openCost = row.openCost + lot.unit * lot.qty
            local q = Quality(row, lot.quality)
            q.openQty = q.openQty + lot.qty
            q.openCost = q.openCost + lot.unit * lot.qty
        end
    end
    -- all time: include the aggregates of pruned records
    if not filter.from and not filter.to and not filter.char then
        for recipe, a in pairs(root.aggregates) do
            if not filter.profession or filter.profession == a.profession then
                local row = Row(recipe, a.name, a.profession)
                row.crafts = row.crafts + a.crafts
                row.made = row.made + a.made
                row.cost = row.cost + a.cost
                row.revenue = row.revenue + a.revenue
                row.soldCost = row.soldCost + a.soldCost
            end
        end
    end
    for _, row in ipairs(rows) do
        row.profit = row.revenue - row.soldCost
        row.unitCost = row.made > 0 and row.cost / row.made or nil
        row.unitRevenue = row.sold > 0 and row.revenue / row.sold or nil
        local list = {}
        for _, q in pairs(row.qualities) do
            q.profit = q.revenue - q.soldCost
            q.unitCost = q.made > 0 and q.cost / q.made or nil
            q.unitRevenue = q.sold > 0 and q.revenue / q.sold or nil
            list[#list + 1] = q
        end
        table.sort(list, function(a, b) return a.quality > b.quality end)
        row.qualityList = list
    end
    table.sort(rows, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        if a.cost ~= b.cost then return a.cost > b.cost end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

-- Recipe name/profession and the set of salvage recipes (also for pruned records).
local function Meta(root)
    local meta, salvage = {}, {}
    for _, r in ipairs(root.crafts) do
        meta[r.recipe] = meta[r.recipe] or { r.name, r.profession }
        if r.kind == "salvage" then salvage[r.recipe] = true end
    end
    for recipe, a in pairs(root.aggregates) do meta[recipe] = meta[recipe] or { a.name, a.profession } end
    return meta, salvage
end

--- Calls fn(match, "sales" | "salvage") for every match in the window that passes the filter.
local function EachMatch(filter, fn)
    local root = module.db.root
    local meta, salvage = Meta(root)
    for _, m in ipairs(root.matches) do
        local info = meta[m.recipe] or {}
        if (not filter.from or m.time >= filter.from) and (not filter.to or m.time < filter.to)
            and (not filter.profession or filter.profession == info[2])
            and (not filter.char or m.char == nil or m.char == filter.char) then
            fn(m, (m.kind == "salvage" or salvage[m.recipe]) and "salvage" or "sales")
        end
    end
end

--- Salvage works on a cash basis: the cost of an operation counts when
-- it happens; yields add their revenue when sold and their cost share when they
-- are used in a craft (the craft carries that cost, so nothing counts twice).
-- Calls fn(time, signed amount) for everything in the window.
local function EachSalvageAmount(filter, fn)
    local root = module.db.root
    local meta = Meta(root)
    local function InWindow(t)
        return (not filter.from or t >= filter.from) and (not filter.to or t < filter.to)
    end
    for _, r in ipairs(root.crafts) do
        if r.kind == "salvage" and InWindow(r.time) and (not filter.profession or filter.profession == r.profession)
            and (not filter.char or filter.char == r.char) then
            fn(r.time, -(r.cost or 0))
        end
    end
    EachMatch(filter, function(m, kind)
        if kind == "salvage" then fn(m.time, m.revenue) end
    end)
    for _, tr in ipairs(root.transfers or {}) do
        local info = meta[tr.recipe] or {}
        if InWindow(tr.time) and (not filter.profession or filter.profession == info[2])
            and (not filter.char or tr.char == nil or tr.char == filter.char) then
            fn(tr.time, tr.cost)
        end
    end
end

--- Realized profit split by source: { sales, orders, salvage, total }.
-- sales = sold crafted items (by the time of the sale), orders = fulfilled
-- crafting orders, salvage = cash basis (see EachSalvageAmount).
-- filter = { from, to, profession, char }
function Stats.Breakdown(filter)
    filter = filter or {}
    local b = { sales = 0, orders = 0, salvage = 0 }
    EachMatch(filter, function(m, kind)
        if kind == "sales" then b.sales = b.sales + m.revenue - m.cost end
    end)
    EachSalvageAmount(filter, function(_, amount) b.salvage = b.salvage + amount end)
    for _, o in ipairs(ns.Orders.List(filter)) do b.orders = b.orders + (o.profit or 0) end
    if not filter.from and not filter.to and not filter.char then
        for _, a in pairs(module.db.root.aggregates) do
            if not filter.profession or filter.profession == a.profession then
                b.sales = b.sales + a.revenue - a.soldCost
            end
        end
    end
    b.total = b.sales + b.orders + b.salvage
    return b
end

local function DayStart(t)
    local d = date("*t", t)
    return time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end
Stats.DayStart = DayStart

--- Profit per day for the last `days` days (oldest first):
-- { { day = start time, sales, orders, salvage, total } }
function Stats.Daily(days, filter)
    filter = filter or {}
    local today = DayStart(time())
    local list, index = {}, {}
    for i = days - 1, 0, -1 do
        local start = DayStart(today - i * 86400 + 3600)   -- +1 h keeps DST days apart
        local bucket = { day = start, sales = 0, orders = 0, salvage = 0 }
        list[#list + 1] = bucket
        index[start] = bucket
    end
    local window = { from = list[1].day, profession = filter.profession, char = filter.char }
    EachMatch(window, function(m, kind)
        local bucket = index[DayStart(m.time)]
        if bucket and kind == "sales" then bucket.sales = bucket.sales + m.revenue - m.cost end
    end)
    EachSalvageAmount(window, function(t, amount)
        local bucket = index[DayStart(t)]
        if bucket then bucket.salvage = bucket.salvage + amount end
    end)
    for _, o in ipairs(ns.Orders.List(window)) do
        local bucket = index[DayStart(o.fulfilledAt or o.time)]
        if bucket then bucket.orders = bucket.orders + (o.profit or 0) end
    end
    for _, bucket in ipairs(list) do bucket.total = bucket.sales + bucket.orders + bucket.salvage end
    return list
end

--- Breakdown of the window and of the equally long period before it:
-- { current, previous, change } (change in percent, nil without a previous value).
function Stats.Compare(filter)
    filter = filter or {}
    local current = Stats.Breakdown(filter)
    if not filter.from then return { current = current } end
    local length = (filter.to or time()) - filter.from
    local previous = Stats.Breakdown({ from = filter.from - length, to = filter.from,
        profession = filter.profession, char = filter.char })
    local change
    if previous.total ~= 0 then change = (current.total - previous.total) / math.abs(previous.total) * 100 end
    return { current = current, previous = previous, change = change }
end

--- Open stock: { qty, cost, value } with value at the current market price.
function Stats.OpenStock(filter)
    filter = filter or {}
    local meta = Meta(module.db.root)
    local stock = { qty = 0, cost = 0, value = 0 }
    for _, lot in ipairs(ns.Lots.Open()) do
        local info = meta[lot.recipe] or {}
        if (not filter.char or lot.char == filter.char)
            and (not filter.profession or filter.profession == info[2]) then
            stock.qty = stock.qty + lot.qty
            stock.cost = stock.cost + lot.qty * lot.unit
            stock.value = stock.value + lot.qty * (ns.Reagents.UnitPrice(lot.key) or 0)
        end
    end
    return stock
end

--- Detail of one recipe (optionally one quality) in the window:
-- { row, reagents = { { key, perCraft, costPerCraft, share } }, savedPerCraft, crafts,
--   history = { { time, kind = "craft"|"sale", quality, qty, amount, profit } } }
function Stats.RecipeDetail(recipe, filter, quality)
    filter = filter or {}
    local root = module.db.root
    local detail = { reagents = {}, history = {}, crafts = 0, savedPerCraft = 0 }
    for _, row in ipairs(Stats.Recipes(filter)) do
        if row.recipe == recipe then
            detail.row = row
            if quality then
                for _, q in ipairs(row.qualityList) do
                    if q.quality == quality then detail.row = q end
                end
            end
        end
    end
    local byKey, total, saved = {}, 0, 0
    for _, r in ipairs(root.crafts) do
        local q = r.outputs[1] and r.outputs[1][3]
        if r.recipe == recipe and r.kind ~= "order" and r.kind ~= "salvage"
            and Passes(filter, r.time, r.profession, r.char) and (not quality or q == quality) then
            detail.crafts = detail.crafts + r.crafts
            saved = saved + (r.saved or 0)
            for _, g in ipairs(r.reagents) do
                local e = byKey[g[1]]
                if not e then
                    e = { key = g[1], qty = 0, cost = 0, purchased = 0, crafted = 0 }
                    byKey[g[1]] = e
                    detail.reagents[#detail.reagents + 1] = e
                end
                local lineCost = g[8] or g[2] * g[3]
                e.qty = e.qty + g[2]
                e.cost = e.cost + lineCost
                e.purchased = e.purchased + (g[5] or 0)
                e.crafted = e.crafted + (g[6] or 0)
                total = total + lineCost
            end
            local made = 0
            for _, o in ipairs(r.outputs) do made = made + o[2] end
            detail.history[#detail.history + 1] = { time = r.time, kind = "craft", quality = q, qty = made,
                amount = -(r.cost or 0) }
        end
    end
    local n = math.max(1, detail.crafts)
    for _, e in ipairs(detail.reagents) do
        e.perCraft = e.qty / n
        e.costPerCraft = e.cost / n
        e.share = total > 0 and e.cost / total or 0
    end
    table.sort(detail.reagents, function(a, b) return a.cost > b.cost end)
    detail.savedPerCraft = saved / n
    EachMatch(filter, function(m, kind)
        if kind == "sales" and m.recipe == recipe and (not quality or m.quality == quality) then
            detail.history[#detail.history + 1] = { time = m.time, kind = "sale", quality = m.quality, qty = m.qty,
                amount = m.revenue, profit = m.revenue - m.cost }
        end
    end)
    table.sort(detail.history, function(a, b) return a.time > b.time end)
    for i = #detail.history, 201, -1 do detail.history[i] = nil end
    if detail.row and detail.row.soldCost and detail.row.soldCost > 0 then
        detail.margin = detail.row.profit / detail.row.soldCost * 100
    end
    return detail
end

function Stats.Enable(m)
    module = m
end
