if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Tasks.lua
-- The task catalog (root.tasks, account-wide) and the state of a task per character.
--   task    { id, kind, name, ref, frequency, value, duration, measured = { value, n,
--             minutes, m }, source, pinned, hidden, note }
--           kind: quest | instance | worldboss | delve | patron | profession
--           source: learned | preset | imported | manual
--   value   copper (a user value wins over the measured average, then the preset)
--   duration minutes (user value, measured average, else the default of the kind)
-- A task is done for a character while the stored completion's resetAt lies ahead;
-- after the reset it counts as open again without logging in.
local _, ns = ...

local Tasks = {}
ns.Tasks = Tasks

local SAMPLES = 10   -- measured averages follow the last ten runs

local function Root() return ns.Routines.db.root end
local function Settings() return ns.Routines.db.settings end

function Tasks.Get(id) return Root().tasks[id] end

--- Add a task or update what the game knows about it (name, ref, frequency).
-- The user's choices (pinned, hidden, value, duration, note) are kept.
function Tasks.Learn(spec)
    local tasks = Root().tasks
    local t = tasks[spec.id]
    if not t then
        t = { id = spec.id, kind = spec.kind, source = spec.source or "learned" }
        tasks[spec.id] = t
    end
    t.name = spec.name or t.name
    t.ref = spec.ref or t.ref
    t.frequency = spec.frequency or t.frequency
    t.icon = spec.icon or t.icon
    if spec.preset then t.preset = spec.preset end
    return t
end

function Tasks.Pin(id, on)
    local t = Tasks.Get(id)
    if not t then return end
    t.pinned = on and true or nil
    if on then t.hidden = nil end
    ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
end

--- Ignore a suggestion: it leaves the suggestions and the routine.
function Tasks.Hide(id, on)
    local t = Tasks.Get(id)
    if not t then return end
    t.hidden = on and true or nil
    if on then t.pinned = nil end
    ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
end

--- Edit the user fields: value (copper, nil = measured), duration (minutes), note.
function Tasks.Edit(id, fields)
    local t = Tasks.Get(id)
    if not t then return end
    t.value, t.duration, t.note = fields.value, fields.duration, fields.note
    ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
end

-- Measurements ------------------------------------------------------------------------------
local function Average(avg, n, x)
    n = math.min((n or 0) + 1, SAMPLES)
    if not avg then return x, n end
    return avg + (x - avg) / n, n
end

--- Add one measured run: value in copper and/or minutes.
function Tasks.Measure(t, value, minutes)
    t.measured = t.measured or {}
    local m = t.measured
    if value then m.value, m.n = Average(m.value, m.n, value) end
    if minutes then m.minutes, m.m = Average(m.minutes, m.m, minutes) end
end

--- Effective value (copper) and duration (minutes) of a task, and where they come from.
function Tasks.Estimate(t, settings)
    settings = settings or Settings()
    local m = t.measured or {}
    local value, valueSource
    if t.value then value, valueSource = t.value, "manual"
    elseif m.value then value, valueSource = m.value, "measured"
    elseif t.preset and t.preset.value then value, valueSource = t.preset.value, "preset"
    else value, valueSource = 0, "none" end
    local minutes, minutesSource
    if t.duration then minutes, minutesSource = t.duration, "manual"
    elseif m.minutes then minutes, minutesSource = m.minutes, "measured"
    elseif t.preset and t.preset.duration then minutes, minutesSource = t.preset.duration, "preset"
    else minutes, minutesSource = (settings.durations or {})[t.kind] or 10, "default" end
    minutes = math.max(1, minutes)
    return value, minutes, valueSource, minutesSource
end

--- Gold per minute (copper).
function Tasks.PerMinute(t, settings)
    local value, minutes = Tasks.Estimate(t, settings)
    return value / minutes
end

-- State per character -------------------------------------------------------------------------
--- Record a completion for a character until resetAt.
function Tasks.MarkDone(charKey, id, resetAt, now)
    local c = Root().chars[charKey]
    if type(c) ~= "table" then return end
    c.done = c.done or {}
    c.done[id] = { at = now or time(), resetAt = resetAt }
end

function Tasks.ClearDone(charKey, id)
    local c = Root().chars[charKey]
    if type(c) == "table" and c.done then c.done[id] = nil end
end

local function Matches(lock, ref)
    if ref.mapID and lock.mapID then return lock.mapID == ref.mapID end
    return type(lock.name) == "string" and type(ref.name) == "string" and lock.name:lower() == ref.name:lower()
end

