if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Routines.lua
-- Routines: the weekly and daily gold checklist of every character. Tasks are
-- learned (daily and weekly quests, world bosses), come from the game (raid and
-- dungeon lockouts, the Great Vault, patron crafting orders, the Workshop's
-- concentration and cooldowns), from community presets or from shared strings.
-- Only pinned tasks make the routine; the rest waits as suggestions. The logged-in
-- character is read live, the others keep their last state until it resets.
-- This file registers the module, knows the reset times and publishes API.Routines.
local ADDON_NAME, ns = ...

local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API then return end
ns.API = API
ns.L = API.L

local Routines = API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "Routines",
    description = function() return API.L["Weekly and daily gold routines per character, sorted by gold per minute."] end,
    order = 45,
    db = {
        sv = "GoblinomicsRoutinesDB",
        version = 1,
        defaults = {
            durations = { quest = 10, instance = 30, worldboss = 5, delve = 15, patron = 3, profession = 2 },
            hiddenChars = {},    -- charKey -> true
            resetNotice = true,  -- chat line after login: what is still open this week
        },
        charDefaults = {},
    },
})
ns.Routines = Routines

-- Reset times ----------------------------------------------------------------------------
--- Time of the next weekly reset (region), or nil.
function Routines.WeeklyResetAt(now)
    now = now or time()
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    return type(left) == "number" and now + left or nil
end

--- Time of the next daily reset, or nil.
function Routines.DailyResetAt(now)
    now = now or time()
    local left = GetQuestResetTime and GetQuestResetTime()
    return type(left) == "number" and left > 0 and now + left or nil
end

--- Character key "Name-Realm" of the logged-in character.
function Routines.CharKey() return Routines.db and Routines.db.charKey end

local PARTS = { "Presets", "Instances", "Learn", "Activities" }
Routines.PARTS = PARTS

function Routines:OnInit()
    local root = self.db.root
    if type(root.tasks) ~= "table" then root.tasks = {} end
end

function Routines:OnEnable()
    local c = self.db.char
    c.name = UnitName and UnitName("player") or c.name
    c.class = UnitClass and select(2, UnitClass("player")) or c.class
    for _, part in ipairs(PARTS) do
        if ns[part] and ns[part].Enable then ns[part].Enable(self) end
    end
end

function Routines:OnDisable()
    for i = #PARTS, 1, -1 do
        local part = ns[PARTS[i]]
        if part and part.Disable then part.Disable(self) end
    end
end

-- Public, read-only ------------------------------------------------------------------------
API.Routines = {
    --- charKey -> { lockouts, lockoutsScanned, worldBosses, level, class } of every character.
    Lockouts = function() return ns.Instances and ns.Instances.All() or {} end,
}
