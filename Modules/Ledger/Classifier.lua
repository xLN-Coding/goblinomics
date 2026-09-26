if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Ledger/Classifier.lua
-- Books every MONEY_DELTA exactly once (so nothing is booked twice):
--   1. warband scope                       -> Transfer / warbank
--   2. expected amount from a monitor hook -> the monitor's decision (repair, mail,
--      mail send with postage, AH deposit, warbank, trade, COD, ...). Money of
--      several mails taken at once ("open all") can arrive as one PLAYER_MONEY:
--      a sum of expected amounts books each part with its own decision; at the
--      mailbox the expected mails that fit are booked and only the rest goes on
--      (in-game finding, M7: auction sales ended up as Mail).
--   3. context snapshot of the delta       -> Vendor, Loot, Quest, AH, Mail, Trade, ...
--   4. otherwise                           -> Other / unknown with the context in the note
-- A single simultaneous ITEMS_DELTA at a merchant is attached to the vendor booking.
local _, ns = ...

local Classifier = {}
ns.Classifier = Classifier

local Store = ns.Store

local ledger
local pending = {}          -- { kind, amount, decision, expires }
local lastMerchant = nil    -- { tx, time } for item attachment
local lastItems = nil       -- { change, time }
local lastTrade = nil       -- { tx, time }
local recentUnknown = {}    -- { tx, amount, time } of Other/unknown bookings, newest last
local RECLASSIFY_WINDOW = 5
local durabilityAt = -math.huge
local PENDING_TTL = 10
local PAIR_WINDOW = 2

