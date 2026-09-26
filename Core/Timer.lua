if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Timer.lua
-- Tracked timers and budgeted jobs.
--   Timer.After(sec, fn, owner)   C_Timer.After with a live counter and owner cancel
--   Timer.Debounce(key, sec, fn)  runs fn once per burst of calls
--   Jobs.Run(owner, name, fn)     coroutine continued through a C_Timer.After(0)
--                                 chain with a 2 ms budget per frame; no OnUpdate
--   Jobs.Yield()                  yield point inside a job, yields only when the
--                                 frame budget is used up
-- Jobs pause in combat and in the restricted mode and resume afterwards.
local _, ns = ...

local Timer, Jobs = {}, {}
ns.Timer, ns.Jobs = Timer, Jobs

local SafeCall = ns.SafeCall
local debugprofilestop = debugprofilestop

-------------------------------------------------------------------------------
-- Timers
-------------------------------------------------------------------------------
local active = 0
local generation = {}   -- owner -> number; bumping it cancels pending timers
local pending = {}      -- debounce keys

function Timer.After(sec, fn, owner)
    owner = owner or "core"
    local gen = generation[owner] or 0
    active = active + 1
    C_Timer.After(sec, function()
        active = active - 1
        if (generation[owner] or 0) == gen then
            SafeCall(fn)
        end
    end)
end

function Timer.Debounce(key, sec, fn, owner)
    if pending[key] then
        return
    end
    pending[key] = true
    Timer.After(sec, function()
        pending[key] = nil
        fn()
    end, owner)
end

function Timer.CancelOwner(owner)
    generation[owner] = (generation[owner] or 0) + 1
    for key in pairs(pending) do
        if type(key) == "string" and key:find(owner .. ":", 1, true) == 1 then
            pending[key] = nil
        end
    end
end

function Timer.ActiveCount()
    return active
end

-------------------------------------------------------------------------------
-- Jobs
-------------------------------------------------------------------------------
Jobs.BUDGET_MS = 2

local queue = {}
local scheduled = false
local deadline = 0
local waitingForCombatEnd = false

local function Paused()
    return (InCombatLockdown and InCombatLockdown()) or (ns.Restriction and ns.Restriction.IsActive())
end

local Step

local function Schedule()
    if scheduled then
        return
    end
    scheduled = true
    C_Timer.After(0, Step)
end

local function OnCombatEnd()
    waitingForCombatEnd = false
    ns.CoreEvents:Unregister("PLAYER_REGEN_ENABLED", "Jobs")
    Schedule()
end

local function Finish(index, job)
    table.remove(queue, index)
    if job.onDone then
        SafeCall(job.onDone)
    end
end

Step = function()
    scheduled = false
    if #queue == 0 then
        return
    end
    if Paused() then
        if InCombatLockdown and InCombatLockdown() and not waitingForCombatEnd then
            waitingForCombatEnd = true
            ns.CoreEvents:Register("PLAYER_REGEN_ENABLED", OnCombatEnd, "Jobs")
        end
        return   -- restricted mode resumes through Jobs.Resume()
    end
    deadline = debugprofilestop() + Jobs.BUDGET_MS
    while #queue > 0 and debugprofilestop() < deadline do
        local job = queue[1]
        local start = debugprofilestop()
        local ok, err = coroutine.resume(job.co)
        ns.Perf.Record(job.owner, job.label, debugprofilestop() - start, ok)
        if not ok then
            ns.errorhandler(tostring(err) .. "\n" .. (debugstack and debugstack(job.co) or ""))
            table.remove(queue, 1)
        elseif coroutine.status(job.co) == "dead" then
            Finish(1, job)
        end
    end
    if #queue > 0 then
        Schedule()
    end
end

--- Start a job. fn runs inside a coroutine and should call Jobs.Yield() regularly.
function Jobs.Run(owner, name, fn, onDone)
    queue[#queue + 1] = {
        owner = owner, name = name, label = "job:" .. name, co = coroutine.create(fn), onDone = onDone,
    }
    Schedule()
end

--- Yield when the frame budget is used up. No-op outside a job.
function Jobs.Yield()
    if coroutine.running() and debugprofilestop() >= deadline then
        coroutine.yield()
    end
end

function Jobs.Resume()
    if #queue > 0 then
        Schedule()
    end
end

function Jobs.CancelOwner(owner)
    for i = #queue, 1, -1 do
        if queue[i].owner == owner then
            table.remove(queue, i)
        end
    end
end

function Jobs.ActiveCount()
    return #queue
end

-- Public: yield point for module jobs (module:RunJob).
ns.API.Yield = Jobs.Yield
