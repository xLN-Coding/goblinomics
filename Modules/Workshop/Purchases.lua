if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Purchases.lua
-- Purchase lots { key, qty, unit, time, source } from the Ledger's auction
-- house purchases and vendor purchases (reagents cost what was paid).
-- Crafts, salvage and auction resales take the oldest lots first, account-wide;
-- lots older than PURCHASE_DAYS no longer count (items may have been mailed away
-- or destroyed), the rest is valued at market price. Without the Ledger module
-- there are no lots and everything stays at market price.
local _, ns = ...

local Purchases = {}
ns.Purchases = Purchases

Purchases.DAYS = 14

local module

local function Lots() return module.db.root.purchases end

--- Add a purchase lot (quantity > 0, unit price in copper).
function Purchases.Add(key, quantity, unit, t, source)
    if not key or not quantity or quantity <= 0 or not unit or unit < 0 then return end
    table.insert(Lots(), { key = key, qty = quantity, unit = unit, time = t or time(), source = source })
end

local function Valid(lot, t)
    return lot.qty > 0 and lot.time <= t and t - lot.time <= Purchases.DAYS * 86400
end

--- Take up to `quantity` of key at time t (FIFO): returns taken quantity, cost.
function Purchases.Take(key, quantity, t)
    t = t or time()
    local taken, cost = 0, 0
    if not key or not quantity or quantity <= 0 then return 0, 0 end
    for _, lot in ipairs(Lots()) do
        if taken >= quantity then break end
        if lot.key == key and Valid(lot, t) then
            local n = math.min(lot.qty, quantity - taken)
            lot.qty = lot.qty - n
            taken = taken + n
            cost = cost + n * lot.unit
        end
    end
    return taken, cost
end

--- Quantity still available for key at time t.
function Purchases.Available(key, t)
    t = t or time()
    local n = 0
    for _, lot in ipairs(Lots()) do
        if lot.key == key and Valid(lot, t) then n = n + lot.qty end
    end
    return n
end

--- Drop used-up and expired lots.
function Purchases.Prune(now)
    now = now or time()
    local kept = {}
    for _, lot in ipairs(Lots()) do
        if lot.qty > 0 and now - lot.time <= Purchases.DAYS * 86400 then kept[#kept + 1] = lot end
    end
    module.db.root.purchases = kept
end

--- A Ledger booking: AH purchases and vendor purchases with an item become lots.
function Purchases.FromBooking(p)
    if not (p and p.itemKey and (p.quantity or 0) > 0 and (p.amount or 0) < 0) then return end
    local ah = p.category == "AH" and p.sub == "purchase"
    local vendor = p.category == "Vendor" and p.sub == "buy"
    if not (ah or vendor) then return end
    Purchases.Add(p.itemKey, p.quantity, -p.amount / p.quantity, p.time, ah and "ah" or "vendor")
end

function Purchases.Enable(m)
    module = m
    if type(m.db.root.purchases) ~= "table" then m.db.root.purchases = {} end
    m:On("LEDGER_TRANSACTION", function(_, p) if not p.merged then Purchases.FromBooking(p) end end)
    m:On("LEDGER_TRANSACTION_ITEM", function(_, p) Purchases.FromBooking(p) end)
    Purchases.Prune()
end
