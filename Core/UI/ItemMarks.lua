if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/ItemMarks.lua
-- Marks speculative items (sale rate below the speculative threshold) with a
-- small Goblinomics logo in the top-right corner of their icon, everywhere:
--   * Goblinomics lists: ItemMarks.Attach(frame, icon) + ItemMarks.Update(frame, key)
--   * text lists:        ItemMarks.Inline(key) returns a small inline logo or ""
--   * item buttons of bags, bank and bag addons (setting, default on).
-- Item buttons get their quality through two routes (finding in EllesmereUI's
-- skin engine): the global SetItemButtonQuality, which delegates to the button's
-- own method when it has one, and callers that invoke the method directly
-- (EllesmereUIBags, the merchant frame). So the global function and
-- ItemButtonMixin.SetItemButtonQuality are both hooked (post-hooks, no taint);
-- the mixin hook reaches every button created afterwards, and Blizzard's bag
-- frames are hooked per button the first time they are shown.
-- Tiers are cached per item key; the price service drops them on invalidation.
local _, ns = ...

local ItemMarks = {}
ns.ItemMarks = ItemMarks

local Theme = ns.Theme
local ICON = Theme.ICON
local SIZE = 14
local INLINE = "|T" .. ICON .. ":12:12|t"

local tiers = {}          -- itemKey -> tier
local hookedButtons = setmetatable({}, { __mode = "k" })

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

--- Item key from an item link, item string, item ID or key.
local function KeyOf(item)
    if item == nil or IsSecret(item) then return nil end
    if type(item) == "number" then return "i:" .. item end
    if type(item) ~= "string" then return nil end
    if item:match("^[ip]:%d") then return item end
    return ns.ItemKey.FromLink(item)
end
ItemMarks.KeyOf = KeyOf

function ItemMarks.IsSpeculative(item)
    local key = KeyOf(item)
    if not key then return false end
    local tier = tiers[key]
    if tier == nil then
        tier = ns.Value.Evaluate(key).tier
        tiers[key] = tier
    end
    return tier == "speculative"
end

--- Small inline logo for text lists, or "" when the item is not speculative.
function ItemMarks.Inline(item)
    return ItemMarks.IsSpeculative(item) and (" " .. INLINE) or ""
end
ItemMarks.INLINE = INLINE

--- Create (once) the marker texture on frame, in the top-right corner of anchor.
function ItemMarks.Attach(frame, anchor, size)
    local mark = frame.goblinomicsSpecMark
    if not mark then
        mark = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetTexture(ICON)
        frame.goblinomicsSpecMark = mark
    end
    local s = size or SIZE
    mark:SetSize(s, s)
    mark:ClearAllPoints()
    mark:SetPoint("TOPRIGHT", anchor or frame, "TOPRIGHT", 2, 2)
    mark:Hide()
    return mark
end

--- Show or hide the marker of frame for an item (link, ID or key); nil hides.
function ItemMarks.Update(frame, item)
    local mark = frame.goblinomicsSpecMark or ItemMarks.Attach(frame, frame.icon or frame.Icon)
    mark:SetShown(item ~= nil and ItemMarks.IsSpeculative(item))
end

-- Item buttons ------------------------------------------------------------------------
local function Enabled()
    local db = ns.coreDB
    return db ~= nil and db.settings.ui.markSpeculative ~= false
end

local function OnQuality(button, _, itemIDOrLink)
    if type(button) ~= "table" or not button.CreateTexture then return end
    if not Enabled() then
        if button.goblinomicsSpecMark then button.goblinomicsSpecMark:Hide() end
        return
    end
    local icon = button.icon or button.Icon or button.IconTexture
    if not button.goblinomicsSpecMark then ItemMarks.Attach(button, icon) end
    ItemMarks.Update(button, itemIDOrLink)
end
ItemMarks.OnQuality = OnQuality

local function HookButton(button)
    if hookedButtons[button] or type(button.SetItemButtonQuality) ~= "function" then return end
    hookedButtons[button] = true
    hooksecurefunc(button, "SetItemButtonQuality", OnQuality)
end

-- Blizzard bag frames: buttons may exist before the mixin hook; hook them when
-- a bag opens and refresh from the container slot.
local function RefreshContainerFrame(frame)
    if not (frame and frame.EnumerateValidItems) then return end
    for _, button in frame:EnumerateValidItems() do
        HookButton(button)
        local bag = button.GetBagID and button:GetBagID()
        local info = bag and C_Container.GetContainerItemInfo(bag, button:GetID())
        OnQuality(button, nil, info and info.hyperlink)
    end
end

local installed = false
function ItemMarks.InstallHooks()
    if installed then return end
    installed = true
    if type(SetItemButtonQuality) == "function" then
        hooksecurefunc("SetItemButtonQuality", OnQuality)
    end
    if ItemButtonMixin and type(ItemButtonMixin.SetItemButtonQuality) == "function" then
        hooksecurefunc(ItemButtonMixin, "SetItemButtonQuality", OnQuality)
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ContainerFrame.OpenBag", function(_, frame)
            pcall(RefreshContainerFrame, frame)
        end, ItemMarks)
    end
end

--- Drop cached tiers (one item or all); called by Price.Invalidate.
function ItemMarks.Invalidate(itemKey)
    if itemKey then tiers[itemKey] = nil else wipe(tiers) end
end

ItemMarks.InstallHooks()

ns.API.ItemMarks = {
    Attach = function(_, frame, anchor, size) return ItemMarks.Attach(frame, anchor, size) end,
    Update = function(_, frame, item) return ItemMarks.Update(frame, item) end,
    Inline = function(_, item) return ItemMarks.Inline(item) end,
    IsSpeculative = function(_, item) return ItemMarks.IsSpeculative(item) end,
}
