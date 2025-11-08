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

---Test that JJ command is created after setup
---@return nil
T.test_jj_command_creation = function()
	child.lua([[
		-- Command should not exist before setup (test runs with --noplugin)
		local exists_before = vim.fn.exists(':JJ') == 2
		expect.equality(exists_before, false)

		-- Run setup
		M.setup()

		-- Command should exist after setup
		local exists_after = vim.fn.exists(':JJ') == 2
		expect.equality(exists_after, true)
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
		expect.equality(#subcommands, 5)  -- status, describe, log, commit, new

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
