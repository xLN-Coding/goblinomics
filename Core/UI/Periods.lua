if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Periods.lua
-- One period model for every tab : 1, 7, 14, 30, 90 and 365
-- days, plus "all" where it makes sense (Ledger, Workshop). A period value is a
-- number of days ending today (1 = today) or "all". Shown as a segmented control.
local _, ns = ...

local Periods = {}
ns.Periods = Periods

local L = ns.L
Periods.LIST = { 1, 7, 14, 30, 90, 365 }
Periods.ALL = "all"

local function DayStart(t)
    local d = date("*t", t)
    return time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end

--- Short label: "Today", "7 d", "1 y", "All".
function Periods.Label(value)
    if value == Periods.ALL then return L["All"] end
    if value == 1 then return L["Today"] end
    if value == 365 then return L["1 y"] end
    return ns.Lf("%d d", value)
end

--- Segmented choices; withAll adds "All".
function Periods.Choices(withAll)
    local list = {}
    for _, days in ipairs(Periods.LIST) do list[#list + 1] = { value = days, label = Periods.Label(days) } end
    if withAll then list[#list + 1] = { value = Periods.ALL, label = Periods.Label(Periods.ALL) } end
    return list
end

--- Start of the period (start of the first day), nil for "all".
function Periods.From(value)
    if value == Periods.ALL or type(value) ~= "number" then return nil end
    local today = DayStart(time())
    return DayStart(today - (value - 1) * 86400 + 3600)
end

--- { days, from } for dashboard cards.
function Periods.Context(days)
    return { days = days, from = Periods.From(days) }
end

--- Segmented control for a period: get() -> value, set(value).
function Periods.Control(parent, get, set, withAll)
    return ns.Widgets.Segmented(parent, function() return Periods.Choices(withAll) end, get, set)
end

ns.API.Periods = {
    LIST = Periods.LIST,
    Label = function(_, v) return Periods.Label(v) end,
    From = function(_, v) return Periods.From(v) end,
    Control = function(_, parent, get, set, withAll) return Periods.Control(parent, get, set, withAll) end,
}
