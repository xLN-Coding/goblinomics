if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Bus.lua
-- Internal event bus on CallbackHandler-1.0 plus demand-driven services.
--
-- Contract: On(event, fn, owner) needs an owner (module id or string); one
-- handler per owner and event; handlers are called fn(event, payload); treat the
-- payload as read-only; subscriber order is not guaranteed. Handlers are timed
-- per owner as "bus:EVENT".
--
-- Services (trackers) start when the first subscriber of one of their events
-- appears and stop with the last one (CallbackHandler OnUsed/OnUnused), so nothing
-- runs while nobody listens.
local _, ns = ...

local Bus = {}
ns.Bus = Bus

local CallbackHandler = LibStub("CallbackHandler-1.0")
local SafeCall = ns.SafeCall
local Record = ns.Perf.Record
local debugprofilestop = debugprofilestop

local target = {}
local registry = CallbackHandler:New(target, "On", "Off", "OffAll")

local subscriptions = {}   -- owner -> event -> true
local subscriptionCount = 0

-- Core events are never emitted while the restricted mode is active.
local CORE_EVENTS = {
    CONTEXT_CHANGED = true, MONEY_DELTA = true, LOOT_RECEIVED = true, ITEMS_DELTA = true,
}
Bus.CORE_EVENTS = CORE_EVENTS

function Bus.On(event, fn, owner)
    if type(event) ~= "string" then
        error("Goblinomics bus: event must be a string", 2)
    end
    if type(fn) ~= "function" then
        error("Goblinomics bus: handler must be a function", 2)
    end
    if type(owner) ~= "string" and type(owner) ~= "table" then
        error("Goblinomics bus: owner (module id or string) required", 2)
    end
    local label = "bus:" .. event
    local perfOwner = type(owner) == "table" and (owner.id or tostring(owner)) or owner
    local byOwner = subscriptions[owner]
    if not byOwner then
        byOwner = {}
        subscriptions[owner] = byOwner
    end
    if not byOwner[event] then
        byOwner[event] = true
        subscriptionCount = subscriptionCount + 1
    end
    target.On(owner, event, function(e, payload)
        local start = debugprofilestop()
        local ok = SafeCall(fn, e, payload)
        Record(perfOwner, label, debugprofilestop() - start, ok)
    end)
end

function Bus.Off(event, owner)
    local byOwner = subscriptions[owner]
    if byOwner and byOwner[event] then
        byOwner[event] = nil
        subscriptionCount = subscriptionCount - 1
        target.Off(owner, event)
    end
end

function Bus.OffAll(owner)
    local byOwner = subscriptions[owner]
    if not byOwner then
        return
    end
    for event in pairs(byOwner) do
        Bus.Off(event, owner)
    end
    subscriptions[owner] = nil
end

local dropped = 0

function Bus.Emit(event, payload)
    if CORE_EVENTS[event] and ns.Restriction and ns.Restriction.IsActive() then
        dropped = dropped + 1
        return
    end
    registry:Fire(event, payload)
end

function Bus.CountSubscriptions()
    return subscriptionCount
end

function Bus.DroppedCount()
    return dropped
end

function Bus.HasSubscribers(event)
    return registry.events[event] ~= nil and next(registry.events[event]) ~= nil
end

-------------------------------------------------------------------------------
-- Services
-------------------------------------------------------------------------------
local services = {}        -- name -> { refs, start, stop, deps }
local eventService = {}    -- bus event -> service name

--- def = { start = fn, stop = fn, deps = { "context", ... }, events = { "MONEY_DELTA", ... } }
function Bus.DefineService(name, def)
    services[name] = { refs = 0, start = def.start, stop = def.stop, deps = def.deps or {} }
    for _, event in ipairs(def.events or {}) do
        eventService[event] = name
        if Bus.HasSubscribers(event) then
            Bus.Acquire(name)
        end
    end
end

function Bus.Acquire(name)
    local s = services[name]
    if not s then
        return
    end
    s.refs = s.refs + 1
    if s.refs == 1 then
        for i = 1, #s.deps do
            Bus.Acquire(s.deps[i])
        end
        if s.start then
            SafeCall(s.start)
        end
    end
end

function Bus.Release(name)
    local s = services[name]
    if not s or s.refs == 0 then
        return
    end
    s.refs = s.refs - 1
    if s.refs == 0 then
        if s.stop then
            SafeCall(s.stop)
        end
        for i = #s.deps, 1, -1 do
            Bus.Release(s.deps[i])
        end
    end
end

function Bus.IsServiceActive(name)
    local s = services[name]
    return s ~= nil and s.refs > 0
end

function registry.OnUsed(_, _, event)
    local name = eventService[event]
    if name then
        Bus.Acquire(name)
    end
end

function registry.OnUnused(_, _, event)
    local name = eventService[event]
    if name then
        Bus.Release(name)
    end
end

-- Public API
function ns.API.On(event, fn, owner) return Bus.On(event, fn, owner) end
function ns.API.Off(event, owner) return Bus.Off(event, owner) end
function ns.API.Emit(event, payload) return Bus.Emit(event, payload) end
