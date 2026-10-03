if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Connectors/TSM/TSM.lua
-- TradeSkillMaster price source: market, destroy and sale rate through TSM_API.
-- The source string per role comes from the Goblinomics settings (TSM price
-- source names or custom price strings). TSM rounds results to whole copper, so
-- the sale rate is queried as (<source>)*1000 and divided afterwards. Every TSM
-- call is wrapped in pcall (TSM raises errors for invalid input).
local ADDON_NAME = ...

if type(TSM_API) ~= "table" then return end
local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API or not API.Price then return end

local L = API.L
local SCALE = 1000
local PROBE_ITEM = "i:2589"   -- Linen Cloth: has DBMarket data on every realm with app data

local function Query(str, key)
    local ok, value = pcall(TSM_API.GetCustomPriceValue, str, key)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local Source = {
    id = "tsm",
    name = "TradeSkillMaster",
    priority = 10,
    roles = { market = true, destroy = true, saleRate = true },
}

function Source:Get(key, role)
    local config = API.Price:Config().tsm or {}
    local str = config[role]
    if type(str) ~= "string" or str == "" then
        return nil
    end
    if role == "saleRate" then
        local scaled = Query("(" .. str .. ")*" .. SCALE, key)
        return scaled and scaled / SCALE or nil
    end
    local value = Query(str, key)
    if not value then
        local base = API.ItemKey.Base(key)
        if base and base ~= key then
            value = Query(str, base)
        end
    end
    return value
end

--- Value of a named TSM price source (e.g. "DBRecent", "DBHistorical") for an item, or nil.
function Source:Query(key, name)
    if type(name) ~= "string" or not name:match("^[%w]+$") then return nil end
    local value = Query(name, key)
    if not value then
        local base = API.ItemKey.Base(key)
        if base and base ~= key then value = Query(name, base) end
    end
    return value
end

function Source:Status()
    if Query("DBMarket", PROBE_ITEM) == nil then
        return { available = true, note = L["TSM desktop app data missing: no DB* prices"] }
    end
    return { available = true }
end

--- valid, errorMessage for a price source string.
function Source.ValidateSource(str)
    local ok, valid, err = pcall(TSM_API.IsCustomPriceValid, str)
    if not ok then
        return false, tostring(valid)
    end
    return valid == true, err
end

--- Known TSM price source keys (built-in and custom sources).
function Source.KnownSources()
    local ok, keys = pcall(TSM_API.GetPriceSourceKeys, {})
    if ok and type(keys) == "table" then
        table.sort(keys)
        return keys
    end
    return {}
end

API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "TSM Connector",
    description = function() return API.L["Prices from TradeSkillMaster."] end,
    order = 80,
    OnEnable = function() API.Price:RegisterSource(Source) end,
    OnDisable = function() API.Price:UnregisterSource(Source.id) end,
})
