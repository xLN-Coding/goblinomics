if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/Freshness.lua
-- Data freshness per location: fresh below freshHours,
-- aging below agingDays, stale beyond; a location never seen is "never"
-- ("not recorded"), which is different from an empty location.
local _, ns = ...

local Freshness = {}
ns.Freshness = Freshness

Freshness.COLORS = {
    fresh = "3fbf3f", aging = "e6c229", stale = "e0702b", never = "7f7f7f",
}

function Freshness.State(seenAt, now, settings)
    if type(seenAt) ~= "number" then
        return "never"
    end
    local age = (now or time()) - seenAt
    local freshHours = settings and settings.freshHours or 6
    local agingDays = settings and settings.agingDays or 3
    if age < freshHours * 3600 then
        return "fresh"
    elseif age < agingDays * 86400 then
        return "aging"
    end
    return "stale"
end

function Freshness.Label(state)
    local L = ns.L
    if state == "fresh" then return L["fresh"] end
    if state == "aging" then return L["aging"] end
    if state == "stale" then return L["stale"] end
    return L["not recorded"]
end

function Freshness.Colorize(state, text)
    return "|cff" .. (Freshness.COLORS[state] or "ffffff") .. text .. "|r"
end

--- "3 h", "2 d" for an age in seconds.
function Freshness.Age(seenAt, now)
    if type(seenAt) ~= "number" then return "-" end
    local age = math.max(0, (now or time()) - seenAt)
    if age < 3600 then return ("%d min"):format(math.floor(age / 60)) end
    if age < 86400 then return ("%d h"):format(math.floor(age / 3600)) end
    return ("%d d"):format(math.floor(age / 86400))
end
