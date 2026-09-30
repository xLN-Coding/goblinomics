if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/RoutinesUI.lua
-- Routines tab: a character dropdown (the logged-in one first) and three views:
--   List         the character's pinned tasks, open first, then by gold per minute;
--                a click edits value, duration and note, the tooltip explains the numbers
--   Overview     per pinned task on how many characters it is still open
--   Suggestions  learned, preset and imported tasks to take over or ignore
-- Export and import share routines as strings. Plus the dashboard card, the
-- settings section and a chat line after login.
local _, ns = ...

local UI = {}
ns.RoutinesUI = UI

local OWNER = "Goblinomics_Routines.Tab"
local L = ns.L
local state = { view = "list", char = nil }
UI.state = state
local tab = {}

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local OPEN = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t"

local function API() return ns.API end
local function Money(copper) return ns.API.Money.Format(math.floor(copper or 0), { abbreviate = true }) end

--- "12 min", "1 h 5 min"
function UI.Minutes(minutes)
    minutes = math.floor((minutes or 0) + 0.5)
    if minutes >= 60 then return ns.API.Lf("%dh %dm", math.floor(minutes / 60), minutes % 60) end
    return ns.API.Lf("%dm", minutes)
end

function UI.KindName(kind)
    if kind == "quest" then return L["Quest"] end
    if kind == "instance" then return L["Instance"] end
    if kind == "worldboss" then return L["World boss"] end
    if kind == "delve" then return L["Delves"] end
    if kind == "patron" then return L["Patron orders"] end
    return L["Profession"]
end

local function SourceText(source)
    if source == "manual" then return L["set by you"] end
    if source == "measured" then return L["measured"] end
    if source == "preset" then return L["preset"] end
    if source == "default" then return L["default"] end
    return L["unknown"]
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

local function CurrentChar()
    return state.char or ns.Routines.CharKey()
end

--- Rows of the current view.
function UI.Rows()
    if state.view == "overview" then return ns.Tasks.Overview() end
    if state.view == "suggestions" then return ns.Tasks.Suggestions() end
    return ns.Tasks.Routine(CurrentChar())
end

