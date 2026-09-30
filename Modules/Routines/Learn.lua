if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Modules/Routines/Learn.lua
-- Daily and weekly quests are learned, not listed by hand, so every expansion
-- works from its first day:
--   QUEST_ACCEPTED    the quest's frequency (quest log) marks it daily or weekly;
--                     it becomes a suggestion (source "learned") and the time is kept
--   QUEST_COMPLETE    the reward panel: gold and items (valued like the wealth)
--   QUEST_TURNED_IN   done until the next daily/weekly reset; the reward is one
--                     measured value, the time since accepting one measured duration
--                     (same session, at most 60 minutes)
-- At login every quest task is checked once with IsQuestFlaggedCompleted.
local _, ns = ...

local Learn = {}
ns.Learn = Learn

local MAX_MINUTES = 60
local accepted = {}   -- questID -> time accepted (this session)
local rewards = {}    -- questID -> copper of the reward panel

local function Frequency(questID)
    local log = C_QuestLog
    if not (log and log.GetLogIndexForQuestID and log.GetInfo) then return nil end
    local index = log.GetLogIndexForQuestID(questID)
    local info = index and log.GetInfo(index)
    local f = info and info.frequency
    local Q = Enum and Enum.QuestFrequency or {}
    if f == (Q.Weekly or 2) then return "weekly" end
    if f == (Q.Daily or 1) then return "daily" end
    return nil
end
Learn.Frequency = Frequency

local function Title(questID)
    return C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or nil
end

--- Learn a daily or weekly quest from the quest log; the task or nil.
function Learn.Quest(questID)
    if type(questID) ~= "number" then return nil end
    local frequency = Frequency(questID)
    local existing = ns.Tasks.Get("q:" .. questID)
    if not frequency and not existing then return nil end
    return ns.Tasks.Learn({ id = "q:" .. questID, kind = "quest", ref = questID, name = Title(questID),
        frequency = frequency })
end

local function ResetFor(task, now)
    if task.frequency == "daily" then return ns.Routines.DailyResetAt(now) end
    return ns.Routines.WeeklyResetAt(now)
end

--- Value of the reward panel: gold plus the items (choices are left out).
function Learn.RewardValue()
    local copper = GetRewardMoney and GetRewardMoney() or 0
    for i = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do
        local link = GetQuestItemLink and GetQuestItemLink("reward", i)
        local count = GetQuestItemInfo and select(3, GetQuestItemInfo("reward", i)) or 1
        local key = link and ns.API.ItemKey.FromLink(link)
        if key then
            local r = ns.API.Value:Evaluate(key, { quantity = count or 1 })
            copper = copper + (r and r.total or 0)
        end
    end
    return copper
end

local function OnAccepted(_, questID)
    if Learn.Quest(questID) then
        accepted[questID] = time()
        ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
    end
end

local function OnComplete()
    local questID = GetQuestID and GetQuestID()
    if type(questID) ~= "number" or questID == 0 then return end
    if Learn.Quest(questID) then rewards[questID] = Learn.RewardValue() end
end

local function OnTurnedIn(_, questID, _, money)
    local task = ns.Tasks.Get("q:" .. tostring(questID))
    if not task then return end
    local now = time()
    ns.Tasks.MarkDone(ns.Routines.CharKey(), task.id, ResetFor(task, now), now)
    local value = rewards[questID] or ((type(money) == "number" and money > 0) and money or nil)
    local started = accepted[questID]
    local minutes = started and (now - started) / 60 or nil
    if minutes and (minutes <= 0 or minutes > MAX_MINUTES) then minutes = nil end
    ns.Tasks.Measure(task, value, minutes)
    rewards[questID], accepted[questID] = nil, nil
    ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
end

--- Check every quest task for the logged-in character (login, after a reset).
function Learn.CheckFlags(now)
    now = now or time()
    local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    if not flagged then return end
    local me = ns.Routines.CharKey()
    for _, task in pairs(ns.Routines.db.root.tasks) do
        if task.kind == "quest" and type(task.ref) == "number" then
            if flagged(task.ref) then
                ns.Tasks.MarkDone(me, task.id, ResetFor(task, now), now)
            else
                ns.Tasks.ClearDone(me, task.id)
            end
        end
    end
    ns.API.Emit("ROUTINES_UPDATED", { part = "tasks" })
end

function Learn.Enable(m)
    m:RegisterEvent("QUEST_ACCEPTED", OnAccepted)
    m:RegisterEvent("QUEST_COMPLETE", OnComplete)
    m:RegisterEvent("QUEST_TURNED_IN", OnTurnedIn)
    m:After(4, function() Learn.CheckFlags() end)
end

function Learn.Disable()
    for k in pairs(accepted) do accepted[k] = nil end
    for k in pairs(rewards) do rewards[k] = nil end
end

