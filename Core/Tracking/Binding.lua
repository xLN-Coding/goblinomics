if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Tracking/Binding.lua
-- Is an item bound for the wealth (cannot go to the auction house)? Soulbound
-- (container info isBound), warbound by bind type (ToWoWAccount, ToBnetAccount,
-- ToBnetAccountUntilEquipped) and "warbound until equipped" items, which report
-- bind type OnEquip and are only recognisable through
-- C_Item.IsBoundToAccountUntilEquip(location) (finding in EllesmereUIQoL and
-- Auctionator). Bind types come from the item cache. An item whose data is not
-- loaded yet counts as not bound for now: IsBound also returns its item id, the
-- data is requested, and Await/OnKnown tell the caller when the bind type is
-- known (GET_ITEM_INFO_RECEIVED is registered only while something waits).
local _, ns = ...

local Binding = {}
ns.Binding = Binding

local events = ns.Events.NewDispatcher("Core.Binding")
local waiting = {}     -- itemID -> { [owner] = true }
local listeners = {}   -- owner -> fn(itemID)
local waitCount = 0

local ItemBind = Enum and Enum.ItemBind or {}
local WARBOUND = {
    [ItemBind.ToWoWAccount or 7] = true,
    [ItemBind.ToBnetAccount or 8] = true,
    [ItemBind.ToBnetAccountUntilEquipped or 9] = true,
}
local ON_EQUIP = ItemBind.OnEquip or 2

local function BindType(item)
    if not item or not C_Item.GetItemInfo then return nil end
    return select(14, C_Item.GetItemInfo(item))
end
Binding.BindType = BindType

--- Warbound by its bind type alone (mail attachments, links).
function Binding.IsWarboundType(item)
    local bindType = BindType(item)
    return bindType ~= nil and WARBOUND[bindType] == true
end

--- true or false once the item data is loaded, nil while it is not.
function Binding.WarboundState(item)
    local bindType = BindType(item)
    if bindType == nil then return nil end
    return WARBOUND[bindType] == true
end

local function OnItemInfo(_, itemID, success)
    local owners = waiting[itemID]
    if not owners or success == false then return end
    waiting[itemID] = nil
    waitCount = waitCount - 1
    if waitCount <= 0 then
        waitCount = 0
        events:Unregister("GET_ITEM_INFO_RECEIVED")
    end
    for owner in pairs(owners) do
        local fn = listeners[owner]
        if fn then ns.SafeCall(fn, itemID) end
    end
end

--- fn(itemID) runs when an item awaited by owner has its data loaded.
function Binding.OnKnown(owner, fn)
    listeners[owner] = fn
end

--- Request the item data and notify owner's OnKnown handler once it is loaded.
function Binding.Await(owner, itemID)
    if type(itemID) ~= "number" then return end
    local owners = waiting[itemID]
    if not owners then
        owners = {}
        waiting[itemID] = owners
        waitCount = waitCount + 1
        if waitCount == 1 then events:Register("GET_ITEM_INFO_RECEIVED", OnItemInfo) end
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    end
    owners[owner] = true
end

function Binding.IsWaiting(itemID)
    return waiting[itemID] ~= nil
end

--- Bound for a container slot: info from C_Container.GetContainerItemInfo.
-- Second result: the item id when the bind type is not known yet.
function Binding.IsBound(info, bag, slot)
    if not info then return false end
    if info.isBound then return true end
    local item = info.itemID or info.hyperlink
    local bindType = BindType(item)
    if bindType == nil then return false, info.itemID end
    if WARBOUND[bindType] then return true end
    if bindType == ON_EQUIP and bag and slot and ItemLocation and C_Item.IsBoundToAccountUntilEquip then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc and (not C_Item.DoesItemExist or C_Item.DoesItemExist(loc)) then
            return C_Item.IsBoundToAccountUntilEquip(loc) == true
        end
    end
    return false
end
