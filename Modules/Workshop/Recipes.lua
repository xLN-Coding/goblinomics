if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/Recipes.lua
-- Recipe facts, cached per session: name, profession (parent profession name,
-- as Journalator shows it), salvage and enchanting flags, quality IDs, and the
-- output item of a recipe at a given quality (reagents: GetRecipeQualityItemIDs;
-- gear: GetRecipeOutputItemData with a quality override, as Auctionator does).
local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

local cache = {}

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

--- { recipeID, name, profession, professionID, isSalvage, isEnchanting, qualityIDs, maxQuality } or nil
function Recipes.Info(recipeID)
    if type(recipeID) ~= "number" or IsSecret(recipeID) then return nil end
    local info = cache[recipeID]
    if info then return info end
    local r = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
    local p = C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
    info = {
        recipeID = recipeID,
        name = r and r.name or ("#" .. recipeID),
        isSalvage = r and r.isSalvageRecipe == true or false,
        isEnchanting = r and r.isEnchantingRecipe == true or false,
        qualityIDs = r and r.qualityIDs or nil,
        maxQuality = r and r.maxQuality or nil,
        professionID = p and (p.parentProfessionID or p.professionID) or nil,
        profession = p and (p.parentProfessionName or p.professionName) or nil,
    }
    -- recipe data can arrive later (categoryID 0 = not loaded yet); do not cache half data
    if r and r.name then cache[recipeID] = info end
    return info
end

-- Runeforging (death knights) is a profession line to the game but not a craft:
-- its recipes are never tracked, and older records of it are removed.
local RUNEFORGING = 960
Recipes.RUNEFORGING = RUNEFORGING

--- Is a recipe left out of the Workshop (runeforging)?
function Recipes.IsIgnored(recipeID)
    local info = Recipes.Info(recipeID)
    return info ~= nil and info.professionID == RUNEFORGING
end

--- Remove records of ignored recipes (crafts, cooldowns of every character).
function Recipes.PurgeIgnored(root)
    local removed = 0
    for i = #(root.crafts or {}), 1, -1 do
        if Recipes.IsIgnored(root.crafts[i].recipe) then
            table.remove(root.crafts, i)
            removed = removed + 1
        end
    end
    for _, c in pairs(root.chars or {}) do
        for recipeID in pairs(type(c) == "table" and c.cooldowns or {}) do
            if Recipes.IsIgnored(recipeID) then c.cooldowns[recipeID] = nil end
        end
    end
    return removed
end

--- Item key of the recipe's output at `quality` (1..n), or nil.
function Recipes.QualityItemKey(recipeID, quality, reagents)
    if not quality or quality < 1 then return nil end
    local ids = C_TradeSkillUI.GetRecipeQualityItemIDs and C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)
    if type(ids) == "table" and ids[quality] then return "i:" .. ids[quality] end
    local info = Recipes.Info(recipeID)
    local qualityID = info and info.qualityIDs and info.qualityIDs[quality]
    if qualityID and C_TradeSkillUI.GetRecipeOutputItemData then
        local out = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagents or {}, nil, qualityID)
        local link = out and out.hyperlink
        if link and not IsSecret(link) then return ns.API.ItemKey.FromLink(link) end
    end
    return nil
end

function Recipes.Reset()
    wipe(cache)
end
