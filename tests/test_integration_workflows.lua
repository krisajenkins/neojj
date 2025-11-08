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
        vim.cmd("JJ status")
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
        vim.cmd("JJ log")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot of this basic status setup.
	expect.reference_screenshot(child.get_screenshot())
end

---Test basic commit view workflow
---@return nil
T.test_workflow_basic_commit = function()
	-- Switch to initial (empty) state
	child.lua([[
		switch_to_state("initial")
	]])

	-- Open commit buffer directly with the working copy commit
	child.lua([[
        vim.cmd("JJ status @")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot of the commit view
	expect.reference_screenshot(child.get_screenshot())
end

---Test navigation from log to commit view
---@return nil
T.test_workflow_log_to_commit_navigation = function()
	-- Switch to initial (empty) state
	child.lua([[
		switch_to_state("initial")
	]])

	-- Open log buffer
	child.lua([[
        vim.cmd("JJ log")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Press Enter on the first commit line to navigate to commit view
	child.lua([[
		-- Move to the first commit line (usually line 4 after header)
		vim.cmd("normal! 4G")
		-- Press Enter to open commit view
		vim.cmd("normal! \\<CR>")
	]])

	-- Wait for commit view to load
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot of the commit view opened from log
	expect.reference_screenshot(child.get_screenshot())
end

---Test commit view with file interactions
---@return nil
T.test_workflow_commit_file_interactions = function()
	-- Switch to state with some file changes
	child.lua([[
		switch_to_state("initial")
	]])

	-- Open commit buffer for the working copy
	child.lua([[
        vim.cmd("JJ status @")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Navigate to a file line (if files are present)
	child.lua([[
		-- Try to find a file line in the commit view
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		for i, line in ipairs(lines) do
			if line:match("^%s*[AMDRC]%s+") then
				-- Found a file line, navigate to it
				vim.cmd("normal! " .. i .. "G")
				break
			end
		end
	]])

	-- Take a screenshot showing file selection
	expect.reference_screenshot(child.get_screenshot())
end

---Test commit view help display
---@return nil
T.test_workflow_commit_help = function()
	-- Switch to initial (empty) state
	child.lua([[
		switch_to_state("initial")
	]])

	-- Open commit buffer
	child.lua([[
        vim.cmd("JJ status @")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Press ? to show help
	child.lua([[
		vim.cmd("normal! ?")
	]])

	-- Take a screenshot of the help display
	expect.reference_screenshot(child.get_screenshot())
end

return T
