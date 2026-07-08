local child = MiniTest.new_child_neovim()

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

---Test that the :JJ command advertises the oplog subcommand.
T.test_oplog_subcommand_registered = function()
	child.lua([[
		require('neojj').setup()

		-- The dispatcher exposes jj_oplog for the oplog subcommand.
		local neojj = require('neojj')
		expect.equality(type(neojj.jj_oplog), "function")
	]])
end

---Test oplog buffer creation.
T.test_oplog_buffer_creation = function()
	child.lua([[
		local OplogBuffer = require('neojj.buffers.oplog')

		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end
		}

		local oplog_buffer = OplogBuffer.new(mock_repo)
		expect.equality(type(oplog_buffer), "table")
		expect.equality(type(oplog_buffer.buffer), "table")
		expect.equality(oplog_buffer.show_help, false)
	]])
end

---Test that reusing an oplog buffer returns the same instance.
T.test_oplog_buffer_reuse = function()
	child.lua([[
		local OplogBuffer = require('neojj.buffers.oplog')

		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end
		}

		local first = OplogBuffer.new(mock_repo)
		local second = OplogBuffer.new(mock_repo)
		expect.equality(first, second)
	]])
end

---Test oplog UI components.
T.test_oplog_ui_components = function()
	child.lua([[
		local OplogUI = require('neojj.buffers.oplog.ui')

		local header = OplogUI.create_header()
		expect.equality(type(header), "table")

		local help = OplogUI.create_help()
		expect.equality(type(help), "table")

		local empty = OplogUI.create_empty_state()
		expect.equality(type(empty), "table")
	]])
end

---Rendering an empty oplog must show the real "no operations" copy.
T.test_oplog_empty_state_renders_real_text = function()
	child.lua([[
		local OplogUI = require('neojj.buffers.oplog.ui')
		local Buffer = require('neojj.lib.buffer')

		-- No raw_lines means OplogUI.create falls through to the empty state.
		local components = OplogUI.create({ operations = {} })

		local buffer = Buffer.create({
			name = 'JJ Oplog - Empty',
			filetype = 'neojj-oplog',
			modifiable = false,
			readonly = true,
		})
		buffer:render(components)

		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		local content = table.concat(lines, '\n')

		expect.equality(content:find('No operations found', 1, true) ~= nil, true)

		buffer:close()
	]])
end

---Test that the oplog buffer renders parsed operations.
T.test_oplog_renders_operations = function()
	child.lua([[
		local OplogUI = require('neojj.buffers.oplog.ui')
		local oplog_parser = require('neojj.lib.jj.parsers.oplog_parser')
		local Highlights = require('neojj.highlights')
		local Buffer = require('neojj.lib.buffer')

		Highlights.setup()

		local sample = "@  \030abc123def456\031user@example.com\0312025-01-01 12:00:00\0312025-01-01 12:00:01\n" ..
			"│  \030push bookmark main\n"

		local state = oplog_parser.parse_oplog_output(sample)
		local components = OplogUI.create(state)

		local buffer = Buffer.create({
			name = 'JJ Oplog - Render',
			filetype = 'neojj-oplog',
			modifiable = false,
			readonly = true,
		})
		buffer:render(components)

		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		local content = table.concat(lines, '\n')

		expect.equality(content:find('abc123def456', 1, true) ~= nil, true)
		expect.equality(content:find('push bookmark main', 1, true) ~= nil, true)

		buffer:close()
	]])
end

return T
