if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Debug.lua
-- Internal debug module: registers like any feature module and prints every core
-- bus event to chat. Off by default; toggled with /gob debug. It is the "dummy
-- module" of the M1 acceptance criteria.
local _, ns = ...

local Money = ns.Money
local L = ns.L
ns.DEBUG_MODULE = "Goblinomics_Debug"

local Debug = ns.API.RegisterModule(ns.DEBUG_MODULE, {
    apiVersion = 1,
    name = "Debug",
    addon = ns.ADDON_NAME,
    internal = true,
    defaultEnabled = false,
    order = 1000,
})

local function Out(tag, text)
    ns.Print("|cff999999[" .. tag .. "]|r " .. text, true)
end

local function Where(payload)
    local ctx = payload.context
    local label = ctx and ns.Context.Label(ctx) or nil
    local parts = { "(" .. (label or "-") .. ")" }
    if payload.restricted then
        parts[#parts + 1] = "[" .. L["restricted"] .. " " .. tostring(payload.restricted) .. "]"
    end
    if payload.reconciled then
        parts[#parts + 1] = "[" .. L["reconciled"] .. "]"
    end
    return table.concat(parts, " ")
end

local function Quantity(n)
    return n > 0 and ("+" .. n) or tostring(n)
end

function Debug:OnEnable()
    self:On("MONEY_DELTA", function(_, p)
        Out("MONEY", p.scope .. " " .. Money.Format(p.amount, { sign = true, color = true }) .. " " .. Where(p))
    end)
    self:On("LOOT_RECEIVED", function(_, p)
        Out("LOOT", p.link .. " x" .. p.quantity .. " (" .. p.source.kind .. ")" .. (p.restricted and " " .. Where(p) or ""))
    end)
    self:On("ITEMS_DELTA", function(_, p)
        local parts = {}
        for i = 1, #p.changes do
            local c = p.changes[i]
            parts[#parts + 1] = (c.link or c.itemKey) .. " " .. Quantity(c.delta)
        end
        Out("ITEMS", table.concat(parts, ", ") .. " " .. Where(p))
    end)
    self:On("CONTEXT_CHANGED", function(_, p)
        Out("CTX", p.key .. " " .. (p.active and "on" or "off"))
    end)
    self:On("RESTRICTED_ENTER", function(_, p)
        Out("RESTRICTED", L["enter"] .. " " .. p.kind)
    end)
    self:On("RESTRICTED_LEAVE", function(_, p)
        Out("RESTRICTED", ns.Lf("leave %s: %d buffered, %d secret%s", p.kind, p.buffered, p.secret,
            p.overflow and (", " .. L["overflow"]) or ""))
    end)
end
