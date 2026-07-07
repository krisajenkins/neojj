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
			child.lua([[ expect = require('mini.test').expect ]])
		end,
		---Post-test cleanup
		---@return nil
		post_once = child.stop,
	},
})

---Test that the :JJ command is available after plugin load and setup.
---The child sources plugin/neojj.lua (no --noplugin), so :JJ exists on
---startup even before setup(); setup() re-registers it idempotently.
---@return nil
T.test_jj_describe_command_creation = function()
	child.lua([[
		-- Plugin was sourced on startup; command exists without a setup() call.
		local exists_before = vim.fn.exists(':JJ') == 2
		expect.equality(exists_before, true)

		-- Run setup
		M.setup()

		-- Command should still exist after setup
		local exists_after = vim.fn.exists(':JJ') == 2
		expect.equality(exists_after, true)
	]])
end

---Test JJ describe command with different arguments
---@return nil
T.test_jj_describe_command_arguments = function()
	child.lua([[
		M.setup()

		-- Mock the jj_describe function to track calls
		local calls = {}
		M.jj_describe = function(dir, revision, split)
			table.insert(calls, { dir = dir, revision = revision, split = split })
		end

		-- Test without arguments (should default to @ revision)
		vim.cmd('JJ describe')
		expect.equality(#calls, 1)
		expect.equality(calls[1].dir, nil)
		expect.equality(calls[1].revision, '@')
		expect.equality(calls[1].split, nil)

		-- Test with specific revision
		vim.cmd('JJ describe abc123')
		expect.equality(#calls, 2)
		expect.equality(calls[2].dir, nil)
		expect.equality(calls[2].revision, 'abc123')
		expect.equality(calls[2].split, nil)
	]])
end

---Test DescribeBuffer creation and basic functionality
---@return nil
T.test_describe_buffer_creation = function()
	child.lua([[
		-- Create a mock repository
		local mock_repo = {
			dir = '/fake/repo',
			is_jj_repo = function() return true end,
		}

		-- Load DescribeBuffer module
		local DescribeBuffer = require('neojj.buffers.describe')
		expect.no_error(function()
			local buffer = DescribeBuffer.new(mock_repo, '@')
			expect.equality(type(buffer), 'table')
			expect.equality(buffer.revision, '@')
			expect.equality(buffer.repo, mock_repo)
		end)
	]])
end

---Test DescribeBuffer keymappings
---@return nil
T.test_describe_buffer_keymappings = function()
	child.lua([[
		-- Create a mock repository
		local mock_repo = {
			dir = '/fake/repo',
			is_jj_repo = function() return true end,
		}

		-- Mock the JJ CLI to avoid actual command execution
		package.loaded['neojj.lib.jj.cli'] = {
			describe = function()
				return {
					arg = function(self, ...) return self end,
					call = function()
						return { success = true, stdout = '', stderr = '' }
					end,
				}
			end,
			log = function()
				return {
					arg = function(self, ...) return self end,
					call = function()
						return { success = true, stdout = 'Test description', stderr = '' }
					end,
				}
			end,
		}

		local DescribeBuffer = require('neojj.buffers.describe')
		-- Create describe buffer
		local buffer = DescribeBuffer.new(mock_repo, '@')
		expect.equality(type(buffer), 'table')
		expect.equality(buffer:is_valid(), true)

		-- The buffer should have specific keymappings set up
		-- We can't easily test the actual mappings in this context,
		-- but we can verify the buffer was created successfully
		expect.equality(type(buffer.buffer), 'table')
	]])
end

---Test buffer cleanup
---@return nil
T.test_describe_buffer_cleanup = function()
	child.lua([[
		-- Create a mock repository
		local mock_repo = {
			dir = '/fake/repo',
			is_jj_repo = function() return true end,
		}

		local DescribeBuffer = require('neojj.buffers.describe')
		-- Create describe buffer
		local buffer = DescribeBuffer.new(mock_repo, '@')

		-- Verify buffer was created successfully
		expect.equality(type(buffer), 'table')
		expect.equality(buffer.revision, '@')
		-- Buffer should close successfully
		buffer:close()
	]])
end

--- Child-side setup for the quit/submit semantics tests.
---
--- Mocks the jj CLI so load_current_description() runs without a real jj, then
--- creates and *opens* a describe buffer in a split (so the child keeps a second
--- window and quit commands never exit the child Neovim). The describe window is
--- left focused as global `db`.
---
--- submit()/abort() are then replaced with invocation counters. The real
--- submit() shells out to `jj describe --stdin` via plenary.job (NOT the mock
--- CLI), so an actual describe call cannot be observed in the harness; counting
--- method invocations is the faithful observable seam for "did we submit, and
--- did we (accidentally) submit twice".
local SETUP = [[
	expect = require('mini.test').expect

	-- Mock the jj CLI used by load_current_description() so no real jj runs.
	local function chain()
		local b = {}
		b.option = function(self) return self end
		b.flag = function(self) return self end
		b.call = function() return { success = true, stdout = '{}' } end
		return b
	end
	package.loaded['neojj.lib.jj.cli'] = { log = function() return chain() end }

	local mock_repo = { dir = '/fake/repo', is_jj_repo = function() return true end }
	local DescribeBuffer = require('neojj.buffers.describe')
	db = DescribeBuffer.new(mock_repo, '@')
	db:show() -- opens a split; child now has two windows
	vim.wait(1000, function() return db.description_loaded end)

	-- Replace submit()/abort() with counters (see note above).
	db._submit_calls = 0
	db._abort_calls = 0
	function db.submit(self)
		self._submit_calls = self._submit_calls + 1
	end
	function db.abort(self)
		self._abort_calls = self._abort_calls + 1
	end

	-- Make the buffer look modified so quit semantics are actually exercised.
	vim.cmd('stopinsert')
	vim.api.nvim_set_option_value('modified', true, { buf = db.buffer.handle })
]]

--- :q! must discard without submitting (regression: it used to overwrite the
--- description because QuitPre submitted whenever the buffer was modified).
T.test_quit_force_discards_without_submit = function()
	child.lua(SETUP)
	child.lua([[
		pcall(function() vim.cmd('q!') end)
		expect.equality(db._submit_calls, 0)
		expect.equality(db._abort_calls, 1)
	]])
end

--- :q on a modified buffer must also route to abort, never submit.
T.test_quit_does_not_submit = function()
	child.lua(SETUP)
	child.lua([[
		pcall(function() vim.cmd('q') end)
		expect.equality(db._submit_calls, 0)
		expect.equality(db._abort_calls, 1)
	]])
end

--- :wq must submit exactly once. Previously BufWriteCmd submitted and then the
--- following QuitPre submitted again, launching two racing `jj describe` jobs.
T.test_write_quit_submits_exactly_once = function()
	child.lua(SETUP)
	child.lua([[
		pcall(function() vim.cmd('wq') end)
		expect.equality(db._submit_calls, 1)
	]])
end

--- :w must submit once and clear 'modified' (so a later QuitPre from :wq does
--- not observe a modified buffer and fire a second submit path).
T.test_write_submits_once_and_clears_modified = function()
	child.lua(SETUP)
	child.lua([[
		pcall(function() vim.cmd('w') end)
		expect.equality(db._submit_calls, 1)
		local modified = vim.api.nvim_get_option_value('modified', { buf = db.buffer.handle })
		expect.equality(modified, false)
	]])
end

--- ZZ must submit (save-and-quit semantics).
T.test_ZZ_submits = function()
	child.lua(SETUP)
	child.type_keys("ZZ")
	child.lua([[
		expect.equality(db._submit_calls, 1)
		expect.equality(db._abort_calls, 0)
	]])
end

--- ZQ must abort without submitting.
T.test_ZQ_aborts_without_submit = function()
	child.lua(SETUP)
	child.type_keys("ZQ")
	child.lua([[
		expect.equality(db._submit_calls, 0)
		expect.equality(db._abort_calls, 1)
	]])
end

--- Legitimate '#'-prefixed lines (Markdown headings, issue refs like '#123')
--- must survive the buffer -> get_description_from_buffer() round-trip. Only our
--- own 'JJ:'-prefixed help lines are stripped. (Regression: the filter used to
--- drop every line starting with '#', silently deleting commit-message data.)
T.test_hash_lines_survive_round_trip = function()
	child.lua([[
		expect = require('mini.test').expect

		local mock_repo = { dir = '/fake/repo', is_jj_repo = function() return true end }
		local DescribeBuffer = require('neojj.buffers.describe')
		local db = DescribeBuffer.new(mock_repo, '@')

		-- Put a description containing '#'-prefixed lines into the buffer,
		-- followed by the kind of 'JJ:' help lines the UI appends.
		vim.api.nvim_buf_set_lines(db.buffer.handle, 0, -1, false, {
			'# Overview',
			'',
			'Closes #123 by rewriting the parser.',
			'',
			'JJ: Commands:',
			'JJ:   :w or :wq    - Submit description',
		})

		local description = db:get_description_from_buffer()

		-- The '#' lines are preserved verbatim...
		expect.equality(description, '# Overview\n\nCloses #123 by rewriting the parser.')
		-- ...and the 'JJ:' help lines are stripped.
		expect.equality(description:find('JJ:'), nil)
	]])
end

--- The re-entry guard in the real submit() must prevent a second concurrent
--- job while one is in flight, and must clear once the job completes so a later
--- legitimate submit still works. plenary.async is mocked to record job launches
--- without executing them, so submitting stays "in flight".
T.test_submit_reentry_guard = function()
	child.lua([[
		expect = require('mini.test').expect

		local run_calls = 0
		package.loaded['plenary.async'] = {
			run = function(fn)
				run_calls = run_calls + 1
			end,
		}

		local mock_repo = { dir = '/fake/repo', is_jj_repo = function() return true end }
		local DescribeBuffer = require('neojj.buffers.describe')
		local db = DescribeBuffer.new(mock_repo, '@')

		-- First submit launches a job and arms the guard.
		db:submit()
		expect.equality(run_calls, 1)
		expect.equality(db.submitting, true)

		-- Second submit while in flight is ignored (no racing second job).
		db:submit()
		expect.equality(run_calls, 1)

		-- Once the in-flight job completes, a later submit works again.
		db.submitting = false
		db:submit()
		expect.equality(run_calls, 2)

		package.loaded['plenary.async'] = nil
	]])
end

--- The async load_current_description() render must not wipe text the user has
--- already typed. The describe buffer opens empty and schedules startinsert, so
--- an impatient user can type before the (async) description load lands. If the
--- buffer is already modified, render_components() must bail out rather than
--- overwrite the user's in-progress text with the loaded description.
T.test_load_does_not_wipe_user_input = function()
	child.lua([[
		expect = require('mini.test').expect

		-- Capture the async load fn instead of running it, so we control exactly
		-- when the description render lands (i.e. after the user has typed).
		local captured_fn
		package.loaded['plenary.async'] = {
			run = function(fn) captured_fn = fn end,
		}
		_G.__run_captured = function() if captured_fn then captured_fn() end end

		-- Mock the jj CLI so the deferred load resolves to a real description.
		local function chain()
			local b = {}
			b.option = function(self) return self end
			b.flag = function(self) return self end
			b.call = function()
				return { success = true, stdout = '{"description":"loaded from jj"}' }
			end
			return b
		end
		package.loaded['neojj.lib.jj.cli'] = { log = function() return chain() end }

		local mock_repo = { dir = '/fake/repo', is_jj_repo = function() return true end }
		local DescribeBuffer = require('neojj.buffers.describe')
		db = DescribeBuffer.new(mock_repo, '@')
		db:show()

		-- The load has NOT resolved yet (async.run only captured its fn).
		-- Simulate the user typing before the description arrives.
		vim.cmd('stopinsert')
		vim.api.nvim_buf_set_lines(db.buffer.handle, 0, -1, false, { 'my work in progress' })
		vim.api.nvim_set_option_value('modified', true, { buf = db.buffer.handle })

		-- Now the async load resolves and tries to render the loaded description.
		_G.__run_captured()
		vim.wait(500, function() return db.description_loaded end)

		-- The user's text must survive; the loaded description must NOT clobber it.
		local lines = vim.api.nvim_buf_get_lines(db.buffer.handle, 0, -1, false)
		expect.equality(lines[1], 'my work in progress')
		expect.equality(table.concat(lines, '\n'):find('loaded from jj'), nil)

		package.loaded['plenary.async'] = nil
	]])
end

return T
