local child, new_set = require("tests.helpers.child")()

---@type table
local T = new_set({
	pre_case = function()
		child.lua([[ M = require('neojj') ]])
	end,
})

---Test that the :JJ command exists after plugin load, without any setup() call.
---The child Neovim sources plugin/neojj.lua (no --noplugin), which registers
---the command, so users who install without calling setup() still get :JJ.
---@return nil
T.test_jj_command_available_without_setup = function()
	child.lua([[
		-- Plugin was sourced on startup; command must exist with no setup() call.
		local exists = vim.fn.exists(':JJ') == 2
		expect.equality(exists, true)
	]])
end

---Test that setup() re-registers the :JJ command (idempotent).
---@return nil
T.test_jj_command_creation = function()
	child.lua([[
		-- Run setup
		M.setup()

		-- Command should exist after setup
		local exists_after = vim.fn.exists(':JJ') == 2
		expect.equality(exists_after, true)
	]])
end

---Test that setup() validates options and rejects a non-numeric log_level.
---@return nil
T.test_setup_validates_options = function()
	child.lua([[
		-- A string log_level silently breaks the logger's numeric comparisons,
		-- so setup() must reject it with a clear error.
		local ok, err = pcall(M.setup, { log_level = "debug" })
		expect.equality(ok, false)
		expect.equality(err:find("log_level") ~= nil, true)

		-- A numeric log_level is accepted.
		expect.no_error(function()
			M.setup({ log_level = vim.log.levels.DEBUG })
		end)
	]])
end

---Test that setup() seeds and overrides the configurable log_limit.
---@return nil
T.test_setup_configures_log_limit = function()
	child.lua([[
		-- The default is a high cap, not the old hardcoded 10.
		expect.equality(M.config.log_limit, 100)

		-- A non-numeric log_limit is rejected up front.
		local ok, err = pcall(M.setup, { log_limit = "lots" })
		expect.equality(ok, false)
		expect.equality(err:find("log_limit") ~= nil, true)

		-- A numeric log_limit is stored on the runtime config.
		M.setup({ log_limit = 250 })
		expect.equality(M.config.log_limit, 250)
	]])
end

---Test that :JJ log parses an optional split and revision count in either order.
---@return nil
T.test_jj_log_command_arguments = function()
	child.lua([[
		M.setup()

		local calls = {}
		M.jj_log = function(dir, split, limit)
			table.insert(calls, { dir = dir, split = split, limit = limit })
		end

		vim.cmd('JJ log')
		expect.equality(calls[1].split, nil)
		expect.equality(calls[1].limit, nil)

		vim.cmd('JJ log vertical')
		expect.equality(calls[2].split, 'vertical')
		expect.equality(calls[2].limit, nil)

		vim.cmd('JJ log 50')
		expect.equality(calls[3].split, nil)
		expect.equality(calls[3].limit, 50)

		vim.cmd('JJ log vertical 25')
		expect.equality(calls[4].split, 'vertical')
		expect.equality(calls[4].limit, 25)
	]])
end

---Test that jj_log wires the configured log_limit through to LogBuffer options.
---@return nil
T.test_jj_log_passes_configured_limit = function()
	child.lua([[
		-- Reload neojj with a stubbed LogBuffer so we can observe the options it
		-- is constructed with, without shelling out to jj.
		package.loaded['neojj'] = nil
		local captured
		package.loaded['neojj.buffers.log'] = {
			new = function(_repo, options)
				captured = options
				return {
					show = function() end,
					show_split = function() end,
					show_tab = function() end,
				}
			end,
		}

		local M2 = require('neojj')
		M2.get_repo = function() return { is_jj_repo = function() return true end } end

		-- With no explicit limit, the configured default (100) flows through.
		M2.jj_log(nil, nil, nil)
		expect.equality(captured.limit, 100)

		-- An explicit limit takes precedence over the default.
		M2.jj_log(nil, nil, 7)
		expect.equality(captured.limit, 7)

		package.loaded['neojj.buffers.log'] = nil
		package.loaded['neojj'] = nil
	]])
end

---Test JJ command completion
---@return nil
T.test_jj_command_completion = function()
	child.lua([[
		M.setup()

		-- Get subcommand completion options
		local subcommands = vim.fn.getcompletion('JJ ', 'cmdline')
		expect.equality(type(subcommands), 'table')
		expect.equality(#subcommands, 7)  -- status, describe, log, oplog, new, annotate, split

		-- Get split completion options for status subcommand
		local splits = vim.fn.getcompletion('JJ status ', 'cmdline')
		expect.equality(type(splits), 'table')
		expect.equality(#splits, 3)
	]])
end

---Test JJ status command with different arguments
---@return nil
T.test_jj_status_command_arguments = function()
	child.lua([[
		M.setup()

		-- Mock the jj_status function to track calls
		local calls = {}
		M.jj_status = function(dir, revision, split)
			table.insert(calls, { dir = dir, revision = revision, split = split })
		end

		-- Test without arguments
		vim.cmd('JJ status')
		expect.equality(#calls, 1)
		expect.equality(calls[1].dir, nil)
		expect.equality(calls[1].revision, nil)
		expect.equality(calls[1].split, nil)

		-- Test with horizontal split
		vim.cmd('JJ status horizontal')
		expect.equality(#calls, 2)
		expect.equality(calls[2].dir, nil)
		expect.equality(calls[2].revision, nil)
		expect.equality(calls[2].split, 'horizontal')

		-- Test with vertical split
		vim.cmd('JJ status vertical')
		expect.equality(#calls, 3)
		expect.equality(calls[3].dir, nil)
		expect.equality(calls[3].revision, nil)
		expect.equality(calls[3].split, 'vertical')

		-- Test with tab
		vim.cmd('JJ status tab')
		expect.equality(#calls, 4)
		expect.equality(calls[4].dir, nil)
		expect.equality(calls[4].revision, nil)
		expect.equality(calls[4].split, 'tab')

		-- Test with change_id and split
		vim.cmd('JJ status abc123 horizontal')
		expect.equality(#calls, 5)
		expect.equality(calls[5].dir, nil)
		expect.equality(calls[5].revision, 'abc123')
		expect.equality(calls[5].split, 'horizontal')

		-- Test with change_id only
		vim.cmd('JJ status xyz789')
		expect.equality(#calls, 6)
		expect.equality(calls[6].dir, nil)
		expect.equality(calls[6].revision, 'xyz789')
		expect.equality(calls[6].split, nil)
	]])
end

return T
