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

-- Example integration test (commented out)
-- ---Integration test for jj status functionality
-- ---@return nil
-- T.jj_status = function()
-- 	child.lua([[ M.jj_status() ]])
-- 	expect.reference_screenshot(child.get_screenshot())
-- end

return T
