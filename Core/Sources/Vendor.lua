if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Sources/Vendor.lua
-- Vendor price source: the merchant sell price from C_Item.GetItemInfo. Item
-- data that is not cached yet is requested; ITEM_DATA_LOAD_RESULT (registered
-- only while something is pending) invalidates the affected keys.
local _, ns = ...

local Price, ItemKey = ns.Price, ns.ItemKey
local events = ns.Events.NewDispatcher("Core.Vendor")

local pending = {}   -- itemID -> { [itemKey] = true }
local waiting = false

local function OnItemDataLoaded(_, itemID)
    local keys = pending[itemID]
    if not keys then return end
    pending[itemID] = nil
    for key in pairs(keys) do
        Price.Invalidate(key)
    end
    if next(pending) == nil then
        waiting = false
        events:Unregister("ITEM_DATA_LOAD_RESULT")
    end
end

local function Request(itemID, key)
    local keys = pending[itemID]
    if not keys then
        keys = {}
        pending[itemID] = keys
        C_Item.RequestLoadItemDataByID(itemID)
    end
    keys[key] = true
    if not waiting then
        waiting = true
        events:Register("ITEM_DATA_LOAD_RESULT", OnItemDataLoaded)
    end
end

local Vendor = {
    id = "vendor",
    name = "Vendor",
    priority = 100,
    roles = { vendor = true },
}

function Vendor:Get(key)
    local itemID = ItemKey.ToItemID(key)
    if not itemID then
        return nil   -- battle pets have no vendor price
    end
    local query = key ~= ItemKey.Base(key) and ItemKey.ToItemString(key) or itemID
    local name, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(query)
    if name == nil then
        Request(itemID, key)
        return nil, "pending"
    end
    if type(sellPrice) == "number" and sellPrice > 0 then
        return sellPrice
    end
    return nil
end

function Vendor:Status()
    return { available = true }
end

ns.VendorSource = Vendor
Price.RegisterSource(Vendor)
