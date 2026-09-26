if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Concentration.lua
-- Concentration value:
--   per craft:      (value of the reached quality - value of the quality below)
--                   x quantity / concentration spent
--   per profession: sum of the value gains / sum of concentration over the
--                   window (default 30 days)
-- Both unit values are market prices stored at the time of the craft. Crafts
-- without a known value of the quality below are left out.
local _, ns = ...

local Concentration = {}
ns.Concentration = Concentration

local module

--- Value gain of a record in copper and its concentration, or nil.
function Concentration.Gain(record)
    if not (record.concentration and record.below and record.reached) then return nil end
    local o = record.outputs and record.outputs[1]
    if not o then return nil end
    return (record.reached - record.below) * o[2], record.concentration
end

--- Copper per concentration point of one record, or nil.
function Concentration.PerPoint(record)
    local gain, points = Concentration.Gain(record)
    if not gain or points <= 0 then return nil end
    return gain / points
end

--- { [profession] = { value = copper per point, crafts, points, gain } } for the window.
function Concentration.ByProfession(days)
    days = days or module.db.settings.concentrationDays
    local cutoff = time() - days * 86400
    local result = {}
    for _, r in ipairs(module.db.root.crafts) do
        if r.time >= cutoff and r.profession then
            local gain, points = Concentration.Gain(r)
            if gain then
                local p = result[r.profession]
                if not p then
                    p = { crafts = 0, points = 0, gain = 0 }
                    result[r.profession] = p
                end
                p.crafts = p.crafts + 1
                p.points = p.points + points
                p.gain = p.gain + gain
            end
        end
    end
    for _, p in pairs(result) do p.value = p.points > 0 and p.gain / p.points or 0 end
    return result
end

--- Recipes by value per concentration point in the window (best first):
-- { { recipe, name, profession, value, crafts, points, gain } }. filter = { profession, char }
function Concentration.ByRecipe(days, filter)
    days = days or module.db.settings.concentrationDays
    filter = filter or {}
    local cutoff = time() - days * 86400
    local list, byRecipe = {}, {}
    for _, r in ipairs(module.db.root.crafts) do
        if r.time >= cutoff and (not filter.profession or filter.profession == r.profession)
            and (not filter.char or filter.char == r.char) then
            local gain, points = Concentration.Gain(r)
            if gain then
                local e = byRecipe[r.recipe]
                if not e then
                    e = { recipe = r.recipe, name = r.name, profession = r.profession, output = r.outputs[1][1],
                        crafts = 0, points = 0, gain = 0 }
                    byRecipe[r.recipe] = e
                    list[#list + 1] = e
                end
                e.crafts = e.crafts + 1
                e.points = e.points + points
                e.gain = e.gain + gain
            end
        end
    end
    for _, e in ipairs(list) do e.value = e.points > 0 and e.gain / e.points or 0 end
    table.sort(list, function(a, b) return a.value > b.value end)
    return list
end

--- Value per point of one recipe in the window, or nil.
function Concentration.ForRecipe(recipe, days)
    for _, e in ipairs(Concentration.ByRecipe(days)) do
        if e.recipe == recipe then return e end
    end
    return nil
end

function Concentration.Enable(m)
    module = m
end
