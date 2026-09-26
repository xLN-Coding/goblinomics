if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Import/ImportUI.lua
-- Settings section "Import" (replaces the core placeholder when this addon
-- loads): one row per source (status, preview, import), "Import all" in the
-- order TSM then Journalator, a preview table per category (new, already known,
-- sum of the new bookings) and the list of imports with undo.
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local UI = {}
ns.ImportUI = UI

local API = ns.API
local L = ns.L
local PREVIEW_ROWS = 9
local LIST_ROWS = 6

local section = {}
UI.section = section

local function Money(copper)
    return API.Money.Format(math.floor((copper or 0) + 0.5), { abbreviate = true, color = true, sign = true })
end

local function SourceName(id) return id == "tsm" and "TSM Accounting" or "Journalator" end

local CATEGORY_NAMES = {
    AH = function() return L["Auction House"] end, Vendor = function() return L["Vendor"] end,
    Repair = function() return L["Repair"] end, Quest = function() return L["Quest"] end,
    Loot = function() return L["Loot"] end, Crafting = function() return L["Crafting"] end,
    Mail = function() return L["Mail"] end, Transfer = function() return L["Transfer"] end,
    Other = function() return L["Other"] end,
}

local function DateRange(d)
    if not d.from then return "" end
    return ns.API.Format:Date(d.from, "long") .. " - " .. ns.API.Format:Date(d.to, "long")
end

local function StatusText(id)
    local d = ns.Import.Detect(id)
    if not d.available then return CODE.dim .. L["not available (addon not loaded)"] .. "|r" end
    if d.count then return API.Lf("%d records", d.count) .. "  " .. DateRange(d) end
    return API.Lf("%d archive stores", d.stores or 0)
end

function UI.SetStatus(text)
    if section.status then section.status:SetText(text or "") end
end

