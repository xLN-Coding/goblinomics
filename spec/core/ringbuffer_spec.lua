describe("Core/Util/RingBuffer", function()
    local RingBuffer

    before_each(function()
        RingBuffer = load_core().RingBuffer
    end)

    it("returns entries oldest first", function()
        local rb = RingBuffer.New(4)
        rb:Push(1, "A", 10, "x")
        rb:Push(2, "B", 20)
        assert.equals(2, rb:Count())
        assert.same({ 1, "A", 10, "x" }, { rb:Get(1) })
        assert.same({ 2, "B", 20 }, { rb:Get(2) })
        assert.is_nil(rb:Get(3))
    end)

    it("overwrites the oldest entry when full and flags overflow", function()
        local rb = RingBuffer.New(3)
        for i = 1, 5 do rb:Push(i, "E", i) end
        assert.is_true(rb.overflow)
        assert.equals(3, rb:Count())
        assert.equals(3, (rb:Get(1)))
        assert.equals(5, (rb:Get(3)))
    end)

    it("clears values and state", function()
        local rb = RingBuffer.New(2)
        rb:Push(1, "E", "payload")
        rb:Clear()
        assert.equals(0, rb:Count())
        assert.is_false(rb.overflow)
        assert.is_nil(rb.values[1])
    end)
end)
