if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/Vault.lua
-- Vault: inventory snapshots of every character (bags, bank, warband bank, mail,
-- auctions, equipment) with a timestamp per location, one wealth figure, a daily
-- value per character and the Gallywix Jealousmeter. This file registers the module
-- and wires the parts together; the other files share the addon namespace.
local ADDON_NAME, ns = ...

local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API then return end
ns.API = API
ns.L = API.L

local Vault = API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "Vault",
    description = function() return API.L["Inventory of every character, wealth and the Jealousmeter."] end,
    order = 10,
    db = {
        sv = "GoblinomicsVaultDB",
        version = 2,
        migrations = {
            -- schema 2: one wealth figure; the old market tier comes closest
            [2] = function(root)
                for _, h in pairs(type(root.history) == "table" and root.history or {}) do
                    if type(h) == "table" and h.wealth == nil then
                        h.wealth = h.market or h.total or 0
                        h.liquid, h.market, h.total = nil, nil, nil
                    end
                end
            end,
        },
        defaults = {
            jealousmeter = { window = false, locked = false, sound = "kit:UI_EPICLOOT_TOAST" },
            freshHours = 6,
            agingDays = 3,
        },
        charDefaults = {},
    },
})
ns.Vault = Vault

-- Public, read-only: other modules read the wealth and its history.
API.Vault = {
    --- Current networth result (nil until the first computation).
    Current = function() return ns.Networth and ns.Networth.Get() end,
    --- Daily history: { ["YYYY-MM-DD"] = { wealth, speculative, gold, chars, warband } }.
    History = function() return Vault.db and Vault.db.root.history or {} end,
    --- Link (M8): snapshot of this account, other accounts' snapshots.
    Snapshot = function(_, label)
        return Vault.db and ns.Remote.Snapshot(Vault.db.root, ns.Networth.Get(), label) or nil
    end,
    SetRemote = function(_, snap)
        if not Vault.db then return false, "disabled" end
        local ok, reason = ns.Remote.Set(Vault.db.root, snap)
        if ok and ns.Networth then ns.Networth.Schedule() end
        return ok, reason
    end,
    RemoveRemote = function(_, id)
        local ok = Vault.db and ns.Remote.Remove(Vault.db.root, id)
        if ok and ns.Networth then ns.Networth.Schedule() end
        return ok
    end,
    Remotes = function() return Vault.db and ns.Remote.Sum(Vault.db.root).accounts or {} end,
}

--- Location ids of a character, in display order.
ns.LOCATIONS = { "bags", "bank", "mail", "auctions", "equipment" }

function Vault:OnInit()
    local root = self.db.root
    if type(root.warband) ~= "table" then root.warband = {} end
    if type(root.history) ~= "table" then root.history = {} end
    if type(root.jealousmeter) ~= "table" then root.jealousmeter = { highestLevel = -1 } end
end

function Vault:OnEnable()
    local c = self.db.char
    c.class = select(2, UnitClass("player"))
    c.name = UnitName("player")
    if type(c.locations) ~= "table" then c.locations = {} end
    for _, part in ipairs({ "Scanner", "Networth", "JealousmeterUI", "VaultUI", "Speculative", "SpeculativeUI", "VaultCards", "Goals" }) do
        if ns[part] and ns[part].Enable then ns[part].Enable(self) end
    end
end

function Vault:OnDisable()
    for _, part in ipairs({ "Goals", "JealousmeterUI", "Networth", "Scanner" }) do
        if ns[part] and ns[part].Disable then ns[part].Disable(self) end
    end
end

function Vault:OnLogout()
    if ns.Scanner then ns.Scanner.OnLogout(self) end
    if ns.Networth then ns.Networth.OnLogout(self) end
end
