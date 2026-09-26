if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Sounds.lua
-- Configurable sounds for every Goblinomics sound (highlights, Jealousmeter,
-- ...). A sound setting is a string:
--   "none"            silent
--   "kit:<NAME>"      a Blizzard sound kit (SOUNDKIT[NAME], PlaySound)
--   "lsm:<name>"      a LibSharedMedia sound (PlaySoundFile), including every
--                     sound that SharedMedia packs and other addons register
-- Old boolean settings still work (true = the default, false = none). All
-- sounds play on the channel chosen in the general settings (default Master).
-- Widgets.SoundPicker is the dropdown with a preview button.
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

local L = ns.L
Sounds.NONE = "none"

-- Blizzard sound kits offered besides LibSharedMedia; missing kits are skipped.
-- Labels are functions so the active locale applies when the menu opens.
local KITS = {
    { "UI_EPICLOOT_TOAST", function() return L["Epic loot toast"] end },
    { "UI_LEGENDARY_LOOT_TOAST", function() return L["Legendary loot toast"] end },
    { "UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_CHANCE", function() return L["Mission complete"] end },
    { "RAID_WARNING", function() return L["Raid warning"] end },
    { "READY_CHECK", function() return L["Ready check"] end },
    { "ALARM_CLOCK_WARNING_3", function() return L["Alarm clock"] end },
    { "UI_BONUS_LOOT_ROLL_END", function() return L["Bonus roll"] end },
    { "IG_QUEST_LIST_COMPLETE", function() return L["Quest complete"] end },
}

Sounds.CHANNELS = { "Master", "SFX", "Music", "Ambience", "Dialog" }

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

--- Sound value from a stored setting; booleans from older versions are mapped.
function Sounds.Resolve(value, default)
    if value == false then return Sounds.NONE end
    if value == nil or value == true then return default or Sounds.NONE end
    return value
end

local function KitLabel(name)
    for _, kit in ipairs(KITS) do
        if kit[1] == name then return kit[2]() end
    end
    return name
end

function Sounds.Label(value)
    if value == nil or value == Sounds.NONE then return L["None"] end
    local kind, name = value:match("^(%a+):(.+)$")
    if kind == "kit" then return KitLabel(name) end
    if kind == "lsm" then return name end
    return value
end

--- { { value, label }, ... }: None, the Blizzard kits, then LibSharedMedia sounds.
function Sounds.Choices()
    local list = { { value = Sounds.NONE, label = L["None"] } }
    for _, kit in ipairs(KITS) do
        if SOUNDKIT and SOUNDKIT[kit[1]] then
            list[#list + 1] = { value = "kit:" .. kit[1], label = kit[2]() }
        end
    end
    local lsm = LSM()
    if lsm then
        for _, name in ipairs(lsm:List("sound") or {}) do
            if name ~= "None" then list[#list + 1] = { value = "lsm:" .. name, label = name } end
        end
    end
    return list
end

--- Menu with submenus: None, "Blizzard" (the kits) and "SharedMedia" (other addons' sounds).
function Sounds.GroupedChoices()
    local flat = Sounds.Choices()
    local list, kits, media = { flat[1] }, {}, {}
    for i = 2, #flat do
        if flat[i].value:find("^kit:") then kits[#kits + 1] = flat[i] else media[#media + 1] = flat[i] end
    end
    if #kits > 0 then list[#list + 1] = { label = "Blizzard", children = kits } end
    if #media > 0 then list[#list + 1] = { label = "SharedMedia", children = media } end
    return list
end

local function Channel()
    local db = ns.coreDB
    local channel = db and db.settings.sound and db.settings.sound.channel
    return channel or "Master"
end

--- Play a sound value; returns true when something was played.
function Sounds.Play(value)
    if type(value) == "number" then
        return PlaySound and PlaySound(value, Channel()) and true or false
    end
    if type(value) ~= "string" or value == Sounds.NONE then return false end
    local kind, name = value:match("^(%a+):(.+)$")
    if kind == "kit" then
        local id = SOUNDKIT and SOUNDKIT[name]
        if not id or not PlaySound then return false end
        PlaySound(id, Channel())
        return true
    elseif kind == "lsm" then
        local lsm = LSM()
        local file = lsm and lsm:Fetch("sound", name, true)
        if not file or not PlaySoundFile then return false end
        PlaySoundFile(file, Channel())
        return true
    end
    return false
end

-- Widget ---------------------------------------------------------------------------
--- Dropdown of all sounds plus a preview button. get() -> value, set(value).
-- opts = { width, default } (default is used for old boolean settings).
function ns.Widgets.SoundPicker(parent, get, set, opts)
    opts = opts or {}
    local W = ns.Widgets
    local width = opts.width or 200
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width + 30, 24)
    local function Current() return Sounds.Resolve(get(), opts.default) end
    f.dropdown = W.Dropdown(f, Sounds.GroupedChoices, Current, function(value)
        set(value)
        Sounds.Play(value)
    end, { width = width, display = Sounds.Label })
    f.dropdown:SetPoint("LEFT")
    f.play = W.IconButton(f, "play", { size = ns.Theme.space.CONTROL_H, onClick = function() Sounds.Play(Current()) end,
        tooltip = L["Play"] })
    f.play:SetPoint("LEFT", f.dropdown, "RIGHT", 6, 0)
    function f:Refresh() self.dropdown:Refresh() end
    return f
end

ns.API.Sounds = {
    Play = function(_, value) return Sounds.Play(value) end,
    Resolve = function(_, value, default) return Sounds.Resolve(value, default) end,
    Choices = function() return Sounds.Choices() end,
    Label = function(_, value) return Sounds.Label(value) end,
}
