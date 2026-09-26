if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Tracking/Binding.lua
-- Is an item bound for the wealth (cannot go to the auction house)? Soulbound
-- (container info isBound), warbound by bind type (ToWoWAccount, ToBnetAccount,
-- ToBnetAccountUntilEquipped) and "warbound until equipped" items, which report
-- bind type OnEquip and are only recognisable through
-- C_Item.IsBoundToAccountUntilEquip(location) (finding in EllesmereUIQoL and
-- Auctionator). Bind types come from the item cache; unknown ones count as not
-- bound until the next scan.
local _, ns = ...

local Binding = {}
ns.Binding = Binding

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

--- Bound for a container slot: info from C_Container.GetContainerItemInfo.
function Binding.IsBound(info, bag, slot)
    if not info then return false end
    if info.isBound then return true end
    local item = info.itemID or info.hyperlink
    local bindType = BindType(item)
    if bindType and WARBOUND[bindType] then return true end
    if bindType == ON_EQUIP and bag and slot and ItemLocation and C_Item.IsBoundToAccountUntilEquip then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc and (not C_Item.DoesItemExist or C_Item.DoesItemExist(loc)) then
            return C_Item.IsBoundToAccountUntilEquip(loc) == true
        end
    end
    return false
end
