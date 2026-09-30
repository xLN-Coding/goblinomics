if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/WorkshopProfessions.lua
-- "Concentration & cooldowns" view of the Workshop and its dashboard card: every
-- character with a profession, the one due first on top. Under each character its
-- current expansion professions (icon, computed concentration as a bar, "full in")
-- and its recipe cooldowns ("ready in", charges). A click on a character folds it.
-- The profession and character filters apply, the period does not. While shown it
-- refreshes once a minute; values are computed, nothing is asked from the game.
local _, ns = ...

local View = {}
ns.WorkshopProfessions = View

local collapsed = {}   -- charKey -> true
View.collapsed = collapsed

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

--- "full" / "full in 3h 12m" style text for a due time.
function View.DueText(at, now, readyText, inText)
    local API = ns.API
    if not at then return "" end
    if at <= now then return API.Theme.CODE.good .. readyText .. "|r" end
    return API.Lf(inText, API.Format:Remaining(at - now))
end

--- Flat rows for the list from Professions.Overview, with the Workshop filters.
function View.Rows(overview, filter)
    filter = filter or {}
    local rows = {}
    for _, e in ipairs(overview) do
        if not filter.char or filter.char == e.key then
            local professions, cooldowns = {}, e.cooldowns
            for _, p in ipairs(e.professions) do
                if not filter.profession or filter.profession == p.name then professions[#professions + 1] = p end
            end
            if filter.profession then cooldowns = {} end
            if #professions > 0 or #cooldowns > 0 then
                rows[#rows + 1] = { kind = "char", entry = e }
                if not collapsed[e.key] then
                    for _, p in ipairs(professions) do rows[#rows + 1] = { kind = "profession", entry = e, profession = p } end
                    for _, cd in ipairs(cooldowns) do rows[#rows + 1] = { kind = "cooldown", entry = e, cooldown = cd } end
                end
            end
        end
    end
    return rows
end

local function Settings() return ns.Workshop.db.settings end

function View.Build(parent)
    local API, L = ns.API, ns.L
    local Theme, W = API.Theme, API.Widgets
    local C, S = Theme.colors, Theme.space
    local page = { frame = CreateFrame("Frame", nil, parent) }
    local f = page.frame
    f:SetAllPoints(parent)

    local hint = Theme.Text(f, "small", C.textDim)
    hint:SetPoint("TOPLEFT", 0, -4)
    hint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Concentration is read when you log in or open a profession window, and computed from then on."])

    local function InitRow(row, data)
        if not row.label then
            W.RowBackground(row)
            row.toggle = Theme.Text(row, "body", C.textDim)
            row.toggle:SetPoint("LEFT", 2, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 24, 0)
            row.label = Theme.Text(row, "body", C.text)
            row.label:SetWordWrap(false)
            row.status = Theme.Text(row, "body", C.text)
            row.status:SetPoint("RIGHT", -S.SM, 0)
            row.status:SetJustifyH("RIGHT")
            row.status:SetWidth(150)
            row.bar = W.ProgressBar(row, 180, 14)
            row.bar:SetPoint("RIGHT", row.status, "LEFT", -S.GAP, 0)
            row:SetScript("OnClick", function(self)
                local d = self.data
                if d.kind ~= "char" then return end
                collapsed[d.entry.key] = not collapsed[d.entry.key] or nil
                ns.WorkshopUI.Refresh()
            end)
            row:SetScript("OnEnter", function(self)
                local d = self.data
                if d.kind ~= "profession" or not d.profession.readAt then return end
                W.ShowTooltip(self, d.profession.name, {
                    API.Lf("Read %s ago", API.Format:Remaining(time() - d.profession.readAt)),
                    L["Log in with the character to read it again."],
                })
            end)
            row:SetScript("OnLeave", W.HideTooltip)
        end
        row.data = data
        local now = time()
        local e = data.entry
        row.label:ClearAllPoints()
        row.label:SetPoint("RIGHT", row.bar, "LEFT", -S.GAP, 0)
        if data.kind == "char" then
            row.zebra:Show()
            row.toggle:SetText(collapsed[e.key] and "+" or "-")
            row.icon:Hide()
            row.bar:Hide()
            row.label:SetPoint("LEFT", 16, 0)
            row.label:SetText("|c" .. ClassColor(e.class) .. e.name .. "|r")
            row.status:SetText(e.dueAt and (e.dueAt <= now and (Theme.CODE.good .. L["something is ready"] .. "|r")
                or API.Lf("next in %s", API.Format:Remaining(e.dueAt - now))) or "")
            return
        end
        row.zebra:Hide()
        row.toggle:SetText("")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        if data.kind == "profession" then
            local p = data.profession
            row.icon:SetTexture(p.icon or 134400)
            row.icon:Show()
            row.label:SetText(p.name or "?")
            row.bar:Show()
            row.bar:SetMinMaxValues(0, p.max or 1000)
            row.bar:SetValue(p.current or 0)
            row.bar:SetLabels(tostring(p.current or 0), tostring(p.max or 1000))
            row.status:SetText(View.DueText(p.fullAt, now, L["full"], "full in %s"))
        else
            local cd = data.cooldown
            row.icon:SetTexture(cd.icon or 134400)
            row.icon:Show()
            row.label:SetText((cd.name or "?") .. (cd.count > 1 and (" " .. Theme.Colorize("(+" .. (cd.count - 1) .. ")",
                C.textDim)) or ""))
            if cd.maxCharges then
                row.bar:Show()
                row.bar:SetMinMaxValues(0, cd.maxCharges)
                row.bar:SetValue(cd.charges or 0)
                row.bar:SetLabels(API.Lf("%d/%d charges", cd.charges or 0, cd.maxCharges), "")
            else
                row.bar:Hide()
            end
            row.status:SetText(View.DueText(cd.readyAt, now, L["ready"], "ready in %s"))
        end
    end

    page.list = W.ScrollList(f, { rowHeight = S.ROW, init = InitRow })
    page.list.box:SetPoint("TOPLEFT", 0, -(S.ROW + S.XS))
    page.list.box:SetPoint("BOTTOMRIGHT", 0, 0)
    page.empty = W.EmptyState(page.list.box, L["No profession data yet: open a profession window once on each character."])

    -- once a minute while visible
    local ticking = false
    local function Tick()
        if not f:IsVisible() then ticking = false return end
        page.Refresh(ns.WorkshopUI.Filter())
        ns.Workshop:After(60, Tick)
    end

    function page.Refresh(filter)
        local root = ns.Workshop.db.root
        local rows = View.Rows(ns.Professions.Overview(root, Settings(), time()), filter)
        page.rows = rows
        page.list:SetData(rows)
        page.empty:SetShown(#rows == 0)
        if not ticking then
            ticking = true
            ns.Workshop:After(60, Tick)
        end
    end
    return page
end

-- Dashboard card: the next due entries over all characters ---------------------------------
local function RegisterCard()
    local API, L = ns.API, ns.L
    local Theme = API.Theme
    local C = Theme.colors
    local ROWS = 5
    API.UI:RegisterWidget({
        id = "workshop.concentration", order = 42, size = "quarter", height = 120,
        events = { "WORKSHOP_PROFESSIONS" },
        title = function() return L["Concentration & cooldowns"] end,
        build = function(f)
            f.lines = {}
            for i = 1, ROWS do
                local left = Theme.Text(f, "small", C.text)
                left:SetPoint("TOPLEFT", 12, -26 - (i - 1) * 16)
                left:SetPoint("RIGHT", f, "RIGHT", -84, 0)
                left:SetWordWrap(false)
                local right = Theme.Text(f, "small", C.textDim)
                right:SetPoint("TOPRIGHT", -12, -26 - (i - 1) * 16)
                right:SetJustifyH("RIGHT")
                f.lines[i] = { left = left, right = right }
            end
            f.empty = Theme.Text(f, "small", C.textDim)
            f.empty:SetPoint("TOPLEFT", 12, -26)
            f.empty:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f.empty:SetJustifyH("LEFT")
            f.empty:SetText(L["Open a profession window once on each character."])
            f:EnableMouse(true)
            f:SetScript("OnMouseUp", function()
                API.UI:Show("workshop")
                ns.WorkshopUI.Show("professions")
            end)
        end,
        refresh = function(f)
            local now = time()
            local due = ns.Professions.Due(ns.Workshop.db.root, Settings(), now)
            for i, line in ipairs(f.lines) do
                local d = due[i]
                line.left:SetText(d and ("|c" .. ClassColor(d.class) .. d.name .. "|r  " .. (d.label or "")) or "")
                line.right:SetText(d and View.DueText(d.at, now, d.kind == "cooldown" and L["ready"] or L["full"], "in %s")
                    or "")
            end
            f.empty:SetShown(#due == 0)
        end,
    })
end

function View.Enable()
    ns.WorkshopUI.AddView({ id = "professions", noPeriod = true,
        label = function() return ns.L["Concentration & cooldowns"] end,
        build = function(parent) return View.Build(parent) end })
    RegisterCard()
end
