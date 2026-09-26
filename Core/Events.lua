if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Events.lua
-- WoW event dispatch. One dispatcher per owner, each with its own frame: the
-- client bills handler CPU to the addon whose code created the frame, so module
-- dispatchers are created inside RegisterModule (running in the module's main
-- chunk). Registration is ref-counted per event, removal during dispatch is safe,
-- every handler runs through ns.SafeCall and is timed into ns.Perf.
local _, ns = ...

local Events = {}
ns.Events = Events

local debugprofilestop = debugprofilestop
local SafeCall = ns.SafeCall
local Record = ns.Perf.Record

local dispatchers = {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

local function IsValidEvent(event)
    local utils = C_EventUtils
    if utils and utils.IsEventValid then
        return utils.IsEventValid(event)
    end
    return true
end

--- Create a dispatcher. owner: label used for perf attribution.
function Events.NewDispatcher(owner)
    local d = setmetatable({ owner = owner, handlers = {}, counts = {}, depth = 0, dirty = false }, Dispatcher)
    d.frame = CreateFrame("Frame")
    d.frame:SetScript("OnEvent", function(_, event, ...)
        d:Dispatch(event, ...)
    end)
    dispatchers[#dispatchers + 1] = d
    return d
end

--- Add a handler fn(event, ...) under an identity key (default: fn itself).
-- Returns false when the client does not know the event.
function Dispatcher:Register(event, fn, key)
    if not IsValidEvent(event) then
        return false
    end
    local list = self.handlers[event]
    if not list then
        list = {}
        self.handlers[event] = list
    end
    list[#list + 1] = { fn = fn, key = key or fn }
    local count = (self.counts[event] or 0) + 1
    self.counts[event] = count
    if count == 1 then
        self.frame:RegisterEvent(event)
    end
    return true
end

local function Compact(list)
    local j = 0
    for i = 1, #list do
        local entry = list[i]
        if entry.fn then
            j = j + 1
            list[j] = entry
        end
    end
    for i = #list, j + 1, -1 do
        list[i] = nil
    end
end

--- Remove the handler registered under key (default: all handlers of the event).
function Dispatcher:Unregister(event, key)
    local list = self.handlers[event]
    if not list then
        return
    end
    local removed = 0
    for i = 1, #list do
        local entry = list[i]
        if entry.fn and (key == nil or entry.key == key) then
            entry.fn = nil
            removed = removed + 1
        end
    end
    if removed == 0 then
        return
    end
    local count = self.counts[event] - removed
    self.counts[event] = count
    if count == 0 then
        self.frame:UnregisterEvent(event)
    end
    if self.depth > 0 then
        self.dirty = true
    else
        Compact(list)
    end
end

function Dispatcher:UnregisterAll()
    for event in pairs(self.handlers) do
        self:Unregister(event)
    end
end

function Dispatcher:IsRegistered(event)
    return (self.counts[event] or 0) > 0
end

function Dispatcher:Dispatch(event, ...)
    local list = self.handlers[event]
    if not list then
        return
    end
    self.depth = self.depth + 1
    local owner = self.owner
    for i = 1, #list do
        local entry = list[i]
        local fn = entry.fn
        if fn then
            local start = debugprofilestop()
            local ok = SafeCall(fn, event, ...)
            Record(owner, event, debugprofilestop() - start, ok)
        end
    end
    self.depth = self.depth - 1
    if self.depth == 0 and self.dirty then
        self.dirty = false
        for _, l in pairs(self.handlers) do
            Compact(l)
        end
    end
end

--- Number of (dispatcher, event) registrations currently live on frames.
function Events.CountRegistered()
    local n = 0
    for i = 1, #dispatchers do
        for _, count in pairs(dispatchers[i].counts) do
            if count > 0 then
                n = n + 1
            end
        end
    end
    return n
end

--- Live registrations as { {owner, event}, ... } for the perf report.
function Events.ListRegistered()
    local result = {}
    for i = 1, #dispatchers do
        local d = dispatchers[i]
        for event, count in pairs(d.counts) do
            if count > 0 then
                result[#result + 1] = { owner = d.owner, event = event }
            end
        end
    end
    return result
end

-- The core's own dispatcher (lifecycle events live here).
ns.CoreEvents = Events.NewDispatcher("Core")
