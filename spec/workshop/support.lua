-- Shared helpers for workshop specs.
local M = {}

function M.link(id, name)
    return ("|cffffffff|Hitem:%d::::::::80:::::|h[%s]|h|r"):format(id, name or "Item")
end

local op = 0
--- Run a craft series: crafts = { results_of_craft_1, results_of_craft_2, ... }
function M.craft(recipeID, reagents, crafts, opts)
    opts = opts or {}
    local call = opts.call or function()
        C_TradeSkillUI.CraftRecipe(recipeID, #crafts, reagents, nil, opts.orderID, opts.concentrating)
    end
    call()
    WoWMock.fire("TRADE_SKILL_CRAFT_BEGIN", recipeID)
    for _, results in ipairs(crafts) do
        WoWMock.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", recipeID)
        for _, r in ipairs(results) do WoWMock.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT", r) end
        WoWMock.advance(0.2)
    end
end

--- One result table; fields: id, name, qty, quality, conc, returned = { {itemID, qty} }, op
function M.result(f)
    op = op + 1
    local returned = {}
    for _, r in ipairs(f.returned or {}) do returned[#returned + 1] = { reagent = { itemID = r[1] }, quantity = r[2] } end
    return { itemID = f.id, hyperlink = f.id and M.link(f.id, f.name) or nil, quantity = f.qty or 1,
        craftingQuality = f.quality, concentrationSpent = f.conc, operationID = f.op or op,
        resourcesReturned = returned, isEnchant = f.isEnchant }
end

return M