--- State of a task for a character at time now: done (bool), detail text or nil,
-- resetAt or nil. Kinds without own state here ask the part that knows them.
function Tasks.State(t, charKey, now)
    now = now or time()
    local c = Root().chars[charKey]
    if type(c) ~= "table" then return false end
    local done = c.done and c.done[t.id]
    if done and done.resetAt and done.resetAt > now then return true, nil, done.resetAt end
    local ref = t.ref
    if t.kind == "instance" and type(ref) == "table" then
        for _, lock in ipairs(c.lockouts or {}) do
            if (lock.resetAt or 0) > now and Matches(lock, ref)
                and (not ref.difficultyID or lock.difficultyID == ref.difficultyID) then
                local cleared = lock.encounters and (lock.progress or 0) >= lock.encounters
                return cleared == true, lock.encounters and ((lock.progress or 0) .. "/" .. lock.encounters) or nil,
                    lock.resetAt
            end
        end
    elseif t.kind == "worldboss" and type(ref) == "table" then
        for _, boss in ipairs(c.worldBosses or {}) do
            if (boss.resetAt or 0) > now and ((ref.id and boss.id == ref.id) or boss.name == ref.name) then
                return true, nil, boss.resetAt
            end
        end
    elseif ns.Activities and ns.Activities.State then
        local activityDone, detail, resetAt = ns.Activities.State(t, c, now)
        if activityDone ~= nil then return activityDone, detail, resetAt end
    end
    return false
end

-- Lists -----------------------------------------------------------------------------------
local function Visible(charKey)
    local hidden = Settings().hiddenChars or {}
    return not hidden[charKey]
end

--- The routine of a character: pinned tasks with state and estimate, open first,
-- then by gold per minute. { { task, done, detail, resetAt, value, minutes, perMinute } }
function Tasks.Routine(charKey, now)
    now = now or time()
    local out = {}
    for _, t in pairs(Root().tasks) do
        if t.pinned and not t.hidden then
            local done, detail, resetAt = Tasks.State(t, charKey, now)
            local value, minutes, valueSource, minutesSource = Tasks.Estimate(t)
            out[#out + 1] = { task = t, done = done, detail = detail, resetAt = resetAt, value = value,
                minutes = minutes, perMinute = value / minutes, valueSource = valueSource, minutesSource = minutesSource }
        end
    end
    table.sort(out, function(a, b)
        if a.done ~= b.done then return not a.done end
        if a.perMinute ~= b.perMinute then return a.perMinute > b.perMinute end
        return (a.task.name or "") < (b.task.name or "")
    end)
    return out
end

--- Open value and minutes of a routine list.
function Tasks.Totals(list)
    local value, minutes, open = 0, 0, 0
    for _, e in ipairs(list) do
        if not e.done then value, minutes, open = value + e.value, minutes + e.minutes, open + 1 end
    end
    return value, minutes, open
end

--- Suggestions: tasks that are neither pinned nor hidden, by gold per minute.
function Tasks.Suggestions()
    local out = {}
    for _, t in pairs(Root().tasks) do
        if not t.pinned and not t.hidden then
            local value, minutes = Tasks.Estimate(t)
            out[#out + 1] = { task = t, value = value, minutes = minutes, perMinute = value / minutes }
        end
    end
    table.sort(out, function(a, b)
        if a.perMinute ~= b.perMinute then return a.perMinute > b.perMinute end
        return (a.task.name or "") < (b.task.name or "")
    end)
    return out
end

--- Characters to show (not hidden), the logged-in one first, then by name.
function Tasks.Characters()
    local list = {}
    local me = ns.Routines.CharKey()
    for charKey, c in pairs(Root().chars) do
        if type(c) == "table" and Visible(charKey) then list[#list + 1] = { key = charKey, name = c.name, class = c.class } end
    end
    table.sort(list, function(a, b)
        if (a.key == me) ~= (b.key == me) then return a.key == me end
        return a.key < b.key
    end)
    return list
end

--- Overview: per pinned task, on how many characters it is still open and the value left.
function Tasks.Overview(now)
    now = now or time()
    local chars = Tasks.Characters()
    local out = {}
    for _, t in pairs(Root().tasks) do
        if t.pinned and not t.hidden then
            local value, minutes = Tasks.Estimate(t)
            local open = 0
            for _, ch in ipairs(chars) do
                if not Tasks.State(t, ch.key, now) then open = open + 1 end
            end
            out[#out + 1] = { task = t, open = open, count = #chars, value = value * open, minutes = minutes * open,
                perMinute = value / minutes }
        end
    end
    table.sort(out, function(a, b)
        if a.perMinute ~= b.perMinute then return a.perMinute > b.perMinute end
        return (a.task.name or "") < (b.task.name or "")
    end)
    return out
end
