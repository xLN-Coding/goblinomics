if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Ledger/Dedup.lua
-- Duplicate detection for imports (M8). TSM and Journalator record the same
-- events as the Ledger, with their own timestamps (mail time instead of the
-- moment it was opened) and TSM with gross auction prices. A booking counts as
-- known when a stored booking of the same character, category and sub-category
-- lies within WINDOW seconds and
--   - both have an item: same item and quantity (auction sales: amount ignored,
--     TSM is gross, the Ledger net),
--   - an auction sale without item on one side: same quantity (if known) and an
--     amount within 10 %,
--   - otherwise: the same amount.
-- Every stored booking matches only once. Imported bookings are added to the
-- index as they go, so TSM followed by Journalator and a repeated import stay
-- free of duplicates. Auction log events match on kind, item (or name),
-- quantity and time.
local _, ns = ...

local Dedup = {}
ns.Dedup = Dedup

Dedup.WINDOW = 300

local function Near(a, b) return math.abs(a - b) <= Dedup.WINDOW end

local function SameBooking(e, b)
    if e.char ~= b.char or e.category ~= b.category or e.sub ~= b.sub or not Near(e.time, b.time) then return false end
    local sale = e.category == "AH" and e.sub == "sale"
    if e.itemKey and b.itemKey then
        if e.itemKey ~= b.itemKey or (e.quantity or 1) ~= (b.quantity or 1) then return false end
        return sale or e.amount == b.amount
    end
    if sale then
        if e.quantity and b.quantity and e.quantity ~= b.quantity then return false end
        return math.abs(e.amount - b.amount) <= math.abs(b.amount) * 0.1
    end
    return e.amount == b.amount
end

--- Index over the stored bookings and auction log events.
function Dedup.New(root)
    local idx = { bookings = {}, events = {} }
    for day, list in pairs(root.tx) do
        for _, tx in ipairs(list) do
            local b = ns.Store.Decode(tx, day)
            local k = (b.char or "") .. "|" .. (b.category or "")
            idx.bookings[k] = idx.bookings[k] or {}
            table.insert(idx.bookings[k], b)
        end
    end
    local E = ns.AuctionLog.F
    for _, ev in ipairs(root.ah.events) do
        local key = ev[E.KEY] or (ev[E.NAME] and root.ah.names[ev[E.NAME]])
        local k = ev[E.KIND]
        idx.events[k] = idx.events[k] or {}
        table.insert(idx.events[k], { time = ev[E.T], itemKey = key, name = ev[E.NAME], quantity = ev[E.QTY] })
    end

    --- true when the booking is already known (and marks the stored one as used)
    function idx:Booking(e)
        local list = self.bookings[(e.char or "") .. "|" .. e.category]
        for _, b in ipairs(list or {}) do
            if not b.used and SameBooking(e, b) then
                b.used = true
                return true
            end
        end
        return false
    end

    function idx:AddBooking(e)
        local k = (e.char or "") .. "|" .. e.category
        self.bookings[k] = self.bookings[k] or {}
        table.insert(self.bookings[k], { time = e.time, char = e.char, category = e.category, sub = e.sub,
            amount = e.amount, itemKey = e.itemKey, quantity = e.quantity, used = true })
    end

    function idx:Event(e)
        for _, x in ipairs(self.events[e.kind] or {}) do
            if not x.used and Near(e.time, x.time) and (e.quantity or 1) == (x.quantity or 1)
                and ((e.itemKey and e.itemKey == x.itemKey) or (e.name and e.name == x.name)) then
                x.used = true
                return true
            end
        end
        return false
    end

    function idx:AddEvent(e)
        self.events[e.kind] = self.events[e.kind] or {}
        table.insert(self.events[e.kind], { time = e.time, itemKey = e.itemKey, name = e.name, quantity = e.quantity,
            used = true })
    end
    return idx
end

--- Import a batch: { source, entries = { booking }, events = { auction event } }.
-- dryRun only counts. Returns { added, duplicates, events, eventDuplicates,
--   categories = { [category] = { new, duplicates, amount } } }.
function Dedup.Import(root, batch, dryRun)
    local idx = Dedup.New(root)
    local result = { added = 0, duplicates = 0, events = 0, eventDuplicates = 0, categories = {} }
    local entries, events = {}, {}
    for _, e in ipairs(batch.entries or {}) do
        local c = result.categories[e.category] or { new = 0, duplicates = 0, amount = 0 }
        result.categories[e.category] = c
        if idx:Booking(e) then
            c.duplicates = c.duplicates + 1
            result.duplicates = result.duplicates + 1
        else
            idx:AddBooking(e)
            c.new = c.new + 1
            c.amount = c.amount + e.amount
            e.source = batch.source
            entries[#entries + 1] = e
        end
    end
    for _, e in ipairs(batch.events or {}) do
        if idx:Event(e) then
            result.eventDuplicates = result.eventDuplicates + 1
        else
            idx:AddEvent(e)
            events[#events + 1] = e
        end
    end
    result.added, result.events = #entries, #events
    if not dryRun then
        table.sort(entries, function(a, b) return a.time < b.time end)
        ns.Store.Import(entries)
        ns.AuctionLog.Import(events, batch.source)
        if ns.Retention then ns.Retention.Run() end
    end
    return result
end
