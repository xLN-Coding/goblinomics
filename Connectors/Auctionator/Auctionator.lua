if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Connectors/Auctionator/Auctionator.lua
-- Auctionator price source: market (latest scan minimum) and destroy (disenchant
-- estimate) through Auctionator.API.v1. Keys with bonus ids and battle pets are
-- looked up by item string so gear levels resolve; plain items by item ID. No
-- sale rate. New scan data invalidates the Goblinomics price cache.
local ADDON_NAME = ...

if not (Auctionator and Auctionator.API and Auctionator.API.v1) then return end
local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API or not API.Price then return end

local L = API.L
local ItemKey = API.ItemKey
local CALLER = "Goblinomics"
local v1 = Auctionator.API.v1

local active = false
local updateRegistered = false

local function Call(fn, ...)
    local ok, value = pcall(fn, CALLER, ...)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local Source = {
    id = "auctionator",
    name = "Auctionator",
    priority = 20,
    roles = { market = true, destroy = true },
}

local function NeedsLink(key)
    return ItemKey.IsPet(key) or key ~= ItemKey.Base(key)
end

function Source:Get(key, role)
    if role == "market" then
        if NeedsLink(key) then
            return Call(v1.GetAuctionPriceByItemLink, ItemKey.ToItemString(key))
        end
        local itemID = ItemKey.ToItemID(key)
        return itemID and Call(v1.GetAuctionPriceByItemID, itemID) or nil
    elseif role == "destroy" then
        if ItemKey.IsPet(key) then return nil end
        return Call(v1.GetDisenchantPriceByItemLink, ItemKey.ToItemString(key))
    end
    return nil
end

function Source:Status()
    if Auctionator.Database == nil then
        return { available = true, note = L["No Auctionator scan data yet"] }
    end
    return { available = true }
end

local function OnDatabaseUpdate()
    if active then
        API.Price:Invalidate()
    end
end

API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "Auctionator Connector",
    description = function() return API.L["Prices from Auctionator."] end,
    order = 81,
    OnEnable = function()
        active = true
        API.Price:RegisterSource(Source)
        if not updateRegistered and v1.RegisterForDBUpdate then
            updateRegistered = pcall(v1.RegisterForDBUpdate, CALLER, OnDatabaseUpdate)
        end
    end,
    OnDisable = function()
        active = false
        API.Price:UnregisterSource(Source.id)
    end,
})