function UI.ShowPreview(id, result)
    section.previewTitle:SetText(API.Lf("Preview: %s", SourceName(id)))
    local list = {}
    for category, c in pairs(result and result.categories or {}) do
        list[#list + 1] = { category = category, new = c.new, duplicates = c.duplicates, amount = c.amount }
    end
    table.sort(list, function(a, b) return a.category < b.category end)
    for i, row in ipairs(section.preview) do
        local e = list[i]
        row.category:SetText(e and (CATEGORY_NAMES[e.category] or CATEGORY_NAMES.Other)() or "")
        row.new:SetText(e and tostring(e.new) or "")
        row.known:SetText(e and tostring(e.duplicates) or "")
        row.amount:SetText(e and Money(e.amount) or "")
    end
    UI.SetStatus(result and API.Lf("%d new bookings, %d already known, %d auction log entries.", result.added,
        result.duplicates, result.events) or L["Nothing to import."])
end

function UI.RefreshList()
    local list = ns.Import.List()
    for i, row in ipairs(section.list or {}) do
        local r = list[i]
        local when = r and ns.API.Format:Date(r.time, "longStamp")
        row.text:SetText(r and ("%s  %s  " .. CODE.dim .. "%s|r"):format(when, SourceName(r.source),
            API.Lf("%d bookings, %d auction log entries", r.added or 0, r.events or 0)) or "")
        row.undo:SetShown(r ~= nil)
        row.record = r
    end
    section.noImports:SetShown(#list == 0)
end

local function Summary(results)
    local added, known = 0, 0
    for _, r in pairs(results) do
        if r then added, known = added + r.added, known + r.duplicates end
    end
    return API.Lf("Imported: %d new bookings, %d already known.", added, known)
end

function UI.Preview(id)
    UI.SetStatus(L["Reading..."])
    ns.Import.Preview(id, function(result) UI.ShowPreview(id, result) end)
end

function UI.Run(id)
    UI.SetStatus(L["Importing..."])
    ns.Import.Run(id, function(result)
        UI.SetStatus(result and Summary({ result }) or L["Nothing to import."])
        UI.RefreshList()
    end)
end

function UI.RunAll()
    UI.SetStatus(L["Importing..."])
    ns.Import.RunAll(function(results)
        UI.SetStatus(Summary(results))
        UI.RefreshList()
    end)
end

function UI.Undo(record)
    API.Widgets.Confirm({
        title = L["Undo import"],
        text = API.Lf("Remove the %d bookings and %d auction log entries of this import?", record.added or 0, record.events or 0),
        confirmText = L["Undo import"],
        onConfirm = function()
            local removed = ns.Import.Undo(record.id)
            UI.SetStatus(API.Lf("%d bookings removed.", removed))
            UI.RefreshList()
        end,
    })
end

function UI.Build(parent, y)
    local W, Theme = API.Widgets, API.Theme
    local C = Theme.colors
    local form = API.Form.New(parent, y)
    form:Group(L["Sources"], L["Imports the TSM Accounting and Journalator history; known bookings are skipped."])
    if not API.Ledger or not API.Ledger.Import then
        form:Note(L["The Ledger module is needed for the import."], C.loss)
        return form:Finish()
    end
    for _, id in ipairs(ns.Import.ORDER) do
        local row = form:Buttons({ label = SourceName(id), description = StatusText(id), buttons = {
            { text = L["Preview"], width = 90, onClick = function() UI.Preview(id) end },
            { text = L["Import"], width = 90, onClick = function() UI.Run(id) end },
        } })
        if not ns.Import.Detect(id).available then
            for _, b in ipairs(row.control.buttons) do b:SetEnabled(false); b:SetAlpha(0.4) end
        end
    end
    form:Buttons({ label = L["All sources"], description = L["TSM first (the longer history), then Journalator."],
        buttons = { { text = L["Import all"], width = 186, onClick = UI.RunAll } } })
    section.status = form:Note("", C.gold).text

    form:Group(L["Preview"])
    form:Custom(20 + 16 + PREVIEW_ROWS * 16, function(box)
        section.previewTitle = Theme.Text(box, 12, C.text)
        section.previewTitle:SetPoint("TOPLEFT", 0, 0)
        section.previewTitle:SetText(L["Choose a source and click Preview."])
        local heads = { { L["Category"], 0 }, { L["New"], 200 }, { L["Known"], 270 }, { L["Sum"], 340 } }
        for _, h in ipairs(heads) do
            local fs = Theme.Text(box, 10, C.textDim)
            fs:SetPoint("TOPLEFT", h[2], -20)
            fs:SetText(h[1]:upper())
        end
        section.preview = {}
        for i = 1, PREVIEW_ROWS do
            local row = {}
            for key, x in pairs({ category = 0, new = 200, known = 270, amount = 340 }) do
                row[key] = Theme.Text(box, 11, C.text)
                row[key]:SetPoint("TOPLEFT", x, -36 - (i - 1) * 16)
            end
            section.preview[i] = row
        end
    end)

    form:Group(L["Imports"], L["Every import can be undone completely."])
    form:Custom(LIST_ROWS * 26, function(box)
        section.noImports = Theme.Text(box, 11, C.textDim)
        section.noImports:SetPoint("TOPLEFT", 0, -4)
        section.noImports:SetText(L["No imports yet."])
        section.list = {}
        for i = 1, LIST_ROWS do
            local row = {}
            row.text = Theme.Text(box, 11, C.text)
            row.text:SetPoint("TOPLEFT", 0, -(i - 1) * 26 - 5)
            row.undo = W.Button(box, L["Undo import"], { width = 120, height = 22, onClick = function()
                if row.record then UI.Undo(row.record) end
            end })
            row.undo:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -(i - 1) * 26)
            section.list[i] = row
        end
    end)
    UI.RefreshList()
    return form:Finish()
end

API.UI:RegisterSettings({ id = "import", title = function() return L["Import"] end, order = 80, build = UI.Build,
    module = "Goblinomics_Import",
    description = function() return L["History from TSM Accounting and Journalator."] end })
