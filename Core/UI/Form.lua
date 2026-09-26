if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Form.lua
-- Settings forms of UI kit v1 : cards with a title and rows
-- of one layout - the name on the left, a short explanation in grey below it,
-- the control right-aligned, a 1 px line between rows. Every settings section
-- builds with it, so all sections look the same.
--   local form = API.Form.New(parent, y)
--   form:Group(title, intro)   -- intro optional
--   form:Toggle({ label, description, get, set })
--   ... Select, Slider, Number, Text, Sound, Buttons, Note, Custom
--   return form:Finish()     -- height for RegisterSettings' build(parent, y)
local _, ns = ...

local Form = {}
ns.Form = Form
local Theme, Widgets = ns.Theme, ns.Widgets
local C = Theme.colors
local L = ns.L

local PAD = Theme.space.PAD
local GAP = Theme.space.GAP
local ROW = 34
local ROW_DESC = 52
Form.PAD, Form.GAP = PAD, GAP

local Methods = {}
Methods.__index = Methods

--- New form in `parent`, starting at offset y (negative, from the top).
function Form.New(parent, y)
    return setmetatable({ parent = parent, start = y or 0, y = y or 0, cards = {} }, Methods)
end

local function CloseCard(self)
    local card = self.card
    if not card then return end
    card:SetHeight(-card.cursor + PAD - 4)
    self.y = self.y + card.cursor - PAD + 4 - GAP
    self.card = nil
end

--- Start a card with a title and an optional introduction.
function Methods:Group(title, description)
    CloseCard(self)
    local card = CreateFrame("Frame", nil, self.parent)
    card:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, self.y)
    card:SetPoint("RIGHT", self.parent, "RIGHT", -4, 0)
    Theme.Backdrop(card, C.panel, C.border)
    card.title = Theme.Text(card, "caption", C.textDim)
    card.title:SetPoint("TOPLEFT", PAD, Theme.space.CARD_TITLE_Y)
    card.title:SetText((title or ""):upper())
    card.cursor = Theme.space.CARD_BODY_Y
    if description then
        card.intro = Theme.Text(card, "small", C.textDim)
        card.intro:SetPoint("TOPLEFT", PAD, Theme.space.CARD_BODY_Y)
        card.intro:SetPoint("RIGHT", card, "RIGHT", -PAD, 0)
        card.intro:SetJustifyV("TOP")
        card.intro:SetText(description)
        card.cursor = Theme.space.CARD_BODY_Y - 22
    end
    card.rows = 0
    self.card = card
    self.cards[#self.cards + 1] = card
    return card
end

--- Next row frame of the current card (a line above every row but the first).
local function NewRow(self, height)
    if not self.card then self:Group("") end
    local card = self.card
    local row = CreateFrame("Frame", nil, card)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, card.cursor)
    row:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    row:SetHeight(height)
    if card.rows > 0 then
        local line = row:CreateTexture(nil, "BORDER")
        line:SetColorTexture(unpack(C.border))
        line:SetPoint("TOPLEFT", PAD, 0)
        line:SetPoint("TOPRIGHT", -PAD, 0)
        line:SetHeight(1)
    end
    card.rows = card.rows + 1
    card.cursor = card.cursor - height
    return row
end

--- Row with label, optional explanation and a control on the right.
function Methods:Row(spec, control, controlWidth)
    local row = NewRow(self, spec.description and ROW_DESC or ROW)
    control:SetParent(row)
    control:ClearAllPoints()
    control:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    local right = -(PAD + (controlWidth or 200) + 16)
    row.label = Theme.Text(row, "body", C.text)
    row.label:SetPoint("RIGHT", row, "RIGHT", right, 0)
    row.label:SetWordWrap(false)
    if spec.description then
        row.label:SetPoint("TOPLEFT", PAD, -10)
        row.description = Theme.Text(row, "caption", C.textDim)
        row.description:SetPoint("TOPLEFT", PAD, -27)
        row.description:SetPoint("RIGHT", row, "RIGHT", right, 0)
        row.description:SetJustifyV("TOP")
        if row.description.SetMaxLines then row.description:SetMaxLines(2) end
        row.description:SetText(spec.description)
    else
        row.label:SetPoint("LEFT", PAD, 0)
    end
    row.label:SetText(spec.label or "")
    row.control = control
    return row
