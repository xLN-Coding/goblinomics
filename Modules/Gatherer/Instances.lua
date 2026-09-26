if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Gatherer/Instances.lua
-- Raid and dungeon catalogue per expansion from the Encounter Journal (as MRT
-- does): EJ_SelectTier + EJ_GetInstanceByIndex(index, isRaid). The journal
-- addon (Blizzard_EncounterJournal, load on demand) is loaded first, out of
-- combat, so every tier has its data. The catalogue is rebuilt whenever the menu
-- opens; only world-boss entries (neither area map nor instance map) are
-- skipped. mapID is the instance map ID that GetSavedInstanceInfo returns as
-- its 14th value, so lockouts match by ID (as AlterEgo does). The journal tier
-- the player had selected is restored.
local _, ns = ...

local Instances = {}
ns.Instances = Instances

local encounters = {}   -- journalID -> count
local JOURNAL_ADDON = "Blizzard_EncounterJournal"

local function Available()
    return EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetTierInfo
end

--- Load the Encounter Journal addon when needed (never in combat).
function Instances.EnsureJournal()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn) then return end
    if C_AddOns.IsAddOnLoaded(JOURNAL_ADDON) or InCombatLockdown() then return end
    pcall(C_AddOns.LoadAddOn, JOURNAL_ADDON)
end

local function IsWorldBosses(areaMapID, mapID)
    return (areaMapID == nil or areaMapID == 0) and (mapID == nil or mapID == 0)
end

--- Expansions (newest first) with their raids (isRaid = true) or dungeons.
function Instances.Catalog(isRaid)
    isRaid = isRaid == true
    local list = {}
    Instances.EnsureJournal()
    if not Available() then return list end
    local previous = EJ_GetCurrentTier and EJ_GetCurrentTier()
    for tier = EJ_GetNumTiers(), 1, -1 do
        EJ_SelectTier(tier)
        local entry = { tier = tier, name = EJ_GetTierInfo(tier), instances = {} }
        local index = 1
        while true do
            local journalID, name, _, _, _, _, _, areaMapID, _, _, mapID = EJ_GetInstanceByIndex(index, isRaid)
            if not journalID then break end
            if not IsWorldBosses(areaMapID, mapID) then
                entry.instances[#entry.instances + 1] = { journalID = journalID, mapID = mapID, name = name,
                    isRaid = isRaid }
            end
            index = index + 1
        end
        if #entry.instances > 0 then list[#list + 1] = entry end
    end
    if previous then EJ_SelectTier(previous) end
    return list
end

--- Number of encounters of a journal instance (nil when unknown).
function Instances.EncounterCount(journalID)
    if not journalID or not EJ_GetEncounterInfoByIndex then return nil end
    if encounters[journalID] then return encounters[journalID] end
    local count = 0
    while EJ_GetEncounterInfoByIndex(count + 1, journalID) do count = count + 1 end
    encounters[journalID] = count > 0 and count or nil
    return encounters[journalID]
end

--- Diagnostic lines for /gob farm instances: tiers and raw instance counts.
function Instances.Report()
    Instances.EnsureJournal()
    local lines = {}
    if not Available() then
        lines[1] = "Encounter Journal API not available"
        return lines
    end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(JOURNAL_ADDON)
    lines[1] = ("journal loaded: %s, tiers: %d"):format(tostring(loaded), EJ_GetNumTiers())
    local previous = EJ_GetCurrentTier and EJ_GetCurrentTier()
    for tier = 1, EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        local counts = {}
        for _, isRaid in ipairs({ true, false }) do
            local n, skipped, index = 0, 0, 1
            while true do
                local journalID, _, _, _, _, _, _, areaMapID, _, _, mapID = EJ_GetInstanceByIndex(index, isRaid)
                if not journalID then break end
                if IsWorldBosses(areaMapID, mapID) then skipped = skipped + 1 else n = n + 1 end
                index = index + 1
            end
            counts[#counts + 1] = ("%s %d (+%d skipped)"):format(isRaid and "raids" or "dungeons", n, skipped)
        end
        lines[#lines + 1] = ("%d %s: %s"):format(tier, tostring(EJ_GetTierInfo(tier)), table.concat(counts, ", "))
    end
    if previous then EJ_SelectTier(previous) end
    return lines
end

--- Localised difficulty name.
function Instances.DifficultyName(difficultyID)
    local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    return name or tostring(difficultyID)
end

function Instances.Reset()
    wipe(encounters)
end
