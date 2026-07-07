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

				-- Wait until the current buffer contains `needle` (or a timeout).
				-- Prefer this over fixed `vim.wait(500)` sleeps: async jj commands
				-- render on their own schedule, so poll for the observable result
				-- (a header, "Change ID:", a help panel) instead of guessing a delay.
				-- Returns true if the text appeared, false on timeout.
				function wait_for_text(needle, timeout)
					return vim.wait(timeout or 2000, function()
						local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
						return text:find(needle, 1, true) ~= nil
					end, 20)
				end
			]])

			-- Now load neojj (it will use our mock CLI)
			child.lua([[ M = require('neojj') ]])
			child.lua([[ M.setup() ]])
			child.lua([[ expect = require('mini.test').expect ]])

			-- Create a fake repo directory for testing.
			--
			-- The directory path must be *deterministic* (not vim.fn.tempname(),
			-- which is random per run) because buffer names are now namespaced per
			-- repo: they embed a short hash of the repo root path, and that name is
			-- shown in the window statusline captured by the reference screenshots.
			-- A random path would produce a different hash — and thus a different
			-- statusline — on every run, so the screenshots could never match.
			child.lua([[
				-- Create a minimal mock repository at a fixed, deterministic path.
				local mock_repo_dir = vim.fn.fnamemodify(vim.fn.resolve('/tmp'), ':p') .. 'neojj_integration_test_repo'
				vim.fn.delete(mock_repo_dir, 'rf')
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

	-- Wait for the status view to finish rendering (async jj status).
	child.lua([[ wait_for_text("JJ Status") ]])

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

	-- Wait for the log view to finish rendering (async jj log).
	child.lua([[ wait_for_text("JJ Log") ]])

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

	-- Wait for the commit view to finish rendering (async jj show).
	child.lua([[ wait_for_text("Change ID:") ]])

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

	-- Wait for the log to render its commit lines (async jj log).
	child.lua([[ wait_for_text("test@example.com") ]])

	-- Position the cursor on the working-copy commit line (the `@` node). That
	-- line carries an interactive component with a change_id, which is what
	-- LogBuffer:show_commit_at_cursor() requires (it early-returns otherwise).
	child.lua([[
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		for i, line in ipairs(lines) do
			if line:match("^@") then
				vim.api.nvim_win_set_cursor(0, { i, 0 })
				break
			end
		end
	]])

	-- Press Enter to open the commit view. type_keys routes through the
	-- buffer-local `<cr>` mapping (unlike `normal!`, which bypasses mappings and,
	-- inside a [[ ]] block, would only receive the literal text `\<CR>`).
	child.type_keys("<CR>")

	-- Wait for the commit/status view to replace the log view. The commit view
	-- renders "Change ID: ..." (see status/ui.lua), so its presence proves the
	-- view actually switched rather than the cursor merely moving.
	child.lua([[ wait_for_text("Change ID:") ]])

	-- Assert the view genuinely switched to the commit view.
	local text = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])
	expect.equality(text:find("Change ID:", 1, true) ~= nil, true)

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

	-- Wait for the commit view to finish rendering (async jj show).
	child.lua([[ wait_for_text("Change ID:") ]])

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

	-- Wait for the commit view to finish rendering (async jj show).
	child.lua([[ wait_for_text("Change ID:") ]])

	-- Press ? to toggle the help panel. type_keys routes through the buffer-local
	-- `?` mapping (→ StatusBuffer:toggle_help); `normal! ?` would instead run
	-- Vim's built-in reverse search and never show the help panel.
	child.type_keys("?")

	-- Wait for the help panel to render (status/ui.lua create_help header).
	child.lua([[ wait_for_text("NeoJJ Status Help") ]])

	-- Assert the help panel is actually displayed.
	local text = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])
	expect.equality(text:find("NeoJJ Status Help", 1, true) ~= nil, true)

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

	-- Wait for the status view to finish rendering (async jj status).
	child.lua([[ wait_for_text("JJ Status") ]])

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

	-- Wait for the status view to finish rendering (async jj status).
	child.lua([[ wait_for_text("JJ Status") ]])

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

	-- Wait for the rendered error banner to appear (async jj status failure).
	child.lua([[ wait_for_text("Error:") ]])

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

	-- Wait for the status header to render (async jj status success).
	child.lua([[ wait_for_text("JJ Status") ]])

	local text = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])

	-- Normal render: the header is present and no error banner is shown.
	expect.equality(text:find("JJ Status", 1, true) ~= nil, true)
	expect.equality(text:find("Error:", 1, true) == nil, true)
end

