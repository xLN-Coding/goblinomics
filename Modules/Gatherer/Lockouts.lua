if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Gatherer/Lockouts.lua
-- Saved instances per character for raid and dungeon farms. RequestRaidInfo()
-- at login, on entering the world and after boss kills; UPDATE_INSTANCE_INFO
-- reads GetSavedInstanceInfo (with difficulty ID and instance map ID, as
-- AlterEgo does) into db.char.lockouts, plus the character's level and class.
-- Lockouts.Grid builds the overview for a farm: one row per character at max
-- level with data, one column per difficulty, cells with the progress
-- ("5/10"), and per difficulty how many characters can still run it.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local Lockouts = {}
ns.Lockouts = Lockouts

-- default columns; difficulties seen in lockouts are added
local RAID_DIFFICULTIES = { 14, 15, 16 }      -- Normal, Heroic, Mythic
local DUNGEON_DIFFICULTIES = { 23 }           -- Mythic (Normal and Heroic dungeons have no lockout)
local ORDER = { 17, 7, 3, 4, 14, 5, 6, 15, 16, 9, 1, 2, 23, 8 }

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
    c.level = level or UnitLevel("player")
    c.class = select(2, UnitClass("player"))
end

--- Read the client's saved instances for the current character.
function Lockouts.Read()
    local now = time()
    local list = {}
    for i = 1, (GetNumSavedInstances() or 0) do
        local name, _, reset, difficultyID, locked, extended, _, isRaid, _, difficultyName, numEncounters, progress,
            _, mapID = GetSavedInstanceInfo(i)
        if name and (locked or extended) and (reset or 0) > 0 then
            list[#list + 1] = {
                name = name, mapID = mapID, difficultyID = difficultyID, difficulty = difficultyName,
                resetAt = now + reset, isRaid = isRaid == true, encounters = numEncounters, progress = progress,
            }
        end
    end
    local c = module.db.char
    c.lockouts = list
    c.lockoutsScanned = now
    StoreCharacter()
    ns.API.Emit("GATHERER_FARMS", { action = "lockouts" })
    return list
end

local function Matches(lock, instance)
    if instance.mapID and lock.mapID then return lock.mapID == instance.mapID end
    return type(lock.name) == "string" and type(instance.name) == "string"
        and lock.name:lower() == instance.name:lower()
end

local function MaxLevel()
    return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or nil
end

local function SortColumns(ids)
    local rank = {}
    for i, id in ipairs(ORDER) do rank[id] = i end
    table.sort(ids, function(a, b)
        local ra, rb = rank[a] or (100 + a), rank[b] or (100 + b)
        return ra < rb
    end)
    return ids
end

--- Overview for a farm with an instance, or nil:
-- { instance, total, columns = { { id, name, free, count } },
--   rows = { { char, class, cells = { [difficultyID] = { progress, encounters, resetAt } } } } }
-- A missing cell means the character is not saved on that difficulty.
function Lockouts.Grid(farm)
    local instance = farm and farm.instance
    if type(instance) ~= "table" then return nil end
    local now = time()
    local maxLevel = MaxLevel()
    local seen, columns = {}, {}
    for _, id in ipairs(instance.isRaid and RAID_DIFFICULTIES or DUNGEON_DIFFICULTIES) do
        seen[id] = true
        columns[#columns + 1] = id
    end
    local total = ns.Instances and ns.Instances.EncounterCount(instance.journalID)
    local rows = {}
    for charKey, c in pairs(module.db.root.chars) do
        if type(c) == "table" and c.lockoutsScanned and (not maxLevel or (c.level or 0) >= maxLevel) then
            local row = { char = charKey, class = c.class, cells = {} }
            for _, lock in ipairs(c.lockouts or {}) do
                if lock.resetAt > now and lock.difficultyID and Matches(lock, instance) then
                    row.cells[lock.difficultyID] = { progress = lock.progress or 0, encounters = lock.encounters,
                        resetAt = lock.resetAt }
                    total = total or lock.encounters
                    if not seen[lock.difficultyID] then
                        seen[lock.difficultyID] = true
                        columns[#columns + 1] = lock.difficultyID
                    end
                end
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b) return a.char < b.char end)
    local result = { instance = instance, total = total, columns = {}, rows = rows }
    for _, id in ipairs(SortColumns(columns)) do
        local free = 0
        for _, row in ipairs(rows) do
            local cell = row.cells[id]
            if not cell or (cell.encounters and cell.progress < cell.encounters) then free = free + 1 end
        end
        result.columns[#result.columns + 1] = { id = id, name = ns.Instances.DifficultyName(id), free = free,
            count = #rows }
    end
    return result
end

--- "2d 4h", "3h 12m", "12m" (the shared format).
function Lockouts.FormatRemaining(seconds)
    return ns.API.Format:Remaining(seconds)
end

--- Cell text: green "free" (or 0/N), yellow partial "5/10", red cleared "10/10".
function Lockouts.CellText(cell, total)
    local L = ns.L
    if not cell then
        return CODE.good .. (total and ("0/" .. total) or L["free"]) .. "|r"
    end
    local encounters = cell.encounters or total
    local text = encounters and (cell.progress .. "/" .. encounters) or tostring(cell.progress)
    local cleared = encounters and cell.progress >= encounters
    return (cleared and CODE.bad or CODE.gold) .. text .. "|r"
end

function Lockouts.Enable(m)
    module = m
    m:RegisterEvent("UPDATE_INSTANCE_INFO", function() Lockouts.Read() end)
    m:RegisterEvent("PLAYER_ENTERING_WORLD", function() RequestSoon(3) end)
    m:RegisterEvent("BOSS_KILL", function() RequestSoon(2) end)
    m:RegisterEvent("PLAYER_LEVEL_UP", function(_, level) StoreCharacter(level) end)
    StoreCharacter()
    Request()
end

function Lockouts.Disable()
    requestToken = requestToken + 1
end
