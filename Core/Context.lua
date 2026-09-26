if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Context.lua
-- Which windows and states are open right now, plus short-lived markers that
-- modules use for "hook, then confirm" attribution (e.g. Ledger marks `repair`
-- when RepairAllItems is called). Snapshots are fresh tables attached to deltas.
--
-- Interaction types are resolved by NAME from Enum.PlayerInteractionType at
-- runtime; names the client does not know are skipped.
local _, ns = ...

local Context = {}
ns.Context = Context

local Bus = ns.Bus
local events = ns.Events.NewDispatcher("Core.Context")

local INTERACTIONS = {
    Merchant = "merchant", MailInfo = "mail", Auctioneer = "auction", Banker = "bank",
    AccountBanker = "warbank", GuildBanker = "guildbank", Trainer = "trainer", TaxiNode = "taxi",
    ItemUpgrade = "upgrade", Transmogrifier = "transmog", Barber = "barber",
    ProfessionsCustomerOrder = "craftingOrder",
}
-- Priority for the one-word label of a snapshot (debug output, UI).
local PRIORITY = {
    "restricted", "merchant", "mail", "auction", "trade", "warbank", "bank", "guildbank", "loot",
    "craft", "craftingOrder", "quest", "trainer", "taxi", "upgrade", "transmog", "barber",
}

local open = {}
local marks = {}
local closedAt = {}   -- key -> GetTime() when the window closed
-- Many windows close before the client books the money (autoloot, taxi map), so a
-- snapshot also lists windows closed within the last RECENT seconds.
local RECENT = 2
Context.RECENT = RECENT
local byType = nil   -- enum value -> key

local function BuildTypeMap()
    byType = {}
    local enum = Enum and Enum.PlayerInteractionType
    if not enum then return end
    for name, key in pairs(INTERACTIONS) do
        local value = enum[name]
        if value ~= nil then
            byType[value] = key
        end
    end
end

--- Set a context key; emits CONTEXT_CHANGED on change.
function Context.Set(key, on)
    on = on and true or nil
    if open[key] == on then
        return
    end
    open[key] = on
    if not on then closedAt[key] = GetTime() end
    Bus.Emit("CONTEXT_CHANGED", { key = key, active = on == true })
end

function Context.IsOpen(key)
    return open[key] == true
end

--- Remember a marker for ttl seconds (default 3). data is optional.
function Context.Mark(name, data, ttl)
    marks[name] = { time = GetTime(), data = data == nil and true or data, ttl = ttl or 3 }
end

--- Fresh snapshot: { merchant = true, ..., marks = { name = data } or nil,
-- recent = { key = true } (closed within RECENT seconds) or nil, restricted = kind }
function Context.Snapshot()
    local s = {}
    for k in pairs(open) do
        s[k] = true
    end
    local now = GetTime()
    local m
    for name, mark in pairs(marks) do
        if now - mark.time <= mark.ttl then
            m = m or {}
            m[name] = mark.data
        else
            marks[name] = nil
        end
    end
    s.marks = m
    local recent
    for key, t in pairs(closedAt) do
        if now - t <= RECENT then
            if not open[key] then
                recent = recent or {}
                recent[key] = true
            end
        else
            closedAt[key] = nil
        end
    end
    s.recent = recent
    local R = ns.Restriction
    local rk = R and (R.ReplayKind() or (R.IsActive() and R.Kind()))
    if rk then
        s.restricted = rk
    else
        s.restricted = nil
    end
    return s
end

--- One-word label for a snapshot ("merchant", "loot", ...), or nil.
function Context.Label(snapshot)
    for i = 1, #PRIORITY do
        if snapshot[PRIORITY[i]] then
            return PRIORITY[i]
        end
    end
    if snapshot.marks then
        return (next(snapshot.marks))
    end
    return nil
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function OnInteraction(event, interactionType)
    if IsSecret(interactionType) then return end
    local key = byType[interactionType]
    if key then
        Context.Set(key, event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    end
end

local SIMPLE = {
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
    LOOT_READY = { "loot", true }, LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false },
    TRADE_SKILL_SHOW = { "craft", true }, TRADE_SKILL_CLOSE = { "craft", false },
    QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
}

local function OnSimple(event)
    local entry = SIMPLE[event]
    Context.Set(entry[1], entry[2])
end

local function OnMoneyChat(_, msg)
    if not IsSecret(msg) then
        Context.Mark("lootMoney")
    end
end

local function OnQuestTurnedIn(_, questID, _, money)
    if IsSecret(questID) or IsSecret(money) then return end
    Context.Mark("questReward", { questID = questID, money = money })
end

Bus.DefineService("context", {
    events = { "CONTEXT_CHANGED" },
    start = function()
        if not byType then BuildTypeMap() end
        events:Register("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", OnInteraction)
        events:Register("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", OnInteraction)
        for event in pairs(SIMPLE) do
            events:Register(event, OnSimple)
        end
        events:Register("CHAT_MSG_MONEY", OnMoneyChat)
        events:Register("QUEST_TURNED_IN", OnQuestTurnedIn)
    end,
    stop = function()
        events:UnregisterAll()
        for k in pairs(open) do open[k] = nil end
        for k in pairs(closedAt) do closedAt[k] = nil end
    end,
})

-- Public: Goblinomics.API.v1.Context() returns a snapshot; :Mark(...) sets a marker.
ns.API.Context = setmetatable({
    Mark = function(_, name, data, ttl) return Context.Mark(name, data, ttl) end,
    Snapshot = function() return Context.Snapshot() end,
    IsOpen = function(_, key) return Context.IsOpen(key) end,
}, {
    __call = function() return Context.Snapshot() end,
})
