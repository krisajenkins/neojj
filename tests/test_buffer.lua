---@type table
local child = MiniTest.new_child_neovim()

---@type table
local T = MiniTest.new_set({
	hooks = {
		---Pre-test hook to set up child Neovim instance
		---@return nil
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.bo.readonly = false

			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ M = require('neojj') ]])
			child.lua([[ M.setup() ]])
			child.lua([[ expect = require('mini.test').expect ]])
			child.lua([[ Buffer = require('neojj.lib.buffer') ]])
		end,
		---Post-test cleanup
		---@return nil
		post_once = child.stop,
	},
})

---A name that is a prefix of an existing buffer must NOT match it (regression
---for `vim.fn.bufnr()` partial file-pattern matching hijacking the wrong buffer).
---@return nil
T.test_prefix_name_does_not_match_existing = function()
	child.lua([[
		-- Create an existing buffer whose name has "NeoJJ Status" as a prefix.
		local existing = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(existing, "NeoJJ Status: abc12345")

		-- Asking for the bare prefix must not return the existing handle.
		local prefix_handle = Buffer.from_name("NeoJJ Status")
		expect.no_equality(prefix_handle, existing)

		-- Asking for the exact name must return the existing handle.
		local exact_handle = Buffer.from_name("NeoJJ Status: abc12345")
		expect.equality(exact_handle, existing)
	]])
end

---Names containing Lua/Vim pattern characters must be matched literally.
---@return nil
T.test_name_with_pattern_chars = function()
	child.lua([[
		local existing = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(existing, "NeoJJ Annotate: a[1]")

		-- Exact match with pattern characters resolves to the same buffer.
		local exact_handle = Buffer.from_name("NeoJJ Annotate: a[1]")
		expect.equality(exact_handle, existing)

		-- A different (non-matching) name must create a distinct buffer.
		local other_handle = Buffer.from_name("NeoJJ Annotate: a[2]")
		expect.no_equality(other_handle, existing)
	]])
end

---When no buffer with the given name exists, a new handle is created.
---@return nil
T.test_creates_when_missing = function()
	child.lua([[
		local handle = Buffer.from_name("NeoJJ Log")
		expect.equality(type(handle), "number")
		expect.equality(vim.api.nvim_buf_is_valid(handle), true)

		-- Repeated lookups of the same name return the same handle.
		local again = Buffer.from_name("NeoJJ Log")
		expect.equality(again, handle)
	]])
end

return T
