if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Setup.lua
-- Setup wizard: an own centred window with a step indicator and
-- the steps Welcome, Price sources, Modules and Done, built with the form kit.
-- It opens by itself on the first login of a fresh installation (5 s later,
-- never in combat or restricted phases); afterwards only with /gob setup or the
-- button in the settings. Skip, Esc and Done mark the setup as done; combat
-- closes the window without marking it.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.Theme.CODE[k] end })

local Setup = {}
ns.Setup = Setup

local UI, Theme, Widgets = ns.UI, ns.Theme, ns.Widgets
local C = Theme.colors
local L = ns.L

local WIDTH, HEIGHT = 660, 520
local OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local MISSING = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

local win
local state = { step = 1, pages = {} }
Setup.state = state

local STEPS = {
    { id = "welcome", title = function() return L["Welcome"] end },
    { id = "prices", title = function() return L["Price sources"] end },
    { id = "modules", title = function() return L["Modules"] end },
    { id = "done", title = function() return L["Done"] end },
}
Setup.STEPS = STEPS

local function Root() return ns.coreDB and ns.coreDB.root end

--- Mark the setup as done (skip, Esc, finish).
function Setup.MarkDone()
    local root = Root()
    if root then root.setup = { done = true, at = time() } end
end

function Setup.IsPending()
    local root = Root()
    return root ~= nil and type(root.setup) == "table" and root.setup.pending == true
end

-- Detection ----------------------------------------------------------------------------
local function Loaded(addon) return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false end

--- { tsm = { installed, active }, auctionator = { installed, active } }
function Setup.PriceSources()
    return {
        tsm = { installed = Loaded("TradeSkillMaster"), active = ns.Price.GetSource("tsm") ~= nil },
        auctionator = { installed = Loaded("Auctionator"), active = ns.Price.GetSource("auctionator") ~= nil },
    }
end

local function SourceName(id) return id == "tsm" and "TradeSkillMaster" or "Auctionator" end

local function IsConnector(m) return m.id:find("Connector", 1, true) ~= nil end

local function ModuleDescription(m)
    local d = m.spec and m.spec.description
    if type(d) == "function" then return d() end
    return d
end

-- Pages --------------------------------------------------------------------------------
local BUILD = {}

function BUILD.welcome(parent)
    local form = ns.Form.New(parent, 0)
    form:Group(L["Welcome to Goblinomics"])
    form:Note(L["Goblinomics tracks your wealth over all characters, every gold movement, your farms and your crafts."],
        C.text, 2)
    form:Note(CODE.good .. "Vault|r  " .. L["Inventory of every character, wealth and the Jealousmeter."], C.text)
    form:Note(CODE.good .. "Ledger|r  " .. L["Books every gold movement into categories and logs the auction house."], C.text, 2)
    form:Note(CODE.good .. "Gatherer|r  " .. L["Farm sessions with HUD and loot highlights."], C.text)
    form:Note(CODE.good .. "Workshop|r  " .. L["Crafts with their real reagent costs and profit per recipe."], C.text)
    form:Note(CODE.good .. "Routines|r  " .. L["Weekly and daily gold routines per character, sorted by gold per minute."], C.text)
    form:Note(L["Two short steps: price sources and modules. Everything can be changed later in the settings."], nil, 2)
    return form:Finish()
end

