if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Link/Link.lua
-- Link (load on demand, M8): several WoW accounts give one networth. Each
-- account exports a string (prefix "GOB1:", LibSerialize + LibDeflate,
-- printable) with its characters' gold and wealth, the warband bank and its
-- daily wealth; the other account imports it as a read-only remote account in
-- the Vault (API.Vault:SetRemote, the newest snapshot wins). The UI stays small: a settings section with export, import and
-- the list of linked accounts.
local ADDON_NAME, ns = ...

local API = Goblinomics and Goblinomics.API and Goblinomics.API.v1
if not API then return end
ns.API = API
ns.L = API.L

local Link = API.RegisterModule(ADDON_NAME, {
    apiVersion = 1,
    name = "Link",
    description = function() return API.L["Adds other WoW accounts to the wealth."] end,
    order = 75,
})
ns.Link = Link

local PREFIX = "GOB1:"
local VERSION = 1
Link.PREFIX = PREFIX

local function Libs() return LibStub("LibDeflate"), LibStub("LibSerialize") end

function Link.Encode(snap)
    local LD, LS = Libs()
    snap.v = VERSION
    return PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize(snap)))
end

--- Snapshot from a string, or nil and a reason ("format", "version").
function Link.Decode(text)
    text = type(text) == "string" and text:gsub("%s", "") or ""
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "format" end
    local LD, LS = Libs()
    local compressed = LD:DecodeForPrint(text:sub(#PREFIX + 1))
    local raw = compressed and LD:DecompressDeflate(compressed)
    if not raw then return nil, "format" end
    local ok, snap = LS:Deserialize(raw)
    if not ok or type(snap) ~= "table" then return nil, "format" end
    if snap.v ~= VERSION then return nil, "version" end
    if type(snap.account) ~= "string" or type(snap.seenAt) ~= "number" or type(snap.chars) ~= "table" then
        return nil, "format"
    end
    return snap
end

--- Export string of this account (nil without the Vault).
function Link.Export()
    if not API.Vault or not API.Vault.Snapshot then return nil end
    local snap = API.Vault:Snapshot(API.Lf("Account of %s", UnitName("player") or "?"))
    return snap and Link.Encode(snap) or nil
end

--- Import a string: true, or false and a reason (format, version, own, older, vault).
function Link.Import(text)
    if not API.Vault or not API.Vault.SetRemote then return false, "vault" end
    local snap, reason = Link.Decode(text)
    if not snap then return false, reason end
    return API.Vault:SetRemote(snap)
end
