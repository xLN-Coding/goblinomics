if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Dashboard.lua
-- Dashboard tab: quick overview over all characters for a chosen period
-- (1, 7, 14, 30, 90, 365 days). Modules register cards with
--   UI.RegisterWidget{ id, order, size = "full"|"twothirds"|"half"|"third"|"quarter",
--                      height, title = fn, events = { bus events }, build(frame), refresh(frame, context) }
-- context = { days, from } (from = start of the first day of the period).
-- Cards are laid out in rows (a card that no longer fits starts a new row), built
-- on the first visit and refreshed on period changes and, debounced, on their
-- events while the dashboard is shown. Build and refresh times go to /gob perf.
local _, ns = ...

local Dashboard = {}
ns.Dashboard = Dashboard

local UI, Theme, Widgets = ns.UI, ns.Theme, ns.Widgets
local C = Theme.colors
local L = ns.L
local OWNER = "Core.Dashboard"
local GAP = 10
local DEFAULT_HEIGHT = 120

Dashboard.PERIODS = ns.Periods.LIST
local FRACTION = { full = 1, twothirds = 2 / 3, half = 1 / 2, third = 1 / 3, quarter = 1 / 4, small = 1 / 2 }

local state = { built = false, cards = {}, dirty = false }

function Dashboard.Days()
    local db = ns.coreDB
    return db and db.settings.ui.dashboardDays or 7
end

--- Context of the period: { days, from }.
function Dashboard.Context(days)
    return ns.Periods.Context(days or Dashboard.Days())
end

--- Pure layout: { { spec, x, y, width, height } }, total height.
function Dashboard.Layout(specs, width)
    local placed, x, y, rowHeight = {}, 0, 0, 0
    local function Wrap()
        y = y + rowHeight + (rowHeight > 0 and GAP or 0)
        x, rowHeight = 0, 0
    end
    for _, spec in ipairs(specs) do
        local f = FRACTION[spec.size or "half"] or 0.5
        if x > 0 and x + f > 1.0001 then Wrap() end
        local w = f * (width + GAP) - GAP
        local h = spec.height or DEFAULT_HEIGHT
        placed[#placed + 1] = { spec = spec, x = x * (width + GAP), y = y, width = w, height = h }
        x = x + f
        if h > rowHeight then rowHeight = h end
    end
    return placed, y + rowHeight
end

local function RefreshCard(card, context)
    if card.spec.refresh then ns.SafeCall(card.spec.refresh, card.frame, context) end
end

function Dashboard.Refresh()
    if not state.built then return end
    local start = debugprofilestop()
    local context = Dashboard.Context()
    for _, card in ipairs(state.cards) do RefreshCard(card, context) end
    ns.Perf.Record(OWNER, "refresh", debugprofilestop() - start, true)
end

local function BuildCards()
    local page = state.page
    for _, card in ipairs(state.cards) do card.frame:Hide() end
    state.cards = {}
    local width = page.GetWidth and page:GetWidth() or 0
    if not width or width <= 0 then width = 692 end
    width = width - 16
    local list = UI.SortedWidgets()
    state.empty:SetShown(#list == 0)
    local placed, height = Dashboard.Layout(list, width)
    for _, p in ipairs(placed) do
        local frame = CreateFrame("Frame", nil, state.panel.content)
        frame:SetPoint("TOPLEFT", p.x, -p.y)
        frame:SetSize(p.width, p.height)
        Theme.Backdrop(frame, C.panel, C.border)
        if p.spec.title then
            frame.title = Theme.Text(frame, "caption", C.textDim)
            frame.title:SetPoint("TOPLEFT", Theme.space.PAD, Theme.space.CARD_TITLE_Y)
            frame.title:SetPoint("RIGHT", frame, "RIGHT", -Theme.space.PAD, 0)
            frame.title:SetWordWrap(false)
            local title = type(p.spec.title) == "function" and p.spec.title() or p.spec.title
            frame.title:SetText(tostring(title):upper())
        end
        ns.SafeCall(p.spec.build, frame)
        state.cards[#state.cards + 1] = { spec = p.spec, frame = frame }
    end
    state.panel:Update(height)
    state.dirty = false
end

local function Build(page)
    local start = debugprofilestop()
    state.page = page
    local S = Theme.space
    local header = Theme.Text(page, "small", C.textDim)
    header:SetPoint("TOPLEFT", 0, -6)
    header:SetText(L["All characters"])
    local period = ns.Periods.Control(page, Dashboard.Days, function(days)
        ns.coreDB.settings.ui.dashboardDays = days
        Dashboard.Refresh()
    end)
    period:SetPoint("TOPRIGHT", -S.GUTTER, 0)
    state.period = period
    state.panel = Widgets.ScrollPanel(page)
    state.panel.box:SetPoint("TOPLEFT", 0, S.CONTENT_TOP)
    state.panel.box:SetPoint("BOTTOMRIGHT", -S.GUTTER, 0)
    state.empty = Widgets.EmptyState(page, L["No cards yet: switch on a module in the settings."])
    state.built = true
    BuildCards()
    Dashboard.Refresh()
    ns.Perf.Record(OWNER, "build", debugprofilestop() - start, true)
end

local function OnShow()
    if state.dirty then BuildCards() end
    Dashboard.Refresh()
    local seen = {}
    for _, card in ipairs(state.cards) do
        for _, event in ipairs(card.spec.events or {}) do
            if not seen[event] then
                seen[event] = true
                ns.Bus.On(event, function()
                    ns.Timer.Debounce(OWNER .. ":refresh", 0.3, Dashboard.Refresh, OWNER)
                end, OWNER)
            end
        end
    end
end

local function OnHide()
    ns.Bus.OffAll(OWNER)
end

-- cards registered later (load-on-demand modules) rebuild the grid on the next visit
UI.OnWidgetsChanged = function()
    if state.built then state.dirty = true end
end

-- cards of a switched-off module go away at once when the dashboard is open
UI.OnModuleWidgets = function()
    if not state.built then return end
    state.dirty = true
    if state.page and state.page:IsShown() then
        BuildCards()
        Dashboard.Refresh()
    end
end

UI.RegisterTab({
    id = "dashboard",
    title = function() return L["Dashboard"] end,
    order = 0,
    build = Build,
    onShow = OnShow,
    onHide = OnHide,
})

Dashboard.State = function() return state end

-- Insights: a load-on-demand tab; Goblinomics_Insights replaces this spec when it
-- loads (UI.EnsureTabLoaded loads it on the first click, never in combat).
local INSIGHTS = "Goblinomics_Insights"
if C_AddOns and C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(INSIGHTS)
    and not C_AddOns.IsAddOnLoaded(INSIGHTS) then
    UI.RegisterTab({
        id = "insights",
        title = function() return L["Insights"] end,
        order = 1,
        loadAddon = INSIGHTS,
        module = INSIGHTS,
        build = function(page)
            local text = Theme.Text(page, "body", C.textDim)
            text:SetPoint("CENTER")
            text:SetText(L["Insights could not be loaded."])
        end,
    })
end
