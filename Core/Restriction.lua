if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Restriction.lua
-- Restricted mode for boss encounters, Mythic+ and rated PvP (WoW 12.x addon
-- restrictions). Every ADDON_RESTRICTION_STATE_CHANGED (it fires on activation
-- and on lift) re-queries all types; a type counts as active while its state is
-- not Inactive. ENCOUNTER_START / CHALLENGE_MODE_START enter immediately as a
-- hint. The mode ends only when Encounter, ChallengeMode and PvPMatch are
-- inactive AND the Combat restriction has lifted (declassification lags combat).
--
-- While active: no core bus events, no UI updates, no bag scans. Trackers call
-- Restriction.Buffer(event, value, extra) which appends to a ring buffer; secret
-- values are stored as a marker (they stay opaque forever). On leave a job replays
-- the buffer through the trackers' replay handlers, runs the leave callbacks
-- (money reconciliation, bag diff) and then emits RESTRICTED_LEAVE.
local _, ns = ...

local Restriction = {}
ns.Restriction = Restriction

local Bus = ns.Bus
local events = ns.Events.NewDispatcher("Core.Restriction")

local CAPACITY = 512
local SECRET = {}   -- marker for secret payloads in the buffer
Restriction.SECRET = SECRET

local buffer = ns.RingBuffer.New(CAPACITY)
local replayBuffer = ns.RingBuffer.New(CAPACITY)
local replayHandlers = {}   -- event -> fn(value, extra, time)
local leaveCallbacks = {}   -- fn(kind)

local active = false
local kind = nil
local enteredAt = 0
local replayKind = nil      -- kind while the replay job runs
local pendingLeave = false
local hintEncounter, hintChallenge = false, false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
Restriction.IsSecret = IsSecret

function Restriction.IsActive()
    return active
end

--- Kind of the restriction being replayed right now ("challenge", ...), else nil.
function Restriction.ReplayKind()
    return replayKind
end

function Restriction.Kind()
    return kind
end

--- Trackers: handler for buffered entries of an event, fn(value, extra, time).
function Restriction.RegisterReplay(event, fn)
    replayHandlers[event] = fn
end

--- Trackers: callback after the replay, fn(kind). Runs in registration order.
function Restriction.OnLeave(fn)
    leaveCallbacks[#leaveCallbacks + 1] = fn
end

function Restriction.Buffer(event, value, extra)
    if IsSecret(value) then value = SECRET end
    if IsSecret(extra) then extra = SECRET end
    buffer:Push(time(), event, value, extra)
end

local function TypeActive(name)
    local types = Enum and Enum.AddOnRestrictionType
    local t = types and types[name]
    local api = C_RestrictedActions
    if t == nil or not api then
        return false
    end
    if api.GetAddOnRestrictionState then
        local state = api.GetAddOnRestrictionState(t)
        local inactive = Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
        return state ~= nil and state ~= inactive
    end
    if api.IsAddOnRestrictionActive then
        return api.IsAddOnRestrictionActive(t) == true
    end
    return false
end

local function CurrentKind()
    if hintChallenge or TypeActive("ChallengeMode") then return "challenge" end
    if hintEncounter or TypeActive("Encounter") then return "encounter" end
    if TypeActive("PvPMatch") then return "pvp" end
    return nil
end

local Leave

local function Enter(newKind)
    active = true
    kind = newKind
    enteredAt = GetTime()
    if ns.Context then ns.Context.Set("restricted", true) end
    events:Register("PLAYER_REGEN_ENABLED", Restriction.Evaluate, "eval")
    events:Register("PLAYER_ENTERING_WORLD", Restriction.Evaluate, "eval")
    Bus.Emit("RESTRICTED_ENTER", { kind = newKind, time = time() })
end

function Restriction.Evaluate()
    local k = CurrentKind()
    if k then
        if not active then
            Enter(k)
        elseif k == "challenge" then
            kind = k
        end
    elseif active and not TypeActive("Combat") then
        Leave()
    end
end

local function Replay()
    local stats = { buffered = replayBuffer:Count(), secret = 0, overflow = replayBuffer.overflow }
    for i = 1, replayBuffer:Count() do
        local t, event, value, extra = replayBuffer:Get(i)
        if value == SECRET or extra == SECRET then
            stats.secret = stats.secret + 1
        else
            local fn = replayHandlers[event]
            if fn then
                ns.SafeCall(fn, value, extra, t)
            end
        end
        ns.Jobs.Yield()
    end
    for i = 1, #leaveCallbacks do
        ns.SafeCall(leaveCallbacks[i], replayKind)
    end
    return stats
end

Leave = function()
    if replayKind then
        pendingLeave = true   -- a replay is still running; leave after it
        active = false
        return
    end
    local leftKind = kind
    local duration = GetTime() - enteredAt
    active, kind = false, nil
    events:Unregister("PLAYER_REGEN_ENABLED", "eval")
    events:Unregister("PLAYER_ENTERING_WORLD", "eval")
    buffer, replayBuffer = replayBuffer, buffer
    replayKind = leftKind
    ns.Jobs.Run("Core.Restriction", "replay", function()
        local stats = Replay()
        replayBuffer:Clear()
        replayKind = nil
        if ns.Context then ns.Context.Set("restricted", false) end
        Bus.Emit("RESTRICTED_LEAVE", {
            kind = leftKind, time = time(), duration = duration,
            buffered = stats.buffered, secret = stats.secret, overflow = stats.overflow,
        })
        if pendingLeave then
            pendingLeave = false
            Leave()
        end
    end)
    ns.Jobs.Resume()
end

local function OnRestrictionChanged()
    Restriction.Evaluate()
end

local function OnEncounterStart()
    hintEncounter = true
    Restriction.Evaluate()
end

local function OnEncounterEnd()
    hintEncounter = false
    Restriction.Evaluate()
end

local function OnChallengeStart()
    hintChallenge = true
    Restriction.Evaluate()
end

local function OnChallengeEnd()
    hintChallenge = false
    Restriction.Evaluate()
end

Bus.DefineService("restriction", {
    events = { "RESTRICTED_ENTER", "RESTRICTED_LEAVE" },
    start = function()
        events:Register("ADDON_RESTRICTION_STATE_CHANGED", OnRestrictionChanged)
        events:Register("ENCOUNTER_START", OnEncounterStart)
        events:Register("ENCOUNTER_END", OnEncounterEnd)
        events:Register("CHALLENGE_MODE_START", OnChallengeStart)
        events:Register("CHALLENGE_MODE_COMPLETED", OnChallengeEnd)
        events:Register("CHALLENGE_MODE_RESET", OnChallengeEnd)
        Restriction.Evaluate()
    end,
    stop = function()
        events:UnregisterAll()
        hintEncounter, hintChallenge = false, false
    end,
})

function ns.API.IsRestricted()
    return active
end
