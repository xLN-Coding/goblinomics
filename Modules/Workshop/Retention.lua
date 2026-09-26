if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Retention.lua
-- After login (as a job): craft records and matches older than retentionDays
-- fold into aggregates per recipe { name, profession, crafts, made, cost,
-- revenue, soldCost }; fulfilled orders older than that are dropped; lots older
-- than a year leave the FIFO. "All time" statistics include the aggregates.
local _, ns = ...

local Retention = {}
ns.Retention = Retention

local LOT_MAX_DAYS = 365

local module

local function Aggregate(root, recipe, name, profession)
    local a = root.aggregates[recipe]
    if not a then
        a = { name = name, profession = profession, crafts = 0, made = 0, cost = 0, revenue = 0, soldCost = 0 }
        root.aggregates[recipe] = a
    end
    a.name = a.name or name
    a.profession = a.profession or profession
    return a
end

function Retention.Run(now)
    local root = module.db.root
    now = now or time()
    local cutoff = now - module.db.settings.retentionDays * 86400
    local names = {}
    local kept = {}
    for _, r in ipairs(root.crafts) do
        names[r.recipe] = { r.name, r.profession }
        if r.time < cutoff then
            if r.kind ~= "order" and r.kind ~= "salvage" then
                local a = Aggregate(root, r.recipe, r.name, r.profession)
                a.crafts = a.crafts + r.crafts
                a.cost = a.cost + (r.cost or 0)
                for _, o in ipairs(r.outputs) do a.made = a.made + o[2] end
            end
        else
            kept[#kept + 1] = r
        end
        ns.API.Yield()
    end
    root.crafts = kept
    local matches = {}
    for _, m in ipairs(root.matches) do
        if m.time < cutoff then
            local n = names[m.recipe] or {}
            local a = Aggregate(root, m.recipe, n[1], n[2])
            a.revenue = a.revenue + m.revenue
            a.soldCost = a.soldCost + m.cost
        else
            matches[#matches + 1] = m
        end
    end
    root.matches = matches
    local transfers = {}
    for _, tr in ipairs(root.transfers or {}) do
        if tr.time >= cutoff then transfers[#transfers + 1] = tr end
    end
    root.transfers = transfers
    local orders = {}
    for _, o in ipairs(root.orders) do
        if (o.fulfilledAt or o.time) >= cutoff then orders[#orders + 1] = o end
    end
    root.orders = orders
    local lotCutoff = now - LOT_MAX_DAYS * 86400
    local lots = {}
    for _, lot in ipairs(root.lots) do
        if lot.time >= lotCutoff then lots[#lots + 1] = lot end
    end
    root.lots = lots
end

function Retention.Enable(m)
    module = m
    m:After(20, function() m:RunJob("retention", function() Retention.Run() end) end)
end
