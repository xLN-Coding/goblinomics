-- Load connector addons into a booted core (the connector reads its API table then).
local M = {}

function M.tsm(data, valid)
    _G.TSM_API = {
        calls = {},
        GetCustomPriceValue = function(str, key)
            if type(key) ~= "string" or not key:match("^[ip]:%d+") then error("Invalid itemString") end
            table.insert(_G.TSM_API.calls, str .. "|" .. key)
            return data[str] and data[str][key]
        end,
        IsCustomPriceValid = function(str)
            if valid[str] then return true end
            return false, "Invalid price source"
        end,
        GetPriceSourceKeys = function(t)
            for _, k in ipairs({ "DBMarket", "DBRecent", "Destroy", "DBRegionSaleRate" }) do table.insert(t, k) end
            return t
        end,
    }
end

function M.auctionator(prices, disenchant, hasDB)
    local listeners = {}
    _G.Auctionator = {
        Database = hasDB ~= false and {} or nil,
        API = { v1 = {
            GetAuctionPriceByItemID = function(caller, id) assert(caller == "Goblinomics"); return prices["id:" .. id] end,
            GetAuctionPriceByItemLink = function(caller, link) assert(caller == "Goblinomics"); return prices[link] end,
            GetDisenchantPriceByItemLink = function(_, link) return disenchant[link] end,
            RegisterForDBUpdate = function(_, cb) table.insert(listeners, cb) end,
        } },
        FireUpdate = function() for _, cb in ipairs(listeners) do cb() end end,
    }
end

--- Boot the core, load the given connector files, log in.
function M.boot(opts, files)
    local ns = load_core({ boot = true, money = opts.money or 1 })
    for _, f in ipairs(files) do
        load_addon_file(f.path, f.addon, {})
        WoWMock.fire("ADDON_LOADED", f.addon)
    end
    WoWMock.loggedIn = true
    WoWMock.fire("PLAYER_LOGIN")
    return ns
end

M.TSM = { path = "Connectors/TSM/TSM.lua", addon = "Goblinomics_Connector_TSM" }
M.AUC = { path = "Connectors/Auctionator/Auctionator.lua", addon = "Goblinomics_Connector_Auctionator" }

function M.cleanup()
    _G.TSM_API = nil
    _G.Auctionator = nil
end

return M