-- Edit dialog ----------------------------------------------------------------------------------
local function Parse(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    return tonumber((text:gsub(",", ".")))
end

function UI.OpenEdit(task)
    local W = API().Widgets
    if not tab.edit then
        local d
        d = W.Dialog({ title = L["Edit task"], width = 420, height = 250, name = "GoblinomicsRoutinesEdit", buttons = {
            { text = L["Remove from routine"], width = 160, onClick = function()
                ns.Tasks.Pin(d.task.id, false)
                d:Hide()
            end },
            { text = L["Save"], primary = true, onClick = function()
                local gold, minutes = Parse(d.value:GetText()), Parse(d.duration:GetText())
                ns.Tasks.Edit(d.task.id, { value = gold and math.floor(gold * 10000) or nil,
                    duration = minutes and math.max(1, minutes) or nil, note = strtrim(d.note:GetText() or "") ~= ""
                        and strtrim(d.note:GetText()) or nil })
                d:Hide()
            end },
        } })
        local function box(width)
            local e = CreateFrame("EditBox", nil, d.body)
            e:SetSize(width, 24)
            e:SetAutoFocus(false)
            e:SetFontObject(ns.API.Theme.Font(12))
            e:SetTextInsets(6, 6, 0, 0)
            ns.API.Theme.Backdrop(e, ns.API.Theme.colors.button, ns.API.Theme.colors.border)
            e:SetScript("OnEscapePressed", function() d:Hide() end)
            return e
        end
        d.value, d.duration, d.note = box(120), box(120), box(240)
        d:Row(L["Value (gold)"], d.value, -30)
        d:Row(L["Duration (minutes)"], d.duration, -62)
        d:Row(L["Note"], d.note, -94)
        d.hint = ns.API.Theme.Text(d.body, "small", ns.API.Theme.colors.textDim)
        d.hint:SetPoint("TOPLEFT", 0, 0)
        d.hint:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
        d.hint:SetText(L["Leave a field empty to use the measured value."])
        tab.edit = d
    end
    local d = tab.edit
    d.task = task
    d:SetTitle(task.name or L["Edit task"])
    d.value:SetText(task.value and tostring(math.floor(task.value / 10000)) or "")
    d.duration:SetText(task.duration and tostring(task.duration) or "")
    d.note:SetText(task.note or "")
    d:Show()
end

-- Tooltip -----------------------------------------------------------------------------------------
function UI.TooltipLines(entry, now)
    local Lf = ns.API.Lf
    local t = entry.task
    local value, minutes, vs, ms = ns.Tasks.Estimate(t)
    local lines = {
        UI.KindName(t.kind) .. (t.frequency and ("  " .. (t.frequency == "daily" and L["daily"] or L["weekly"])) or ""),
        Lf("Value: %s (%s)", Money(value), SourceText(vs)),
        Lf("Duration: %s (%s)", UI.Minutes(minutes), SourceText(ms)),
        Lf("Gold per minute: %s", Money(value / math.max(1, minutes))),
    }
    local m = t.measured
    if m and (m.n or m.m) then lines[#lines + 1] = Lf("Measured over %d runs", math.max(m.n or 0, m.m or 0)) end
    if entry.resetAt and entry.resetAt > now then
        lines[#lines + 1] = Lf("Resets in %s", ns.API.Format:Remaining(entry.resetAt - now))
    end
    if t.note then lines[#lines + 1] = t.note end
    return t.name or "?", lines
end

-- Tab ---------------------------------------------------------------------------------------------
local columns

local function InitRow(row, data)
    local A, W = API(), API().Widgets
    local Theme = A.Theme
    local C = Theme.colors
    if not row.cells then
        columns:Cells(row, "body")
        W.RowBackground(row)
        row.take = W.Button(row, L["Take over"], { width = 90, onClick = function(b)
            ns.Tasks.Pin(b:GetParent().data.task.id, true)
        end })
        row.take:SetPoint("RIGHT", -96, 0)
        row.ignore = W.Button(row, L["Ignore"], { width = 84, onClick = function(b)
            ns.Tasks.Hide(b:GetParent().data.task.id, true)
        end })
        row.ignore:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function(self)
            if state.view ~= "suggestions" then UI.OpenEdit(self.data.task) end
        end)
        row:SetScript("OnEnter", function(self)
            local title, lines = UI.TooltipLines(self.data, time())
            W.ShowTooltip(self, title, lines)
        end)
        row:SetScript("OnLeave", W.HideTooltip)
    end
    row.data = data
    local c = row.cells
    local t = data.task
    local suggestion = state.view == "suggestions"
    row.take:SetShown(suggestion)
    row.ignore:SetShown(suggestion)
    c.check:SetText(state.view == "list" and (data.done and READY or OPEN) or "")
    local name = t.name or t.id
    if data.detail then name = name .. "  " .. Theme.Colorize(data.detail, C.textDim) end
    c.name:SetText(name)
    c.name:SetTextColor(unpack((state.view == "list" and data.done) and C.textDim or C.text))
    c.kind:SetText(Theme.Colorize(UI.KindName(t.kind), C.textDim))
    if suggestion then
        c.value:SetText("")
        c.minutes:SetText("")
        c.perMinute:SetText(Money(data.perMinute))
        c.extra:SetText("")
    else
        c.value:SetText(Money(data.value))
        c.minutes:SetText(UI.Minutes(data.minutes))
        c.perMinute:SetText(Theme.Colorize(Money(data.perMinute), C.gold))
        c.extra:SetText(state.view == "overview" and ("%d/%d"):format(data.open, data.count) or "")
    end
end

function UI.Refresh()
    if not tab.list then return end
    local A = API()
    local rows = UI.Rows()
    tab.views:Refresh()
    tab.char:SetShown(state.view == "list")
    local text
    if state.view == "list" then
        local value, minutes, open = ns.Tasks.Totals(rows)
        text = A.Lf("Open: %d tasks, %s in %s", open, Money(value), UI.Minutes(minutes))
    elseif state.view == "overview" then
        local value, minutes = 0, 0
        for _, r in ipairs(rows) do value, minutes = value + r.value, minutes + r.minutes end
        text = A.Lf("All characters: %s in %s", Money(value), UI.Minutes(minutes))
    else
        text = L["Learned, preset and imported tasks. Take over what belongs in your routine."]
    end
    tab.summary:SetText(text)
    tab.list:SetData(rows)
    tab.empty:SetText(state.view == "list" and L["No tasks yet: take some over from the suggestions."]
        or state.view == "overview" and L["No tasks in your routine yet."]
        or L["No suggestions yet: accept a weekly quest or open a profession window."])
    tab.empty:SetShown(#rows == 0)
end

local function CharChoices()
    local list = {}
    for _, ch in ipairs(ns.Tasks.Characters()) do
        list[#list + 1] = { value = ch.key, label = "|c" .. ClassColor(ch.class) .. (ch.name or ch.key) .. "|r" }
    end
    return list
end

local function BuildTab(page)
    local A = API()
    local W, Theme = A.Widgets, A.Theme
    local C, S = Theme.colors, Theme.space
    tab.views = W.Segmented(page, { { value = "list", label = L["List"] }, { value = "overview", label = L["Overview"] },
        { value = "suggestions", label = L["Suggestions"] } }, function() return state.view end, function(v)
            state.view = v
            UI.Refresh()
        end, { min = 90 })
    tab.views:SetPoint("TOPLEFT", 0, 0)
    local import = W.Button(page, L["Import"], { auto = true, onClick = function()
        ns.TextDialog.ShowPaste({ title = L["Import routine"], onAccept = function(text)
            local added, err = ns.Share.Import(text)
            if not added then return false, err == "version" and L["This string needs a newer Goblinomics."]
                or L["That is not a routine string."] end
            state.view = "suggestions"
            UI.Refresh()
            return true
        end })
    end })
    import:SetPoint("TOPRIGHT", -S.GUTTER, 0)
    local export = W.Button(page, L["Export"], { auto = true, onClick = function()
        local text = ns.Share.Export()
        if text then ns.TextDialog.ShowCopy({ title = L["Export routine"], text = text }) end
    end })
    export:SetPoint("RIGHT", import, "LEFT", -S.SM, 0)
    local filterY = -(S.CONTROL_H + S.SM)
    tab.char = W.Dropdown(page, CharChoices, CurrentChar, function(v)
        state.char = v
        UI.Refresh()
    end, { size = "L" })
    tab.char:SetPoint("TOPLEFT", 0, filterY)
    tab.summary = Theme.Text(page, "body", C.text)
    tab.summary:SetPoint("TOPRIGHT", page, "TOPRIGHT", -S.GUTTER, filterY - 4)
    tab.summary:SetJustifyH("RIGHT")
    columns = W.Columns({
        { key = "check", label = "", width = 18 },
        { key = "name", label = L["Task"] },
        { key = "kind", label = L["Type"], width = 90 },
        { key = "value", label = L["Value"], width = 70, align = "RIGHT" },
        { key = "minutes", label = L["Time"], width = 56, align = "RIGHT" },
        { key = "perMinute", label = L["Gold/min"], width = 70, align = "RIGHT" },
        { key = "extra", label = "", width = 50, align = "RIGHT" },
    })
    local headerY = filterY - S.CONTROL_H - S.SM
    local header = columns:Header(page)
    header:SetPoint("TOPLEFT", 0, headerY)
    header:SetPoint("RIGHT", page, "RIGHT", -S.GUTTER, 0)
    tab.list = W.ScrollList(page, { rowHeight = S.ROW, init = InitRow })
    tab.list.box:SetPoint("TOPLEFT", 0, headerY - S.HEADER_H - S.XS)
    tab.list.box:SetPoint("BOTTOMRIGHT", -S.GUTTER, 0)
    tab.empty = W.EmptyState(tab.list.box, "")
    UI.Refresh()
end

-- Dashboard card ---------------------------------------------------------------------------------
local function RegisterCard()
    local A = API()
    local Theme = A.Theme
    local C = Theme.colors
    A.UI:RegisterWidget({
        id = "routines.week", order = 44, size = "quarter", height = 120, events = { "ROUTINES_UPDATED" },
        title = function() return L["Routines"] end,
        build = function(f)
            f.value = Theme.Text(f, 16, C.gold)
            f.value:SetPoint("TOPLEFT", 12, -28)
            f.lines = Theme.Text(f, 10, C.textDim)
            f.lines:SetPoint("TOPLEFT", 12, -52)
            f.lines:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f.lines:SetJustifyH("LEFT")
            f:EnableMouse(true)
            f:SetScript("OnMouseUp", function() A.UI:Show("routines") end)
        end,
        refresh = function(f)
            local list = ns.Tasks.Routine(ns.Routines.CharKey())
            local value, minutes, open = ns.Tasks.Totals(list)
            f.value:SetText(Money(value))
            local lines = { A.Lf("%d open, %s", open, UI.Minutes(minutes)) }
            for _, e in ipairs(list) do
                if not e.done and #lines < 4 then
                    lines[#lines + 1] = (e.task.name or "?") .. "  " .. Money(e.perMinute) .. "/min"
                end
            end
            if #list == 0 then lines = { L["Pin tasks in the Routines tab."] } end
            f.lines:SetText(table.concat(lines, "\n"))
        end,
    })
end

-- Settings ----------------------------------------------------------------------------------------
local function BuildSettings(parent, y)
    local A = API()
    local settings = ns.Routines.db.settings
    local form = A.Form.New(parent, y)
    form:Group(L["Default durations (minutes)"], L["Used until own runs measure a task."])
    for _, kind in ipairs({ "quest", "instance", "worldboss", "delve", "patron", "profession" }) do
        form:Number({ label = UI.KindName(kind), min = 1,
            get = function() return settings.durations[kind] end,
            set = function(n)
                settings.durations[kind] = n
                A.Emit("ROUTINES_UPDATED", { part = "settings" })
            end })
    end
    form:Group(L["Notices"])
    form:Toggle({ label = L["Chat line at login"], description = L["What is still open in your routine this week."],
        get = function() return settings.resetNotice end,
        set = function(on) settings.resetNotice = on end })
    local chars = {}
    for charKey, c in pairs(ns.Routines.db.root.chars) do
        if type(c) == "table" then chars[#chars + 1] = charKey end
    end
    table.sort(chars)
    if #chars > 0 then
        form:Group(L["Characters"], L["Switched off characters are left out of the overview."])
        for _, charKey in ipairs(chars) do
            form:Toggle({ label = charKey:match("^([^%-]+)") or charKey, description = charKey,
                get = function() return not settings.hiddenChars[charKey] end,
                set = function(on)
                    settings.hiddenChars[charKey] = (not on) or nil
                    A.Emit("ROUTINES_UPDATED", { part = "settings" })
                end })
        end
    end
    return form:Finish()
end

--- Chat line after login: what is still open in the routine this week, or nil.
function UI.LoginLine(charKey)
    local list = ns.Tasks.Routine(charKey)
    local value, minutes, open = ns.Tasks.Totals(list)
    if open == 0 then return nil end
    return ns.API.Lf("Routines - %d open: %s in %s", open, Money(value), UI.Minutes(minutes))
end

function UI.Enable(m)
    local A = API()
    A.UI:RegisterTab({
        id = "routines", title = function() return L["Routines"] end, order = 35,
        build = BuildTab,
        onShow = function()
            UI.Refresh()
            A.On("ROUTINES_UPDATED", UI.Refresh, OWNER)
        end,
        onHide = function() A.Off("ROUTINES_UPDATED", OWNER) end,
    })
    A.UI:RegisterSettings({ id = "routines", title = function() return L["Routines"] end, order = 45,
        build = BuildSettings, description = function() return L["Default durations and which characters count."] end })
    RegisterCard()
    m:After(8, function()
        if not m.db.settings.resetNotice then return end
        local line = UI.LoginLine(ns.Routines.CharKey())
        if line then A.Print(line) end
    end)
end
