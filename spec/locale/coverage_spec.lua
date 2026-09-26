-- Every L["..."] / Lf("...") key used in the addon code must have a deDE entry.
local function lua_files()
    local files = {}
    local p = io.popen('find Core Modules Connectors -name "*.lua"')
    for line in p:lines() do files[#files + 1] = line end
    p:close()
    return files
end

describe("Locale coverage", function()
    it("has a German entry for every key used in code", function()
        local ns = load_core()
        local de = ns.RegisterLocale("deDE")
        local missing = {}
        for _, file in ipairs(lua_files()) do
            local fh = assert(io.open(file))
            local src = fh:read("*a")
            fh:close()
            for key in src:gmatch('L%["([^"]*)"%]') do
                if de[key] == nil then missing[#missing + 1] = file .. ": " .. key end
            end
            for key in src:gmatch('Lf%("([^"]*)"') do
                if de[key] == nil then missing[#missing + 1] = file .. ": " .. key end
            end
        end
        assert.same({}, missing)
    end)

    it("uses English text as keys, never ids or dynamic keys", function()
        local bad = {}
        for _, file in ipairs(lua_files()) do
            local fh = assert(io.open(file))
            local src = fh:read("*a")
            fh:close()
            for key in src:gmatch('L%["([^"]*)"%]') do
                if key:match("^[%w_]+:[%w_]") then bad[#bad + 1] = file .. ": " .. key end
            end
            for key in src:gmatch('L%["([^"]*)"%s*%.%.') do
                bad[#bad + 1] = file .. ": dynamic key " .. key
            end
        end
        assert.same({}, bad)
    end)

    it("never looks up a translation with a computed key", function()
        local bad = {}
        for _, file in ipairs(lua_files()) do
            if file ~= "Core/Locale.lua" then
                local fh = assert(io.open(file))
                local n = 0
                for line in fh:lines() do
                    n = n + 1
                    if line:match("[^%w_]L%[[^\"%]]") and not line:match("^%s*%-%-") then
                        bad[#bad + 1] = file .. ":" .. n
                    end
                end
                fh:close()
            end
        end
        assert.same({}, bad)
    end)

    it("has no German entries that no code uses any more", function()
        local src = {}
        for _, file in ipairs(lua_files()) do
            local fh = assert(io.open(file))
            src[#src + 1] = fh:read("*a")
            fh:close()
        end
        local all = table.concat(src, "\n")
        local fh = assert(io.open("Locales/deDE.lua"))
        local unused = {}
        for key in fh:read("*a"):gmatch('\nL%["(.-)"%] =') do
            if not all:find('"' .. key .. '"', 1, true) then unused[#unused + 1] = key end
        end
        fh:close()
        assert.same({}, unused)
    end)
end)
