if GOBLINOMICS_CLIENT_BLOCKED then return end
-- Core/Util/RingBuffer.lua
-- Fixed-capacity ring buffer with four parallel columns (time, event, value,
-- extra). Push is an append into preexisting arrays: no table per entry, which
-- keeps the restricted mode (boss encounters, M+) allocation free.
-- Pure Lua. Covered by spec/core/ringbuffer_spec.lua.
local _, ns = ...

local RingBuffer = {}
RingBuffer.__index = RingBuffer
ns.RingBuffer = RingBuffer

function RingBuffer.New(capacity)
    return setmetatable({
        capacity = capacity,
        first = 1,        -- index of the oldest entry
        count = 0,
        overflow = false,
        times = {}, events = {}, values = {}, extras = {},
    }, RingBuffer)
end

--- Append an entry; when full, the oldest entry is overwritten and `overflow` set.
function RingBuffer:Push(time, event, value, extra)
    local cap = self.capacity
    local index
    if self.count < cap then
        index = (self.first + self.count - 1) % cap + 1
        self.count = self.count + 1
    else
        index = self.first
        self.first = self.first % cap + 1
        self.overflow = true
    end
    self.times[index] = time
    self.events[index] = event
    self.values[index] = value
    self.extras[index] = extra
end

--- i-th oldest entry (1 = oldest): time, event, value, extra.
function RingBuffer:Get(i)
    if i < 1 or i > self.count then
        return nil
    end
    local index = (self.first + i - 2) % self.capacity + 1
    return self.times[index], self.events[index], self.values[index], self.extras[index]
end

function RingBuffer:Count()
    return self.count
end

--- Empty the buffer and release the stored values.
function RingBuffer:Clear()
    for i = 1, self.capacity do
        self.times[i], self.events[i], self.values[i], self.extras[i] = nil, nil, nil, nil
    end
    self.first, self.count, self.overflow = 1, 0, false
end
