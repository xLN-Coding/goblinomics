if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Workshop/ProfessionButton.lua
-- "+ Market" in Blizzard's profession window: a small button next to the "Track
-- recipe" box of the selected recipe. A click puts the recipe's product onto the
-- Market Pulse list (every quality tier of it), a second click takes it off. Only an
-- own child button with HookScript/hooksecurefunc, nothing of Blizzard's is replaced.
local _, ns = ...

local Button = {}
ns.ProfessionButton = Button

local button

--- Item keys a recipe makes: its quality tiers, else its output item; nil when unknown.
function Button.Keys(recipeID)
    local ts = C_TradeSkillUI
    if not (ts and recipeID) then return nil end
    local keys = {}
    local ids = ts.GetRecipeQualityItemIDs and ts.GetRecipeQualityItemIDs(recipeID)
    if type(ids) == "table" and #ids > 0 then
        for _, id in ipairs(ids) do keys[#keys + 1] = "i:" .. id end
        return keys
    end
    local out = ts.GetRecipeOutputItemData and ts.GetRecipeOutputItemData(recipeID)
    local id = out and (out.itemID or (out.hyperlink and tonumber(out.hyperlink:match("item:(%d+)"))))
    if id then return { "i:" .. id } end
    return nil
end

local function OnList(keys)
    for _, key in ipairs(keys or {}) do
        if not ns.Pulse.Has(key) then return false end
    end
    return keys ~= nil and #keys > 0
end

local function CurrentRecipe()
    local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    return info and info.recipeID
end

--- Toggle the products of a recipe on the list; true when they are on it afterwards.
function Button.Toggle(recipeID)
    local keys = Button.Keys(recipeID)
    if not keys then return false end
    if OnList(keys) then
        for _, key in ipairs(keys) do ns.Pulse.Remove(key) end
        return false
    end
    for _, key in ipairs(keys) do ns.Pulse.Add(key) end
    return true
end

function Button.Refresh()
    if not button then return end
    local recipeID = CurrentRecipe()
    local keys = Button.Keys(recipeID)
    button:SetShown(keys ~= nil)
    if keys then button.label:SetText(OnList(keys) and ns.L["- Market"] or ns.L["+ Market"]) end
end

--- Create the button once the profession window exists (called when it opens).
function Button.Attach()
    if button then return Button.Refresh() end
    local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    if not form then return end
    local W = ns.API.Widgets
    button = W.Button(form, ns.L["+ Market"], { width = 84, onClick = function()
        Button.Toggle(CurrentRecipe())
        Button.Refresh()
    end })
    button:SetHeight(20)
    local track = form.TrackRecipeCheckbox
    if track then
        button:SetPoint("RIGHT", track, "LEFT", -6, 0)
    else
        button:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, -12)
    end
    button:SetScript("OnEnter", function(self)
        W.ShowTooltip(self, "Goblinomics", { ns.L["Put this product on your Market list in the Workshop, or take it off."] })
    end)
    button:SetScript("OnLeave", W.HideTooltip)
    if form.Init then hooksecurefunc(form, "Init", function() Button.Refresh() end) end
    form:HookScript("OnShow", function() Button.Refresh() end)
    Button.button = button
    Button.Refresh()
end

function Button.Enable()
    ns.API.On("WORKSHOP_PULSE", function() Button.Refresh() end, "Goblinomics_Workshop.ProfessionButton")
end

function Button.Disable()
    if button then button:Hide() end
    if ns.API then ns.API.Off("WORKSHOP_PULSE", "Goblinomics_Workshop.ProfessionButton") end
end
