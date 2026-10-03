if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/PulseNotices.lua
-- Price drop warnings of Market Pulse, after the daily snapshot: a toast for every
-- item that newly drops below the threshold (once per item and day) and a chat line
-- after login with all of them. Both can be switched off in the Workshop settings.
local _, ns = ...

local PulseNotices = {}
ns.PulseNotices = PulseNotices

local OWNER = "Goblinomics_Workshop.PulseNotices"
local module
local loginDone = false

local function Name(key)
    local id = tonumber(key:match("^i:(%d+)"))
    local name = id and C_Item.GetItemInfo(id)
    return name or key
end

--- Warned rows, and the chat line for them (nil when there is none).
function PulseNotices.Line(rows)
    local parts = {}
    for _, r in ipairs(rows) do
        if r.warning then parts[#parts + 1] = ("%s %+.0f%%"):format(Name(r.key), r.trend * 100) end
    end
    if #parts == 0 then return nil end
    return ns.API.Lf("Price drop: %s", table.concat(parts, ", "))
end

function PulseNotices.Check(now)
    if not module then return end
    now = now or time()
    local settings, root = module.db.settings, module.db.root
    local rows = ns.Pulse.Rows(now)
    if not loginDone then
        loginDone = true
        local line = settings.pulseChat and PulseNotices.Line(rows)
        if line then ns.API.Print(line) end
    end
    local day = ns.Pulse.Day(now)
    for _, r in ipairs(rows) do
        if r.warning and root.pulseNotices[r.key] ~= day then
            root.pulseNotices[r.key] = day
            if settings.pulseToast then
                ns.API.UI:Toast({ title = ns.L["Price drop"], text = ("%s %+.0f%%"):format(Name(r.key), r.trend * 100) })
            end
        end
    end
end

function PulseNotices.Enable(m)
    module = m
    loginDone = false
    ns.API.On("WORKSHOP_PULSE", function(payload)
        if payload and payload.day then PulseNotices.Check() end
    end, OWNER)
    -- the login line also comes when today's snapshot was taken in an earlier session
    m:After(14, function() if not loginDone then PulseNotices.Check() end end)
end

function PulseNotices.Disable()
    if ns.API then ns.API.Off("WORKSHOP_PULSE", OWNER) end
end
