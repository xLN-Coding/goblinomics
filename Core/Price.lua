if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Price.lua
-- PriceService. Sources register per role (market, destroy, saleRate, vendor);
-- Get walks the role's chain and returns the first positive value. Chains:
-- market/destroy start with the preferred source (setting), then by priority;
-- saleRate and vendor use whatever sources offer them. Results are cached per
-- session, "no value" included, and invalidated on setting changes and source
-- data updates; invalidation emits PRICES_CHANGED (debounced).
local _, ns = ...

local Price = {}
ns.Price = Price

local SafeCall = ns.SafeCall
local ROLES = { market = true, destroy = true, saleRate = true, vendor = true }
Price.ROLES = ROLES

local sources = {}     -- id -> source
local chains = {}      -- role -> ordered list (rebuilt lazily)
local cache = {}       -- role -> itemKey -> value | false
local cacheSource = {} -- role -> itemKey -> source id

function Price.Config()
    local db = ns.coreDB
    if db and db.settings.pricing then
        return db.settings.pricing
    end
    return ns.CORE_DB_SPEC.defaults.pricing
end

local function BuildChain(role)
    local list = {}
    for _, src in pairs(sources) do
        if src.roles[role] then
            list[#list + 1] = src
        end
    end
    local preferred = (role == "market" or role == "destroy") and Price.Config().preferred or nil
    table.sort(list, function(a, b)
        if preferred then
            if a.id == preferred and b.id ~= preferred then return true end
            if b.id == preferred and a.id ~= preferred then return false end
        end
        local pa, pb = a.priority or 50, b.priority or 50
        if pa ~= pb then return pa < pb end
        return a.id < b.id
    end)
    chains[role] = list
    return list
end

function Price.Chain(role)
    return chains[role] or BuildChain(role)
end

local changedPending = false

local function EmitChanged()
    changedPending = false
    ns.Bus.Emit("PRICES_CHANGED", {})
end

--- Clear the cache for one item key or everything; emits PRICES_CHANGED (debounced).
function Price.Invalidate(itemKey)
    if itemKey then
        for role, byKey in pairs(cache) do
            byKey[itemKey] = nil
            cacheSource[role][itemKey] = nil
        end
    else
        for role in pairs(cache) do
            cache[role], cacheSource[role] = nil, nil
        end
    end
    -- speculative markers cache the tier per item (loaded after this file)
    if ns.ItemMarks then ns.ItemMarks.Invalidate(itemKey) end
    if not changedPending and ns.Bus.HasSubscribers("PRICES_CHANGED") then
        changedPending = true
        ns.Timer.After(0.5, EmitChanged, "Core.Price")
    end
end

local function ResetChains()
    for role in pairs(chains) do chains[role] = nil end
end

--- Does any registered source provide this role (e.g. "saleRate", only TSM)?
function Price.HasRole(role)
    return #Price.Chain(role) > 0
end

-- The UI hides what needs a sale rate (speculative items) while no source has one.
local function SourcesChanged(hadSaleRate)
    ResetChains()
    Price.Invalidate()
    if hadSaleRate ~= Price.HasRole("saleRate") and ns.UI and ns.UI.VisibilityChanged then
        ns.UI.VisibilityChanged()
    end
end

--- src = { id, name, priority, roles = {market = true, ...}, Get(self, key, role), Status(self) }
function Price.RegisterSource(src)
    if type(src) ~= "table" or type(src.id) ~= "string" or type(src.Get) ~= "function" or type(src.roles) ~= "table" then
        error("Goblinomics Price:RegisterSource: source needs id, roles and Get", 3)
    end
    local had = Price.HasRole("saleRate")
    sources[src.id] = src
    SourcesChanged(had)
end

function Price.UnregisterSource(id)
    if sources[id] then
        local had = Price.HasRole("saleRate")
        sources[id] = nil
        SourcesChanged(had)
    end
end

--- value, sourceId, pending for an item key and role; nil when no source has a value.
function Price.Get(itemKey, role)
    if type(itemKey) ~= "string" or not ROLES[role] then
        return nil
    end
    local byKey = cache[role]
    if not byKey then
        byKey = {}
        cache[role] = byKey
        cacheSource[role] = {}
    end
    local cached = byKey[itemKey]
    if cached ~= nil then
        if cached == false then return nil end
        return cached, cacheSource[role][itemKey]
    end
    local pending = false
    local chain = Price.Chain(role)
    for i = 1, #chain do
        local src = chain[i]
        local ok, value, flag = SafeCall(src.Get, src, itemKey, role)
        if ok then
            if type(value) == "number" and value > 0 then
                byKey[itemKey] = value
                cacheSource[role][itemKey] = src.id
                return value, src.id
            end
            if flag == "pending" then
                pending = true
            end
        end
    end
    if pending then
        return nil, nil, true
    end
    byKey[itemKey] = false
    return nil
end

--- Set the preferred market/destroy source ("tsm" or "auctionator").
function Price.SetPreferred(id)
    Price.Config().preferred = id
    ResetChains()
    Price.Invalidate()
end

--- Registered sources with status: { {id, name, roles, available, note}, ... } by priority.
function Price.Sources()
    local list = {}
    for _, src in pairs(sources) do
        local status = { available = true }
        if src.Status then
            local ok, s = SafeCall(src.Status, src)
            if ok and type(s) == "table" then status = s end
        end
        list[#list + 1] = {
            id = src.id, name = src.name or src.id, roles = src.roles, priority = src.priority or 50,
            available = status.available ~= false, note = status.note,
        }
    end
    table.sort(list, function(a, b) return a.priority < b.priority end)
    return list
end

--- Value of a named source of any registered provider (e.g. TSM's "DBRecent"):
-- value, sourceId; nil when no source knows it.
function Price.Query(itemKey, name)
    if type(itemKey) ~= "string" or type(name) ~= "string" then return nil end
    for id, src in pairs(sources) do
        if src.Query then
            local ok, value = SafeCall(src.Query, src, itemKey, name)
            if ok and type(value) == "number" then return value, id end
        end
    end
    return nil
end

function Price.GetSource(id)
    return sources[id]
end

ns.API.Price = {
    RegisterSource = function(_, src) return Price.RegisterSource(src) end,
    UnregisterSource = function(_, id) return Price.UnregisterSource(id) end,
    Get = function(_, itemKey, role) return Price.Get(itemKey, role) end,
    Invalidate = function(_, itemKey) return Price.Invalidate(itemKey) end,
    Sources = function() return Price.Sources() end,
    Config = function() return Price.Config() end,
    GetSource = function(_, id) return Price.GetSource(id) end,
    HasRole = function(_, role) return Price.HasRole(role) end,
    Query = function(_, itemKey, name) return Price.Query(itemKey, name) end,
}
