if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Gatherer/FarmEditor.lua
-- Dialog to create or edit a farm: name, category, for raid and dungeon farms
-- the instance (menu by expansion from the Encounter Journal), highlight
-- threshold and the expected highlights (items that always
-- notify the player when looted in a session of this farm). Items are added by
-- shift-clicking an item while the item box has focus (hook on the client's link
-- insertion, as AceGUI does) or from the farm's last session.
local _, ns = ...

local FarmEditor = {}
ns.FarmEditor = FarmEditor

local MAX_ITEM_ROWS = 8

local dialog
local form = {}
local hooked = false

local function ItemKeyFromText(text)
    local API = ns.API
    if type(text) ~= "string" then return nil end
    local link = text:match("|H(item:[^|]+)|h")
    if link then return API.ItemKey.FromLink("|H" .. link .. "|h") end
    local id = tonumber(strtrim(text))
    return id and ("i:" .. id) or nil
end
FarmEditor.ItemKeyFromText = ItemKeyFromText

local function AddItem(list, key)
    if key and not tContains(list, key) then list[#list + 1] = key end
end

local function OnInsertLink(text)
    if dialog and dialog:IsShown() and dialog.itemBox:HasFocus() then
        local key = ItemKeyFromText(text)
        if key then
            AddItem(form.expectedHighlights, key)
            dialog.itemBox:SetText("")
            FarmEditor.RefreshItems()
        end
        return true
    end
end

local function HookLinks()
    if hooked then return end
    hooked = true
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
    end
end

local function Field(d, label, y, width, field, numeric, tooltipLines)
    local W = ns.API.Widgets
    local box = W.EditBox(d.body, {
        width = width,
        get = function() return form[field] and tostring(form[field]) or "" end,
        set = function(text) form[field] = text; return true end,
        tooltip = tooltipLines and label, tooltipLines = tooltipLines,
    })
    box:SetScript("OnTextChanged", function(self) form[field] = self:GetText() end)
    if numeric then box:SetNumeric(true) end
    d:Row(label, box, y)
    return box
end

--- Instance choices by expansion (submenus) for raids or dungeons of the category.
local function InstanceChoices()
    local L = ns.L
    local isRaid = form.category == "raid"
    local list = { { value = "none", label = L["None"] } }
    for _, expansion in ipairs(ns.Instances.Catalog(isRaid)) do
        local children = {}
        for _, inst in ipairs(expansion.instances) do children[#children + 1] = { value = inst.journalID, label = inst.name } end
        list[#list + 1] = { label = expansion.name, children = children }
    end
    return list
end

local function SetInstance(journalID)
    form.instance = nil
    if journalID ~= "none" then
        local isRaid = form.category == "raid"
        for _, expansion in ipairs(ns.Instances.Catalog(isRaid)) do
            for _, inst in ipairs(expansion.instances) do
                if inst.journalID == journalID then
                    form.instance = { journalID = inst.journalID, mapID = inst.mapID, name = inst.name, isRaid = isRaid }
                end
            end
        end
    end
    FarmEditor.RefreshInstance()
end

local function Build()
    local API = ns.API
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    local L = ns.L
    local d
    d = W.Dialog({ name = "GoblinomicsGathererFarmEditor", width = 480, height = 500,
        buttons = {
            { text = L["Cancel"], onClick = function() d:Hide() end },
            { text = L["Save"], primary = true, onClick = function() FarmEditor.Save() end },
        } })
    local step = S.CONTROL_H + S.SM
    local y = 0
    d.fields = {}
    d.fields.name = Field(d, L["Name"], y, 260, "name")
    y = y - step
    d.category = W.Dropdown(d.body, function()
        local list = {}
        for _, cat in ipairs(ns.CATEGORIES) do list[#list + 1] = { value = cat, label = ns.CategoryName(cat) } end
        return list
    end, function() return form.category end, function(v)
        form.category = v
        FarmEditor.RefreshInstance()
    end, { size = "L" })
    d:Row(L["Category"], d.category, y)
    y = y - step
    d.instance = W.Dropdown(d.body, InstanceChoices, function()
        return form.instance and form.instance.journalID or "none"
    end, SetInstance, { width = 260, placeholder = L["Choose instance"], emptyValue = "none",
        display = function() return form.instance and form.instance.name end, tooltip = L["Instance"],
        tooltipLines = { L["Choose the instance by expansion. The overview then shows its lockouts per character."] } })
    d.instanceLabel = d:Row(L["Dungeon"], d.instance, y)
    y = y - step
    d.fields.highlightThreshold = Field(d, L["Notify from value (gold)"], y, 110, "highlightThreshold", true, {
        L["During a session of this farm you get a notification for every loot stack worth at least this much."],
        L["Leave empty to use the value from the Gatherer settings."],
    })
    d.thresholdHint = Theme.Text(d.body, "caption", C.textDim)
    d.thresholdHint:SetPoint("TOPLEFT", 140 + 110 + S.SM, y - 6)
    d.thresholdHint:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
    y = y - step
    d.itemBox = W.EditBox(d.body, { width = 170, get = function() return "" end, set = function(text)
        AddItem(form.expectedHighlights, ItemKeyFromText(text))
        FarmEditor.RefreshItems()
        return true
    end, tooltip = L["Expected highlights"],
        tooltipLines = { L["You get a notification whenever you loot one of these items in a session of this farm, whatever its value."],
            L["Click here, then shift-click an item, or type an item ID and press Enter."] } })
    d:Row(L["Expected highlights"], d.itemBox, y)
    d.fromSession = W.Button(d.body, L["From last session"], { auto = true, onClick = function()
        FarmEditor.AddFromLastSession()
    end, tooltip = L["From last session"],
        tooltipLines = { L["Adds every item of the farm's current or last session."] } })
    d.fromSession:SetPoint("LEFT", d.itemBox, "RIGHT", S.SM, 0)
    y = y - step

    d.itemRows = {}
    for i = 1, MAX_ITEM_ROWS do
        local row = CreateFrame("Frame", nil, d.body)
        row:SetHeight(S.ROW)
        row:SetPoint("TOPLEFT", 0, y - (i - 1) * (S.ROW + 2))
        row:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
        row.name = Theme.Text(row, "body", C.text)
        row.name:SetPoint("LEFT", 0, 0)
        row.name:SetPoint("RIGHT", -30, 0)
        row.name:SetWordWrap(false)
        row.delete = W.IconButton(row, "close", { onClick = function()
            for j = #form.expectedHighlights, 1, -1 do
                if form.expectedHighlights[j] == row.key then table.remove(form.expectedHighlights, j) end
            end
            FarmEditor.RefreshItems()
        end })
        row.delete:SetPoint("RIGHT", 0, 0)
        d.itemRows[i] = row
    end
    d.more = Theme.Text(d.body, "caption", C.textDim)
    d.more:SetPoint("TOPLEFT", 0, y - MAX_ITEM_ROWS * (S.ROW + 2))

    d.error = Theme.Text(d.body, "small", C.loss)
    d.error:SetPoint("BOTTOMLEFT", 0, 0)
    return d
end

--- Show the instance menu only for raid and dungeon farms; drop a choice of the other kind.
function FarmEditor.RefreshInstance()
    if not dialog then return end
    local L = ns.L
    local isInstance = ns.IsInstanceCategory(form.category)
    if form.instance and (not isInstance or form.instance.isRaid ~= (form.category == "raid")) then
        form.instance = nil
    end
    dialog.instanceLabel:SetShown(isInstance)
    dialog.instance:SetShown(isInstance)
    dialog.instanceLabel:SetText(form.category == "raid" and L["Raid"] or L["Dungeon"])
    dialog.instance:Refresh()
end

function FarmEditor.RefreshItems()
    if not dialog then return end
    local items = form.expectedHighlights
    for i = 1, MAX_ITEM_ROWS do
        local row, key = dialog.itemRows[i], items[i]
        row.key = key
        if key then
            row.name:SetText(ns.Valuation.ItemName(key) .. ns.API.ItemMarks:Inline(key))
            row:Show()
        else
            row:Hide()
        end
    end
    dialog.more:SetText(#items > MAX_ITEM_ROWS and ns.API.Lf("%d more items", #items - MAX_ITEM_ROWS) or "")
end

function FarmEditor.AddFromLastSession()
    local source
    local active = ns.Session.Active()
    if active and active.farmId == form.id then
        source = active.items
    else
        local last = form.id and ns.Farms.History(form.id)[1]
        source = last and last.items
    end
    if not source then return end
    local keys = {}
    for key in pairs(source) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do AddItem(form.expectedHighlights, key) end
    FarmEditor.RefreshItems()
end

--- Open for a farm (nil = new farm).
function FarmEditor.Open(farm)
    HookLinks()
    dialog = dialog or Build()
    local L = ns.L
    wipe(form)
    form.id = farm and farm.id or nil
    form.name = farm and farm.name or ""
    form.category = farm and farm.category or "gathering"
    form.instance = farm and farm.instance and CopyTable(farm.instance) or nil
    form.highlightThreshold = farm and farm.highlightThreshold or nil
    form.expectedHighlights = {}
    for _, key in ipairs(farm and farm.expectedHighlights or {}) do form.expectedHighlights[#form.expectedHighlights + 1] = key end
    dialog:SetTitle(farm and L["Edit farm"] or L["New farm"])
    for field, box in pairs(dialog.fields) do
        box:SetText(form[field] and tostring(form[field]) or "")
    end
    dialog.category:Refresh()
    FarmEditor.RefreshInstance()
    dialog.error:SetText("")
    local default = ns.Highlights.Threshold(nil)
    dialog.thresholdHint:SetText(default > 0
        and ns.API.Lf("empty: %s (settings)", ns.API.Money.Format(default, { abbreviate = true }))
        or L["empty: off (settings)"])
    dialog.fromSession:SetShown(farm ~= nil)
    FarmEditor.RefreshItems()
    dialog:Show()
end

--- Spec for Farms.Create/Update from the form.
function FarmEditor.Spec()
    return {
        name = form.name, category = form.category,
        instance = form.instance or false,
        highlightThreshold = tonumber(form.highlightThreshold) or 0,
        expectedHighlights = form.expectedHighlights,
    }
end

function FarmEditor.Save()
    local spec = FarmEditor.Spec()
    local farm, err
    if form.id then
        farm, err = ns.Farms.Update(form.id, spec)
    else
        farm, err = ns.Farms.Create(spec)
    end
    if not farm then
        dialog.error:SetText(err == "name" and ns.L["Please enter a name."] or tostring(err))
        return false
    end
    dialog:Hide()
    if ns.GathererUI then ns.GathererUI.Select(farm.id) end
    return true
end

FarmEditor.Form = function() return form end