end

function Methods:Toggle(spec)
    local box = Widgets.Checkbox(self.parent, "", spec.get, spec.set, { width = 36 })
    return self:Row(spec, box, 36)
end

function Methods:Select(spec)
    local width = spec.width or 180
    local drop = Widgets.Dropdown(self.parent, spec.choices, spec.get, spec.set,
        { width = width, scroll = spec.scroll })
    return self:Row(spec, drop, width)
end

--- Two to five options side by side: spec.options = { { value, label } }.
function Methods:Segmented(spec)
    local seg = Widgets.Segmented(self.parent, spec.options, spec.get, spec.set, { min = spec.min or 60 })
    local width = seg.GetWidth and seg:GetWidth()
    if type(width) ~= "number" or width <= 1 then width = 60 * #spec.options end
    return self:Row(spec, seg, width)
end

function Methods:Slider(spec)
    local width = spec.width or 220
    local slider = Widgets.Slider(self.parent, { min = spec.min, max = spec.max, step = spec.step or 1, width = width,
        format = spec.format, get = spec.get, set = spec.set, release = spec.release })
    return self:Row(spec, slider, width)
end

--- Whole numbers >= spec.min (default 0).
function Methods:Number(spec)
    local width = spec.width or 90
    local box = Widgets.EditBox(self.parent, {
        width = width,
        get = function() return tostring(spec.get() or 0) end,
        set = function(text)
            local n = tonumber(text)
            if not n or n < (spec.min or 0) then return false, L["Please enter a number."] end
            spec.set(math.floor(n))
            return true
        end,
    })
    if box.SetNumeric then box:SetNumeric(true) end
    return self:Row(spec, box, width)
end

--- Free text; spec.set(text) may return false, message.
function Methods:Text(spec)
    local width = spec.width or 220
    local box = Widgets.EditBox(self.parent, { width = width, get = spec.get, set = spec.set,
        tooltip = spec.tooltip, tooltipLines = spec.tooltipLines })
    return self:Row(spec, box, width)
end

function Methods:Sound(spec)
    local width = spec.width or 180
    local picker = Widgets.SoundPicker(self.parent, spec.get, spec.set, { width = width, default = spec.default })
    return self:Row(spec, picker, width + 30)
end

--- Buttons right-aligned, with an optional label: buttons = { { text, onClick, width, tooltip } }.
function Methods:Buttons(spec)
    local holder = CreateFrame("Frame", nil, self.parent)
    local x, total = 0, 0
    holder.buttons = {}
    for i = #spec.buttons, 1, -1 do
        local b = spec.buttons[i]
        local width = b.width or 120
        local button = Widgets.Button(holder, b.text, { width = width, onClick = b.onClick, tooltip = b.tooltip,
            tooltipLines = b.tooltipLines })
        button:SetPoint("RIGHT", holder, "RIGHT", -x, 0)
        x = x + width + 6
        total = total + width + (i > 1 and 6 or 0)
        holder.buttons[i] = button
    end
    holder:SetSize(total, 24)
    return self:Row(spec, holder, total)
end

--- A note over the full width (lines: expected number of lines, default 1).
function Methods:Note(text, color, lines)
    local row = NewRow(self, 12 + 14 * (lines or 1))
    row.text = Theme.Text(row, "small", color or C.textDim)
    row.text:SetPoint("TOPLEFT", PAD, -6)
    row.text:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    row.text:SetJustifyV("TOP")
    row.text:SetText(text or "")
    return row
end

--- Free content: build(frame) fills a frame of `height` inside the card's padding.
function Methods:Custom(height, build)
    local row = NewRow(self, height + 12)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetPoint("TOPLEFT", PAD, -6)
    frame:SetPoint("BOTTOMRIGHT", -PAD, 6)
    row.content = frame
    build(frame)
    return row
end

--- Close the last card; returns the height used since the start.
function Methods:Finish()
    CloseCard(self)
    return self.start - self.y - GAP
end

ns.API.Form = Form
