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

---Two different repositories must not share the same underlying status buffer,
---otherwise the second repo's mappings clobber the first's. Buffer names are
---namespaced per repo, so distinct repos yield distinct buffer handles.
---@return nil
T.test_status_buffers_namespaced_per_repo = function()
	child.lua([[
		local StatusBuffer = require('neojj.buffers.status')
		local function make_repo(dir, root)
			return { dir = dir, get_root = function() return root end }
		end

		local repo_a = make_repo("/tmp/neojj-repo-a", "/tmp/neojj-repo-a")
		local repo_b = make_repo("/tmp/neojj-repo-b", "/tmp/neojj-repo-b")

		local a = StatusBuffer.new(repo_a)
		local b = StatusBuffer.new(repo_b)
		expect.no_equality(a:get_handle(), b:get_handle())

		-- The same repo reuses its own instance (and buffer handle).
		local a2 = StatusBuffer.new(repo_a)
		expect.equality(a2:get_handle(), a:get_handle())

		-- Two repos that share a basename but live at different paths still get
		-- distinct handles (the namespace hash disambiguates them).
		local repo_c = make_repo("/tmp/x/project", "/tmp/x/project")
		local repo_d = make_repo("/tmp/y/project", "/tmp/y/project")
		expect.no_equality(StatusBuffer.new(repo_c):get_handle(), StatusBuffer.new(repo_d):get_handle())
	]])
end

---Log views for two different repos must likewise coexist rather than share one
---module-global instance (and one buffer).
---@return nil
T.test_log_buffers_namespaced_per_repo = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')
		local function make_repo(dir, root)
			return { dir = dir, get_root = function() return root end }
		end

		local repo_a = make_repo("/tmp/neojj-repo-a", "/tmp/neojj-repo-a")
		local repo_b = make_repo("/tmp/neojj-repo-b", "/tmp/neojj-repo-b")

		local a = LogBuffer.new(repo_a)
		local b = LogBuffer.new(repo_b)
		expect.no_equality(a:get_handle(), b:get_handle())

		-- The same repo reuses its own instance (and buffer handle).
		local a2 = LogBuffer.new(repo_a)
		expect.equality(a2:get_handle(), a:get_handle())
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
