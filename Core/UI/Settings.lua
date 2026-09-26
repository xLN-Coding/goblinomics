if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Settings.lua
-- Settings page of the shell (sections registered with UI.RegisterSettings), the
-- core section and the small entry in Blizzard's options (Esc > Options > AddOns).
local _, ns = ...

local UI, Theme, Widgets = ns.UI, ns.Theme, ns.Widgets
local C = Theme.colors
local L = ns.L

-------------------------------------------------------------------------------
-- Settings page: the sections on the left, the selected one
-- on the right with its title. Sections are built when first selected and kept;
-- the last selection is remembered. Demand-loaded sections (Import, Link) load
-- their addon only when selected.
-------------------------------------------------------------------------------
local NAV_W = 200
local page = { built = {}, buttons = {} }
UI.settingsPage = page

local function DescriptionOf(section)
    local d = section.description
    if type(d) == "function" then return d() end
    return d
end

local function NavButton(i)
    local b = page.buttons[i]
    if b then return b end
    b = Widgets.NavButton(page.nav, "", { onClick = function(self) UI.SelectSettings(self.id) end })
    b:SetPoint("TOPLEFT", page.nav, "TOPLEFT", 0, -Theme.space.SM - (i - 1) * Theme.space.NAV_STEP)
    b:SetPoint("RIGHT", page.nav, "RIGHT", 0, 0)
    page.buttons[i] = b
    return b
end

local function RefreshNav()
    if not page.nav then return end
    local list = UI.SortedSettings()
    for i, section in ipairs(list) do
        local b = NavButton(i)
        b.id = section.id
        b:SetText(UI.Title(section))
        b:SetSelected(section.id == page.selected)
        b:Show()
    end
    for i = #list + 1, #page.buttons do page.buttons[i]:Hide() end
end

--- Show a section (built on first use); remembers the choice.
function UI.SelectSettings(id)
    if not page.panel then return end
    local section = UI.GetSettings(id)
    if not UI.IsActive(section) then
        local first = UI.SortedSettings()[1]
        if not first then return end
        section, id = first, first.id
    end
    page.selected = id
    if ns.coreDB then ns.coreDB.settings.ui.settingsSection = id end
    for key, entry in pairs(page.built) do entry.frame:SetShown(key == id) end
    local entry = page.built[id]
    if not entry then
        local frame = CreateFrame("Frame", nil, page.panel.content)
        frame:SetPoint("TOPLEFT", page.panel.content, "TOPLEFT", 0, 0)
        frame:SetPoint("RIGHT", page.panel.content, "RIGHT", 0, 0)
        local ok, height = ns.SafeCall(section.build, frame, 0)
        height = (ok and type(height) == "number") and height or 0
        frame:SetHeight(math.max(1, height))
        entry = { frame = frame, height = height }
        page.built[id] = entry
    end
    entry.frame:Show()
    page.title:SetText(UI.Title(section))
    local description = DescriptionOf(section)
    page.description:SetText(description or "")
    page.panel:Update(entry.height)
    if page.panel.box.ScrollToBegin then page.panel.box:ScrollToBegin() end
    RefreshNav()
end

UI.OnSettingsChanged = RefreshNav

-- the section of a switched-off module disappears; if it was selected, General is shown
UI.OnModuleSettings = function()
    if not page.panel then return end
    if page.selected and not UI.IsActive(UI.GetSettings(page.selected)) then
        UI.SelectSettings("core")
    else
        RefreshNav()
    end
end

UI.RegisterTab({
    id = "settings",
    title = function() return L["Settings"] end,
    order = 100,
    bottom = true,
    build = function(p)
        page.nav = CreateFrame("Frame", nil, p)
        page.nav:SetPoint("TOPLEFT")
        page.nav:SetPoint("BOTTOMLEFT")
        page.nav:SetWidth(NAV_W)
        Theme.Backdrop(page.nav, C.sidebar, C.border)
        local right = CreateFrame("Frame", nil, p)
        right:SetPoint("TOPLEFT", NAV_W + 16, 0)
        right:SetPoint("BOTTOMRIGHT")
        page.title = Theme.Text(right, "page", C.gold)
        page.title:SetPoint("TOPLEFT", 0, -2)
        page.description = Theme.Text(right, "small", C.textDim)
        page.description:SetPoint("TOPLEFT", 0, -24)
        page.description:SetPoint("RIGHT", right, "RIGHT", -20, 0)
        page.panel = Widgets.ScrollPanel(right)
        page.panel.box:SetPoint("TOPLEFT", 0, -46)
        page.panel.box:SetPoint("BOTTOMRIGHT", -14, 0)
        UI.SelectSettings(ns.coreDB and ns.coreDB.settings.ui.settingsSection or "core")
    end,
    onShow = RefreshNav,
})

-------------------------------------------------------------------------------
-- Core section
-------------------------------------------------------------------------------
local function ModuleDescription(m)
    local d = m.spec and m.spec.description
    if type(d) == "function" then return d() end
    if d then return d end
    return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(m.addon, "Notes") or nil
end

