if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Presets.lua
-- Community presets: tasks that come with the addon as suggestions (source "preset").
-- Kept apart from the logic so they are easy to update per patch. Only entries that
-- were checked in the game go in here; quest IDs change between patches, and a wrong
-- ID would mark a task done that is not. Fields as in a shared string (Share.lua),
-- value in copper and duration in minutes as a starting point until own runs measure it.
local _, ns = ...

local Presets = {}
ns.Presets = Presets

Presets.LIST = {
    { id = "delve:vault", kind = "delve", frequency = "weekly", ref = { vault = true }, duration = 15,
        name = function() return ns.L["Delves for the Great Vault"] end },
}

--- Add the presets that are not known yet as suggestions; returns how many were added.
function Presets.Apply(root)
    local added = 0
    for _, p in ipairs(Presets.LIST) do
        if not root.tasks[p.id] then
            root.tasks[p.id] = { id = p.id, kind = p.kind, frequency = p.frequency, ref = p.ref, source = "preset",
                name = type(p.name) == "function" and p.name() or p.name,
                preset = { value = p.value, duration = p.duration } }
            added = added + 1
        end
    end
    return added
end

function Presets.Enable(m)
    Presets.Apply(m.db.root)
end
