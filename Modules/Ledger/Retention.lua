if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Ledger/Retention.lua
-- Raw transactions older than the retention window (default 90 days) become daily
-- aggregates per character, category and tag; totals stay identical. Runs as a job
-- shortly after login, one day per step (never at logout: script watchdog).
-- Auction log events older than 180 days are pruned.
local _, ns = ...

local Retention = {}
ns.Retention = Retention

local API = ns.API
local AH_EVENT_DAYS = 180

local ledger

local function Aggregate(root, day)
    local F = ns.Store.F
    local byChar = root.daily[day] or {}
    root.daily[day] = byChar
    for _, tx in ipairs(root.tx[day] or {}) do
        local cells = byChar[tx[F.CHAR]]
        if not cells then
            cells = {}
            byChar[tx[F.CHAR]] = cells
        end
        local cell = tx[F.CAT] .. "|" .. (tx[F.TAG] or "")
        local sum = cells[cell]
        if not sum then
            sum = { amount = 0, count = 0 }
            cells[cell] = sum
        end
        sum.amount = sum.amount + tx[F.AMT]
        sum.count = sum.count + (tx[F.COUNT] or 1)
    end
    root.tx[day] = nil
end
Retention.Aggregate = Aggregate

--- Days of raw data older than the window, oldest first.
function Retention.DueDays(root, days, now)
    local cutoff = date("%Y-%m-%d", (now or time()) - days * 86400)
    local due = {}
    for day in pairs(root.tx) do
        if day < cutoff then due[#due + 1] = day end
    end
    table.sort(due)
    return due
end

function Retention.Run()
    if not ledger then return end
    local root = ledger.db.root
    local due = Retention.DueDays(root, ledger.db.settings.retentionDays or 90)
    ledger:RunJob("retention", function()
        for _, day in ipairs(due) do
            Aggregate(root, day)
            API.Yield()
        end
        if ns.AuctionLog then ns.AuctionLog.Prune(AH_EVENT_DAYS) end
    end)
end

function Retention.Enable(module)
    ledger = module
    module:After(10, Retention.Run)
end
