if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/UI.lua
-- UI registries and the public UI API. Registering tabs, dashboard widgets and
-- settings sections never creates frames; the shell builds everything on first
-- open. Pure logic, covered by spec/ui/registry_spec.lua.
local _, ns = ...

local UI = {}
ns.UI = UI

local tabs = {}       -- id -> spec
local widgets = {}    -- id -> spec
local sections = {}   -- id -> spec
local sidePanel = nil -- the right-hand column (one per window)
local tooltipProviders, providerOrder = {}, {}

local function Check(spec, what)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        error(("Goblinomics UI:%s: spec.id must be a non-empty string"):format(what), 3)
    end
end

--- Every registration remembers its module (spec.module; during a module's
-- OnEnable it is filled in automatically). Entries of switched-off modules are
-- left out everywhere, so a module disappears from tabs, dashboard, settings,
-- side panel and tooltips as soon as it is switched off.
local function Owner(spec)
    if spec.module == nil and ns.Modules then spec.module = ns.Modules.current end
end

function UI.IsActive(spec)
    return spec ~= nil and (not spec.module or not ns.Modules or ns.Modules.IsEnabled(spec.module))
end

local function Sorted(map, filter)
    local list = {}
    for _, spec in pairs(map) do
        if UI.IsActive(spec) and (not filter or filter(spec)) then
            list[#list + 1] = spec
        end
    end
    table.sort(list, function(a, b)
        local oa, ob = a.order or 100, b.order or 100
        if oa ~= ob then return oa < ob end
        return a.id < b.id
    end)
    return list
end

--- spec = { id, title (string or function), order, build(page), onShow(page), onHide(page), bottom, loadAddon }
-- Registering an existing id replaces it (a demand-loaded module fills its placeholder).
function UI.RegisterTab(spec)
    Check(spec, "RegisterTab")
    Owner(spec)
    tabs[spec.id] = spec
    if UI.OnTabsChanged then UI.OnTabsChanged(spec.id) end
end

--- spec = { id, order, size = "small" | "wide", build(tile) }
function UI.RegisterWidget(spec)
    Check(spec, "RegisterWidget")
    Owner(spec)
    widgets[spec.id] = spec
    if UI.OnWidgetsChanged then UI.OnWidgetsChanged() end
end

--- spec = { id, title, order, build(container) -> height }
function UI.RegisterSettings(spec)
    Check(spec, "RegisterSettings")
    Owner(spec)
    sections[spec.id] = spec
    if UI.OnSettingsChanged then UI.OnSettingsChanged() end
end

function UI.GetTab(id) return tabs[id] end
function UI.GetSettings(id) return sections[id] end

--- spec = { id, width, build(frame), onShow(frame) } - right-hand column of the main window.
function UI.RegisterSidePanel(spec)
    Check(spec, "RegisterSidePanel")
    Owner(spec)
    sidePanel = spec
    if UI.OnSidePanelChanged then UI.OnSidePanelChanged() end
end

function UI.GetSidePanel() return UI.IsActive(sidePanel) and sidePanel or nil end

--- fn(tooltip) adds lines to the minimap / LDB / compartment tooltip.
function UI.RegisterTooltipProvider(id, fn, module)
    if not tooltipProviders[id] then providerOrder[#providerOrder + 1] = id end
    local spec = { fn = fn, module = module }
    Owner(spec)
    tooltipProviders[id] = spec
end

local headerProviders, headerOrder = {}, {}

--- fn(tooltip) adds lines to the tooltip of the logo in the main window header.
function UI.RegisterHeaderTooltipProvider(id, fn, module)
    if not headerProviders[id] then headerOrder[#headerOrder + 1] = id end
    local spec = { fn = fn, module = module }
    Owner(spec)
    headerProviders[id] = spec
end

local function Fill(order, providers, tt)
    for i = 1, #order do
        local spec = providers[order[i]]
        if spec and UI.IsActive(spec) then ns.SafeCall(spec.fn, tt) end
    end
end

function UI.FillHeaderTooltip(tt) Fill(headerOrder, headerProviders, tt) end
function UI.FillTooltipProviders(tt) Fill(providerOrder, tooltipProviders, tt) end

--- A module was switched on or off: every part of the UI updates its lists.
function UI.ModuleStateChanged(id, enabled)
    for _, name in ipairs({ "OnModuleTabs", "OnModuleWidgets", "OnModuleSettings", "OnModuleSidePanel" }) do
        if UI[name] then ns.SafeCall(UI[name], id, enabled) end
    end
end

--- Titles may be strings or functions (core tabs translate at display time,
-- because the locale is activated after the core files load).
function UI.Title(spec)
    local t = spec.title
    if type(t) == "function" then return t() end
    return t or spec.id
end

--- Sidebar order: regular tabs by order, then bottom tabs (settings) by order.
function UI.SortedTabs()
    local list = Sorted(tabs, function(s) return not s.bottom end)
    local bottom = Sorted(tabs, function(s) return s.bottom end)
    for i = 1, #bottom do
        list[#list + 1] = bottom[i]
    end
    return list
end

function UI.SortedWidgets() return Sorted(widgets) end
function UI.SortedSettings() return Sorted(sections) end

--- Make sure a demand-loaded tab's addon is loaded. Returns true when usable.
function UI.EnsureTabLoaded(spec)
    local addon = spec.loadAddon
    if not addon or not C_AddOns then
        return true
    end
    if C_AddOns.IsAddOnLoaded(addon) then
        return true
    end
    if InCombatLockdown() then
        return false
    end
    local loaded = C_AddOns.LoadAddOn(addon)
    return loaded == true
end

-- Window control; the shell provides the implementation when first needed.
function UI.Toggle(tabId)
    if ns.Shell then
        ns.Shell.Toggle(tabId)
    end
end

function UI.Show(tabId)
    if ns.Shell then
        ns.Shell.Show(tabId)
    end
end

function UI.Hide()
    if ns.Shell then
        ns.Shell.Hide()
    end
end

function UI.IsShown()
    return ns.Shell ~= nil and ns.Shell.IsShown()
end

function UI.Toast(spec)
    if ns.Toast then
        ns.Toast.Show(spec)
    end
end

-- Public API, colon style: Goblinomics.API.v1.UI:RegisterTab{...}
ns.API.UI = {
    RegisterTab = function(_, spec) return UI.RegisterTab(spec) end,
    RegisterWidget = function(_, spec) return UI.RegisterWidget(spec) end,
    RegisterSettings = function(_, spec) return UI.RegisterSettings(spec) end,
    Toggle = function(_, tabId) return UI.Toggle(tabId) end,
    Show = function(_, tabId) return UI.Show(tabId) end,
    Hide = function() return UI.Hide() end,
    Toast = function(_, spec) return UI.Toast(spec) end,
    RegisterSidePanel = function(_, spec) return UI.RegisterSidePanel(spec) end,
    RegisterTooltipProvider = function(_, id, fn, module) return UI.RegisterTooltipProvider(id, fn, module) end,
    RegisterHeaderTooltipProvider = function(_, id, fn, module) return UI.RegisterHeaderTooltipProvider(id, fn, module) end,
    IsShown = function() return UI.IsShown() end,
}
