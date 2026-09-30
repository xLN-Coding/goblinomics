if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Activities.lua
-- Tasks whose state comes from other systems:
--   delve       the Great Vault's world row (delves and other world activities):
--               C_WeeklyRewards progress towards its highest threshold, per character
--   patron      patron (NPC) crafting orders seen at the crafting table, per character
--               and profession: count, value (tip plus rewards at market price), expiry;
--               done when none is left. Read only when the game lists them.
--   profession  concentration full / cooldown ready from the Workshop (API.Workshop:Due);
--               open while it is due, otherwise "ready in"
-- Values: delves from the Gatherer's delve runs if any, patron orders from their rewards,
-- concentration from its gold value per point.
local _, ns = ...

local Activities = {}
ns.Activities = Activities

local VAULT_ID = "delve:vault"
local module

local function Now() return time() end

-- Great Vault ----------------------------------------------------------------------------------
local function WorldType()
    local E = Enum and Enum.WeeklyRewardChestThresholdType
    return E and (E.World or E.Activities) or 6
end

--- Read the world row of the Great Vault for the current character.
function Activities.ReadVault(now)
    now = now or Now()
    local wr = C_WeeklyRewards
    if not (wr and wr.GetActivities) then return end
    local activities = wr.GetActivities(WorldType()) or {}
    if #activities == 0 then return end
    local progress, top = 0, 0
    for _, a in ipairs(activities) do
        progress = math.max(progress, a.progress or 0)
        top = math.max(top, a.threshold or 0)
    end
    local c = module.db.char
    c.vault = { progress = progress, threshold = top, resetAt = ns.Routines.WeeklyResetAt(now), readAt = now }
    ns.Tasks.Learn({ id = VAULT_ID, kind = "delve", name = ns.L["Delves for the Great Vault"], frequency = "weekly",
        ref = { vault = true } })
    ns.API.Emit("ROUTINES_UPDATED", { part = "vault" })
end

-- Patron orders --------------------------------------------------------------------------------
local function RewardValue(order)
    local value = order.tipAmount or 0
    for _, r in ipairs(order.npcOrderRewards or {}) do
        local key = r.itemLink and ns.API.ItemKey.FromLink(r.itemLink)
        if key then
            local e = ns.API.Value:Evaluate(key, { quantity = r.count or 1 })
            value = value + (e and e.total or 0)
        end
    end
    return value
end

--- Read the patron orders the game lists for the open profession (nothing when none are listed).
function Activities.ReadPatronOrders(now)
    now = now or Now()
    local co = C_CraftingOrders
    if not (co and co.GetCrafterOrders) then return end
    local orders = co.GetCrafterOrders() or {}
    local npc = Enum and Enum.CraftingOrderType and Enum.CraftingOrderType.Npc or 3
    local info = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local profession = info and info.professionName
    if not profession then return end
    local count, value, expires = 0, 0, nil
    local listed = false
    for _, o in ipairs(orders) do
        listed = true
        if o.orderType == npc then
            count = count + 1
            value = value + RewardValue(o)
            if o.expirationTime and (not expires or o.expirationTime < expires) then expires = o.expirationTime end
        end
    end
    if not listed then return end
    local c = module.db.char
    c.patron = c.patron or {}
    c.patron[profession] = { count = count, value = value, expires = expires, readAt = now }
    local task = ns.Tasks.Learn({ id = "patron:" .. profession, kind = "patron", frequency = "weekly",
        name = ns.API.Lf("Patron orders (%s)", profession), ref = { profession = profession } })
    if count > 0 then ns.Tasks.Measure(task, value) end
    ns.API.Emit("ROUTINES_UPDATED", { part = "patron" })
end

local function OnFulfilled()
    local c = module and module.db.char
    for _, p in pairs(c and c.patron or {}) do
        if p.count and p.count > 0 then p.count = p.count - 1 end
    end
    ns.API.Emit("ROUTINES_UPDATED", { part = "patron" })
end

