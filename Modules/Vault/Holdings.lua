if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/Holdings.lua
-- What makes up the wealth of one character or of the warband bank: every item
-- with quantity, value and where it lies, by the same rules as the networth
-- (bound units left out, auctions count in full, equipment and never-seen
-- locations skipped), so the items add up to the row's items + auctions.
-- Computed on demand for the rows expanded in the Vault tab, as a job.
local _, ns = ...

local Holdings = {}
ns.Holdings = Holdings

local API = ns.API
local LOCATIONS = { "bags", "bank", "mail", "auctions" }
local WARBAND = "warband"
Holdings.WARBAND = WARBAND

local vault
local current = {}   -- ownerKey -> result
local running = {}   -- ownerKey -> true while a job runs
local again = {}     -- ownerKey -> onDone of a run requested while one was running

--- Pure computation over the Vault DB root for ownerKey (a character key or
-- "warband"). Returns { items = { { key, quantity, unit, value, tier,
-- locations = { { location, quantity, value, state } } } }, value, updated }
-- with items sorted by value (then key) and locations by value.
function Holdings.Collect(root, settings, now, ownerKey)
    now = now or time()
    local byKey, evaluated, count = {}, {}, 0
    local function Evaluate(key)
        local r = evaluated[key]
        if not r then
            r = API.Value:Evaluate(key)
            evaluated[key] = r
            count = count + 1
            if count % 50 == 0 then API.Yield() end
        end
        return r
    end
    local function Scan(loc, location)
        if type(loc) ~= "table" or type(loc.items) ~= "table" then return end
        local state = ns.Freshness.State(loc.seenAt, now, settings)
        if state == "never" then return end
        for key, n in pairs(loc.items) do
            local counted = location == "auctions" and n or n - math.min(n, loc.bound and loc.bound[key] or 0)
            if counted > 0 then
                local r = Evaluate(key)
                local value = r.unit * counted
                local e = byKey[key]
                if not e then
                    e = { key = key, quantity = 0, unit = r.unit, value = 0, tier = r.tier, locations = {} }
                    byKey[key] = e
                end
                e.quantity = e.quantity + counted
                e.value = e.value + value
                e.locations[#e.locations + 1] = { location = location, quantity = counted, value = value, state = state }
            end
        end
    end
    if ownerKey == WARBAND then
        Scan(root.warband, WARBAND)
    else
        local c = root.chars and root.chars[ownerKey]
        local locs = type(c) == "table" and c.locations
        if type(locs) == "table" then
            for _, id in ipairs(LOCATIONS) do Scan(locs[id], id) end
        end
    end

    local result = { items = {}, value = 0, updated = now }
    for _, e in pairs(byKey) do
        table.sort(e.locations, function(a, b)
            if a.value == b.value then return a.location < b.location end
            return a.value > b.value
        end)
        result.items[#result.items + 1] = e
        result.value = result.value + e.value
    end
    table.sort(result.items, function(a, b)
        if a.value == b.value then return a.key < b.key end
        return a.value > b.value
    end)
    return result
end

--- Last result for ownerKey, nil before the first run.
function Holdings.Get(ownerKey) return current[ownerKey] end

function Holdings.IsRunning(ownerKey) return running[ownerKey] == true end

--- Recompute ownerKey in a job; onDone(result) afterwards.
-- A request during a run is remembered and runs once the current one is done.
function Holdings.Run(ownerKey, onDone)
    if not vault then return end
    if running[ownerKey] then
        again[ownerKey] = onDone or again[ownerKey] or true
        return
    end
    running[ownerKey] = true
    vault:RunJob("holdings", function()
        current[ownerKey] = Holdings.Collect(vault.db.root, vault.db.settings, time(), ownerKey)
        running[ownerKey] = nil
        if onDone then onDone(current[ownerKey]) end
        local pendingDone = again[ownerKey]
        if pendingDone then
            again[ownerKey] = nil
            Holdings.Run(ownerKey, type(pendingDone) == "function" and pendingDone or nil)
        end
    end)
end

function Holdings.Enable(module)
    vault = module
end

function Holdings.Disable()
    for k in pairs(current) do current[k] = nil end
    for k in pairs(running) do running[k] = nil end
    for k in pairs(again) do again[k] = nil end
end
