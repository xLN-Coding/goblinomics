if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Init.lua
-- First core file after the libraries. Creates the single global table
-- `Goblinomics`, the public API namespace `Goblinomics.API.v1` (= ns.API) and the
-- small helpers every other core file relies on: safe calls, printing, identity.
local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.API_VERSION = 1
ns.PREFIX = "|cff3fbf3fGoblinomics|r"

local API = {}
ns.API = API

local function ReadVersion()
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata
    local version = getMeta and getMeta(ADDON_NAME, "Version")
    if type(version) ~= "string" or version == "" or version:sub(1, 1) == "@" then
        return "dev"
    end
    return version
end

Goblinomics = {
    VERSION = ReadVersion(),
    API_VERSION = ns.API_VERSION,
    API = { v1 = API },
}

-------------------------------------------------------------------------------
-- Safe calls: errors reach the error handler (BugSack) without stopping the
-- caller. The error handler is looked up late so BugGrabber can replace it.
-------------------------------------------------------------------------------
local function errorhandler(err)
    return geterrorhandler()(err)
end
ns.errorhandler = errorhandler

-- The WoW client's xpcall forwards extra arguments; stock Lua 5.1 (busted) does
-- not. Detect once so the hot path allocates no closure in the client.
local nativeArgs = select(2, xpcall(function(a) return a end, function() end, true)) == true

local SafeCall
if nativeArgs then
    SafeCall = function(fn, ...)
        return xpcall(fn, errorhandler, ...)
    end
else
    SafeCall = function(fn, ...)
        local n, args = select("#", ...), { ... }
        return xpcall(function() return fn(unpack(args, 1, n)) end, errorhandler)
    end
end
ns.SafeCall = SafeCall

-------------------------------------------------------------------------------
-- Output
-------------------------------------------------------------------------------
--- Print a line to the default chat frame. Ordinary messages are dropped while
-- the restricted mode is active (boss encounter, M+); pass force = true for
-- output the user explicitly asked for.
function ns.Print(msg, force)
    if not force and ns.Restriction and ns.Restriction.IsActive() then
        return
    end
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(ns.PREFIX .. ": " .. tostring(msg))
    end
end
API.Print = function(msg, force) return ns.Print(msg, force) end

-------------------------------------------------------------------------------
-- Identity
-------------------------------------------------------------------------------
--- "Name-Realm" of the current character. Reliable from PLAYER_LOGIN on.
function ns.CharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName and GetRealmName() or "Unknown"):gsub("[%s%-]", "")
    end
    return name .. "-" .. realm
end
