if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Perf.lua
-- Always-on, cheap timing statistics per owner (core subsystem or module) and
-- label (WoW event or "bus:EVENT"). Each stat keeps count, total, max, errors and
-- a preallocated ring of the last 128 durations for the p95. The /gob perf report
-- adds Blizzard's addon profiler, memory per addon and the idle state.
local _, ns = ...

local Perf = {}
ns.Perf = Perf

local RING = 128
local stats = {}   -- owner -> label -> stat
local owners = {}  -- registration order of owners

local function NewStat()
    local ring = {}
    for i = 1, RING do ring[i] = 0 end
    return { count = 0, total = 0, max = 0, errors = 0, ring = ring, pos = 0 }
end

--- Record one handler run. ms: duration in milliseconds; ok: false when it raised.
function Perf.Record(owner, label, ms, ok)
    local byOwner = stats[owner]
    if not byOwner then
        byOwner = {}
        stats[owner] = byOwner
        owners[#owners + 1] = owner
    end
    local s = byOwner[label]
    if not s then
        s = NewStat()
        byOwner[label] = s
    end
    s.count = s.count + 1
    s.total = s.total + ms
    if ms > s.max then
        s.max = ms
    end
    if ok == false then
        s.errors = s.errors + 1
    end
    local pos = s.pos % RING + 1
    s.pos = pos
    s.ring[pos] = ms
end

local function P95(s)
    local n = s.count < RING and s.count or RING
    if n == 0 then
        return 0
    end
    local copy = {}
    for i = 1, n do copy[i] = s.ring[i] end
    table.sort(copy)
    return copy[math.ceil(n * 0.95)]
end
Perf.P95 = P95

--- Aggregated view: list of { owner, count, total, max, errors, p95, labels = {...} }
-- sorted by total time, descending. p95 of an owner is the worst label p95.
function Perf.Summary()
    local result = {}
    for i = 1, #owners do
        local owner = owners[i]
        local entry = { owner = owner, count = 0, total = 0, max = 0, errors = 0, p95 = 0, labels = {} }
        for label, s in pairs(stats[owner]) do
            local p = P95(s)
            entry.count = entry.count + s.count
            entry.total = entry.total + s.total
            entry.errors = entry.errors + s.errors
            if s.max > entry.max then entry.max = s.max end
            if p > entry.p95 then entry.p95 = p end
            entry.labels[#entry.labels + 1] = {
                label = label, count = s.count, total = s.total, max = s.max, errors = s.errors, p95 = p,
            }
        end
        table.sort(entry.labels, function(a, b) return a.total > b.total end)
        result[#result + 1] = entry
    end
    table.sort(result, function(a, b) return a.total > b.total end)
    return result
end

function Perf.Get(owner, label)
    return stats[owner] and stats[owner][label]
end

function Perf.Reset()
    for k in pairs(stats) do stats[k] = nil end
    for i = #owners, 1, -1 do owners[i] = nil end
end

--- Idle state for the report: counts of live registrations, timers and jobs.
function Perf.IdleState()
    return {
        events = ns.Events and ns.Events.CountRegistered() or 0,
        subscriptions = ns.Bus and ns.Bus.CountSubscriptions() or 0,
        timers = ns.Timer and ns.Timer.ActiveCount() or 0,
        jobs = ns.Jobs and ns.Jobs.ActiveCount() or 0,
    }
end

-------------------------------------------------------------------------------
-- /gob perf report
-------------------------------------------------------------------------------
local function AddonNames()
    local names, seen = { ns.ADDON_NAME }, { [ns.ADDON_NAME] = true }
    for _, m in ipairs(ns.Modules and ns.Modules.List() or {}) do
        if not m.internal and not seen[m.addon] then
            seen[m.addon] = true
            if not C_AddOns or not C_AddOns.IsAddOnLoaded or C_AddOns.IsAddOnLoaded(m.addon) then
                names[#names + 1] = m.addon
            end
        end
    end
    return names
end

local function Profiler(name)
    local profiler = C_AddOnProfiler
    local metric = Enum and Enum.AddOnProfilerMetric
    if not (profiler and profiler.GetAddOnMetric and metric) then return nil end
    local function get(key)
        return metric[key] and profiler.GetAddOnMetric(name, metric[key]) or 0
    end
    return get("RecentAverageTime"), get("PeakTime"), get("EncounterAverageTime")
end

local function MemoryKB(names)
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not (update and get) then return nil end
    update()
    local result = {}
    for i = 1, #names do
        result[i] = get(names[i]) or 0
    end
    return result
end

--- Lines of the performance report (also used by the spec).
function Perf.ReportLines()
    local L = ns.L
    local lines = {}
    local idle = Perf.IdleState()
    local idleOk = idle.timers == 0 and idle.jobs == 0
    lines[#lines + 1] = ("%s: %d timers, %d jobs, no OnUpdate, %d WoW events, %d bus subscriptions%s"):format(
        L["Idle"], idle.timers, idle.jobs, idle.events, idle.subscriptions, idleOk and " |cff3fbf3fOK|r" or "")
    lines[#lines + 1] = "calls / avg / p95 / max ms / errors"
    for _, entry in ipairs(Perf.Summary()) do
        local avg = entry.count > 0 and entry.total / entry.count or 0
        lines[#lines + 1] = ("%s: %d / %.3f / %.3f / %.3f / %d"):format(
            entry.owner, entry.count, avg, entry.p95, entry.max, entry.errors)
        for i = 1, math.min(3, #entry.labels) do
            local s = entry.labels[i]
            lines[#lines + 1] = ("   %s: %d / %.3f / %.3f"):format(
                s.label, s.count, s.count > 0 and s.total / s.count or 0, s.p95)
        end
    end
    local names = AddonNames()
    for i = 1, #names do
        local recent, peak, encounter = Profiler(names[i])
        if recent then
            lines[#lines + 1] = ("Profiler %s: recent %.3f / peak %.3f / encounter %.3f ms"):format(
                names[i], recent, peak, encounter)
        end
    end
    if InCombatLockdown() then
        lines[#lines + 1] = L["Memory is not measured in combat"]
    else
        local kb = MemoryKB(names)
        if kb then
            local parts = {}
            for i = 1, #names do parts[i] = ("%s %.0f KB"):format(names[i], kb[i]) end
            lines[#lines + 1] = "Memory: " .. table.concat(parts, ", ")
        end
    end
    lines[#lines + 1] = "|cff999999" .. L["Blizzard's profiler bills bus handlers to Goblinomics"] .. "|r"
    return lines
end

function ns.PerfReport(arg)
    if arg == "reset" then
        Perf.Reset()
        ns.Print(ns.L["Performance counters reset"], true)
        return
    end
    for _, line in ipairs(Perf.ReportLines()) do
        ns.Print(line, true)
    end
end
