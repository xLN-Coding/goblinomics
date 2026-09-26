if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Gatherer/TextDialog.lua
-- One reusable dialog with a multi-line edit box: copy text out (summary, export
-- strings; the text is selected, Ctrl+C copies) or paste text in (import).
local _, ns = ...
local CODE = setmetatable({}, { __index = function(_, k) return ns.API.Theme.CODE[k] end })

local TextDialog = {}
ns.TextDialog = TextDialog

local dialog

local function Build()
    local API = ns.API
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    local L = ns.L
    local d
    d = W.Dialog({ name = "GoblinomicsGathererTextDialog", width = 480, height = 340,
        buttons = {
            { text = L["Close"], onClick = function() d:Hide() end },
            { text = L["OK"], primary = true, onClick = function()
                if d.onAccept then
                    local ok, err = d.onAccept(d.edit:GetText())
                    if ok == false then
                        d.hint:SetText(CODE.bad .. (err or "") .. "|r")
                        return
                    end
                end
                d:Hide()
            end },
        } })
    d.ok = d.buttons[2]
    d.hint = Theme.Text(d.body, "small", C.textDim)
    d.hint:SetPoint("TOPLEFT")
    d.hint:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
    local bg = CreateFrame("Frame", nil, d.body)
    bg:SetPoint("TOPLEFT", 0, -20)
    bg:SetPoint("BOTTOMRIGHT")
    Theme.Backdrop(bg, C.button, C.border)
    local scroll = CreateFrame("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", S.SM, -S.SM)
    scroll:SetPoint("BOTTOMRIGHT", -24, S.SM)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(Theme.Font(Theme.SIZE.body))
    edit:SetTextColor(unpack(C.text))
    edit:SetWidth(400)
    edit:SetScript("OnEscapePressed", function() d:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if d.readOnly and userInput then
            self:SetText(d.text or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    d.edit = edit
    return d
end

--- Show text to copy. opts = { title, text, hint }
function TextDialog.ShowCopy(opts)
    dialog = dialog or Build()
    dialog.readOnly, dialog.text, dialog.onAccept = true, opts.text, nil
    dialog:SetTitle(opts.title or "")
    dialog.hint:SetText(opts.hint or ns.L["Press Ctrl+C to copy."])
    dialog.ok:Hide()
    dialog.edit:SetText(opts.text or "")
    dialog:Show()
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
end

--- Ask for text to paste. opts = { title, hint, onAccept(text) -> ok, error }
function TextDialog.ShowPaste(opts)
    dialog = dialog or Build()
    dialog.readOnly, dialog.text, dialog.onAccept = false, nil, opts.onAccept
    dialog:SetTitle(opts.title or "")
    dialog.hint:SetText(opts.hint or ns.L["Paste the text with Ctrl+V."])
    dialog.ok:Show()
    dialog.edit:SetText("")
    dialog:Show()
    dialog.edit:SetFocus()
end

function TextDialog.Hide()
    if dialog then dialog:Hide() end
end
