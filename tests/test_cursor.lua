-- Tests for the cursor-interaction system: Buffer:get_component_at_cursor and
-- Buffer:get_item_at_cursor. Both read the cursor via Buffer:get_cursor, which
-- needs a VISIBLE window (it falls back to {1, 0} when the buffer isn't shown),
-- so these are child-nvim tests that render into a real split window.
local child = MiniTest.new_child_neovim()
local expect = MiniTest.expect

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.bo.readonly = false
			child.o.lines = 40
			child.o.columns = 120
			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ expect = require('mini.test').expect ]])
		end,
		post_once = child.stop,
	},
})

---Render StatusUI.create_test_ui into a fresh Buffer shown in a split window.
---Leaves the buffer instance available in the child as `_G.buffer`. The
---modified_files are `src/main.lua` (M), `src/ui.lua` (A), `old_file.lua` (D)
---plus a conflict `conflicted.lua`, so tests can assert against those paths.
---@return nil
local function render_test_status()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')
		local Highlights = require('neojj.highlights')
		Highlights.setup()

		_G.buffer = Buffer.create({
			name = "Test Cursor Status",
			filetype = "neojj-status",
			kind = "split",
			modifiable = false,
			readonly = true,
		})
		_G.buffer:open()
		_G.buffer:render(StatusUI.create_test_ui())
		vim.cmd('redraw')

		-- Move the cursor to the first buffer line whose text contains `needle`.
		-- Returns the 1-indexed line, or nil if no line matched.
		function cursor_to_text(needle)
			local lines = vim.api.nvim_buf_get_lines(_G.buffer.handle, 0, -1, false)
			for i, l in ipairs(lines) do
				if l:find(needle, 1, true) then
					_G.buffer:set_cursor(i, 0)
					return i
				end
			end
			return nil
		end
	]])
end

---A file row yields the interactive component's item, keyed by `path`.
---@return nil
T.test_get_item_at_cursor_on_file_row = function()
	render_test_status()
	local path = child.lua_get([[(function()
		local ln = cursor_to_text("src/main.lua")
		expect.no_equality(ln, vim.NIL)
		local item = _G.buffer:get_item_at_cursor()
		return item and item.path or vim.NIL
	end)()]])
	expect.equality(path, "src/main.lua")
end

---An added file row resolves to that file's item too (not the row above it).
---@return nil
T.test_get_item_at_cursor_on_added_file_row = function()
	render_test_status()
	local path = child.lua_get([[(function()
		cursor_to_text("src/ui.lua")
		local item = _G.buffer:get_item_at_cursor()
		return item and item.path or vim.NIL
	end)()]])
	expect.equality(path, "src/ui.lua")
end

---get_component_at_cursor on a file row returns an interactive component.
---@return nil
T.test_get_component_at_cursor_is_interactive = function()
	render_test_status()
	local is_interactive = child.lua_get([[(function()
		cursor_to_text("old_file.lua")
		local component = _G.buffer:get_component_at_cursor()
		return component ~= nil and component:is_interactive()
	end)()]])
	expect.equality(is_interactive, true)
end

---A line ABOVE the first interactive component (the "JJ Status" header on line
---1) has no component, so get_item_at_cursor returns nil.
---@return nil
T.test_get_item_at_cursor_above_first_component = function()
	render_test_status()
	local is_nil = child.lua_get([[(function()
		_G.buffer:set_cursor(1, 0)
		return _G.buffer:get_item_at_cursor() == nil
	end)()]])
	expect.equality(is_nil, true)
end

---The last line falls within the final interactive component (the conflict),
---so get_item_at_cursor resolves to `conflicted.lua`.
---@return nil
T.test_get_item_at_cursor_last_line = function()
	render_test_status()
	local path = child.lua_get([[(function()
		local n = vim.api.nvim_buf_line_count(_G.buffer.handle)
		_G.buffer:set_cursor(n, 0)
		local item = _G.buffer:get_item_at_cursor()
		return item and item.path or vim.NIL
	end)()]])
	expect.equality(path, "conflicted.lua")
end

---An empty buffer (no components rendered) has no interactive component, so
---get_item_at_cursor returns nil rather than erroring.
---@return nil
T.test_get_item_at_cursor_empty_buffer = function()
	child.lua([[
		local Buffer = require('neojj.lib.buffer')
		_G.buffer = Buffer.create({
			name = "Test Cursor Empty",
			filetype = "neojj-status",
			kind = "split",
			modifiable = false,
			readonly = true,
		})
		_G.buffer:open()
		_G.buffer:render({})
		vim.cmd('redraw')
	]])
	local is_nil = child.lua_get([[(function()
		_G.buffer:set_cursor(1, 0)
		return _G.buffer:get_item_at_cursor() == nil
	end)()]])
	expect.equality(is_nil, true)
end

return T
