---@type table
-- local expect = MiniTest.expect

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
			child.o.columns = 160

			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ M = require('neojj') ]])

			---Helper function to read test data files
			---@param filename string Name of the test data file
			---@return string[] File contents as array of lines
			child.lua([=[ function slurp_test_data(filename)
          return vim.fn.readfile('tests/'..filename)
      end ]=])
		end,
		---Post-test cleanup
		---@return nil
		post_once = child.stop,
	},
})

---Integration test for jj status functionality (requires JJ repo)
---@return nil
T.jj_status_ui = function()
	child.lua([[
		-- Create a test status UI without requiring actual JJ repo
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Create test buffer
		local buffer = Buffer.create_status("JJ Status Test")

		-- Create test UI
		local components = StatusUI.create_test_ui()

		-- Render and show
		buffer:render(components)
		buffer:show()

		-- Set consistent window size
		vim.api.nvim_win_set_width(0, 80)
		vim.api.nvim_win_set_height(0, 25)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	]])

	-- Take reference screenshot
	expect.reference_screenshot(child.get_screenshot(), {
		path = "tests/screenshots/jj_status_ui.txt",
	})
end

---Test basic jj_status function (mock)
---@return nil
T.jj_status_basic = function()
	child.lua([[
		-- Mock a basic test by creating components directly
		local StatusUI = require('neojj.buffers.status.ui')
		local components = StatusUI.create_test_ui()

		-- Verify components were created
		expect(#components).to_be_greater_than(0)

		-- Verify header exists
		local header_found = false
		for _, component in ipairs(components) do
			if component:get_tag() == "Col" then
				local children = component:get_children()
				if #children > 0 and children[1]:get_value() == "JJ Status" then
					header_found = true
					break
				end
			end
		end
		expect(header_found).to_be(true)
	]])
end

return T
