if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/PricingSettings.lua
-- Settings section "Prices": preferred market source, TSM source strings per
-- role (only with TSM), the speculative sale-rate threshold and the status of
-- every price source. Every change invalidates the price cache.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.Theme.CODE[k] end })

local UI, Theme, Price = ns.UI, ns.Theme, ns.Price
local C = Theme.colors
local L = ns.L

local function Rate(v)
    return ("%.2f"):format(v)
end

UI.RegisterSettings({
    id = "pricing",
    title = function() return L["Prices"] end,
    description = function() return L["Where Goblinomics takes its prices from and how items count."] end,
    order = 10,
    build = function(parent, y)
        local cfg = Price.Config()
        local form = ns.Form.New(parent, y)

        form:Group(L["Source"])
        form:Segmented({ label = L["Preferred market source"],
            description = L["Market prices come from here first; the other source fills gaps."],
            options = { { value = "tsm", label = "TSM" }, { value = "auctionator", label = "Auctionator" } },
            get = function() return cfg.preferred end,
            set = function(value) Price.SetPreferred(value) end })

        local tsm = Price.GetSource("tsm")
        if tsm then
            local known = tsm.KnownSources()
            local tip = {}
            for i = 1, math.min(#known, 24) do tip[i] = known[i] end
            form:Group(L["TSM price sources"], L["TSM price source or custom price string"])
            local roles = {
                { "market", L["TSM market source"], L["Value of tradable items."] },
                { "destroy", L["TSM destroy source"], L["Value when an item is milled, prospected or disenchanted."] },
                { "saleRate", L["TSM sale rate source"], L["How often an item sells; decides what is speculative."] },
            }
            for _, entry in ipairs(roles) do
                local role = entry[1]
                form:Text({ label = entry[2], description = entry[3], width = 200,
                    get = function() return cfg.tsm[role] end,
                    set = function(text)
                        text = strtrim(text)
                        local valid, err = tsm.ValidateSource(text)
                        if not valid then
                            return false, err or L["Invalid TSM price source"]
                        end
                        cfg.tsm[role] = text
                        Price.Invalidate()
                        return true
                    end,
                    tooltip = L["TSM price source or custom price string"], tooltipLines = { table.concat(tip, ", ") } })
            end
        end

        if Price.HasRole("saleRate") then   -- speculative needs a sale rate (TSM)
            form:Group(L["Valuation"])
            form:Slider({ label = L["Speculative below sale rate"],
                description = L["Items that sell less often count as speculative: in the wealth, but shown separately."],
                min = 0, max = 0.5, step = 0.01, format = Rate,
                get = function() return cfg.speculativeThreshold end,
                set = function(v)
                    cfg.speculativeThreshold = v
                    Price.Invalidate()
                end })
            form:Number({ label = L["Speculative from (gold per item)"],
                description = L["Cheaper items are never speculative, so the list stays free of junk."], min = 0,
                get = function() return math.floor((cfg.speculativeMinValue or 0) / 10000) end,
                set = function(n)
                    cfg.speculativeMinValue = math.max(0, n) * 10000
                    Price.Invalidate()
                end })
        end

        form:Group(L["Price sources"])
        for _, src in ipairs(Price.Sources()) do
            local roles = {}
            for role in pairs(src.roles) do roles[#roles + 1] = role end
            table.sort(roles)
            local line = src.name .. " " .. CODE.dim .. "(" .. table.concat(roles, ", ") .. ")|r"
            if src.note then line = line .. "  " .. CODE.bad .. src.note .. "|r" end
            form:Note(line, C.text)
        end
        return form:Finish()
    end,
})
