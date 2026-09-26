if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/Speculative.lua
-- Speculative items over all characters and the warband bank: which item, where
-- (character and location), how many, what they are worth and their sale rate
-- (TSM by default). Speculative = tradable and a sale rate below the
-- speculative threshold, the same rule the networth uses. Bound items and
-- equipment are left out. Runs as a job over the Vault snapshots.
local _, ns = ...

local Speculative = {}
ns.Speculative = Speculative

local API = ns.API
local LOCATIONS = { "bags", "bank", "mail", "auctions" }

local vault
local current
local running = false

--- Pure computation over the Vault DB root. Returns
-- { items = { { key, quantity, unit, value, saleRate, source,
--               locations = { { char, name, class, location, quantity, value, state } } } },
--   value, quantity, updated } with items sorted by value, locations by quantity.
function Speculative.Collect(root, settings, now)
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
    local function Add(key, n, charKey, c, location, state)
        local r = Evaluate(key)
        if r.tier ~= "speculative" then return end
        local e = byKey[key]
        if not e then
            e = { key = key, quantity = 0, unit = r.unit, value = 0, saleRate = r.saleRate, source = r.sources.saleRate,
                locations = {} }
            byKey[key] = e
        end
        e.quantity = e.quantity + n
        e.value = e.value + r.unit * n
        e.locations[#e.locations + 1] = { char = charKey, name = c and (c.name or charKey), class = c and c.class,
            location = location, quantity = n, value = r.unit * n, state = state }
    end
    local function Scan(loc, charKey, c, location)
        if type(loc) ~= "table" or type(loc.items) ~= "table" then return end
        local state = ns.Freshness.State(loc.seenAt, now, settings)
        if state == "never" then return end
        for key, n in pairs(loc.items) do
            local tradable = n - math.min(n, loc.bound and loc.bound[key] or 0)
            if tradable > 0 then Add(key, tradable, charKey, c, location, state) end
        end
    end
    for charKey, c in pairs(root.chars or {}) do
        if type(c) == "table" and type(c.locations) == "table" then
            for _, id in ipairs(LOCATIONS) do Scan(c.locations[id], charKey, c, id) end
        end
    end
    Scan(root.warband, nil, nil, "warband")

    local result = { items = {}, value = 0, quantity = 0, updated = now }
    for _, e in pairs(byKey) do
        table.sort(e.locations, function(a, b)
            if a.quantity == b.quantity then return (a.char or "") < (b.char or "") end
            return a.quantity > b.quantity
        end)
        result.items[#result.items + 1] = e
        result.value = result.value + e.value
        result.quantity = result.quantity + e.quantity
    end
    table.sort(result.items, function(a, b)
        if a.value == b.value then return a.key < b.key end
        return a.value > b.value
    end)
    return result
end

function Speculative.Get() return current end

--- Recompute in a job; onDone(result) afterwards.
function Speculative.Run(onDone)
    if not vault or running then return end
    running = true
    vault:RunJob("speculative", function()
        current = Speculative.Collect(vault.db.root, vault.db.settings, time())
        running = false
        API.Emit("VAULT_SPECULATIVE_UPDATED", current)
        if onDone then onDone(current) end
    end)
end

function Speculative.Enable(module)
    vault = module
end
