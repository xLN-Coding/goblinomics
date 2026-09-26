if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Orders.lua
-- Fulfilled crafting orders: own reagent cost (customer reagents excluded by
-- Reagents), commission = tip - consortium cut and the NPC reward items at
-- market value, booked when CRAFTINGORDERS_FULFILL_ORDER_RESPONSE reports Ok
-- (Journalator's pattern). Profit = commission + rewards - own reagents.
-- Order crafts create no lots: the item goes to the customer.
local _, ns = ...

local Orders = {}
ns.Orders = Orders

local OK = Enum and Enum.CraftingOrderResult and Enum.CraftingOrderResult.Ok or 0

local module
local snapshots = {}    -- orderID -> snapshot from the craft call (this session)

local function Find(orderID)
    for i = #module.db.root.orders, 1, -1 do
        local o = module.db.root.orders[i]
        if o.orderID == orderID then return o end
    end
    return nil
end

--- A craft for an order: remember its cost until the order is fulfilled.
function Orders.OnCraft(record, snapshot)
    local orderID = snapshot and snapshot.orderID or record.order
    if not orderID then return end
    snapshots[orderID] = snapshot
    local o = Find(orderID)
    if o and o.status == "crafted" then
        o.cost = o.cost + (record.cost or 0)
        return
    end
    table.insert(module.db.root.orders, {
        id = ns.NextId(), time = record.time, char = record.char, orderID = orderID, recipe = record.recipe,
        name = record.name, profession = record.profession, customer = snapshot and snapshot.customer,
        cost = record.cost or 0, incomplete = record.incomplete, craft = record.id, status = "crafted",
        output = record.outputs[1] and record.outputs[1][1],
    })
end

local function RewardValue(rewards)
    local value = 0
    for _, r in ipairs(type(rewards) == "table" and rewards or {}) do
        local link = r.itemLink
        local key = link and ns.API.ItemKey.FromLink(link)
        if key then value = value + (ns.Reagents.UnitPrice(key) or 0) * (r.count or 1) end
    end
    return value
end

local function OnFulfill(_, result, orderID)
    if result ~= OK or not orderID then return end
    local o = Find(orderID)
    local snapshot = snapshots[orderID]
    if not snapshot then
        local claimed = C_CraftingOrders and C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
        if type(claimed) == "table" and claimed.orderID == orderID then
            snapshot = { tip = claimed.tipAmount, consortiumCut = claimed.consortiumCut,
                rewards = claimed.npcOrderRewards, customer = claimed.customerName }
        end
    end
    if not o then
        o = { id = ns.NextId(), time = time(), char = module.db.charKey, orderID = orderID, cost = 0,
            incomplete = true, status = "crafted", customer = snapshot and snapshot.customer }
        table.insert(module.db.root.orders, o)
    end
    o.commission = ((snapshot and snapshot.tip) or 0) - ((snapshot and snapshot.consortiumCut) or 0)
    o.rewards = RewardValue(snapshot and snapshot.rewards)
    o.profit = o.commission + o.rewards - o.cost
    o.status = "fulfilled"
    o.fulfilledAt = time()
    snapshots[orderID] = nil
    ns.API.Emit("WORKSHOP_ORDER", o)
end

--- The craft record of an order, or nil.
function Orders.CraftOf(o)
    if not o.craft then return nil end
    for _, r in ipairs(module.db.root.crafts) do
        if r.id == o.craft then return r end
    end
    return nil
end

--- Count an order without own reagent cost (orders booked before the customer
-- slot fix could carry reagents the customer supplied).
function Orders.ClearCost(o)
    o.cost = 0
    o.manual = true
    o.incomplete = nil
    o.profit = (o.commission or 0) + (o.rewards or 0)
    ns.API.Emit("WORKSHOP_ORDER", o)
end

--- Fulfilled orders (newest first) matching filter { from, profession, char }.
function Orders.List(filter)
    filter = filter or {}
    local list = {}
    for _, o in ipairs(module.db.root.orders) do
        local t = o.fulfilledAt or o.time
        if o.status == "fulfilled" and (not filter.from or t >= filter.from) and (not filter.to or t < filter.to)
            and (not filter.profession or filter.profession == o.profession)
            and (not filter.char or filter.char == o.char) then
            list[#list + 1] = o
        end
    end
    table.sort(list, function(a, b) return (a.fulfilledAt or a.time) > (b.fulfilledAt or b.time) end)
    return list
end

function Orders.Enable(m)
    module = m
    m:RegisterEvent("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", OnFulfill)
end

function Orders.Disable()
    wipe(snapshots)
end
