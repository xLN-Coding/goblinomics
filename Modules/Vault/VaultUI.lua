if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Vault/VaultUI.lua
-- Vault tab (alt overview with freshness per location, one wealth figure with
-- the speculative part), the wealth tooltip and the "Vault" settings section.
-- The dashboard cards live in Cards.lua.
local _, ns = ...

local VUI = {}
ns.VaultUI = VUI

local API = ns.API
local L = API.L
local Money = API.Money
local Freshness = ns.Freshness
local LETTERS = { bags = "T", bank = "B", mail = "P", auctions = "A", equipment = "E" }

-- Display names of the locations (English text is the locale key).
local function LocationName(id)
    if id == "bags" then return L["Bags"] end
    if id == "bank" then return L["Bank"] end
    if id == "mail" then return L["Mail"] end
    if id == "auctions" then return L["Auctions"] end
    return L["Equipment"]
end
local OWNER_TAB = "Goblinomics_Vault.Tab"

local vault
local tab = {}      -- widgets of the tab page

local function Fmt(copper)
    return Money.Format(copper or 0, { abbreviate = true })
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

local function Rows(result)
    local rows = {}
    for charKey, c in pairs(result.chars) do
        local last = c.goldSeenAt
        for _, loc in pairs(c.locations) do
            if loc.seenAt and (not last or loc.seenAt > last) then last = loc.seenAt end
        end
        rows[#rows + 1] = { key = charKey, char = c, last = last }
    end
    table.sort(rows, function(a, b) return a.char.wealth > b.char.wealth end)
    rows[#rows + 1] = { key = "warband", warband = result.warband, last = result.warband.seenAt }
    return rows
end

local function Pct(v) return API.Format:Percent(v) end

local function LocationTooltip(owner, row)
    local W = API.Widgets
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if row.warband then
        local w = row.warband
        W.TooltipTitle(L["Warband bank"])
        W.TooltipPair(L["Status"], Freshness.Colorize(w.state, Freshness.Label(w.state)))
        W.TooltipPair(L["Seen by"], w.seenBy or "-")
        W.TooltipPair(L["Items"], Fmt(w.items))
    else
        W.TooltipTitle(row.char.name)
        for _, id in ipairs(ns.LOCATIONS) do
            local loc = row.char.locations[id]
            W.TooltipPair(LocationName(id) .. ": " .. Freshness.Colorize(loc.state, Freshness.Label(loc.state)),
                (loc.state == "never" and "-" or (Fmt(loc.value) .. "  " .. Freshness.Age(loc.seenAt))))
        end
    end
    GameTooltip:Show()
end

local columns   -- Widgets.Columns, built with the tab

local function InitRow(row, data)
    local Theme = API.Theme
    local C = Theme.colors
    if not row.cells then
        columns:Cells(row)
        API.Widgets.RowBackground(row)
        row:SetScript("OnEnter", function(self) LocationTooltip(self, self.data) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.data = data
    local cells = row.cells
    if data.warband then
        local w = data.warband
        cells.name:SetText(Theme.Colorize(L["Warband bank"], C.gold))
        cells.gold:SetText(Fmt(w.gold))
        cells.items:SetText(Fmt(w.items + w.auctions))
        cells.wealth:SetText(Fmt(w.wealth))
        cells.locations:SetText(Freshness.Colorize(w.state, "W"))
    else
        local c = data.char
        cells.name:SetText("|c" .. ClassColor(c.class) .. c.name .. "|r")
        cells.gold:SetText(Fmt(c.gold))
        cells.items:SetText(Fmt(c.items + c.auctions))
        cells.wealth:SetText(Fmt(c.wealth))
        local letters = {}
        for _, id in ipairs(ns.LOCATIONS) do
            local loc = c.locations[id]
            letters[#letters + 1] = Freshness.Colorize(loc.state, LETTERS[id])
        end
        cells.locations:SetText(table.concat(letters, " "))
    end
    cells.seen:SetText(Freshness.Age(data.last))
end

local function RefreshTab()
    local result = ns.Networth.Get()
    if not tab.list or not result then return end
    local Theme = API.Theme
    local speculative = API.Price:HasRole("saleRate")
        and ("  " .. Theme.Colorize("(" .. L["of which speculative"] .. " " .. Fmt(result.speculative) .. ")",
            Theme.colors.textDim)) or ""
    tab.summary:SetText(("%s %s%s   %s %s   %s %s   %s %s   %s"):format(
        L["Wealth"], Fmt(result.wealth), speculative,
        L["Gold"], Fmt(result.gold), L["Auctions"], Fmt(result.auctions), L["Items"], Fmt(result.items),
        Theme.Colorize(L["Confidence"] .. " " .. Pct(result.confidence), Theme.colors.textDim)))
    tab.list:SetData(Rows(result))
end

local function BuildTab(page)
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    local goals = W.Button(page, L["Manage goals"], { auto = true,
        onClick = function() if ns.Goals then ns.Goals.OpenDialog() end end })
    goals:SetPoint("TOPRIGHT", -S.GUTTER, 0)
    local summary = Theme.Text(page, "body", C.text)
    summary:SetPoint("LEFT", page, "TOPLEFT", 0, -S.CONTROL_H / 2)
    summary:SetPoint("RIGHT", goals, "LEFT", -S.GAP, 0)
    summary:SetWordWrap(false)
    tab.summary = summary
    columns = W.Columns({
        { key = "name", label = L["Character"] },
        { key = "gold", label = L["Gold"], width = 90, align = "RIGHT" },
        { key = "items", label = L["Items"], width = 90, align = "RIGHT" },
        { key = "wealth", label = L["Wealth"], width = 90, align = "RIGHT" },
        { key = "locations", label = L["Locations"], width = 150, align = "CENTER" },
        { key = "seen", label = L["Seen"], width = 52, align = "RIGHT" },
    })
    local header = columns:Header(page)
    header:SetPoint("TOPLEFT", 0, S.CONTENT_TOP)
    header:SetPoint("RIGHT", page, "RIGHT", -S.GUTTER, 0)
    tab.list = W.ScrollList(page, { rowHeight = S.ROW, init = InitRow })
    tab.list.box:SetPoint("TOPLEFT", 0, S.CONTENT_TOP - S.HEADER_H - S.XS)
    tab.list.box:SetPoint("BOTTOMRIGHT", -S.GUTTER, 0)
    RefreshTab()
end

-- Dashboard tiles --------------------------------------------------------------
local function Line(left, right) API.Widgets.TooltipPair(left, right) end

local function Explain(text) API.Widgets.TooltipHint(text) end

-- Tooltip of the wealth tile: what the value contains, with the breakdown.
local TIPS = {
    ["vault.wealth"] = function(r, cfg)
        API.Widgets.TooltipTitle(L["Wealth"])
        Explain(L["Gold of all characters, the warband bank and mail, your active auctions and every item that can be sold (market price, vendor price for items that cannot go to the auction house). Bound and warbound items and equipped gear are not counted."])  -- luacheck: ignore 631
        GameTooltip:AddLine(" ")
        Line(L["Gold"], Fmt(r.gold))
        Line(L["Auctions"], Fmt(r.auctions))
        Line(L["Items"], Fmt(r.items))
        if API.Price:HasRole("saleRate") then   -- speculative needs a sale rate (TSM)
            GameTooltip:AddLine(" ")
            Explain(L["Speculative: items with a sale rate below %s; counted, but they rarely sell."]
                :format(Pct(cfg.speculativeThreshold)))
            Line(L["of which speculative"], Fmt(r.speculative))
        end
        if r.remote then
            GameTooltip:AddLine(" ")
            Line(L["Other accounts"], Fmt(r.remote.wealth))
        end
    end,
}

--- Wealth tooltip (used by the dashboard's gold card).
function VUI.WealthTooltip(owner)
    local r = ns.Networth.Get()
    if not r then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    TIPS["vault.wealth"](r, API.Price:Config())
    GameTooltip:Show()
end

-- Settings ---------------------------------------------------------------------
local function BuildSettings(parent, y)
    local settings = vault.db.settings
    local form = API.Form.New(parent, y)
    form:Group(L["Jealousmeter"])
    form:Toggle({ label = L["Show the Jealousmeter window"],
        description = L["A small window with Gallywix' face next to the main window."],
        get = function() return settings.jealousmeter.window end,
        set = function(on)
            settings.jealousmeter.window = on
            ns.JealousmeterUI.ApplyWindowSetting()
        end })
    form:Toggle({ label = L["Lock the Jealousmeter window"], description = L["The window can no longer be moved."],
        get = function() return settings.jealousmeter.locked end,
        set = function(on) settings.jealousmeter.locked = on end })
    form:Sound({ label = L["Sound on level-up"], description = L["Plays when you reach a new Jealousmeter level."],
        get = function() return settings.jealousmeter.sound end,
        set = function(value) settings.jealousmeter.sound = value end, default = "kit:UI_EPICLOOT_TOAST" })
    form:Group(L["Data freshness"], L["Bank, mail and auctions are only seen when you open them."])
    form:Slider({ label = L["Fresh for (hours)"], description = L["A location counts as up to date for this long."],
        min = 1, max = 24,
        get = function() return settings.freshHours end,
        set = function(v)
            settings.freshHours = v
            ns.Networth.Schedule()
        end })
    form:Slider({ label = L["Aging up to (days)"], description = L["After this, a location counts as stale."],
        min = 1, max = 14,
        get = function() return settings.agingDays end,
        set = function(v)
            settings.agingDays = v
            ns.Networth.Schedule()
        end })
    return form:Finish()
end

function VUI.Enable(module)
    vault = module
    API.UI:RegisterTab({
        id = "vault", title = function() return L["Vault"] end, order = 10,
        build = BuildTab,
        onShow = function()
            RefreshTab()
            API.On("NETWORTH_UPDATED", RefreshTab, OWNER_TAB)
        end,
        onHide = function() API.Off("NETWORTH_UPDATED", OWNER_TAB) end,
    })
    API.UI:RegisterHeaderTooltipProvider("vault.freshness", function(tt)
        local r = ns.Networth.Get()
        if not r then return end
        local counts = { fresh = 0, aging = 0, stale = 0, never = 0 }
        for _, c in pairs(r.chars) do
            for _, loc in pairs(c.locations) do counts[loc.state] = counts[loc.state] + 1 end
        end
        tt:AddLine(" ")
        tt:AddDoubleLine(L["Data freshness"], Pct(r.confidence), API.Theme.colors.gold[1], API.Theme.colors.gold[2],
            API.Theme.colors.gold[3], 1, 1, 1)
        tt:AddLine(L["share of item value from fresh data"], 0.6, 0.6, 0.6, true)
        for _, state in ipairs({ "fresh", "aging", "stale", "never" }) do
            tt:AddDoubleLine(Freshness.Colorize(state, Freshness.Label(state)), tostring(counts[state]), 1, 1, 1, 1, 1, 1)
        end
    end)
    API.UI:RegisterSettings({ id = "vault", title = function() return L["Vault"] end, order = 20, build = BuildSettings,
        description = function() return L["Jealousmeter and how long scanned locations stay fresh."] end })
end
