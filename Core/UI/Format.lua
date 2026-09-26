if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Format.lua
-- Number, percent and date formats that follow the language:
-- German "12,3K", "25 %", "26.09."; English "12.3K", "25%", "09/26". Abbreviated
-- gold amounts (Money.Format abbreviate, chart axes) use the decimal separator
-- from here, so they never collide with the thousands separator ("1.234g").
local _, ns = ...

local Format = {}
ns.Format = Format
local L = ns.L

--- Decimal separator of the active language.
function Format.Decimal() return L["."] end

--- Number with `decimals` digits and the language's decimal separator.
function Format.Number(n, decimals)
    local text = ("%." .. (decimals or 0) .. "f"):format(n or 0)
    local sep = Format.Decimal()
    if sep ~= "." then text = text:gsub("%.", sep) end
    return text
end

--- Share (0..1) as percent: "25 %" / "25%".
function Format.Percent(share, decimals)
    return ns.Lf("%s%%", Format.Number((share or 0) * 100, decimals or 0))
end

local function WeekdayName(t)
    local names = CALENDAR_WEEKDAY_NAMES
    return names and names[tonumber(date("%w", t)) + 1] or date("%A", t)
end

--- Date of a timestamp: "short" (26.09.), "long" (26.09.2026), "time" (14:05),
-- "weekday" (Freitag), "weekdayShort" (Fr), "full" (Freitag, 26.09.2026),
-- "stamp" (26.09. 14:05), "longStamp" (26.09.2026 14:05).
function Format.Date(t, style)
    t = t or time()
    if style == "long" then return date(L["%m/%d/%Y"], t) end
    if style == "time" then return date("%H:%M", t) end
    if style == "stamp" then return date(L["%m/%d"], t) .. " " .. date("%H:%M", t) end
    if style == "longStamp" then return date(L["%m/%d/%Y"], t) .. " " .. date("%H:%M", t) end
    if style == "weekday" then return WeekdayName(t) end
    if style == "weekdayShort" then
        local name = WeekdayName(t)
        local out, n = "", 0
        for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            if n > 2 then break end
            out = out .. ch
        end
        return out
    end
    if style == "full" then return WeekdayName(t) .. ", " .. date(L["%m/%d/%Y"], t) end
    return date(L["%m/%d"], t)
end

--- Timestamp of a day key "YYYY-MM-DD" (noon, safe against DST).
function Format.DayTime(key)
    local y, m, d = tostring(key or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

--- A day key formatted like Format.Date (style default "short").
function Format.Day(key, style)
    local t = Format.DayTime(key)
    return t and Format.Date(t, style) or tostring(key or "")
end

ns.API.Format = {
    Number = function(_, n, d) return Format.Number(n, d) end,
    Percent = function(_, s, d) return Format.Percent(s, d) end,
    Date = function(_, t, style) return Format.Date(t, style) end,
    Day = function(_, key, style) return Format.Day(key, style) end,
}
