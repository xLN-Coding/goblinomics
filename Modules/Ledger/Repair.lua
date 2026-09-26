if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Ledger/Repair.lua
-- One-time repair (schema 2): before the fix in the classifier, money of several
-- mails taken at once ("open all") arrived as one PLAYER_MONEY and was booked as
-- Mail/in from the context (no sender note). The auction log still recorded the
-- sales at that moment, so those bookings are split back: every logged sale
-- within the booking's time span that has no AH booking yet becomes an AH/sale
-- booking. The auction log keeps the gross price only; the net is estimated as
-- price minus the 5 % cut plus the deposit returned with the sale (deposit per
-- unit from the posting log). A small rest (rounding) is spread over the sales,
-- a larger one stays as Mail.
local _, ns = ...

local Repair = {}
ns.Repair = Repair

local T, CHAR, CAT, SUB, AMT, KEY, QTY, NOTE, COUNT = 1, 2, 3, 4, 5, 6, 7, 9, 10
local E_T, E_KIND, E_KEY, E_QTY, E_AMT = 1, 2, 3, 4, 5
local SPAN = 65          -- merge window (60 s) plus slack
local ABSORB = 0.05      -- rest up to 5 % of the sales counts as deposits/rounding


--- Returns the number of split bookings.
function Repair.MergedMail(root)
    local events = root.ah and root.ah.events or {}
    local deposits = root.ah and root.ah.deposits or {}
    local function Net(e)
        local perUnit = e[E_KEY] and deposits[e[E_KEY]] or 0
        return math.floor(e[E_AMT] * 0.95) + math.floor(perUnit * (e[E_QTY] or 1) + 0.5)
    end
    local sales = {}
    for _, e in ipairs(events) do
        if e[E_KIND] == "sale" and (e[E_AMT] or 0) > 0 then sales[#sales + 1] = { e = e } end
    end
    if #sales == 0 then return 0 end
    -- sales that already have their booking
    for _, list in pairs(root.tx or {}) do
        for _, tx in ipairs(list) do
            if tx[CAT] == "AH" and tx[SUB] == "sale" then
                for _, s in ipairs(sales) do
                    if not s.used and math.abs(s.e[E_T] - tx[T]) <= 3 and s.e[E_KEY] == tx[KEY]
                        and (s.e[E_QTY] or 1) == (tx[QTY] or 1) then
                        s.used = true
                        break
                    end
                end
            end
        end
    end
    local split = 0
    for _, list in pairs(root.tx or {}) do
        local i = 1
        while i <= #list do
            local tx = list[i]
            local found = {}
            if tx[CAT] == "Mail" and tx[SUB] == "in" and tx[NOTE] == nil and (tx[AMT] or 0) > 0 then
                local sum = 0
                for _, s in ipairs(sales) do
                    local dt = tx[T] - s.e[E_T]
                    if not s.used and dt >= -3 and dt <= SPAN and sum + Net(s.e) <= tx[AMT] then
                        found[#found + 1] = s
                        sum = sum + Net(s.e)
                    end
                end
                if #found > 0 then
                    local rest = tx[AMT] - sum
                    local absorb = rest <= sum * ABSORB
                    local new = {}
                    local given = 0
                    for _, s in ipairs(found) do
                        s.used = true
                        local net = Net(s.e)
                        if absorb then net = math.floor(net * tx[AMT] / sum) end
                        given = given + net
                        new[#new + 1] = { s.e[E_T], tx[CHAR], "AH", "sale", net, s.e[E_KEY], s.e[E_QTY] }
                    end
                    if absorb then
                        new[1][AMT] = new[1][AMT] + (tx[AMT] - given)
                    else
                        tx[AMT] = rest
                        tx[COUNT] = nil
                        new[#new + 1] = tx
                    end
                    table.remove(list, i)
                    for k, n in ipairs(new) do table.insert(list, i + k - 1, n) end
                    i = i + #new - 1
                    split = split + 1
                end
            end
            i = i + 1
        end
    end
    return split
end
