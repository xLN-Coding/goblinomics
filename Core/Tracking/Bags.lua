if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Tracking/Bags.lua
-- ITEMS_DELTA stream from the carried bags (backpack, bags 1-4, reagent bag).
-- BAG_UPDATE marks a bag dirty and schedules a scan for the next frame (on Retail
-- BAG_UPDATE_DELAYED does not fire for every bag). Slots whose item info is not
-- loaded yet, or that report count 0 (item going away), keep their old state and
-- the bag is rescanned shortly after. Scans wait for combat end and for the end
-- of the restricted mode. Positive deltas are netted against loot claims; the
-- rest is emitted. No delta is emitted until one complete baseline scan exists.
local _, ns = ...

local Bags = {}
ns.Bags = Bags

local Bus, Context, Restriction, Timer, Loot = ns.Bus, ns.Context, ns.Restriction, ns.Timer, ns.Loot
local ItemKey = ns.ItemKey
local events = ns.Events.NewDispatcher("Core.Bags")
local OWNER = "Core.Bags"
local RETRY_DELAY = 0.5

local carried = nil      -- list of bag ids
local isCarried = {}
local slotKey, slotCount, slotBound = {}, {}, {}   -- [bag][slot]
local totals = {}                    -- itemKey -> count
local boundTotals = {}               -- itemKey -> count of bound units
local links = {}                     -- itemKey -> last seen hyperlink
local linkCache = {}                 -- hyperlink -> itemKey
local dirty = {}
local baseline = false
local scratch = {}
local waitingForCombat = false

local function BuildBagList()
    local e = Enum and Enum.BagIndex
    if e and e.Backpack then
        carried = { e.Backpack, e.Bag_1, e.Bag_2, e.Bag_3, e.Bag_4, e.ReagentBag }
    else
        carried = { 0, 1, 2, 3, 4, 5 }
    end
    for i = 1, #carried do
        isCarried[carried[i]] = true
    end
end

local function ApplyBound(key, delta)
    local n = (boundTotals[key] or 0) + delta
    boundTotals[key] = n > 0 and n or nil
end

local function ScanBag(bag, deltas)
    local keys = slotKey[bag]
    local counts = slotCount[bag]
    local bounds = slotBound[bag]
    if not keys then
        keys, counts, bounds = {}, {}, {}
        slotKey[bag], slotCount[bag], slotBound[bag] = keys, counts, bounds
    end
    local numSlots = C_Container.GetContainerNumSlots(bag) or 0
    local complete = true
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local key, count, bound = nil, 0, nil
        if info then
            count = info.stackCount or 0
            bound = ns.Binding.IsBound(info, bag, slot) or nil
            local link = info.hyperlink
            if count == 0 or not info.itemID or not link then
                complete = false
                key, count, bound = keys[slot], counts[slot] or 0, bounds[slot]
            else
                key = linkCache[link]
                if not key then
                    key = ItemKey.FromLink(link)
                    linkCache[link] = key
                end
                if key then links[key] = link else count = 0 end
            end
        end
        if not key then bound = nil end
        local oldKey, oldCount, oldBound = keys[slot], counts[slot] or 0, bounds[slot]
        if oldKey ~= key or oldCount ~= count or oldBound ~= bound then
            if oldKey then
                deltas[oldKey] = (deltas[oldKey] or 0) - oldCount
                if oldBound then ApplyBound(oldKey, -oldCount) end
            end
            if key then
                deltas[key] = (deltas[key] or 0) + count
                if bound then ApplyBound(key, count) end
            end
            keys[slot] = key
            counts[slot] = key and count or nil
            bounds[slot] = bound
        end
    end
    for slot, oldKey in pairs(keys) do
        if slot > numSlots then
            deltas[oldKey] = (deltas[oldKey] or 0) - (counts[slot] or 0)
            if bounds[slot] then ApplyBound(oldKey, -(counts[slot] or 0)) end
            keys[slot], counts[slot], bounds[slot] = nil, nil, nil
        end
    end
    return complete
end

local Schedule

