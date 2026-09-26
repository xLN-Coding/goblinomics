if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/WorkshopSummary.lua
-- Summary page (graphic): realized profit large with the change against the
-- previous period and the split into sold crafts / crafting orders / salvage;
-- open stock (items, cost, current market value); profit per day as stacked
-- bars; top recipes by profit and the best recipes by concentration value per
-- point, plus one line per profession.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local Summary = {}
ns.WorkshopSummary = Summary

local TOP = 5

local module

--- Days of the profit-per-day chart: the period, at least 14 and at most 90 days.
local function DaysFor(period)
    if type(period) ~= "number" then return 30 end
    return math.max(14, math.min(90, period))
end

function Summary.Build(parent)
    local API, L, UI = ns.API, ns.L, ns.WorkshopUI
    local Theme, W = API.Theme, API.Widgets
    local C = Theme.colors
    local page = {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    page.frame = f

    -- key figures
    local kpi = CreateFrame("Frame", nil, f)
    kpi:SetPoint("TOPLEFT", 0, 0)
    kpi:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    kpi:SetHeight(74)
    Theme.Backdrop(kpi, C.panel, C.border)
    local accent = kpi:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(unpack(C.gold))
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(3)
    local profitLabel = Theme.Text(kpi, 10, C.textDim)
    profitLabel:SetPoint("TOPLEFT", 12, -8)
    profitLabel:SetText(L["Realized profit"]:upper())
    page.total = Theme.Text(kpi, "value", C.gold)
    page.total:SetPoint("TOPLEFT", 12, -22)
    page.change = Theme.Text(kpi, 11, C.textDim)
    page.change:SetPoint("LEFT", page.total, "RIGHT", 10, -2)
    page.split = Theme.Text(kpi, 11, C.textDim)
    page.split:SetPoint("BOTTOMLEFT", 12, 8)
    page.split:SetPoint("RIGHT", kpi, "RIGHT", -170, 0)
    page.split:SetWordWrap(false)
    local stockLabel = Theme.Text(kpi, 10, C.textDim)
    stockLabel:SetPoint("TOPRIGHT", -12, -8)
    stockLabel:SetText(L["Open stock"]:upper())
    page.stockQty = Theme.Text(kpi, 16, C.text)
    page.stockQty:SetPoint("TOPRIGHT", -12, -24)
    page.stockQty:SetJustifyH("RIGHT")
    page.stockValue = Theme.Text(kpi, 11, C.textDim)
    page.stockValue:SetPoint("BOTTOMRIGHT", -12, 8)
    page.stockValue:SetJustifyH("RIGHT")

    -- profit per day
    UI.Section(f, L["Profit per day"], 0, -86)
    local legend = Theme.Text(f, 10, C.textDim)
    legend:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -86)
    legend:SetJustifyH("RIGHT")
    legend:SetText((CODE.good .. "%s|r  " .. CODE.gold .. "%s|r  " .. CODE.dim .. "%s|r"):format(L["Sold crafts"], L["Crafting orders"],
        L["Salvage"]))
    page.chart = W.BarChart(f, {
        width = 420, height = 100, gap = 2,
        series = { { key = "sales", color = C.accent }, { key = "orders", color = C.gold },
            { key = "salvage", color = C.neutral } },
        tooltip = function(bar)
            local v = bar.values
            return ns.API.Format:Date(bar.day, "long"), {
                L["Sold crafts"] .. ": " .. UI.Money(v.sales, { color = true, sign = true }),
                L["Crafting orders"] .. ": " .. UI.Money(v.orders, { color = true, sign = true }),
                L["Salvage"] .. ": " .. UI.Money(v.salvage, { color = true, sign = true }),
                L["Total"] .. ": " .. UI.Money(bar.total, { color = true, sign = true }),
            }
        end,
    })
    page.chart:SetPoint("TOPLEFT", 0, -102)
    page.chart:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    page.chartEmpty = Theme.Text(f, 11, C.textDim)
    page.chartEmpty:SetPoint("TOPLEFT", 4, -140)
    page.chartEmpty:SetText(L["No sales or orders in this period."])

    -- top recipes and concentration
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", 0, -216)
    left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 0)
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", f, "TOP", 8, -216)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.Section(left, L["Top recipes"], 0, 0)
    page.concentrationTitle = UI.Section(right, "", 0, 0)
    local function Rows(host, withBar)
        local rows = {}
        for i = 1, TOP do
            local y = -16 - (i - 1) * 20
            local r = {}
            if withBar then
                r.bar = host:CreateTexture(nil, "BACKGROUND")
                r.bar:SetColorTexture(unpack(C.accentSoft))
                r.bar:SetPoint("TOPLEFT", 0, y + 1)
                r.bar:SetHeight(18)
            end
            r.name = Theme.Text(host, 11, C.text)
            r.name:SetPoint("TOPLEFT", 4, y - 2)
            r.name:SetPoint("RIGHT", host, "RIGHT", -70, 0)
            r.name:SetWordWrap(false)
            r.value = Theme.Text(host, 11, C.text)
            r.value:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2, y - 2)
            r.value:SetJustifyH("RIGHT")
            rows[i] = r
        end
        return rows
    end
    page.top = Rows(left, true)
    page.conc = Rows(right, false)
    page.topEmpty = Theme.Text(left, 11, C.textDim)
    page.topEmpty:SetPoint("TOPLEFT", 4, -18)
    page.topEmpty:SetText(L["No sold crafts yet."])
    page.concEmpty = Theme.Text(right, 11, C.textDim)
    page.concEmpty:SetPoint("TOPLEFT", 4, -18)
    page.concEmpty:SetText(L["No concentrated crafts yet"])
    page.professions = Theme.Text(right, 10, C.textDim)
    page.professions:SetPoint("TOPLEFT", 4, -16 - TOP * 20 - 6)
    page.professions:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    page.professions:SetJustifyH("LEFT")
    page.leftFrame = left

    function page.Refresh(filter)
        local state = UI.state
        local cmp = ns.Stats.Compare(filter)
        local b = cmp.current
        page.total:SetText(UI.Money(b.total, { color = true, sign = true }))
        if cmp.change then
            local color = cmp.change >= 0 and "3fbf3f" or "d9463e"
            page.change:SetText(("|cff%s%+.0f%%|r %s"):format(color, cmp.change, L["vs. previous period"]))
        else
            page.change:SetText("")
        end
        page.split:SetText(UI.BreakdownText(b, "   "))
        local stock = ns.Stats.OpenStock(filter)
        page.stockQty:SetText(API.Lf("%d items", stock.qty))
        page.stockValue:SetText(API.Lf("cost %s, worth %s", UI.Money(stock.cost), UI.Money(stock.value)))

        local days = ns.Stats.Daily(DaysFor(state.period), filter)
        local bars, any = {}, false
        for i, d in ipairs(days) do
            bars[i] = { day = d.day, total = d.total, values = { sales = d.sales, orders = d.orders, salvage = d.salvage } }
            if d.total ~= 0 or d.sales ~= 0 or d.orders ~= 0 then any = true end
        end
        page.chart:SetData(bars)
        page.chartEmpty:SetShown(not any)

        local recipes = {}
        for _, r in ipairs(ns.Stats.Recipes(filter)) do
            if r.sold > 0 then recipes[#recipes + 1] = r end
        end
        local best = recipes[1] and math.max(1, recipes[1].profit) or 1
        local width = (page.leftFrame.GetWidth and page.leftFrame:GetWidth()) or 0
        if not width or width <= 0 then width = 200 end
        for i, row in ipairs(page.top) do
            local r = recipes[i]
            row.name:SetText(r and (r.output and (UI.ItemLabel(r.output)) or r.name) or "")
            row.value:SetText(r and UI.Money(r.profit, { color = true, sign = true }) or "")
            row.bar:SetShown(r ~= nil and r.profit > 0)
            if r and r.profit > 0 then row.bar:SetWidth(math.max(2, width * r.profit / best)) end
        end
        page.topEmpty:SetShown(#recipes == 0)

        local days30 = module and module.db.settings.concentrationDays or 30
        page.concentrationTitle:SetText(API.Lf("Concentration value (%d days)", days30):upper())
        local conc = ns.Concentration.ByRecipe(nil, filter)
        for i, row in ipairs(page.conc) do
            local e = conc[i]
            row.name:SetText(e and ((e.output and (UI.ItemLabel(e.output))) or e.name) or "")
            row.value:SetText(e and API.Lf("%s/pt", UI.Money(e.value)) or "")
        end
        page.concEmpty:SetShown(#conc == 0)
        local parts = {}
        for profession, c in pairs(ns.Concentration.ByProfession()) do
            if not filter.profession or filter.profession == profession then
                parts[#parts + 1] = ("%s %s"):format(profession, API.Lf("%s/pt", UI.Money(c.value)))
            end
        end
        table.sort(parts)
        page.professions:SetText(table.concat(parts, "   "))
    end

    return page
end

function Summary.Enable(m)
    module = m
end
