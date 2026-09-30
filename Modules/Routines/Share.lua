if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Share.lua
-- Routine exchange strings, to share routines with a community:
--   !GOB:ROUTINE:1!<data>   task definitions: id, kind, name, ref, frequency, value,
--                           duration, note (no progress, no characters)
-- data = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(LibSerialize:Serialize(payload)))
-- Import checks every field. Tasks already known keep the user's choices; new ones
-- arrive as suggestions (source "imported") to pin or ignore.
local _, ns = ...

local Share = {}
ns.Share = Share

local VERSION = 1
local MAX_TASKS = 300
local KINDS = { quest = true, instance = true, worldboss = true, delve = true, patron = true, profession = true }

local function Libs()
    local serialize = LibStub and LibStub("LibSerialize", true)
    local deflate = LibStub and LibStub("LibDeflate", true)
    return serialize, deflate
end

local function Text(v, max) return type(v) == "string" and #v <= max and v or nil end
local function Number(v, min, max) return type(v) == "number" and v >= min and v <= max and v or nil end

--- A ref from a string: a quest ID, or a table with a few known fields.
local function Ref(ref)
    if type(ref) == "number" then return Number(ref, 1, 10000000) end
    if type(ref) ~= "table" then return nil end
    local out = {}
    for _, k in ipairs({ "mapID", "difficultyID", "id", "lineID", "recipeID" }) do out[k] = Number(ref[k], 0, 100000000) end
    for _, k in ipairs({ "name", "profession" }) do out[k] = Text(ref[k], 100) end
    out.isRaid = ref.isRaid == true or nil
    out.vault = ref.vault == true or nil
    return next(out) and out or nil
end

--- A task from a string, or nil when a field is not valid.
function Share.Clean(t)
    if type(t) ~= "table" then return nil end
    local id = Text(t.id, 80)
    if not id or not id:match("^[%w:%-]+$") or not KINDS[t.kind] then return nil end
    return {
        id = id, kind = t.kind, name = Text(t.name, 120), ref = Ref(t.ref),
        frequency = (t.frequency == "daily" or t.frequency == "weekly") and t.frequency or nil,
        value = Number(t.value, 0, 1e12), duration = Number(t.duration, 1, 600), note = Text(t.note, 300),
    }
end

--- String for the given task ids (default: every pinned task), or nil.
function Share.Export(ids)
    local serialize, deflate = Libs()
    if not (serialize and deflate) then return nil end
    local tasks = ns.Routines.db.root.tasks
    local list = {}
    local function Add(t)
        local value, minutes = ns.Tasks.Estimate(t)
        list[#list + 1] = { id = t.id, kind = t.kind, name = t.name, ref = t.ref, frequency = t.frequency,
            value = value > 0 and math.floor(value) or nil, duration = math.floor(minutes + 0.5), note = t.note }
    end
    if ids then
        for _, id in ipairs(ids) do if tasks[id] then Add(tasks[id]) end end
    else
        for _, t in pairs(tasks) do if t.pinned then Add(t) end end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    local data = deflate:EncodeForPrint(deflate:CompressDeflate(serialize:Serialize({ tasks = list })))
    return ("!GOB:ROUTINE:%d!%s"):format(VERSION, data)
end

--- Import a string: added count, known count; or nil and an error ("format", "version", "libs").
function Share.Import(text)
    local serialize, deflate = Libs()
    if not (serialize and deflate) then return nil, "libs" end
    text = strtrim(text or ""):gsub("%s", "")
    local version, data = text:match("^!GOB:ROUTINE:(%d+)!(.+)$")
    if not version then return nil, "format" end
    if tonumber(version) > VERSION then return nil, "version" end
    local decoded = deflate:DecodeForPrint(data)
    local raw = decoded and deflate:DecompressDeflate(decoded)
    if not raw then return nil, "format" end
    local ok, payload = serialize:Deserialize(raw)
    if not ok or type(payload) ~= "table" or type(payload.tasks) ~= "table" then return nil, "format" end
    local tasks = ns.Routines.db.root.tasks
    local added, known = 0, 0
    for i = 1, math.min(#payload.tasks, MAX_TASKS) do
        local t = Share.Clean(payload.tasks[i])
        if t then
            local existing = tasks[t.id]
            if existing then
                known = known + 1
                existing.name = existing.name or t.name
                existing.ref = existing.ref or t.ref
                existing.frequency = existing.frequency or t.frequency
            else
                added = added + 1
                tasks[t.id] = { id = t.id, kind = t.kind, name = t.name, ref = t.ref, frequency = t.frequency,
                    note = t.note, source = "imported", preset = { value = t.value, duration = t.duration } }
            end
        end
    end
    ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
    return added, known
end
