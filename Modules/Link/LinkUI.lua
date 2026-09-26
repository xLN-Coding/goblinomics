if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Link/LinkUI.lua
-- Settings section "Account link" (replaces the core placeholder): export
-- string to copy, a field to paste the other account's string, the linked
-- accounts with their wealth, date and a remove button.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local UI = {}
ns.LinkUI = UI

local API = ns.API
local L = ns.L
local ROWS = 4

local section = {}
UI.section = section

local REASONS = {
    format = function() return L["This is not a Goblinomics link string."] end,
    version = function() return L["The string comes from another Goblinomics version."] end,
    own = function() return L["This string comes from this account."] end,
    older = function() return L["This account is already linked with a newer state."] end,
    vault = function() return L["The Vault module is needed for the link."] end,
}

function UI.RefreshList()
    local list = API.Vault and API.Vault.Remotes and API.Vault:Remotes() or {}
    for i, row in ipairs(section.rows or {}) do
        local a = list[i]
        row.text:SetText(a and ("%s  " .. CODE.dim .. "%s|r  %s  " .. CODE.dim .. "%s|r"):format(a.label, API.Lf("%d characters", a.chars),
            API.Money.Format(a.wealth, { abbreviate = true }),
            ns.API.Format:Date(a.seenAt or 0, "longStamp")) or "")
        row.remove:SetShown(a ~= nil)
        row.account = a
    end
    section.none:SetShown(#list == 0)
end

function UI.Import(text)
    local ok, reason = ns.Link.Import(text)
    section.status:SetText(ok and (CODE.good .. L["Account linked."] .. "|r")
        or (CODE.bad .. (REASONS[reason] or REASONS.format)() .. "|r"))
    UI.RefreshList()
    return ok
end

function UI.Build(parent, y)
    local W, Theme = API.Widgets, API.Theme
    local C = Theme.colors
    local form = API.Form.New(parent, y)
    form:Group(L["Export"], L["Several WoW accounts: export the string on one account and import it on the other."])
    form:Custom(26, function(box)
        local export = W.EditBox(box, { width = 300, get = function() return section.exported or "" end,
            set = function() return true end })
        export:SetPoint("TOPLEFT", 0, 0)
        export:SetPoint("RIGHT", box, "RIGHT", -180, 0)
        export:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        local make = W.Button(box, L["Create export string"], { width = 170, onClick = function()
            section.exported = ns.Link.Export() or ""
            export:SetText(section.exported)
            export:SetFocus()
            export:HighlightText()
        end })
        make:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    end)

    form:Group(L["Import string"], L["Paste the string of the other account."])
    form:Custom(26, function(box)
        local input = W.EditBox(box, { width = 300, get = function() return "" end,
            set = function(text) return UI.Import(text) end })
        input:SetPoint("TOPLEFT", 0, 0)
        input:SetPoint("RIGHT", box, "RIGHT", -180, 0)
        section.input = input
        local import = W.Button(box, L["Import string"], { width = 170, onClick = function()
            if UI.Import(input:GetText()) then input:SetText("") end
        end })
        import:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    end)
    section.status = form:Note("", C.text).text

    form:Group(L["Linked accounts"])
    form:Custom(ROWS * 26, function(box)
        section.none = Theme.Text(box, 11, C.textDim)
        section.none:SetPoint("TOPLEFT", 0, -4)
        section.none:SetText(L["No other accounts linked."])
        section.rows = {}
        for i = 1, ROWS do
            local row = {}
            row.text = Theme.Text(box, 11, C.text)
            row.text:SetPoint("TOPLEFT", 0, -(i - 1) * 26 - 5)
            row.remove = W.Button(box, L["Remove"], { width = 90, height = 22, onClick = function()
                if row.account then
                    API.Vault:RemoveRemote(row.account.id)
                    UI.RefreshList()
                end
            end })
            row.remove:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -(i - 1) * 26)
            section.rows[i] = row
        end
    end)
    UI.RefreshList()
    return form:Finish()
end

API.UI:RegisterSettings({ id = "link", title = function() return L["Account link"] end, order = 85, build = UI.Build,
    module = "Goblinomics_Link",
    description = function() return L["Other WoW accounts in one wealth figure."] end })
