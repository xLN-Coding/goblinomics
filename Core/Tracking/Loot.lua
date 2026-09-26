if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Tracking/Loot.lua
-- LOOT_RECEIVED stream from the player's own CHAT_MSG_LOOT lines, parsed with the
-- client's GlobalStrings (any locale). Multiple-count patterns are tried before
-- single ones, otherwise the single pattern swallows the "x5". The loot source
-- comes from the loot window (GetLootSourceInfo GUID type, fishing). Every item
-- is recorded as a claim so the bag diff does not report it a second time.
local _, ns = ...

local Loot = {}
ns.Loot = Loot

local Bus, Context, Restriction = ns.Bus, ns.Context, ns.Restriction
local ChatPattern, ItemKey = ns.ChatPattern, ns.ItemKey
local events = ns.Events.NewDispatcher("Core.Loot")
local IsSecret = Restriction.IsSecret

local CLAIM_TTL = 60
local WINDOW_GRACE = 5

-- { GlobalString name, kind override }; order matters (multiple first).
local PATTERNS = {
    { "LOOT_ITEM_SELF_MULTIPLE" },
    { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "push" },
    { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "bonus" },
    { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "craft" },
    { "LOOT_ITEM_SELF" },
    { "LOOT_ITEM_PUSHED_SELF", "push" },
    { "LOOT_ITEM_BONUS_ROLL_SELF", "bonus" },
    { "LOOT_ITEM_CREATED_SELF", "craft" },
}

local GUID_KINDS = { Creature = "creature", Vehicle = "creature", GameObject = "object", Item = "item" }

local sources = {}         -- link -> kind, from the last loot window
local windowOpen = false
local windowClosedAt = -math.huge
local claims = {}          -- itemKey -> { qty, time }
local secretDropped = 0

--- Parse a loot line: link, quantity, kind override (nil|"push"|"bonus"|"craft").
function Loot.Parse(msg)
    if type(msg) ~= "string" then return nil end
    for i = 1, #PATTERNS do
        local fmt = _G[PATTERNS[i][1]]
        if fmt then
            local link, count = ChatPattern.Match(fmt, msg)
            if link then
                return link, tonumber(count) or 1, PATTERNS[i][2]
            end
        end
    end
    return nil
end

local function GuidKind(guid)
    if guid == nil or IsSecret(guid) or type(guid) ~= "string" then
        return "unknown"
    end
    return GUID_KINDS[guid:match("^(%a+)")] or "unknown"
end
Loot.GuidKind = GuidKind

local function OnLootReady()
    for k in pairs(sources) do sources[k] = nil end
    windowOpen = true
    local fishing = IsFishingLoot and IsFishingLoot()
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and not IsSecret(link) then
            sources[link] = fishing and "fishing" or GuidKind((GetLootSourceInfo(slot)))
        end
    end
end

local function OnLootClosed()
    windowOpen = false
    windowClosedAt = GetTime()
end

local function SourceKind(link, override)
    if override == "craft" or override == "bonus" then
        return override
    end
    local fromWindow = sources[link]
    if fromWindow and (windowOpen or GetTime() - windowClosedAt <= WINDOW_GRACE) then
        return fromWindow
    end
    return override or "push"
end

-- Claims ---------------------------------------------------------------------
function Loot.Claim(key, qty)
    local c = claims[key]
    if c then
        c.qty = c.qty + qty
        c.time = GetTime()
    else
        claims[key] = { qty = qty, time = GetTime() }
    end
end

--- Consume up to `amount` claimed units of key; returns the consumed amount.
function Loot.Consume(key, amount)
    local c = claims[key]
    if not c then return 0 end
    if GetTime() - c.time > CLAIM_TTL then
        claims[key] = nil
        return 0
    end
    local used = amount < c.qty and amount or c.qty
    c.qty = c.qty - used
    if c.qty <= 0 then claims[key] = nil end
    return used
end

function Loot.SecretDropped() return secretDropped end

-- Processing -----------------------------------------------------------------
local function Process(msg, guid, t)
    if IsSecret(msg) then
        secretDropped = secretDropped + 1
        return
    end
    if type(guid) == "string" and guid ~= "" and not IsSecret(guid) and guid ~= UnitGUID("player") then
        return
    end
    local link, qty, override = Loot.Parse(msg)
    if not link then return end
    local key = ItemKey.FromLink(link)
    if not key then return end
    Loot.Claim(key, qty)
    Bus.Emit("LOOT_RECEIVED", {
        itemKey = key, link = link, quantity = qty,
        source = { kind = SourceKind(link, override) },
        time = t, context = Context.Snapshot(),
        restricted = Restriction.ReplayKind() or false,
    })
end

local function OnChatLoot(_, msg, ...)
    local guid = select(11, ...)   -- arg 12 of CHAT_MSG_LOOT (msg is arg 1)
    if Restriction.IsActive() then
        Restriction.Buffer("CHAT_MSG_LOOT", msg, guid)
        return
    end
    Process(msg, guid, time())
end

Restriction.RegisterReplay("CHAT_MSG_LOOT", function(msg, guid, t) Process(msg, guid, t) end)

-- The loot claims are also needed by the bag tracker, so "loot" is a dependency
-- of "bags" even when nobody listens to LOOT_RECEIVED.
Bus.DefineService("loot", {
    deps = { "context", "restriction" },
    events = { "LOOT_RECEIVED" },
    start = function()
        events:Register("CHAT_MSG_LOOT", OnChatLoot)
        events:Register("LOOT_READY", OnLootReady)
        events:Register("LOOT_CLOSED", OnLootClosed)
    end,
    stop = function()
        events:UnregisterAll()
        for k in pairs(claims) do claims[k] = nil end
        for k in pairs(sources) do sources[k] = nil end
        windowOpen = false
    end,
})