---Test that `:JJ status` in a directory with no `.jj` ancestor reports a
---friendly "not a repository" message and does not crash.
---@return nil
T.test_workflow_status_not_a_repository = function()
	-- is_jj_repo() is decided by the REAL filesystem (util.find_jj_dir walks up
	-- looking for `.jj`), NOT the mock CLI — so mock injection is irrelevant to
	-- this path. We just need a cwd whose ancestors contain no `.jj`. The project
	-- tree and the pre_case mock repo dir both have a `.jj`, so use a fresh temp
	-- dir under $TMPDIR (vim.fn.tempname() is random per run, which is fine here:
	-- this test asserts on buffer/notify text, not on a reference screenshot).
	child.lua([[
		_G.saved_cwd = vim.fn.getcwd()
		_G.nojj_dir = vim.fn.tempname() .. '_nojj'
		vim.fn.mkdir(_G.nojj_dir, 'p')
		vim.cmd('cd ' .. _G.nojj_dir)

		-- M.jj_status short-circuits with a friendly `vim.notify(..., ERROR)`
		-- before any status buffer is created. The ERROR-level notify would
		-- otherwise be re-raised out of the command call by the test RPC, so
		-- capture the messages instead of letting them surface.
		_G.saved_notify = vim.notify
		_G.notified = {}
		vim.notify = function(msg)
			table.insert(_G.notified, msg)
		end
	]])

	-- Running the command must not raise, even outside a jj repository.
	local ok = child.lua_get([[
		select(1, pcall(function() vim.cmd("JJ status") end))
	]])

	local notified = child.lua_get([[ _G.notified ]])

	-- Restore state and clean up the temp dir.
	child.lua([[
		vim.notify = _G.saved_notify
		vim.cmd('cd ' .. _G.saved_cwd)
		vim.fn.delete(_G.nojj_dir, 'rf')
	]])

	-- The command completed without error (no crash).
	expect.equality(ok, true)

	-- A friendly "not a repository" message was surfaced.
	local found = false
	for _, msg in ipairs(notified) do
		if type(msg) == "string" and msg:find("Not a jj repository", 1, true) then
			found = true
		end
	end
	expect.equality(found, true)
end

---Test that <Tab> on a file row in the status buffer toggles its diff open.
---@return nil
T.test_keybinding_tab_toggles_file_diff = function()
	-- Use the revision (commit) view so the diff is embedded from `jj show`
	-- (parse_show_output) rather than fetched via a separate `jj diff` call.
	child.lua([[
		switch_to_state("multiple-changes")
		vim.cmd("JJ status @")
	]])

	-- Wait for the src/main.lua file row to render (async jj show).
	child.lua([[ wait_for_text("src/main.lua") ]])

	-- Position the cursor on the `src/main.lua` file row. That row carries an
	-- interactive component with `item.path`, which is what toggle_file_diff
	-- requires (it early-returns otherwise).
	child.lua([[
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		for i, line in ipairs(lines) do
			if line:find("src/main.lua", 1, true) then
				vim.api.nvim_win_set_cursor(0, { i, 0 })
				break
			end
		end
	]])

	local before = child.lua_get([[ vim.api.nvim_buf_line_count(0) ]])

	-- Press <Tab> to expand the diff. type_keys routes through the buffer-local
	-- `<tab>` mapping (→ StatusBuffer:toggle_file_diff); `normal! <Tab>` would not.
	child.type_keys("<Tab>")

	-- Wait for the diff hunk header to render (async jj diff for src/main.lua).
	child.lua([[ wait_for_text("@@") ]])

	local after = child.lua_get([[ vim.api.nvim_buf_line_count(0) ]])
	local text = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])

	-- Expanding the diff adds lines and surfaces a hunk marker.
	expect.equality(after > before, true)
	expect.equality(text:find("@@", 1, true) ~= nil, true)
end

---Test that `y` in the log buffer yanks the change ID at the cursor.
---@return nil
T.test_keybinding_y_yanks_change_id = function()
	child.lua([[
		switch_to_state("multiple-changes")
		vim.cmd("JJ log")
	]])

	-- Wait for the log to render its commit lines (async jj log).
	child.lua([[ wait_for_text("test@example.com") ]])

	-- Position the cursor on the working-copy `@` line. In the multiple-changes
	-- fixture that node's change_id is `ttokvzsn` (see multiple-changes-log.txt).
	child.lua([[
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		for i, line in ipairs(lines) do
			if line:match("^@") then
				vim.api.nvim_win_set_cursor(0, { i, 0 })
				break
			end
		end
	]])

	-- Press y to yank. type_keys routes through the buffer-local `y` mapping
	-- (→ LogBuffer:yank_change_id_at_cursor), which writes to the `+` register.
	child.type_keys("y")

	local reg = child.lua_get([[ vim.fn.getreg("+") ]])
	expect.equality(reg, "ttokvzsn")
end

---Test that `q` closes the status view (its buffer is wiped).
---@return nil
T.test_keybinding_q_closes_status = function()
	child.lua([[
		switch_to_state("multiple-changes")
		vim.cmd("JJ status")
	]])

	-- Wait for the status view to finish rendering (async jj status).
	child.lua([[ wait_for_text("JJ Status") ]])

	local handle = child.lua_get([[ vim.api.nvim_get_current_buf() ]])

	-- Press q. type_keys routes through the buffer-local `q` mapping
	-- (→ Buffer:close), which wipes the bufhidden="wipe" status buffer.
	child.type_keys("q")

	local valid = child.lua_get(("vim.api.nvim_buf_is_valid(%d)"):format(handle))
	expect.equality(valid, false)
end

---Test that `r` refreshes the status buffer, picking up new working-copy state.
---@return nil
T.test_keybinding_r_refreshes_status = function()
	child.lua([[
		switch_to_state("initial")
		vim.cmd("JJ status")
	]])

	-- Wait for the initial status view to render (async jj status).
	child.lua([[ wait_for_text("JJ Status") ]])

	-- The initial state has no src/main.lua change; multiple-changes does.
	local before = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])
	expect.equality(before:find("src/main.lua", 1, true) == nil, true)

	-- Switch the underlying repo state, then refresh.
	child.lua([[ switch_to_state("multiple-changes") ]])

	-- Press r. type_keys routes through the buffer-local `r` mapping
	-- (→ StatusBuffer:refresh), which re-runs jj status against the new state.
	child.type_keys("r")

	-- Wait for the new working-copy file to appear (async refresh).
	child.lua([[ wait_for_text("src/main.lua") ]])

	local after = child.lua_get([[
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	]])
	expect.equality(after:find("src/main.lua", 1, true) ~= nil, true)
end

return T