function BUILD.prices(parent)
    local form = ns.Form.New(parent, 0)
    local found = Setup.PriceSources()
    form:Group(L["Found"], L["Goblinomics takes market prices from TradeSkillMaster or Auctionator."])
    for _, id in ipairs({ "tsm", "auctionator" }) do
        local s = found[id]
        local status = s.active and (OK .. " " .. L["active"])
            or s.installed and (MISSING .. " " .. L["installed, connector not loaded"])
            or (MISSING .. " " .. L["not installed"])
        form:Note(SourceName(id) .. "   " .. status, C.text)
    end
    local active = {}
    for _, id in ipairs({ "tsm", "auctionator" }) do
        if found[id].active then active[#active + 1] = id end
    end
    if #active == 0 then
        form:Group(L["No price source"])
        form:Note(L["Without TSM or Auctionator only vendor prices are known; wealth and farm values stay far too low."],
            C.loss, 2)
        form:Note(L["Install one of them (Auctionator is simple, TSM has more price sources), then run /gob setup."],
            nil, 2)
    else
        local cfg = ns.Price.Config()
        form:Group(L["Preferred"])
        if #active == 2 then
            form:Segmented({ label = L["Preferred market source"],
                description = L["Market prices come from here first; the other source fills gaps."],
                options = { { value = "tsm", label = "TSM" }, { value = "auctionator", label = "Auctionator" } },
                get = function() return cfg.preferred end,
                set = function(value) ns.Price.SetPreferred(value) end })
        else
            if cfg.preferred ~= active[1] then ns.Price.SetPreferred(active[1]) end
            form:Note(ns.Lf("Uses %s.", SourceName(active[1])), C.text)
        end
        local tsm = ns.Price.GetSource("tsm")
        if tsm then
            form:Text({ label = L["TSM market source"], description = L["Value of tradable items."], width = 200,
                get = function() return cfg.tsm.market end,
                set = function(text)
                    text = strtrim(text)
                    local valid, err = tsm.ValidateSource(text)
                    if not valid then return false, err or L["Invalid TSM price source"] end
                    cfg.tsm.market = text
                    ns.Price.Invalidate()
                    return true
                end })
        end
    end
    return form:Finish()
end

function BUILD.modules(parent)
    local form = ns.Form.New(parent, 0)
    form:Group(L["Modules"], L["Switch off what you do not need; switched-off modules disappear and stop tracking."])
    for _, m in ipairs(ns.Modules.List()) do
        if not m.internal and not IsConnector(m) then
            local id = m.id
            form:Toggle({ label = m.name, description = ModuleDescription(m),
                get = function() return ns.Modules.IsEnabled(id) end,
                set = function(on) ns.Modules.SetEnabled(id, on) end })
        end
    end
    return form:Finish()
end

function BUILD.done(parent)
    local form = ns.Form.New(parent, 0)
    form:Group(L["Ready"])
    local found = Setup.PriceSources()
    local source = found.tsm.active and found.auctionator.active and SourceName(ns.Price.Config().preferred)
        or found.tsm.active and SourceName("tsm") or found.auctionator.active and SourceName("auctionator")
        or L["vendor prices only"]
    form:Note(L["Price source"] .. ": " .. source, C.text)
    local names = {}
    for _, m in ipairs(ns.Modules.List()) do
        if not m.internal and not IsConnector(m) and ns.Modules.IsEnabled(m.id) then names[#names + 1] = m.name end
    end
    form:Note(L["Active modules"] .. ": " .. (#names > 0 and table.concat(names, ", ") or "-"), C.text, 2)
    form:Group(L["Good to know"])
    form:Note(L["/gob opens the window; the minimap button and the addon compartment do too."])
    form:Note(L["Open bank, mail and the auction house once per character so the wealth is complete."], nil, 2)
    form:Note(L["/gob setup opens this setup again."])
    return form:Finish()
end

-- Window --------------------------------------------------------------------------------
local function StepColors(i)
    if i < state.step then return C.accent, C.text end
    if i == state.step then return C.gold, C.text end
    return C.track, C.textDim
end

local function RefreshSteps()
    for i, s in ipairs(win.steps) do
        local color, text = StepColors(i)
        s.dot:SetColorTexture(unpack(color))
        s.number:SetTextColor(i <= state.step and 0.05 or 0.9, i <= state.step and 0.05 or 0.9, i <= state.step and 0.05 or 0.9)
        s.label:SetTextColor(unpack(text))
        if s.line then s.line:SetColorTexture(unpack(i <= state.step and C.accent or C.track)) end
    end
end

function Setup.Go(i)
    if not win then return end
    state.step = math.max(1, math.min(#STEPS, i))
    local step = STEPS[state.step]
    for id, page in pairs(state.pages) do page.frame:SetShown(id == step.id) end
    local page = state.pages[step.id]
    if not page or step.id == "done" then
        if page then page.frame:Hide() end
        local frame = CreateFrame("Frame", nil, win.panel.content)
        frame:SetPoint("TOPLEFT")
        frame:SetPoint("RIGHT")
        local ok, height = ns.SafeCall(BUILD[step.id], frame)
        height = ok and height or 0
        frame:SetHeight(math.max(1, height))
        page = { frame = frame, height = height }
        state.pages[step.id] = page
    end
    page.frame:Show()
    win.panel:Update(page.height)
    if win.panel.box.ScrollToBegin then win.panel.box:ScrollToBegin() end
    win.stepTitle:SetText(step.title())
    win.back:SetShown(state.step > 1)
    win.next:SetText(state.step == #STEPS and L["Finish"] or L["Next"])
    win.skip:SetShown(state.step < #STEPS)
    RefreshSteps()
end

local function Close(markDone)
    win.closing = true
    if markDone then Setup.MarkDone() end
    win:Hide()
    win.closing = false
    ns.UIEvents:Unregister("PLAYER_REGEN_DISABLED", "setup")
end

local function Build()
    local S = Theme.space
    -- the shared dialog frame (header bar, close button); the header carries the logo
    win = Widgets.Dialog({ name = "GoblinomicsSetupWindow", title = L["Set up Goblinomics"], width = WIDTH,
        height = HEIGHT })
    local logo = win.header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", S.DIALOG_PAD, 0)
    logo:SetTexture(Theme.LOGO)
    win.title:ClearAllPoints()
    win.title:SetPoint("LEFT", logo, "RIGHT", S.SM, 0)
    win.title:SetPoint("RIGHT", -40, 0)
    local body = win.body
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", S.DIALOG_PAD, -36 - S.PAD)
    body:SetPoint("BOTTOMRIGHT", -S.DIALOG_PAD, S.CONTROL_H + 2 * S.PAD)

    -- step indicator: numbered dots joined by lines
    win.steps = {}
    local stepW = (WIDTH - 2 * S.DIALOG_PAD) / #STEPS
    for i, step in ipairs(STEPS) do
        local st = {}
        local x = (i - 1) * stepW + stepW / 2
        st.dot = body:CreateTexture(nil, "ARTWORK")
        st.dot:SetSize(22, 22)
        st.dot:SetPoint("CENTER", body, "TOPLEFT", x, -12)
        st.number = Theme.Text(body, "small", C.text)
        st.number:SetPoint("CENTER", st.dot, "CENTER", 0, 0)
        st.number:SetText(tostring(i))
        st.label = Theme.Text(body, "caption", C.textDim)
        st.label:SetPoint("TOP", st.dot, "BOTTOM", 0, -4)
        st.label:SetText(step.title())
        if i > 1 then
            st.line = body:CreateTexture(nil, "BORDER")
            st.line:SetHeight(2)
            st.line:SetPoint("LEFT", win.steps[i - 1].dot, "RIGHT", 4, 0)
            st.line:SetPoint("RIGHT", st.dot, "LEFT", -4, 0)
        end
        win.steps[i] = st
    end

    win.stepTitle = Theme.Text(body, "title", C.text)
    win.stepTitle:SetPoint("TOPLEFT", 0, -58)
    win.panel = Widgets.ScrollPanel(body)
    win.panel.box:SetPoint("TOPLEFT", 0, -82)
    win.panel.box:SetPoint("BOTTOMRIGHT", -S.GUTTER, 0)

    win.skip = Widgets.Button(win, L["Skip"], { width = S.DIALOG_BTN_W, onClick = function() Close(true) end,
        tooltip = L["Skip"], tooltipLines = { L["You can open the setup again any time with /gob setup."] } })
    win.skip:SetPoint("BOTTOMLEFT", S.DIALOG_PAD, S.PAD)
    win.next = Widgets.Button(win, L["Next"], { width = S.DIALOG_BTN_W, onClick = function()
        if state.step == #STEPS then
            Close(true)
            UI.Show("dashboard")
        else
            Setup.Go(state.step + 1)
        end
    end })
    win.next:SetPoint("BOTTOMRIGHT", -S.DIALOG_PAD, S.PAD)
    win.back = Widgets.Button(win, L["Back"], { width = S.DIALOG_BTN_W, onClick = function() Setup.Go(state.step - 1) end })
    win.back:SetPoint("RIGHT", win.next, "LEFT", -S.SM, 0)

    -- Esc and the close button close like Skip
    win:SetScript("OnHide", function(self)
        if not self.closing then Setup.MarkDone() end
    end)
end

--- Open the wizard at the first step (never in combat).
function Setup.Show()
    if InCombatLockdown() then
        ns.Print(L["Cannot open the setup in combat."], true)
        return false
    end
    if not win then Build() end
    for _, page in pairs(state.pages) do page.frame:Hide() end
    state.pages = {}
    win:Show()
    Setup.Go(1)
    -- combat closes the window; the setup stays pending
    ns.UIEvents:Register("PLAYER_REGEN_DISABLED", function() Close(false) end, "setup")
    return true
end

function Setup.IsShown() return win ~= nil and win:IsShown() end
Setup.window = function() return win end

-- First start ------------------------------------------------------------------------------
local function TryAutoShow()
    if not Setup.IsPending() then return end
    if InCombatLockdown() or (ns.Restriction and ns.Restriction.IsActive()) then
        ns.Timer.After(10, TryAutoShow, "Core.Setup")
        return
    end
    Setup.Show()
end

--- Called at PLAYER_LOGIN (Bootstrap): a fresh installation opens the wizard 5 s later.
function Setup.OnLogin()
    if Setup.IsPending() then ns.Timer.After(5, TryAutoShow, "Core.Setup") end
end

ns.API.UI.ShowSetup = function() return Setup.Show() end
