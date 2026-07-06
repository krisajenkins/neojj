local child = MiniTest.new_child_neovim()
local expect = MiniTest.expect

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.bo.readonly = false
			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ expect = require('mini.test').expect ]])
		end,
		post_once = child.stop,
	},
})

---Test jj log command creation
---@return nil
T.test_jj_log_command_creation = function()
	child.lua([[
		require('neojj').setup()

		-- Check that JJ command exists
		local commands = vim.api.nvim_get_commands({})
		expect.equality(commands.JJ ~= nil, true)
		expect.equality(commands.JJ.nargs, "+")
	]])
end

---Test jj log command arguments
---@return nil
T.test_jj_log_command_arguments = function()
	child.lua([[
		require('neojj').setup()

		-- Test command completion exists
		local commands = vim.api.nvim_get_commands({})
		expect.equality(commands.JJ.complete ~= nil, true)
	]])
end

---Test log buffer creation
---@return nil
T.test_log_buffer_creation = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')
		local jj = require('neojj.lib.jj')

		-- Create a mock repository
		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end
		}

		-- Test log buffer creation
		local log_buffer = LogBuffer.new(mock_repo)
		expect.equality(type(log_buffer), "table")
		expect.equality(type(log_buffer.buffer), "table")
		expect.equality(log_buffer.show_help, false)
	]])
end

---Test that reusing a log buffer merges options rather than replacing them.
---@return nil
T.test_log_buffer_merges_options_on_reuse = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')

		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end
		}

		-- First construction configures a limit and revset.
		local first = LogBuffer.new(mock_repo, { limit = 50, revisions = "@" })
		expect.equality(first.options.limit, 50)
		expect.equality(first.options.revisions, "@")

		-- Reuse with no options must keep the previously configured values.
		local second = LogBuffer.new(mock_repo)
		expect.equality(first, second)
		expect.equality(second.options.limit, 50)
		expect.equality(second.options.revisions, "@")

		-- Reuse with a new value overrides only that key.
		local third = LogBuffer.new(mock_repo, { limit = 200 })
		expect.equality(third.options.limit, 200)
		expect.equality(third.options.revisions, "@")
	]])
end

---Test log UI components
---@return nil
T.test_log_ui_components = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')

		-- Test creating test UI
		local components = LogUI.create_test_ui()
		expect.equality(type(components), "table")
		expect.equality(#components > 0, true)

		-- Test header creation
		local header = LogUI.create_header()
		expect.equality(type(header), "table")

		-- Test help creation
		local help = LogUI.create_help()
		expect.equality(type(help), "table")

		-- Test empty state
		local empty = LogUI.create_empty_state()
		expect.equality(type(empty), "table")
	]])
end

---Test log graph highlighting
---@return nil
T.test_log_graph_highlighting = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')

		-- Test graph character highlighting
		expect.equality(LogUI.get_graph_highlight("@"), "NeoJJLogWorkingCopy")
		expect.equality(LogUI.get_graph_highlight("○"), "NeoJJLogCommit")
		expect.equality(LogUI.get_graph_highlight("◆"), "NeoJJLogImmutable")
		expect.equality(LogUI.get_graph_highlight("│"), "NeoJJLogGraphLine")
		expect.equality(LogUI.get_graph_highlight("├"), "NeoJJLogGraphLine")
		expect.equality(LogUI.get_graph_highlight("x"), "NeoJJLogGraph") -- fallback
	]])
end

---Test log parsing
---@return nil
T.test_log_parsing = function()
	child.lua([[
		local log_parser = require('neojj.lib.jj.parsers.log_parser')

		-- Test parsing sample log output in the NeoJJ template format.
		-- "\30" is the record separator (graph|payload); "\31" separates fields.
		local sample_output =
			"@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\n" ..
			"│  \030Adding jj log support.\n" ..
			"○  \030knsrwpnn\031user@example.com\0312025-07-14 20:58:50\031\0311e062938\031\n" ..
			"│  \030Implementing status functions.\n"

		local parsed = log_parser.parse_log_output(sample_output)
		expect.equality(type(parsed), "table")
		expect.equality(type(parsed.revisions), "table")
		expect.equality(type(parsed.graph_data), "table")
		expect.equality(type(parsed.raw_lines), "table")

		-- Should have parsed at least 2 revisions
		expect.equality(#parsed.revisions >= 2, true)

		-- Basic structure validation
		expect.equality(#parsed.revisions > 0, true)
		if #parsed.revisions > 0 then
			local first_rev = parsed.revisions[1]
			expect.equality(type(first_rev.change_id), "string")
			expect.equality(type(first_rev.author), "string")
			expect.equality(type(first_rev.commit_id), "string")
		end
	]])
end

---Test log buffer screenshot
---@return nil
T.test_log_screenshot = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')
		local LogUI = require('neojj.buffers.log.ui')
		local Highlights = require('neojj.highlights')
		local Buffer = require('neojj.lib.buffer')

		-- Setup highlights
		Highlights.setup()

		-- Create a test buffer
		local buffer = Buffer.create({
			name = "Test Log",
			filetype = "neojj-test",
			kind = "split",
			modifiable = false,
			readonly = true,
		})

		-- Create test log UI
		local components = LogUI.create_test_ui()

		buffer:open()
		buffer:render(components)

		-- Ensure buffer is visible
		vim.cmd('redraw')
	]])

	-- Take screenshot
	expect.reference_screenshot(child.get_screenshot())
end

return T