--- Monitors announce an expected money change. amount: signed copper, or
-- "positive" / "negative" when only the direction is known (exact amounts win).
function Classifier.Expect(kind, amount, decision, ttl)
    pending[#pending + 1] = { kind = kind, amount = amount, decision = decision, expires = GetTime() + (ttl or PENDING_TTL) }
end

function Classifier.Cancel(kind)
    for i = #pending, 1, -1 do
        if pending[i].kind == kind then table.remove(pending, i) end
    end
end

function Classifier.MarkDurability()
    durabilityAt = GetTime()
end

local function TakePending(amount)
    local now = GetTime()
    for i = #pending, 1, -1 do
        if pending[i].expires < now then table.remove(pending, i) end
    end
    for i = 1, #pending do
        local e = pending[i]
        if e.amount == amount then
            table.remove(pending, i)
            return e
        end
    end
    local sign = amount >= 0 and "positive" or "negative"
    for i = 1, #pending do
        if pending[i].amount == sign then
            return table.remove(pending, i)
        end
    end
    return nil
end

local MAX_SUBSET = 16

--- Exact amounts of the same sign as `amount`, oldest first (at most MAX_SUBSET).
local function Candidates(amount, kind)
    local list = {}
    for i = 1, #pending do
        local e = pending[i]
        if type(e.amount) == "number" and e.amount ~= 0 and (e.amount > 0) == (amount > 0)
            and (not kind or e.kind == kind) then
            list[#list + 1] = e
            if #list >= MAX_SUBSET then break end
        end
    end
    return list
end

local function Remove(entries)
    for _, e in ipairs(entries) do
        for i = #pending, 1, -1 do
            if pending[i] == e then table.remove(pending, i) break end
        end
    end
end

--- Several expected amounts that add up exactly to `amount` (oldest first), or nil.
function Classifier.TakeSum(amount)
    local cands = Candidates(amount)
    if #cands < 2 then return nil end
    local chosen = {}
    local function Search(i, sum)
        if sum == amount then return #chosen > 1 end
        if i > #cands then return false end
        local a = cands[i].amount
        if math.abs(sum + a) <= math.abs(amount) then
            chosen[#chosen + 1] = cands[i]
            if Search(i + 1, sum + a) then return true end
            chosen[#chosen] = nil
        end
        return Search(i + 1, sum)
    end
    if not Search(1, 0) then return nil end
    Remove(chosen)
    return chosen
end

--- At the mailbox: expected mail money that fits into `amount` (oldest first) and the rest.
function Classifier.TakeMail(amount)
    if amount <= 0 then return nil end
    local chosen, sum = {}, 0
    for _, e in ipairs(Candidates(amount, "mailMoney")) do
        if sum + e.amount <= amount then
            chosen[#chosen + 1] = e
            sum = sum + e.amount
        end
    end
    if #chosen == 0 then return nil end
    Remove(chosen)
    return chosen, amount - sum
end

local function CharKey()
    return ledger.db.charKey or ns.API.KnownCharacters()[1]
end

local function Book(p, d, amount)
    return Store.Add({
        time = p.time or time(), char = CharKey(), category = d.category, sub = d.sub,
        amount = amount or p.amount, itemKey = d.itemKey, quantity = d.quantity, tag = d.tag, note = d.note,
    })
end
Classifier.Book = Book

local function ContextLabel(ctx)
    for _, key in ipairs({ "merchant", "mail", "auction", "trade", "warbank", "bank", "loot", "quest", "craft",
        "craftingOrder", "taxi", "trainer", "transmog", "barber", "upgrade", "guildbank" }) do
        if ctx[key] then return key end
    end
    return ctx.marks and (next(ctx.marks)) or nil
end

local function FromContext(p)
    local ctx = p.context or {}
    local marks = ctx.marks or {}
    local positive = p.amount >= 0
    if p.restricted then
        return { category = "Loot", sub = "instance" }
    end
    local quest = marks.questReward
    local questAmount = type(quest) == "table" and quest.money or nil
    if (quest and (questAmount == nil or questAmount == p.amount)) or ctx.quest then
        return { category = "Quest", sub = positive and "reward" or "cost" }
    end
    if ctx.merchant then
        if not positive and GetTime() - durabilityAt <= PAIR_WINDOW then
            return { category = "Repair", sub = "repair" }
        end
        return { category = "Vendor", sub = positive and "sell" or "buy", merchant = true }
    end
    if ctx.loot or marks.lootMoney then
        return { category = "Loot", sub = "money" }
    end
    if ctx.auction then
        return { category = "AH", sub = positive and "refund" or "purchase" }
    end
    if ctx.mail then
        return { category = "Mail", sub = positive and "in" or "out" }
    end
    if ctx.trade then
        return { category = "Other", sub = "trade", note = ns.Monitors and ns.Monitors.TradePartner(), trade = true }
    end
    if ctx.warbank or ctx.bank then
        return { category = "Transfer", sub = "warbank" }
    end
    if ctx.craftingOrder then
        return { category = "Crafting", sub = positive and "commission" or "fee" }
    end
    if ctx.craft and positive then
        -- fulfilled crafting orders pay the commission at the profession window
        return { category = "Crafting", sub = "commission" }
    end
    for _, key in ipairs({ "taxi", "trainer", "transmog", "barber", "upgrade", "guildbank" }) do
        if ctx[key] then return { category = "Other", sub = key } end
    end
    -- windows that closed just before the money arrived (autoloot, taxi map, ...)
    local recent = ctx.recent
    if recent then
        if recent.loot then return { category = "Loot", sub = "money" } end
        if recent.merchant then return { category = "Vendor", sub = positive and "sell" or "buy", merchant = true } end
        if recent.taxi then return { category = "Other", sub = "taxi" } end
        if recent.craft and positive then return { category = "Crafting", sub = "commission" } end
        if recent.quest then return { category = "Quest", sub = positive and "reward" or "cost" } end
        if recent.mail then return { category = "Mail", sub = positive and "in" or "out" } end
        if recent.auction then return { category = "AH", sub = positive and "refund" or "purchase" } end
        if recent.trade then
            return { category = "Other", sub = "trade", note = ns.Monitors and ns.Monitors.TradePartner(), trade = true }
        end
        for _, key in ipairs({ "trainer", "transmog", "barber", "upgrade", "craftingOrder" }) do
            if recent[key] then
                if key == "craftingOrder" then return { category = "Crafting", sub = positive and "commission" or "fee" } end
                return { category = "Other", sub = key }
            end
        end
    end
    return { category = "Other", sub = "unknown", note = ContextLabel(ctx) }
end
Classifier.FromContext = FromContext

local function AttachItem(tx, change)
    if tx and change and not tx[Store.F.KEY] then
        Store.Update(tx, { itemKey = change.itemKey, quantity = math.abs(change.delta) })
    end
end

local function BookDecision(p, d)
    if d.split then
        local booked = 0
        local first
        for i = 1, #d.split do
            local part = d.split[i]
            if part.amount ~= 0 then
                local tx = Book(p, part, part.amount)
                first = first or tx
                booked = booked + part.amount
            end
        end
        if booked ~= p.amount then
            Book(p, { category = "Other", sub = "unknown", note = "remainder" }, p.amount - booked)
        end
        return first
    end
    local tx = Book(p, d)
    if d.onBooked then d.onBooked(tx) end
    return tx
end

function Classifier.OnMoney(_, p)
    if p.scope == "warband" then
        -- the warband bank's side of a deposit or withdrawal (the character's side is "warbank")
        Book(p, { category = "Transfer", sub = "warband" })
        return
    end
    local expected = TakePending(p.amount)
    if expected then
        BookDecision(p, expected.decision)
        return
    end
    local parts, rest = Classifier.TakeSum(p.amount), 0
    if not parts then
        local ctx = p.context or {}
        if ctx.mail or (ctx.recent and ctx.recent.mail) then parts, rest = Classifier.TakeMail(p.amount) end
    end
    if parts then
        for _, e in ipairs(parts) do
            BookDecision(setmetatable({ amount = e.amount }, { __index = p }), e.decision)
        end
        if not rest or rest == 0 then return end
        p = setmetatable({ amount = rest }, { __index = p })
    end
    local d = FromContext(p)
    local tx = Book(p, d)
    local now = GetTime()
    if d.merchant then
        lastMerchant = { tx = tx, time = now }
        if lastItems and now - lastItems.time <= PAIR_WINDOW then
            AttachItem(tx, lastItems.change)
            lastItems = nil
        end
    elseif d.trade then
        lastTrade = { tx = tx, time = now, amount = p.amount }
    elseif d.sub == "unknown" then
        recentUnknown[#recentUnknown + 1] = { tx = tx, amount = p.amount, time = now }
        if #recentUnknown > 10 then table.remove(recentUnknown, 1) end
    end
end

local function OnItems(_, p)
    if not (p.context and p.context.merchant) or #p.changes ~= 1 then return end
    local now = GetTime()
    if lastMerchant and now - lastMerchant.time <= PAIR_WINDOW then
        AttachItem(lastMerchant.tx, p.changes[1])
        lastMerchant = nil
    else
        lastItems = { change = p.changes[1], time = now }
    end
end

--- A late confirmation (e.g. QUEST_TURNED_IN after PLAYER_MONEY for world quests):
-- reclassify the most recent Other/unknown booking with exactly this amount.
-- Returns true when a booking was changed.
-- amount = "positive" matches the most recent positive unknown booking (loot chat
-- lines carry a formatted amount that is not parsed).
function Classifier.Reclassify(amount, decision)
    local now = GetTime()
    for i = #recentUnknown, 1, -1 do
        local entry = recentUnknown[i]
        if now - entry.time > RECLASSIFY_WINDOW then
            table.remove(recentUnknown, i)
        elseif entry.amount == amount or (amount == "positive" and entry.amount > 0) then
            table.remove(recentUnknown, i)
            Store.Update(entry.tx, { category = decision.category, sub = decision.sub, note = decision.note })
            return true
        end
    end
    return false
end

--- A trade finished (monitor): show the popup for the matching booking.
function Classifier.TradeComplete(trade)
    local net = (trade.moneyIn or 0) - (trade.moneyOut or 0)
    if net == 0 then return end
    local show = ns.TradePopup and ns.TradePopup.Show or function() end
    if lastTrade and GetTime() - lastTrade.time <= 5 and lastTrade.amount == net then
        show(lastTrade.tx, trade.partner, net)
        lastTrade = nil
        return
    end
    Classifier.Expect("trade", net, {
        category = "Other", sub = "trade", note = trade.partner,
        onBooked = function(tx) show(tx, trade.partner, net) end,
    })
end

function Classifier.Enable(module)
    ledger = module
    module:On("MONEY_DELTA", Classifier.OnMoney)
    module:On("ITEMS_DELTA", OnItems)
end

function Classifier.Disable()
    for i = #pending, 1, -1 do pending[i] = nil end
    lastMerchant, lastItems, lastTrade = nil, nil, nil
    for i = #recentUnknown, 1, -1 do recentUnknown[i] = nil end
end