UI.RegisterSettings({
    id = "core",
    title = function() return L["General"] end,
    order = 0,
    build = function(parent, y)
        local settings = ns.coreDB.settings
        local form = ns.Form.New(parent, y)

        form:Group(L["Display"])
        form:Toggle({ label = L["Show minimap button"], description = L["A button at the minimap opens the window."],
            get = function() return not settings.minimap.hide end,
            set = function(on) ns.EntryPoints.SetMinimapShown(on) end })
        form:Select({ label = L["Language"], description = L["Takes effect after reloading the interface."],
            choices = ns.Locale.Choices,
            get = function() return settings.locale end,
            set = function(value)
                if value == settings.locale then return end
                settings.locale = value
                Widgets.Confirm({
                    title = L["Language"],
                    text = L["The new language is used after reloading the interface. Reload now?"],
                    confirmText = L["Reload"], cancelText = L["Later"],
                    onConfirm = function() ReloadUI() end,
                })
            end })
        form:Slider({ label = L["Window scale"], description = L["Applied when you release the slider."],
            min = 0.8, max = 1.5, step = 0.05, release = true,
            format = function(v) return ns.Format.Percent(v) end,
            get = function() return settings.ui.scale end,
            set = function(value)
                settings.ui.scale = value
                ns.Shell.SetScale(value)
            end })

        form:Group(L["Sound"])
        form:Select({ label = L["Sound channel"], description = L["All Goblinomics sounds play on this channel."],
            choices = function()
                local list = {}
                local names = { Master = L["Master"], SFX = L["SFX"], Music = L["Music"], Ambience = L["Ambience"],
                    Dialog = L["Dialog"] }
                for _, id in ipairs(ns.Sounds.CHANNELS) do list[#list + 1] = { value = id, label = names[id] or id } end
                return list
            end,
            get = function() return settings.sound.channel end,
            set = function(value) settings.sound.channel = value end })

        form:Group(L["Bags"])
        form:Toggle({ label = L["Mark speculative items in bags and bank"] .. " " .. ns.ItemMarks.INLINE,
            description = L["Speculative items (sale rate below the threshold) get a small logo in the top-right corner."],
            get = function() return settings.ui.markSpeculative ~= false end,
            set = function(on) settings.ui.markSpeculative = on end })

        form:Group(L["Modules"], L["Switched off modules stop tracking; their data stays."])
        local any = false
        for _, m in ipairs(ns.Modules.List()) do
            if not m.internal then
                any = true
                local id = m.id
                form:Toggle({ label = m.name, description = ModuleDescription(m),
                    get = function() return ns.Modules.IsEnabled(id) end,
                    set = function(on) ns.Modules.SetEnabled(id, on) end })
            end
        end
        if not any then form:Note(L["No modules registered"]) end

        form:Group(L["Setup"])
        form:Buttons({ label = L["Setup wizard"], description = L["Price sources and modules step by step."],
            buttons = { { text = L["Start setup again"], width = 170, onClick = function() ns.Setup.Show() end } } })

        form:Group(L["Troubleshooting"])
        form:Toggle({ label = L["Print core events to chat"],
            description = L["Money, loot, item and context events appear in the chat."],
            get = function() return ns.Modules.IsEnabled(ns.DEBUG_MODULE) end,
            set = function(on) ns.Modules.SetEnabled(ns.DEBUG_MODULE, on) end })
        return form:Finish()
    end,
})

-------------------------------------------------------------------------------
-- Demand-loaded sections (M8): Import and Link register their real section when
-- they load; the placeholder loads the addon when the settings page is built
-- and hands over to the new builder (never in combat).
-------------------------------------------------------------------------------
local function DemandSection(id, addon, title, order)
    if not (C_AddOns and C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(addon)) then return end
    local placeholder
    placeholder = {
        id = id, title = title, order = order, module = addon,
        build = function(parent, y)
            if UI.EnsureTabLoaded({ loadAddon = addon }) then
                local spec = UI.GetSettings(id)
                if spec and spec ~= placeholder then return spec.build(parent, y) end
            end
            local text = Theme.Text(parent, 12, C.textDim)
            text:SetPoint("TOPLEFT", 0, y)
            text:SetText(L["Not available in combat. Open the settings again afterwards."])
            return 24
        end,
    }
    if not C_AddOns.IsAddOnLoaded(addon) then UI.RegisterSettings(placeholder) end
end

DemandSection("import", "Goblinomics_Import", function() return L["Import"] end, 80)
DemandSection("link", "Goblinomics_Link", function() return L["Account link"] end, 85)

-------------------------------------------------------------------------------
-- Blizzard options entry
-------------------------------------------------------------------------------
local category

function ns.RegisterBlizzardOptions()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local title = Theme.Text(panel, 16, C.accent)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Goblinomics")
    local open = Widgets.Button(panel, L["Open Goblinomics"], {
        width = 200, height = 26,
        onClick = function()
            if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
            UI.Show("settings")
        end,
    })
    open:SetPoint("TOPLEFT", 16, -48)
    category = Settings.RegisterCanvasLayoutCategory(panel, "Goblinomics")
    Settings.RegisterAddOnCategory(category)
end

function ns.OpenBlizzardOptions()
    if category and not InCombatLockdown() then
        Settings.OpenToCategory(category:GetID())
    end
end
