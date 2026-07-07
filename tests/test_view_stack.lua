---@type table
local expect = MiniTest.expect

local view_stack = require("neojj.lib.view_stack")

---Create a throwaway scratch buffer for use as a frame.
---@return number bufnr
local function scratch()
	return vim.api.nvim_create_buf(false, true)
end

---@type table
local T = MiniTest.new_set({
	hooks = {
		---Start each test from an empty stack (module state is process-global).
		---@return nil
		pre_case = function()
			view_stack.clear()
		end,
	},
})

---Test that push records frames and depth/top reflect the top of the stack.
---@return nil
T.test_push_and_depth = function()
	local a, b = scratch(), scratch()

	vim.api.nvim_set_current_buf(a)
	view_stack.push(a)
	vim.api.nvim_set_current_buf(b)
	view_stack.push(b)

	expect.equality(view_stack.depth(), 2)
	expect.equality(view_stack.top().bufnr, b)
end

---Test that re-pushing an existing buffer moves it to the top rather than
---duplicating it (mirrors revisiting a singleton view).
---@return nil
T.test_push_dedupes_to_top = function()
	local a, b = scratch(), scratch()

	view_stack.push(a)
	view_stack.push(b)
	view_stack.push(a) -- move a back to the top

	expect.equality(view_stack.depth(), 2)
	expect.equality(view_stack.top().bufnr, a)
end

---Test that popping reveals the frame beneath in the stack window.
---@return nil
T.test_pop_reveals_beneath = function()
	local a, b = scratch(), scratch()

	vim.api.nvim_set_current_buf(a)
	view_stack.push(a)
	vim.api.nvim_set_current_buf(b)
	view_stack.push(b)

	local popped = view_stack.pop()

	expect.equality(popped, true)
	expect.equality(vim.api.nvim_get_current_buf(), a)
	expect.equality(view_stack.depth(), 1)
end

---Test that popping an empty stack is a no-op returning false.
---@return nil
T.test_pop_empty_returns_false = function()
	expect.equality(view_stack.pop(), false)
end

---Test that a popped frame's teardown runs (used to close owned NeoJJ views).
---@return nil
T.test_pop_runs_teardown = function()
	local a, b = scratch(), scratch()

	vim.api.nvim_set_current_buf(a)
	view_stack.push(a)

	local torn = false
	vim.api.nvim_set_current_buf(b)
	view_stack.push(b, {
		teardown = function()
			torn = true
		end,
	})

	view_stack.pop()

	expect.equality(torn, true)
end

---Test that the last frame's teardown runs when the stack empties.
---@return nil
T.test_pop_last_frame_tears_down = function()
	local a = scratch()

	vim.api.nvim_set_current_buf(a)
	local torn = false
	view_stack.push(a, {
		teardown = function()
			torn = true
		end,
	})

	local popped = view_stack.pop()

	expect.equality(popped, true)
	expect.equality(torn, true)
	expect.equality(view_stack.depth(), 0)
end

---Test that frames whose buffer was wiped externally are pruned.
---@return nil
T.test_prune_drops_wiped_buffers = function()
	local a, b = scratch(), scratch()

	view_stack.push(a)
	view_stack.push(b)
	vim.api.nvim_buf_delete(b, { force = true })

	expect.equality(view_stack.depth(), 1)
	expect.equality(view_stack.top().bufnr, a)
end

---Test that raise() steps back one level when already on the top frame (the
---file-opened-from-status case).
---@return nil
T.test_raise_pops_when_on_top = function()
	local a, b = scratch(), scratch()

	vim.api.nvim_set_current_buf(a)
	view_stack.push(a)
	vim.api.nvim_set_current_buf(b)
	view_stack.push(b)

	-- Currently on b, which is the top frame: raise steps back to a.
	view_stack.raise()

	expect.equality(vim.api.nvim_get_current_buf(), a)
	expect.equality(view_stack.depth(), 1)
end

---Test that raise() focuses the top frame (without popping) when the current
---buffer is not a frame.
---@return nil
T.test_raise_focuses_top_when_elsewhere = function()
	local a, b, other = scratch(), scratch(), scratch()

	vim.api.nvim_set_current_buf(a)
	view_stack.push(a)
	vim.api.nvim_set_current_buf(b)
	view_stack.push(b)

	-- Wander off to a buffer that is not on the stack.
	vim.api.nvim_set_current_buf(other)
	view_stack.raise()

	-- The top frame is focused, and nothing was popped.
	expect.equality(vim.api.nvim_get_current_buf(), b)
	expect.equality(view_stack.depth(), 2)
end

return T
