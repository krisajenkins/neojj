---@type table
local expect = MiniTest.expect

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
			child.o.lines = 40
			child.o.columns = 120

			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ M = require('neojj') ]])
			child.lua([[ M.setup() ]])
			child.lua([[ expect = require('mini.test').expect ]])

			-- Setup helper to switch repository states
			child.lua([[
				local demo_repo_path = vim.fn.fnamemodify('fixtures/demo-repo', ':p')

				-- Helper to switch to a known repository state
				function switch_to_state(bookmark_name)
					local Cli = require('neojj.lib.jj.cli')

					-- Change to demo repo directory only if not already there
					if vim.fn.getcwd() ~= demo_repo_path then
						vim.cmd('cd ' .. demo_repo_path)
					end

					-- Switch to the bookmark using JJ CLI
					local result = Cli.raw()
						:arg("edit")
						:arg(bookmark_name)
						:cwd(demo_repo_path)
						:call()

					-- JJ edit outputs to stderr even on success, check success flag
					if not result.success then
						error("Failed to switch to state " .. bookmark_name .. ": " .. (result.stderr or "Unknown error"))
					end

					-- Give JJ time to update working copy
					vim.wait(100)

					return result
				end

				-- Ensure demo repo exists
				if vim.fn.isdirectory(demo_repo_path) == 0 then
					error("Demo repository not found at " .. demo_repo_path .. ". Run: fixtures/create-demo-repo.sh")
				end
			]])
		end,

		---Post-test cleanup
		---@return nil
		post_once = child.stop,
	},
})

---Test basic status display workflow
---@return nil
T.test_workflow_basic_status_empty = function()
	-- Switch to initial (empty) state
	child.lua([[
		switch_to_state("initial")
	]])

	-- Open status buffer
	child.lua([[
        vim.cmd("JJStatus")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot of this basic status setup.
	expect.reference_screenshot(child.get_screenshot())
end

---Test basic status display workflow
---@return nil
T.test_workflow_basic_log = function()
	-- Switch to initial (empty) state
	child.lua([[
		switch_to_state("initial")
	]])

	-- Open status buffer
	child.lua([[
        vim.cmd("JJLog")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot of this basic status setup.
	expect.reference_screenshot(child.get_screenshot())
end

return T
