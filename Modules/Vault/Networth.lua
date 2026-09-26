if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/Networth.lua
-- One wealth figure over all characters of the account plus the warband bank:
--   wealth = gold (characters, warband bank, mail) + active auctions
--            + items that can be sold (market price, vendor price for items
--              that cannot go to the auction house)
--   speculative = the part of the items with a sale rate below the threshold
-- Bound and warbound items and equipped gear are not counted. Stale locations
-- count; never-seen locations contribute nothing and are reported as "never".
-- Other accounts from Link (Remote.lua) add their gold and wealth; result.remote
-- lists them, the characters and the warband stay local.
-- Confidence = share of item value from fresh or aging locations. Runs as a job
-- (debounced); emits NETWORTH_UPDATED.
local _, ns = ...

local Networth = {}
ns.Networth = Networth

local API = ns.API
local Freshness = ns.Freshness

local vault
local current
local scheduled, running, rerun = false, false, false

local function NewValuer()
    local cache, count = {}, 0
    return function(key)
        local r = cache[key]
        if not r then
            r = API.Value:Evaluate(key)
            cache[key] = r
            count = count + 1
            if count % 50 == 0 then API.Yield() end
        end
        return r
    end
end

local function NewAcc()
    return { gold = 0, auctions = 0, items = 0, speculative = 0 }
end

-- Location kinds: auctions always sell; equipment is not counted.
local LOCATION_KIND = { auctions = "auction", equipment = "skip" }

--- Adds a location to acc; returns its item value (for confidence).
local function AddLocation(acc, loc, value, kind)
    if type(loc) ~= "table" or kind == "skip" then return 0 end
    acc.gold = acc.gold + (loc.money or 0)
    if type(loc.items) ~= "table" then return 0 end
    local worth = 0
    for key, n in pairs(loc.items) do
        local sellable = kind == "auction" and n or n - math.min(n, loc.bound and loc.bound[key] or 0)
        if sellable > 0 then
            local r = value(key)
            local amount = r.unit * sellable
            worth = worth + amount
            if kind == "auction" then
                acc.auctions = acc.auctions + amount
            else
                acc.items = acc.items + amount
            end
            if r.tier == "speculative" then acc.speculative = acc.speculative + amount end
        end
    end
    return worth
end

local function Finish(acc)
    return { gold = acc.gold, auctions = acc.auctions, items = acc.items, speculative = acc.speculative,
        wealth = acc.gold + acc.auctions + acc.items }
end

--- Pure computation over the Vault DB root.
function Networth.Compute(root, settings, now)
    now = now or time()
    local value = NewValuer()
    local total = NewAcc()
    local freshWorth, allWorth = 0, 0
    local result = { chars = {}, updated = now }

    for charKey, c in pairs(root.chars or {}) do
        if type(c) == "table" then
            local acc = NewAcc()
            acc.gold = c.gold or 0
            local locs = {}
            for _, id in ipairs(ns.LOCATIONS) do
                local loc = c.locations and c.locations[id]
                local state = Freshness.State(loc and loc.seenAt, now, settings)
                local worth = 0
                if state ~= "never" then
                    worth = AddLocation(acc, loc, value, LOCATION_KIND[id])
                    allWorth = allWorth + worth
                    if state == "fresh" or state == "aging" then freshWorth = freshWorth + worth end
                end
                locs[id] = { state = state, seenAt = loc and loc.seenAt, value = worth, money = loc and loc.money }
            end
            local r = Finish(acc)
            r.name, r.class, r.locations, r.goldSeenAt = c.name or charKey, c.class, locs, c.goldSeenAt
            result.chars[charKey] = r
            for k, v in pairs(acc) do total[k] = total[k] + v end
        end
    end

    local wb = root.warband or {}
    local wAcc = NewAcc()
    wAcc.gold = wb.gold or 0
    local wState = Freshness.State(wb.seenAt, now, settings)
    local wWorth = 0
    if wState ~= "never" then
        wWorth = AddLocation(wAcc, wb, value)
        allWorth = allWorth + wWorth
        if wState == "fresh" or wState == "aging" then freshWorth = freshWorth + wWorth end
    end
    result.warband = Finish(wAcc)
    result.warband.state, result.warband.seenAt, result.warband.seenBy = wState, wb.seenAt, wb.seenBy
    result.warband.value = wWorth
    for k, v in pairs(wAcc) do total[k] = total[k] + v end

    for k, v in pairs(Finish(total)) do result[k] = v end
    if ns.Remote and root.remote and next(root.remote) then
        local remote = ns.Remote.Sum(root)
        result.remote = remote
        result.gold = result.gold + remote.gold
        result.wealth = result.wealth + remote.wealth
    end
    result.confidence = allWorth > 0 and freshWorth / allWorth or 1
    return result
end

function Networth.Get()
    return current
end

function Networth.Run()
    if not vault then return end
    if running then
        rerun = true
        return
    end
    running = true
    vault:RunJob("networth", function()
        current = Networth.Compute(vault.db.root, vault.db.settings, time())
        running = false
        API.Emit("NETWORTH_UPDATED", current)
        if rerun then
            rerun = false
            Networth.Schedule()
        end
    end)
end

function Networth.Schedule()
    if not vault or scheduled then return end
    scheduled = true
    vault:After(2, function()
        scheduled = false
        Networth.Run()
    end)
end

--- Daily value (last value of the day wins).
function Networth.RecordDay(result)
    result = result or current
    if not vault or not result then return end
    local chars = {}
    for charKey, c in pairs(result.chars) do chars[charKey] = { gold = c.gold, wealth = c.wealth } end
    local remote
    for _, a in ipairs(result.remote and result.remote.accounts or {}) do
        remote = remote or {}
        remote[a.id] = a.wealth
    end
    vault.db.root.history[date("%Y-%m-%d")] = {
        wealth = result.wealth, speculative = result.speculative, gold = result.gold, chars = chars,
        warband = { gold = result.warband.gold, wealth = result.warband.wealth }, remote = remote,
    }
end

function Networth.Enable(module)
    vault = module
    module:On("PRICES_CHANGED", Networth.Schedule)
    Networth.Schedule()
end

function Networth.Disable()
    scheduled, running, rerun = false, false, false
end

function Networth.OnLogout()
    if not vault then return end
    current = Networth.Compute(vault.db.root, vault.db.settings, time())
    Networth.RecordDay(current)
end
