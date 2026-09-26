if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/Remote.lua
-- Other WoW accounts (M8, Link): read-only snapshots imported from a Link
-- string, root.remote[account] = { label, seenAt, chars = { [charKey] = { name,
-- class, gold, wealth } }, warband = { gold, wealth }, history = { [day] =
-- wealth } }. The newest snapshot (seenAt) wins. Their gold and wealth are added
-- to the networth (result.remote); daily history entries keep the remote parts
-- in h.remote[account] so exports never pass another account's wealth on and a
-- removed account can be taken out again.
local _, ns = ...

local Remote = {}
ns.Remote = Remote

--- A stable id of this account (random, created once).
function Remote.AccountId(root)
    if type(root.accountId) ~= "string" then
        root.accountId = ("%08x%08x"):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    end
    return root.accountId
end

local function Totals(snap)
    local gold, wealth = 0, 0
    for _, c in pairs(snap.chars or {}) do
        gold, wealth = gold + (c.gold or 0), wealth + (c.wealth or 0)
    end
    local wb = snap.warband or {}
    return gold + (wb.gold or 0), wealth + (wb.wealth or 0)
end
Remote.Totals = Totals

--- { gold, wealth, accounts = { { id, label, seenAt, gold, wealth, chars } } } over all remote accounts.
function Remote.Sum(root)
    local sum = { gold = 0, wealth = 0, accounts = {} }
    for id, snap in pairs(root.remote or {}) do
        local gold, wealth = Totals(snap)
        sum.gold, sum.wealth = sum.gold + gold, sum.wealth + wealth
        local n = 0
        for _ in pairs(snap.chars or {}) do n = n + 1 end
        sum.accounts[#sum.accounts + 1] = { id = id, label = snap.label or id, seenAt = snap.seenAt, gold = gold,
            wealth = wealth, chars = n }
    end
    table.sort(sum.accounts, function(a, b) return a.label < b.label end)
    return sum
end

--- Local part of a history entry (without other accounts).
function Remote.LocalWealth(h)
    local w = h.wealth or 0
    for _, part in pairs(h.remote or {}) do w = w - part end
    return w
end

local function ApplyHistory(root, id, history, sign)
    for day, w in pairs(history or {}) do
        local h = root.history[day]
        if type(h) == "table" and type(w) == "number" then
            h.remote = h.remote or {}
            if sign > 0 and not h.remote[id] then
                h.remote[id] = w
                h.wealth = (h.wealth or 0) + w
            elseif sign < 0 and h.remote[id] then
                h.wealth = (h.wealth or 0) - h.remote[id]
                h.remote[id] = nil
                if next(h.remote) == nil then h.remote = nil end
            end
        end
    end
end

--- Store a snapshot; returns true, or false and a reason ("own", "older").
function Remote.Set(root, snap)
    if snap.account == Remote.AccountId(root) then return false, "own" end
    root.remote = root.remote or {}
    local old = root.remote[snap.account]
    if old and (old.seenAt or 0) >= (snap.seenAt or 0) then return false, "older" end
    if old then ApplyHistory(root, snap.account, old.history, -1) end
    root.remote[snap.account] = { label = snap.label, seenAt = snap.seenAt, chars = snap.chars or {},
        warband = snap.warband or {}, history = snap.history or {} }
    ApplyHistory(root, snap.account, snap.history, 1)
    return true
end

function Remote.Remove(root, id)
    local old = root.remote and root.remote[id]
    if not old then return false end
    ApplyHistory(root, id, old.history, -1)
    root.remote[id] = nil
    return true
end

--- Snapshot of this account for a Link string (local values only).
function Remote.Snapshot(root, result, label)
    local snap = { account = Remote.AccountId(root), label = label, seenAt = time(), chars = {}, history = {} }
    for charKey, c in pairs(result and result.chars or {}) do
        snap.chars[charKey] = { name = c.name, class = c.class, gold = c.gold, wealth = c.wealth }
    end
    local wb = result and result.warband or {}
    snap.warband = { gold = wb.gold or 0, wealth = wb.wealth or 0 }
    for day, h in pairs(root.history or {}) do
        if type(h) == "table" and h.wealth then snap.history[day] = Remote.LocalWealth(h) end
    end
    return snap
end
