if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Instances.lua
-- Raid and dungeon lockouts and world bosses of every character (moved here from
-- the Gatherer, which still shows them per instance farm). RequestRaidInfo() at
-- login, on entering the world and after boss kills; UPDATE_INSTANCE_INFO reads
-- GetSavedInstanceInfo (difficulty ID and instance map ID, as AlterEgo does) and
-- GetSavedWorldBossInfo into the character's table, plus level and class.
-- Lockouts the Gatherer stored before are taken over once.
local _, ns = ...

local Instances = {}
ns.Instances = Instances

local module
local requestToken = 0

local function Request()
    if RequestRaidInfo then RequestRaidInfo() end
end

local function RequestSoon(delay)
    requestToken = requestToken + 1
    local token = requestToken
    module:After(delay, function()
        if token == requestToken then Request() end
    end)
end

local function StoreCharacter(level)
    local c = module.db.char
    c.level = level or (UnitLevel and UnitLevel("player")) or c.level
    c.class = UnitClass and select(2, UnitClass("player")) or c.class
end

--- Read saved instances and world bosses of the current character.
function Instances.Read()
    local now = time()
    local list = {}
    for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
        local name, _, reset, difficultyID, locked, extended, _, isRaid, _, difficultyName, numEncounters, progress,
            _, mapID = GetSavedInstanceInfo(i)
        if name and (locked or extended) and (reset or 0) > 0 then
            list[#list + 1] = {
                name = name, mapID = mapID, difficultyID = difficultyID, difficulty = difficultyName,
                resetAt = now + reset, isRaid = isRaid == true, encounters = numEncounters, progress = progress,
            }
        end
    end
    local bosses = {}
    for i = 1, (GetNumSavedWorldBosses and GetNumSavedWorldBosses() or 0) do
        local name, id, reset = GetSavedWorldBossInfo(i)
        if name and (reset or 0) > 0 then bosses[#bosses + 1] = { name = name, id = id, resetAt = now + reset } end
    end
    local c = module.db.char
    c.lockouts = list
    c.worldBosses = bosses
    c.lockoutsScanned = now
    StoreCharacter()
    ns.API.Emit("ROUTINES_UPDATED", { part = "instances" })
    return list, bosses
end

--- charKey -> { lockouts, lockoutsScanned, worldBosses, level, class } (the stored tables).
function Instances.All()
    local out = {}
    for charKey, c in pairs(module and module.db.root.chars or {}) do
        if type(c) == "table" and c.lockoutsScanned then out[charKey] = c end
    end
    return out
end

--- Take over lockouts the Gatherer stored (before 0.9.3) for characters Routines has not seen.
function Instances.Migrate(root, gathererRoot)
    local moved = 0
    for charKey, g in pairs(type(gathererRoot) == "table" and type(gathererRoot.chars) == "table" and gathererRoot.chars
        or {}) do
        if type(g) == "table" and g.lockoutsScanned then
            local c = root.chars[charKey]
            if type(c) ~= "table" then
                c = {}
                root.chars[charKey] = c
            end
            if not c.lockoutsScanned then
                c.lockouts, c.lockoutsScanned = g.lockouts, g.lockoutsScanned
                c.level, c.class = c.level or g.level, c.class or g.class
                moved = moved + 1
            end
        end
    end
    return moved
end

function Instances.Enable(m)
    module = m
    Instances.Migrate(m.db.root, _G.GoblinomicsGathererDB)
    m:RegisterEvent("UPDATE_INSTANCE_INFO", function() Instances.Read() end)
    m:RegisterEvent("PLAYER_ENTERING_WORLD", function() RequestSoon(3) end)
    m:RegisterEvent("BOSS_KILL", function() RequestSoon(2) end)
    m:RegisterEvent("PLAYER_LEVEL_UP", function(_, level) StoreCharacter(level) end)
    StoreCharacter()
    Request()
end

function Instances.Disable()
    requestToken = requestToken + 1
end
