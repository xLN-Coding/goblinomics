if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Util/ChatPattern.lua
-- Turns a Blizzard GlobalString format (e.g. LOOT_ITEM_SELF_MULTIPLE =
-- "You receive loot: %sx%d.") into an anchored Lua pattern with captures, so chat
-- messages can be parsed in any client locale without hard-coded English text.
--
-- Handles: %s / %d specifiers, positional specifiers (%1$s, %2$d), literal
-- percent signs (%%), Lua magic characters in the surrounding text, and the
-- grammar tokens some locales use (|3-N(%s) declension wrappers, |4a:b; plurals).
--
-- Pure Lua, no WoW API. Covered by spec/core/chat_pattern_spec.lua.
local _, ns = ...

local ChatPattern = {}
ns.ChatPattern = ChatPattern
if ns.API then ns.API.ChatPattern = ChatPattern end

local cache = {}          -- fmt -> { pattern = "...", order = { ... }, positional = bool }
local PLURAL_MARK = "\1"  -- placeholder for |4a:b; tokens during escaping
local PERCENT_MARK = "\2" -- placeholder for literal %%
local SPECIFIER_MARK = "\3" -- placeholder for %s / %d / %N$s while escaping

--- Build an anchored Lua pattern for a GlobalString format.
-- @return pattern     string   e.g. "^You receive loot: (.-)x(%d+)%.$"
-- @return order       table    order[i] = format-argument index captured by capture i
-- @return positional  boolean  true when the format used %N$ specifiers
function ChatPattern.Build(fmt)
    if type(fmt) ~= "string" then
        return nil
    end
    local cached = cache[fmt]
    if cached then
        return cached.pattern, cached.order, cached.positional
    end

    local s = fmt
    s = s:gsub("|3%-%d+%((.-)%)", "%1")   -- |3-1(%s) -> %s
    s = s:gsub("|4[^;]-;", PLURAL_MARK)   -- |4item:items; -> loose word match later
    s = s:gsub("%%%%", PERCENT_MARK)      -- %% -> literal percent later

    -- Pull the specifiers out first so the escaping step cannot touch their '$'.
    local kinds, order, positional, idx = {}, {}, false, 0
    s = s:gsub("%%(%d*)%$?([sd])", function(pos, kind)
        idx = idx + 1
        kinds[idx] = kind
        if pos ~= "" then
            positional = true
            order[idx] = tonumber(pos)
        else
            order[idx] = idx
        end
        return SPECIFIER_MARK
    end)

    s = s:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0") -- escape magic characters

    local cursor = 0
    s = s:gsub(SPECIFIER_MARK, function()
        cursor = cursor + 1
        if kinds[cursor] == "d" then
            return "(%d+)"
        end
        return "(.-)"
    end)

    s = s:gsub(PLURAL_MARK, "%%S+")
    s = s:gsub(PERCENT_MARK, "%%%%")

    local pattern = "^" .. s .. "$"
    cache[fmt] = { pattern = pattern, order = order, positional = positional }
    return pattern, order, positional
end

--- Match a message against a GlobalString format.
-- Returns the captured values in FORMAT-ARGUMENT order (so %2$s ... %1$s still
-- yields arg1, arg2), or nil when the message does not match.
function ChatPattern.Match(fmt, message)
    if type(message) ~= "string" then
        return nil
    end
    local pattern, order, positional = ChatPattern.Build(fmt)
    if not pattern then
        return nil
    end
    if not positional then
        return message:match(pattern)
    end
    local captures = { message:match(pattern) }
    if captures[1] == nil then
        return nil
    end
    local args, n = {}, 0
    for i = 1, #captures do
        local argIndex = order[i]
        args[argIndex] = captures[i]
        if argIndex > n then
            n = argIndex
        end
    end
    return unpack(args, 1, n)
end

--- Drop cached patterns (locale change, tests).
function ChatPattern.ClearCache()
    for k in pairs(cache) do
        cache[k] = nil
    end
end
