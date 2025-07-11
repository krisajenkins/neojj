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

---Test that JJDescribe command is created after setup
---@return nil
T.test_jjdescribe_command_creation = function()
	child.lua([[
		-- Command should not exist before setup
		local exists_before = vim.fn.exists(':JJDescribe') == 2
		expect.equality(exists_before, false)

		-- Run setup
		M.setup()

		-- Command should exist after setup
		local exists_after = vim.fn.exists(':JJDescribe') == 2
		expect.equality(exists_after, true)
	]])
end

---Test JJDescribe command with different arguments
---@return nil
T.test_jjdescribe_command_arguments = function()
	child.lua([[
		M.setup()

		-- Mock the jj_describe function to track calls
		local calls = {}
		M.jj_describe = function(dir, revision, split)
			table.insert(calls, { dir = dir, revision = revision, split = split })
		end

		-- Test without arguments (should default to @ revision)
		vim.cmd('JJDescribe')
		expect.equality(#calls, 1)
		expect.equality(calls[1].dir, nil)
		expect.equality(calls[1].revision, '@')
		expect.equality(calls[1].split, nil)

		-- Test with specific revision
		vim.cmd('JJDescribe abc123')
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
		local DescribeBuffer = require('neojj.buffers.describe')expect.no_error(function()
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

return T
