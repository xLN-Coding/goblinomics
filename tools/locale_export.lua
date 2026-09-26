-- tools/locale_export.lua (run by tools/locale-export.sh, Lua 5.1)
-- Writes the phrases for the CurseForge localization app into release/locale/:
--   enUS.lua  every key used in the code, L["..."] = true (import as the base language)
--   deDE.lua  the German translations from Locales/deDE.lua (import to keep CurseForge in sync)
-- Format: lua_additive_table, the format the locale files' packager markers request.
local function Files()
    local list = {}
    local p = io.popen('find Core Modules Connectors -name "*.lua" | sort')
    for line in p:lines() do list[#list + 1] = line end
    p:close()
    return list
end

local function Quote(s)
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local keys, seen = {}, {}
for _, file in ipairs(Files()) do
    local fh = assert(io.open(file))
    local src = fh:read("*a")
    fh:close()
    for _, pattern in ipairs({ 'L%["([^"]*)"%]', 'Lf%("([^"]*)"' }) do
        for key in src:gmatch(pattern) do
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
end
table.sort(keys)

os.execute("mkdir -p release/locale")
local out = assert(io.open("release/locale/enUS.lua", "w"))
for _, key in ipairs(keys) do out:write("L[", Quote(key), "] = true\n") end
out:close()

-- German: load the locale file with a stand-in namespace
local de = {}
local chunk = assert(loadfile("Locales/deDE.lua"))
chunk("Goblinomics", { RegisterLocale = function() return de end })
out = assert(io.open("release/locale/deDE.lua", "w"))
local translated = 0
for _, key in ipairs(keys) do
    local v = de[key]
    if type(v) == "string" then
        out:write("L[", Quote(key), "] = ", Quote(v), "\n")
        translated = translated + 1
    end
end
out:close()
print(("%d phrases, %d German translations -> release/locale/"):format(#keys, translated))
