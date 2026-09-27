if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Locale.lua
-- Locale engine. Keys are the English source text, so English needs no entries.
-- Locale files fetch their table with ns.RegisterLocale(code) and fill it at load;
-- the effective locale (settings override or client locale) is activated at the
-- core's ADDON_LOADED, when SavedVariables are available. A value of `true`
-- means "keep the English text". All strings of all modules live in the core's
-- Locales/ folder, one file per WoW language, all maintained in the repository.
-- The language setting offers only languages that have translations; missing
-- strings fall back to English.
local _, ns = ...

local Locale = {}
ns.Locale = Locale

local ORDER = { "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local NATIVE_NAMES = {
    enUS = "English", deDE = "Deutsch", frFR = "Fran\195\167ais", esES = "Espa\195\177ol (EU)",
    esMX = "Espa\195\177ol (AL)", itIT = "Italiano", ptBR = "Portugu\195\170s",
    ruRU = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185",
    koKR = "\237\149\156\234\181\173\236\150\180", zhCN = "\231\174\128\228\189\147\228\184\173\230\150\135",
    zhTW = "\231\185\129\233\171\148\228\184\173\230\150\135",
}
local SUPPORTED = {}
for _, code in ipairs(ORDER) do SUPPORTED[code] = true end
Locale.ORDER = ORDER

local tables = {}     -- code -> translations
local activeCode = "enUS"
local active = nil    -- translation table of the active locale, nil for English

local L = setmetatable({}, {
    __index = function(_, key)
        local value = active and active[key]
        if value == nil or value == true then
            return key
        end
        return value
    end,
    __newindex = function()
        error("Goblinomics: write translations through ns.RegisterLocale(code)", 2)
    end,
})
ns.L = L
ns.API.L = L

--- Return the translation table for a locale code, creating it on first use.
function ns.RegisterLocale(code)
    local t = tables[code]
    if not t then
        t = {}
        tables[code] = t
    end
    return t
end

--- Format a translated string.
function ns.Lf(key, ...)
    return L[key]:format(...)
end
ns.API.Lf = ns.Lf

--- True when a locale has at least one translation (English always).
function Locale.HasTranslations(code)
    return code == "enUS" or (tables[code] ~= nil and next(tables[code]) ~= nil)
end

--- Effective locale: the setting, else the client language; languages without
-- any translation resolve to English.
local function Resolve(override)
    if type(override) == "string" and SUPPORTED[override] and Locale.HasTranslations(override) then
        return override
    end
    local client = GetLocale and GetLocale() or "enUS"
    if client == "enGB" then
        client = "enUS"
    end
    if SUPPORTED[client] and Locale.HasTranslations(client) then
        return client
    end
    return "enUS"
end

--- Activate the effective locale. override: "auto", nil or a supported code.
function Locale.Activate(override)
    activeCode = Resolve(override)
    if activeCode == "enUS" then
        active = nil
    else
        active = tables[activeCode]
    end
    return activeCode
end

function Locale.GetActive()
    return activeCode
end

--- Choices for the language setting: { {value = "auto"|code, label = ...}, ... };
-- only languages with translations.
function Locale.Choices()
    local result = { { value = "auto", label = L["Automatic"] } }
    for i = 1, #ORDER do
        local code = ORDER[i]
        if Locale.HasTranslations(code) then
            result[#result + 1] = { value = code, label = NATIVE_NAMES[code] }
        end
    end
    return result
end

Locale.Activate(nil)
