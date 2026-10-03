-- Market Pulse: the board of your own products, trend, daily prices, warnings and the view.
local fake = require("spec.support.sources")
local S = require("spec.workshop.support")

describe("Workshop: Market Pulse", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, wns, P
    local recent, market14 = {}, {}

    before_each(function()
        ns, wns = load_workshop({ before = function()
            WoWMock.recipes[100] = { name = "Flask", profession = "Alchemy", qualityItemIDs = { 501, 502 },
                schematic = { reagentSlotSchematics = {} } }
        end })
        recent, market14 = {}, {}
        local src = fake("tsm", 10, { market = { ["i:502"] = 1000, ["i:700"] = 50, ["i:800"] = 9000 } })
        function src:Query(key, name)
            if name == "DBRecent" then return recent[key] end
            if name == "DBMarket" then return market14[key] end
            return nil
        end
        ns.Price.RegisterSource(src)
        ns.API.Gatherer = { Summaries = function() return { { started = WoWMock.now, items = { ["i:700"] = 40, ["i:999"] = 3 } } } end }
        ns.API.Vault = { ItemCount = function(_, key) return key == "i:502" and 5 or 0 end }
        ns.API.Ledger = { AuctionStats = function(_, key)
            return key == "i:502" and { saleRate = 0.6, averagePrice = 1200, lastSale = WoWMock.now - 60, sold = 3,
                posted = 5, expired = 1, cancelled = 1, revenue = 3600, depositLost = 40 } or nil end }
        P = wns.Pulse
    end)

    after_each(function()
        ns.API.Gatherer, ns.API.Vault, ns.API.Ledger = nil, nil, nil
    end)

    local function keys(map)
        local list = {}
        for k in pairs(map) do list[#list + 1] = k end
        table.sort(list)
        return list
    end

    it("shows only the items on your own list, with where they came from", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2 }) } })
        assert.same({}, keys(P.Items()))                                -- nothing comes on its own
        P.Add("i:502")
        P.Add("i:700")
        P.Add("i:800")
        local items = P.Items()
        assert.same({ "i:502", "i:700", "i:800" }, keys(items))
        assert.is_true(items["i:502"].craft)
        assert.equals(40, items["i:700"].farmed)
        assert.is_nil(items["i:800"].craft or items["i:800"].farm)
        assert.is_true(P.Has("i:700"))
        P.Remove("i:700")
        assert.same({ "i:502", "i:800" }, keys(P.Items()))
    end)

    it("takes the trend from TSM, else from the own daily prices", function()
        recent["i:502"], market14["i:502"] = 820, 1000
        local trend, source = P.Trend("i:502")
        assert.equals("tsm", source)
        assert.is_true(math.abs(trend + 0.18) < 1e-9)
        local root = GoblinomicsWorkshopDB
        root.pulse["i:700"] = {}
        for i = 1, 4 do root.pulse["i:700"][P.Day(WoWMock.now - i * 86400)] = 100 end
        root.pulse["i:700"][P.Day(WoWMock.now)] = 80
        trend, source = P.Trend("i:700")
        assert.equals("history", source)
        assert.is_true(math.abs(trend + 0.2) < 1e-9)
        assert.is_nil(P.Trend("i:800"))                                  -- neither TSM nor history
    end)

    it("stores the daily price once a day and prunes after 90 days", function()
        P.Add("i:502")
        P.Add("i:700")
        P.Snapshot()
        WoWMock.flush()
        local root = GoblinomicsWorkshopDB
        local today = P.Day(WoWMock.now)
        assert.equals(1000, root.pulse["i:502"][today])
        assert.equals(50, root.pulse["i:700"][today])
        root.pulse["i:502"][today] = 1
        P.Snapshot()
        WoWMock.flush()
        assert.equals(1, root.pulse["i:502"][today])                    -- only once a day
        root.pulse["i:502"]["2020-01-01"] = 5
        P.Prune()
        assert.is_nil(root.pulse["i:502"]["2020-01-01"])
        assert.equals(50, P.History("i:700", 1)[1])
    end)

    it("warns only for items in stock below the threshold, toasts once a day and prints at login", function()
        P.Add("i:502")
        P.Add("i:700")
        recent["i:502"], market14["i:502"] = 820, 1000                  -- -18 %, 5 in stock
        recent["i:700"], market14["i:700"] = 10, 50                     -- -80 %, nothing in stock
        local rows = P.Rows()
        local byKey = {}
        for _, r in ipairs(rows) do byKey[r.key] = r end
        assert.is_true(byKey["i:502"].warning)
        assert.is_false(byKey["i:700"].warning)
        assert.equals(0.6, byKey["i:502"].saleRate)
        assert.equals(5, byKey["i:502"].stock)
        GoblinomicsWorkshopDB.settings.pulseThreshold = 20
        assert.is_false(P.Rows()[2].warning or P.Rows()[1].warning)
        GoblinomicsWorkshopDB.settings.pulseThreshold = 15
        local toasts = {}
        ns.Toast.Show = function(spec) toasts[#toasts + 1] = spec end
        for k in pairs(WoWMock.chat) do WoWMock.chat[k] = nil end
        wns.PulseNotices.Check()
        wns.PulseNotices.Check()
        assert.equals(1, #toasts)
        local printed = false
        for _, line in ipairs(WoWMock.chat) do if line:find("Price drop", 1, true) then printed = true end end
        assert.is_true(printed)
        assert.is_nil(wns.PulseNotices.Line({ { key = "i:1", warning = false } }))
    end)

    it("filters, sorts and shows the view and its details", function()
        S.craft(100, {}, { { S.result({ id = 502, quality = 2 }) } })
        P.Add("i:502")
        P.Add("i:700")
        recent["i:502"], market14["i:502"] = 820, 1000
        local V = wns.WorkshopPulse
        local rows = P.Rows()
        assert.equals(2, #V.Filter(rows, { source = "all", search = "" }))
        assert.equals(1, #V.Filter(rows, { source = "farm", search = "" }))
        assert.equals(1, #V.Filter(rows, { source = "all", search = "", onlyWarnings = true }))
        local byStock = V.Filter(rows, { source = "all", search = "", sort = "stock" })
        assert.equals("i:502", byStock[1].key)
        assert.equals("i:42", V.ParseItem("42"))
        assert.equals("i:502", V.ParseItem("|cffffffff|Hitem:502::::::::80:::::|h[F]|h|r"))
        assert.is_nil(V.ParseItem("hello"))
        local root = GoblinomicsWorkshopDB
        root.pulse["i:502"] = { [P.Day(WoWMock.now - 86400)] = 1000, [P.Day(WoWMock.now)] = 800 }   -- draws a sparkline
        local tab = ns.UI.GetTab("workshop")
        tab.build(CreateFrame("Frame"))
        tab.onShow()
        wns.WorkshopUI.Show("market")
        assert.equals(2, #wns.WorkshopUI.CurrentPage().rows)
        V.OpenDetail(rows[1])
        local left, right = V.DetailLines(rows[1])
        assert.is_truthy(table.concat(left, "|"):find("Latest scan", 1, true))
        assert.is_truthy(table.concat(right, "|"):find("Posted 5, sold 3", 1, true))
        V.Detail().buttons[1]:GetScript("OnClick")(V.Detail().buttons[1], "LeftButton")
        assert.is_false(P.Has(rows[1].key))                            -- removed from the list
        V.OpenAdd()
        local d = V.Adder()
        d.box:SetText("800")
        d.box:GetScript("OnTextChanged")(d.box)
        assert.equals("i:800", d.key)
        d.buttons[2]:GetScript("OnClick")(d.buttons[2], "LeftButton")
        assert.is_true(P.Has("i:800"))
        tab.onHide()
    end)

    it("puts a recipe's product on the list from the profession window and takes it off again", function()
        local B = wns.ProfessionButton
        assert.same({ "i:501", "i:502" }, B.Keys(100))                  -- every quality tier
        assert.is_nil(B.Keys(nil))
        assert.is_true(B.Toggle(100))
        assert.is_true(P.Has("i:501") and P.Has("i:502"))
        assert.is_false(B.Toggle(100))
        assert.is_false(P.Has("i:501") or P.Has("i:502"))
        local form = CreateFrame("Frame")
        function form:GetRecipeInfo() return { recipeID = 100 } end
        _G.ProfessionsFrame = { CraftingPage = { SchematicForm = form } }
        B.Attach()
        assert.equals("+ Market", B.button.label:GetText())
        B.button:GetScript("OnClick")(B.button, "LeftButton")
        assert.is_true(P.Has("i:502"))
        assert.equals("- Market", B.button.label:GetText())
        _G.ProfessionsFrame = nil
    end)
end)
