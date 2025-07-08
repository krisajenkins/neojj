---@type table
local expect = MiniTest.expect

---@class TestModule
---@field get_repo function
---@field status function

---@type TestModule
local M

---@type table
local T = MiniTest.new_set({
	hooks = {
		---Pre-test hook to set up environment
		---@return nil
		pre_case = function()
			-- Set up runtime path for telescope
			vim.cmd([[ set rtp+=deps/plenary.nvim ]])

			-- Load the module fresh for each test
			package.loaded["neojj"] = nil
			M = require("neojj")
		end,
	},
})

---Simple unit test for basic functionality
---@return nil
T["Simple test"] = function()
	---@type table
	local repo = M.get_repo(".")
	expect.no_equality(repo, nil) -- Repo should be created
	expect.equality(type(repo.get_root), "function") -- Should have get_root method

	-- Test that status doesn't crash (it may or may not be a jj repo)
	print(vim.inspect(M.status(".")))
end

return T
