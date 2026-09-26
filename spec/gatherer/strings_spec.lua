describe("Gatherer: farm and watchlist strings", function()
    after_each(function() assert.same({}, WoWMock.errors) end)

    local pns

    before_each(function()
        pns = select(2, load_gatherer())
    end)

    it("round-trips a farm under a unique name without its history", function()
        local farm = pns.Farms.Create({ name = "Herbs", category = "raid", expectedHighlights = { "i:1", "i:2" },
            instance = { journalID = 1296, mapID = 2769, name = "Liberation of Undermine", isRaid = true }, highlightThreshold = 900 })
        pns.Farms.AddSummary({ farmId = farm.id, started = 1, duration = 60, total = 1, gph = 60 })
        local text = pns.Strings.ExportFarms({ farm.id })
        assert.truthy(text:match("^!GOB:FARM:2!"))
        local kind, created = pns.Strings.Import("  " .. text .. "\n")
        assert.equals("farms", kind)
        local copy = created[1]
        assert.equals("Herbs (2)", copy.name)
        assert.are_not.equal(farm.id, copy.id)
        assert.equals("raid", copy.category)
        assert.same({ "i:1", "i:2" }, copy.expectedHighlights)
        assert.same({ journalID = 1296, mapID = 2769, name = "Liberation of Undermine", isRaid = true }, copy.instance)
        assert.equals(900, copy.highlightThreshold)
        assert.equals(0, pns.Farms.Stats(copy.id).runs)
    end)

    it("imports version 1 farm strings with expected items and a farm watchlist as highlights", function()
        local serialize, deflate = LibStub("LibSerialize"), LibStub("LibDeflate")
        local text = "!GOB:FARM:1!" .. deflate:EncodeForPrint(deflate:CompressDeflate(serialize:Serialize({
            farms = { { name = "Old", category = "dungeon", expectedItems = { "i:3" }, watchlist = { "i:4", "i:3" },
                instance = "The Stonevault", expectedGPH = 1 } },
        })))
        local kind, created = pns.Strings.Import(text)
        assert.equals("farms", kind)
        assert.same({ "i:3", "i:4" }, created[1].expectedHighlights)
        assert.same({ name = "The Stonevault", isRaid = false }, created[1].instance)
        assert.is_nil(created[1].expectedGPH)
    end)

    it("round-trips the global watchlist", function()
        pns.Highlights.SetWatched("i:7", true)
        pns.Highlights.SetWatched("i:8", true)
        local text = pns.Strings.ExportWatchlist()
        pns.Highlights.SetWatched("i:7", false)
        pns.Highlights.SetWatched("i:8", false)
        local kind, keys = pns.Strings.Import(text)
        assert.equals("watchlist", kind)
        assert.same({ "i:7", "i:8" }, keys)
        assert.same({ "i:7", "i:8" }, pns.Highlights.Watchlist())
    end)

    it("rejects invalid strings, newer versions and malformed payloads", function()
        assert.same({ nil, "format" }, { pns.Strings.Import("hello") })
        assert.same({ nil, "format" }, { pns.Strings.Import("!GOB:FARM:1!notbase64$$") })
        local good = pns.Strings.ExportWatchlist()
        assert.same({ nil, "version" }, { pns.Strings.Import((good:gsub("^!GOB:WATCH:1!", "!GOB:WATCH:2!"))) })
        local serialize, deflate = LibStub("LibSerialize"), LibStub("LibDeflate")
        local function encode(kind, payload)
            return "!GOB:" .. kind .. ":1!" .. deflate:EncodeForPrint(deflate:CompressDeflate(serialize:Serialize(payload)))
        end
        assert.same({ nil, "format" }, { pns.Strings.Import(encode("FARM", { farms = { { name = "" } } })) })
        assert.same({ nil, "format" }, { pns.Strings.Import(encode("WATCH", { items = { "evil()" } })) })
        assert.same({ nil, "format" }, { pns.Strings.Import(encode("OTHER", {})) })
        assert.equals(0, #pns.Farms.List())
    end)
end)
