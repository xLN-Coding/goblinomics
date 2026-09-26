if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Ledger/TradePopup.lua
-- After every completed trade with gold: a small popup to assign category and tag
-- (e.g. Boosting). "Remember for this trade partner" pre-fills the next popup for
-- the same partner. Ignoring keeps the booking as Other / Trade. The popup waits
-- while in combat or in the restricted mode.
local _, ns = ...

local TP = {}
ns.TradePopup = TP

local API = ns.API
local L = ns.L

local ledger
local queue = {}
local frame
local waiting = false

local function Partners()
    return ledger.db.root.tradePartners
end

--- Defaults for a partner: category, tag, remembered?
function TP.Defaults(partner)
    local memo = partner and Partners()[partner]
    if memo then return memo.category, memo.tag, true end
    return "Other", nil, false
end

--- Apply the user's choice to a queued item.
function TP.Apply(item, category, tag, remember)
    tag = tag and strtrim(tag) or nil
    if tag == "" then tag = nil end
    ns.Store.Update(item.tx, { category = category, tag = tag or "" })
    if item.partner then
        if remember then
            Partners()[item.partner] = { category = category, tag = tag }
        else
            Partners()[item.partner] = nil
        end
    end
end

local function Blocked()
    return InCombatLockdown() or API.IsRestricted()
end

local function Resume()
    waiting = false
    ledger:UnregisterEvent("PLAYER_REGEN_ENABLED")
    API.Off("RESTRICTED_LEAVE", "Goblinomics_Ledger.TradePopup")
    TP.Next()
end

function TP.Next()
    if TP.IsOpen() or #queue == 0 then return end
    if Blocked() then
        if not waiting then
            waiting = true
            ledger:RegisterEvent("PLAYER_REGEN_ENABLED", Resume)
            API.On("RESTRICTED_LEAVE", Resume, "Goblinomics_Ledger.TradePopup")
        end
        return
    end
    TP.Open(table.remove(queue, 1))
end

--- Called by the classifier with the booking of a finished trade.
function TP.Show(tx, partner, amount)
    if not tx then return end
    queue[#queue + 1] = { tx = tx, partner = partner, amount = amount }
    TP.Next()
end

function TP.Queued() return #queue end

-- Frame ---------------------------------------------------------------------------------
local function Build()
    local W, Theme = API.Widgets, API.Theme
    local C, S = Theme.colors, Theme.space
    local state = {}
    frame = W.Dialog({ name = "GoblinomicsTradePopup", width = 400, height = 318, closable = false,
        buttons = {
            { text = L["Ignore"], onClick = function()
                frame:Hide()
                TP.Next()
            end },
            { text = L["Apply"], primary = true, onClick = function()
                TP.Apply(state.item, state.category, state.tag, state.remember)
                frame:Hide()
                TP.Next()
            end },
        } })
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", 0, 160)
    frame.state = state
    frame.amount = Theme.Text(frame.body, "title", C.text)
    frame.amount:SetPoint("TOPLEFT")
    -- category as a 3 x 3 grid of chips: one click instead of opening a menu
    local grid = CreateFrame("Frame", nil, frame.body)
    grid:SetPoint("TOPLEFT", 0, -26)
    grid:SetPoint("RIGHT", frame.body, "RIGHT", 0, 0)
    grid:SetHeight(3 * S.CONTROL_H + 2 * S.SM)
    frame.chips = {}
    local chipW = math.floor((400 - 2 * S.DIALOG_PAD - 2 * S.SM) / 3)
    for i, cat in ipairs(ns.Store.CATEGORIES) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local chip = W.Button(grid, ns.CategoryName(cat), { width = chipW, dimOff = true, onClick = function()
            state.category = cat
            TP.RefreshChips()
        end })
        chip:SetPoint("TOPLEFT", col * (chipW + S.SM), -row * (S.CONTROL_H + S.SM))
        chip.category = cat
        frame.chips[i] = chip
    end
    local y = -26 - 3 * S.CONTROL_H - 2 * S.SM - S.GAP
    frame.tag = W.EditBox(frame.body, {
        width = 180,
        get = function() return state.tag or "" end,
        set = function(text) state.tag = text; return true end,
        tooltip = L["Tag"], tooltipLines = { table.concat(ns.Store.Tags(), ", ") },
    })
    frame.tag:SetScript("OnTextChanged", function(self) state.tag = self:GetText() end)
    frame:Row(L["Tag"], frame.tag, y)
    frame.remember = W.Checkbox(frame.body, L["Remember for this trade partner"],
        function() return state.remember end, function(on) state.remember = on end)
    frame.remember:SetPoint("TOPLEFT", 0, y - S.CONTROL_H - S.SM)
end

function TP.RefreshChips()
    if not frame then return end
    for _, chip in ipairs(frame.chips) do chip:SetSelected(chip.category == frame.state.category) end
end

function TP.Open(item)
    if not frame then Build() end
    local state = frame.state
    local category, tag, remembered = TP.Defaults(item.partner)
    state.item, state.category, state.tag, state.remember = item, category, tag, remembered
    frame:SetTitle(ns.L["Trade with %s"]:format(item.partner or "?"))
    frame.amount:SetText(API.Money.Format(item.amount or 0, { sign = true, color = true }))
    TP.RefreshChips()
    frame.tag:SetText(tag or "")
    frame.remember:Refresh()
    frame:Show()
end

function TP.IsOpen()
    return frame ~= nil and frame:IsShown()
end

function TP.Enable(module)
    ledger = module
end

function TP.Disable()
    if frame then frame:Hide() end
    for i = #queue, 1, -1 do queue[i] = nil end
end
