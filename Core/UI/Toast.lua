if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/UI/Toast.lua
-- Stacked toasts at the top centre: fade in, hold, fade out through an
-- AnimationGroup. Frames are pooled. During the restricted mode toasts are
-- queued; a bus subscription exists only while something waits for the end.
local _, ns = ...

local Toast = {}
ns.Toast = Toast
local Theme = ns.Theme
local C = Theme.colors

local WIDTH, HEIGHT, GAP, MAX_VISIBLE = 320, 56, 6, 4
local pool, visible, queue = {}, {}, {}
local anchor

local function Layout()
    for i = 1, #visible do
        local f = visible[i]
        f:ClearAllPoints()
        f:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (HEIGHT + GAP))
    end
end

local function Release(f)
    f:Hide()
    for i = #visible, 1, -1 do
        if visible[i] == f then table.remove(visible, i) end
    end
    pool[#pool + 1] = f
    Layout()
    if #queue > 0 and not ns.Restriction.IsActive() then
        Toast.Show(table.remove(queue, 1))
    end
end

local function Acquire()
    local f = table.remove(pool)
    if f then return f end
    f = CreateFrame("Frame", nil, anchor)
    f:SetSize(WIDTH, HEIGHT)
    Theme.Backdrop(f, C.bg, C.borderHover)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("LEFT", 8, 0)
    f.title = Theme.Text(f, "title", C.gold)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
    f.title:SetPoint("RIGHT", -8, 0)
    f.text = Theme.Text(f, 11, C.text)
    f.text:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 10, 2)
    f.text:SetPoint("RIGHT", -8, 0)
    local ag = f:CreateAnimationGroup()
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.5)
    fadeOut:SetStartDelay(4)
    fadeOut:SetOrder(2)
    ag:SetScript("OnFinished", function() Release(f) end)
    f.anim = ag
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function() ag:Stop() Release(f) end)
    return f
end

--- spec = { title, text, icon, sound }
local waitingForLeave = false

local function OnRestrictedLeave()
    waitingForLeave = false
    ns.Bus.Off("RESTRICTED_LEAVE", "Core.Toast")
    while #queue > 0 and #visible < MAX_VISIBLE do
        Toast.Show(table.remove(queue, 1))
    end
end

function Toast.Show(spec)
    if ns.Restriction.IsActive() or #visible >= MAX_VISIBLE then
        queue[#queue + 1] = spec
        if ns.Restriction.IsActive() and not waitingForLeave then
            waitingForLeave = true
            ns.Bus.On("RESTRICTED_LEAVE", OnRestrictedLeave, "Core.Toast")
        end
        return
    end
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetSize(WIDTH, 1)
        anchor:SetPoint("TOP", 0, -140)
        anchor:SetFrameStrata("DIALOG")
    end
    local f = Acquire()
    f.icon:SetTexture(spec.icon or Theme.ICON)
    f.title:SetText(spec.title or "Goblinomics")
    f.text:SetText(spec.text or "")
    f:SetAlpha(1) -- base alpha; the group animates 0 -> 1, holds, then 1 -> 0
    visible[#visible + 1] = f
    Layout()
    f:Show()
    f.anim:Play()
    if spec.sound then
        ns.Sounds.Play(spec.sound)
    end
end
