local fake = require("spec.support.sources")

local HERB = "|cffffffff|Hitem:210796::::::::80:::::|h[Mycobloom]|h|r"

describe("Gatherer: HUD and summary window", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local ns, pns

    local function lootLine(link, qty)
        WoWMock.fire("CHAT_MSG_LOOT", "You receive loot: " .. link .. "x" .. qty .. ".", nil, nil, nil, nil, nil, nil,
            nil, nil, nil, nil, WoWMock.player.guid)
    end

    before_each(function()
        ns, pns = load_gatherer()
        ns.Price.RegisterSource(fake("tsm", 10, { market = { ["i:210796"] = 100000 } }))
    end)

    it("shows only while a session exists and follows pause and loot", function()
        assert.is_false(pns.HUD.IsShown())
        local farm = pns.Farms.Create({ name = "Herbs" })
        pns.Session.Start(farm.id)
        local hud = _G.GoblinomicsGathererHUD
        assert.is_true(hud:IsShown())
        assert.equals("Herbs", hud.title:GetText())
        assert.equals("No loot yet", hud.items[1].name:GetText())
        lootLine(HERB, 5)
        WoWMock.advance(1)
        assert.equals(HERB .. " x5", hud.items[1].name:GetText())
        assert.equals("00:00:01", hud.time:GetText())
        pns.Session.Pause()
        assert.equals("Resume", hud.pause.label:GetText())
        assert.equals("Paused", hud.status:GetText())
        pns.HUD.StopAndSummarize()
        assert.is_false(hud:IsShown())
        assert.is_true(_G.GoblinomicsGathererSummary:IsShown())
        assert.truthy(_G.GoblinomicsGathererSummary.text:find("Farm: Herbs", 1, true))
    end)

    it("can be hidden for the current session and shown again", function()
        pns.Session.Start(nil)
        pns.HUD.HideForSession()
        assert.is_false(pns.HUD.IsShown())
        pns.HUD.ShowForSession()
        assert.is_true(pns.HUD.IsShown())
        pns.Session.Stop()
        pns.Session.Start(nil)
        assert.is_true(pns.HUD.IsShown())
    end)

    it("summary window: earned gold on top, items as links sorted by value", function()
        local ORE = "|cffffffff|Hitem:210930::::::::80:::::|h[Bismuth]|h|r"
        ns.Price.RegisterSource(fake("auctionator", 20, { market = { ["i:210930"] = 500000 } }))
        local farm = pns.Farms.Create({ name = "Herbs" })
        pns.Session.Start(farm.id)
        lootLine(HERB, 5)    -- 5 x 10 g = 50 g
        lootLine(ORE, 2)     -- 2 x 50 g = 100 g
        WoWMock.advance(1800)
        pns.HUD.StopAndSummarize()
        local w = _G.GoblinomicsGathererSummary
        assert.equals("Session summary: Herbs", w.title:GetText())
        assert.truthy(w.total:GetText():find("150", 1, true))
        assert.truthy(w.gph:GetText():find("300", 1, true))
        local rows = w.items.box._rows
        assert.equals(2, #rows)
        assert.equals(ORE, rows[1].name:GetText())
        assert.equals("x2", rows[1].qty:GetText())
        assert.equals(HERB, rows[2].name:GetText())
        assert.equals("ITEMS (2)", w.itemsTitle:GetText())
    end)

    it("summary rows fall back to the cached item link and keep the value at the stop", function()
        WoWMock.items[210796] = { name = "Mycobloom", link = HERB }
        local summary = { farmName = "Old", duration = 60, items = { ["i:210796"] = 3 }, values = { ["i:210796"] = 777 },
            market = 777, vendor = 0, speculative = 0, rawGold = 0, repair = 0, total = 777, gph = 46620, realized = 0 }
        local _, rows = pns.Summary.Build(summary)
        assert.equals(HERB, rows[1].link)
        assert.equals(777, rows[1].value)
    end)
end)