-- Workshop: concentration and cooldowns ---------------------------------------------------------
--- Due entries of the Workshop, learned as tasks "prof:c:<line>" and "prof:r:<recipe>".
function Activities.LearnProfessions(now)
    local workshop = ns.API.Workshop
    if not (workshop and workshop.Due) then return {} end
    local due = workshop:Due(now) or {}
    for _, d in ipairs(due) do
        if d.kind == "concentration" and d.lineID then
            ns.Tasks.Learn({ id = "prof:c:" .. d.lineID, kind = "profession", icon = d.icon,
                name = ns.API.Lf("Use concentration (%s)", d.label or "?"), ref = { lineID = d.lineID, profession = d.label } })
        elseif d.kind == "cooldown" and d.recipeID then
            ns.Tasks.Learn({ id = "prof:r:" .. d.recipeID, kind = "profession", icon = d.icon, name = d.label,
                ref = { recipeID = d.recipeID, profession = d.profession } })
        end
    end
    return due
end

local dueCache, dueAt = nil, nil
local function Due(now)
    if not dueCache or dueAt ~= now then
        local workshop = ns.API.Workshop
        dueCache = workshop and workshop.Due and workshop:Due(now) or {}
        dueAt = now
    end
    return dueCache
end

--- Value of spending a character's full concentration of a profession.
function Activities.ConcentrationValue(profession, points)
    local workshop = ns.API.Workshop
    local byProfession = workshop and workshop.ConcentrationValue and workshop:ConcentrationValue() or {}
    local entry = profession and byProfession[profession]
    return entry and entry.value and entry.value * (points or 1000) or nil
end

-- State ------------------------------------------------------------------------------------------
--- done, detail, resetAt for delve, patron and profession tasks; nil for other kinds.
function Activities.State(t, c, now, charKey)
    now = now or Now()
    local ref = t.ref or {}
    if t.kind == "delve" and ref.vault then
        local v = c.vault
        if not v or not v.resetAt or v.resetAt <= now then return false, nil, nil end
        return (v.progress or 0) >= (v.threshold or 1), ("%d/%d"):format(v.progress or 0, v.threshold or 0), v.resetAt
    elseif t.kind == "patron" then
        local p = c.patron and c.patron[ref.profession]
        if not p then return false, nil, nil end
        if p.expires and p.expires <= now then return false, nil, nil end   -- new orders may be there
        return (p.count or 0) == 0, p.count and tostring(p.count) or nil, p.expires
    elseif t.kind == "profession" then
        for _, d in ipairs(Due(now)) do
            if d.char == charKey and ((ref.lineID and d.lineID == ref.lineID) or (ref.recipeID and d.recipeID == ref.recipeID)) then
                if d.at <= now then return false, ns.L["ready"], nil end
                return true, ns.API.Lf("in %s", ns.API.Format:Remaining(d.at - now)), d.at
            end
        end
        return true, nil, nil       -- the character does not have it
    end
    return nil
end

--- Estimated value for tasks measured elsewhere: delves and instances from Gatherer runs,
-- concentration from its value per point. nil when nothing is known.
function Activities.Estimate(t)
    local gatherer = ns.API.Gatherer
    if t.kind == "instance" and t.ref and t.ref.mapID and gatherer and gatherer.InstanceStats then
        local s = gatherer:InstanceStats(t.ref.mapID)
        if s then return s.value, s.minutes end
    elseif t.kind == "profession" and t.ref and t.ref.lineID then
        return Activities.ConcentrationValue(t.ref.profession, 1000), nil
    end
    return nil
end

function Activities.Enable(m)
    module = m
    m:RegisterEvent("WEEKLY_REWARDS_UPDATE", function() Activities.ReadVault() end)
    m:RegisterEvent("TRADE_SKILL_SHOW", function() m:After(2, function() Activities.ReadPatronOrders() end) end)
    m:RegisterEvent("CRAFTINGORDERS_UPDATE_ORDER_COUNT", function() m:After(1, function() Activities.ReadPatronOrders() end) end)
    m:RegisterEvent("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", OnFulfilled)
    ns.API.On("WORKSHOP_PROFESSIONS", function() Activities.LearnProfessions() end, "Goblinomics_Routines.Activities")
    m:After(5, function()
        Activities.ReadVault()
        Activities.LearnProfessions()
    end)
end

function Activities.Disable()
    dueCache = nil
    if ns.API then ns.API.Off("WORKSHOP_PROFESSIONS", "Goblinomics_Routines.Activities") end
end