local function OnCombatEnd()
    waitingForCombat = false
    events:Unregister("PLAYER_REGEN_ENABLED", "combat")
    Schedule()
end

local function Flush()
    if Restriction.IsActive() then
        return   -- the restricted mode flushes on leave
    end
    if InCombatLockdown() then
        if not waitingForCombat then
            waitingForCombat = true
            events:Register("PLAYER_REGEN_ENABLED", OnCombatEnd, "combat")
        end
        return
    end
    for k in pairs(scratch) do scratch[k] = nil end
    local incomplete = false
    for bag in pairs(dirty) do
        dirty[bag] = nil
        if not ScanBag(bag, scratch) then
            dirty[bag] = true
            incomplete = true
        end
    end
    local changes
    for key, d in pairs(scratch) do
        if d ~= 0 then
            local total = (totals[key] or 0) + d
            totals[key] = total ~= 0 and total or nil
            if baseline then
                local rest = d
                if d > 0 then
                    rest = d - Loot.Consume(key, d)
                end
                if rest ~= 0 then
                    changes = changes or {}
                    changes[#changes + 1] = { itemKey = key, link = links[key], delta = rest }
                end
            end
        end
    end
    if not incomplete then
        baseline = true
    end
    if changes then
        Bus.Emit("ITEMS_DELTA", {
            changes = changes, time = time(), context = Context.Snapshot(),
            restricted = Restriction.ReplayKind() or false,
        })
    end
    if incomplete then
        Timer.After(RETRY_DELAY, Schedule, OWNER)
    end
end
Bags.Flush = Flush

Schedule = function()
    Timer.Debounce(OWNER .. ":flush", 0, Flush, OWNER)
end

local function OnBagUpdate(_, bag)
    if isCarried[bag] then
        dirty[bag] = true
        Schedule()
    end
end

local function MarkAllDirty()
    for i = 1, #carried do
        dirty[carried[i]] = true
    end
end

Restriction.OnLeave(function()
    if Bus.IsServiceActive("bags") then
        Flush()
    end
end)

function Bags.GetCount(key)
    return totals[key] or 0
end

function Bags.HasBaseline()
    return baseline
end

--- Copy of the carried-bag inventory: { items = {key = n}, bound = {key = n}, links = {key = link} }.
-- nil until a complete baseline scan exists.
function Bags.Snapshot()
    if not baseline then return nil end
    local items, bound, linksOut = {}, {}, {}
    for key, n in pairs(totals) do
        items[key] = n
        linksOut[key] = links[key]
    end
    for key, n in pairs(boundTotals) do
        bound[key] = n
    end
    return { items = items, bound = bound, links = linksOut }
end

ns.API.Bags = {
    Snapshot = function() return Bags.Snapshot() end,
    GetCount = function(_, key) return Bags.GetCount(key) end,
    HasBaseline = function() return Bags.HasBaseline() end,
    IsBound = function(_, info, bag, slot) return ns.Binding.IsBound(info, bag, slot) end,
    IsWarboundType = function(_, item) return ns.Binding.IsWarboundType(item) end,
}

Bus.DefineService("bags", {
    deps = { "context", "restriction", "loot" },
    events = { "ITEMS_DELTA" },
    start = function()
        if not carried then BuildBagList() end
        baseline = false
        MarkAllDirty()
        events:Register("BAG_UPDATE", OnBagUpdate)
        events:Register("BAG_UPDATE_DELAYED", Schedule)
        if IsLoggedIn() then
            Schedule()
        end
    end,
    stop = function()
        events:UnregisterAll()
        Timer.CancelOwner(OWNER)
        waitingForCombat = false
        for k in pairs(slotKey) do slotKey[k] = nil end
        for k in pairs(slotCount) do slotCount[k] = nil end
        for k in pairs(slotBound) do slotBound[k] = nil end
        for k in pairs(totals) do totals[k] = nil end
        for k in pairs(boundTotals) do boundTotals[k] = nil end
        for k in pairs(dirty) do dirty[k] = nil end
        baseline = false
    end,
})
