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

			-- Set up the mock CLI before loading neojj
			child.lua([[
				-- Get absolute paths
				local cwd = vim.fn.getcwd()
				local fixtures_dir = cwd .. '/tests/fixtures/jj-outputs'
				local helpers_dir = cwd .. '/tests/helpers'

				-- Add helpers to package path
				package.path = helpers_dir .. '/?.lua;' .. package.path

				-- Load and configure the mock CLI
				local MockCli = require('mock_cli')
				MockCli.set_fixtures_dir(fixtures_dir)
				MockCli.set_state('initial')

				-- Inject the mock into package.loaded BEFORE neojj loads
				package.loaded['neojj.lib.jj.cli'] = MockCli.create_mock_module()

				-- Also make MockCli globally available for state switching
				_G.MockCli = MockCli

				-- Helper to switch to a known repository state
				function switch_to_state(state_name)
					MockCli.set_state(state_name)
				end
			]])

			-- Now load neojj (it will use our mock CLI)
			child.lua([[ M = require('neojj') ]])
			child.lua([[ M.setup() ]])
			child.lua([[ expect = require('mini.test').expect ]])

			-- Create a fake repo directory for testing
			child.lua([[
				-- Create a minimal mock repository
				local mock_repo_dir = vim.fn.tempname() .. '_neojj_test'
				vim.fn.mkdir(mock_repo_dir, 'p')
				vim.fn.mkdir(mock_repo_dir .. '/.jj', 'p')

				-- Change to the mock repo directory
				vim.cmd('cd ' .. mock_repo_dir)
				_G.mock_repo_dir = mock_repo_dir
			]])
		end,

		---Post-test cleanup
		---@return nil
		post_once = function()
			-- Clean up temp directory
			child.lua([[
				if _G.mock_repo_dir then
					vim.fn.delete(_G.mock_repo_dir, 'rf')
				end
			]])
			child.stop()
		end,
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
		switch_to_state("multiple-changes")
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

---Test status with multiple file changes
---@return nil
T.test_workflow_multiple_changes_status = function()
	-- Switch to multiple-changes state
	child.lua([[
		switch_to_state("multiple-changes")
	]])

	-- Open status buffer
	child.lua([[
        vim.cmd("JJ status")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot showing modified, added, and deleted files
	expect.reference_screenshot(child.get_screenshot())
end

---Test conflict state display
---@return nil
T.test_workflow_conflict_status = function()
	-- Switch to conflict state
	child.lua([[
		switch_to_state("conflict-state")
	]])

	-- Open status buffer
	child.lua([[
        vim.cmd("JJ status")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	-- Take a screenshot showing conflict markers
	expect.reference_screenshot(child.get_screenshot())
end

---Test that a failing `jj status` surfaces an error in the status buffer
---instead of rendering an empty status.
---@return nil
T.test_workflow_status_refresh_failure = function()
	child.lua([[
		switch_to_state("initial")
		-- Make `jj status` fail mid-refresh (e.g. repo locked / version mismatch).
		_G.MockCli.set_failure("status", "jj: internal error: the working copy is locked")
		-- The failure is also surfaced via `vim.notify` at ERROR level, which the
		-- test RPC would otherwise re-raise out of `nvim_exec2`; capture it instead.
		_G.saved_notify = vim.notify
		vim.notify = function() end
		vim.cmd("JJ status")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	local text = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])

	-- Restore notify and clear the simulated failure for later tests.
	child.lua([[
		vim.notify = _G.saved_notify
		_G.MockCli.clear_failures()
	]])

	-- The buffer must show the rendered error, not a bare "JJ Status" header.
	expect.equality(text:find("Error:", 1, true) ~= nil, true)
	expect.equality(text:find("locked", 1, true) ~= nil, true)
end

---Test that a successful refresh still renders working-copy files.
---@return nil
T.test_workflow_status_refresh_success_renders_files = function()
	child.lua([[
		switch_to_state("multiple-changes")
		_G.MockCli.clear_failures()
		vim.cmd("JJ status")
	]])

	-- Wait for async operations to complete
	child.lua([[ vim.wait(500) ]])

	local text = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])

	-- Normal render: the header is present and no error banner is shown.
	expect.equality(text:find("JJ Status", 1, true) ~= nil, true)
	expect.equality(text:find("Error:", 1, true) == nil, true)
end

return T
