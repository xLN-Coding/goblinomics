if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Pulse.lua
-- Market Pulse: the market of your own products, no market scan.
--   items     what you crafted (Stats) or farmed (Gatherer sessions) in the last
--             pulseDays days, plus items added by hand; hidden ones and items
--             without a market price are left out
--   trend     TSM's latest scan against its 14-day value (DBRecent / DBMarket - 1);
--             without TSM today's own snapshot against the average of the last 14 days
--   history   once a day the market price of every board item (root.pulse[key][day]),
--             kept 90 days (Retention) - TSM keeps no price history of its own
--   your sales sale rate, average price and last sale from the Ledger's auction log
--   warning   trend at or below -pulseThreshold % while you have the item in stock
local _, ns = ...

local Pulse = {}
ns.Pulse = Pulse

local SPARK_DAYS = 14
local KEEP_DAYS = 90
local module
local snapshotRunning = false

local function API() return ns.API end
local function Day(t) return date("%Y-%m-%d", t) end
Pulse.Day = Day

local function Root() return module.db.root end
local function Settings() return module.db.settings end

--- Board items: key -> { key, craft = true, farm = true, manual = true, farmed = qty }.
function Pulse.Items(now)
    now = now or time()
    local root, settings = Root(), Settings()
    local from = now - (settings.pulseDays or 30) * 86400
    local items = {}
    local function Add(key, source)
        if type(key) ~= "string" then return nil end
        local e = items[key]
        if not e then
            e = { key = key }
            items[key] = e
        end
        e[source] = true
        return e
    end
    for _, r in ipairs(ns.Stats.Recipes({ from = from })) do
        local any = false
        for _, q in ipairs(r.qualityList or {}) do
            if q.key and (q.made or 0) > 0 then Add(q.key, "craft"); any = true end
        end
        if not any and r.output and (r.made or 0) > 0 then Add(r.output, "craft") end
    end
    local gatherer = API().Gatherer
    if gatherer and gatherer.Summaries then
        for _, s in ipairs(gatherer:Summaries(from) or {}) do
            for key, qty in pairs(s.items or {}) do
                local e = Add(key, "farm")
                if e then e.farmed = (e.farmed or 0) + (qty or 0) end
            end
        end
    end
    for key in pairs(root.pulseManual or {}) do Add(key, "manual") end
    for key in pairs(root.pulseHidden or {}) do items[key] = nil end
    for key in pairs(items) do
        if not API().Price:Get(key, "market") then items[key] = nil end
    end
    return items
end

--- Market prices of the last `days` days from the own snapshots, oldest first (nil for missing days).
function Pulse.History(key, days, now)
    now = now or time()
    local byDay = Root().pulse and Root().pulse[key] or {}
    local out = {}
    for i = days - 1, 0, -1 do out[#out + 1] = byDay[Day(now - i * 86400)] or false end
    return out
end

--- Trend as a fraction (-0.18 = 18 % below) and where it comes from ("tsm" or "history"), or nil.
function Pulse.Trend(key, now)
    local A = API()
    local recent = A.Price:Query(key, "DBRecent")
    local market = A.Price:Query(key, "DBMarket")
    if recent and market and market > 0 then return recent / market - 1, "tsm" end
    local history = Pulse.History(key, SPARK_DAYS + 1, now)
    local today = history[#history]
    local sum, n = 0, 0
    for i = 1, #history - 1 do
        if history[i] then sum, n = sum + history[i], n + 1 end
    end
    if today and n >= 3 and sum > 0 then return today / (sum / n) - 1, "history" end
    return nil
end

--- One board row per item, by trend (biggest drop first).
-- { key, craft, farm, manual, stock, market, trend, trendSource, spark, saleRate, averagePrice,
--   lastSale, sold, warning }
function Pulse.Rows(now)
    now = now or time()
    local A = API()
    local threshold = (Settings().pulseThreshold or 15) / 100
    local rows = {}
    for key, e in pairs(Pulse.Items(now)) do
        local row = { key = key, craft = e.craft, farm = e.farm, manual = e.manual }
        row.market = A.Price:Get(key, "market")
        row.stock = A.Vault and A.Vault.ItemCount and A.Vault:ItemCount(key) or nil
        row.trend, row.trendSource = Pulse.Trend(key, now)
        row.spark = Pulse.History(key, SPARK_DAYS, now)
        local ah = A.Ledger and A.Ledger.AuctionStats and A.Ledger:AuctionStats(key, 30)
        if ah then
            row.saleRate, row.averagePrice, row.lastSale, row.sold = ah.saleRate, ah.averagePrice, ah.lastSale, ah.sold
        end
        row.warning = row.trend ~= nil and row.trend <= -threshold and (row.stock or 0) > 0
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        local x, y = a.trend or math.huge, b.trend or math.huge
        if x ~= y then return x < y end
        return a.key < b.key
    end)
    return rows
end

--- Store today's market price of every board item once a day (a job).
function Pulse.Snapshot(now, onDone)
    if not module or snapshotRunning then return end
    now = now or time()
    local root = Root()
    local day = Day(now)
    if root.pulseDay == day then return end
    snapshotRunning = true
    module:RunJob("pulseSnapshot", function()
        root.pulse = root.pulse or {}
        local i = 0
        for key in pairs(Pulse.Items(now)) do
            local value = API().Price:Get(key, "market")
            if value then
                root.pulse[key] = root.pulse[key] or {}
                root.pulse[key][day] = value
            end
            i = i + 1
            if i % 20 == 0 then API().Yield() end
        end
        root.pulseDay = day
        snapshotRunning = false
        API().Emit("WORKSHOP_PULSE", { day = day })
        if onDone then onDone() end
    end)
end

--- Drop snapshots older than KEEP_DAYS (Retention).
function Pulse.Prune(now)
    now = now or time()
    local cutoff = Day(now - KEEP_DAYS * 86400)
    for key, byDay in pairs(Root().pulse or {}) do
        for day in pairs(byDay) do
            if day < cutoff then byDay[day] = nil end
        end
        if not next(byDay) then Root().pulse[key] = nil end
    end
end

function Pulse.Add(key)
    if type(key) ~= "string" then return end
    Root().pulseManual[key] = true
    Root().pulseHidden[key] = nil
    API().Emit("WORKSHOP_PULSE", {})
end

function Pulse.Hide(key, on)
    Root().pulseHidden[key] = on and true or nil
    if on then Root().pulseManual[key] = nil end
    API().Emit("WORKSHOP_PULSE", {})
end

function Pulse.Enable(m)
    module = m
    local root = m.db.root
    for _, k in ipairs({ "pulse", "pulseManual", "pulseHidden", "pulseNotices" }) do
        if type(root[k]) ~= "table" then root[k] = {} end
    end
    API().On("PRICES_CHANGED", function() Pulse.Snapshot() end, "Goblinomics_Workshop.Pulse")
    m:After(10, function() Pulse.Snapshot() end)
end

function Pulse.Disable()
    snapshotRunning = false
    if ns.API then ns.API.Off("PRICES_CHANGED", "Goblinomics_Workshop.Pulse") end
end
