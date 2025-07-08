local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.bo.readonly = false
			child.o.lines = 40
			child.o.columns = 160

			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ M = require('neojj') ]])

			child.lua([=[ function slurp_test_data(filename)
          return vim.fn.readfile('tests/'..filename)
      end ]=])
		end,
		post_once = child.stop,
	},
})

-- T.jj_status = function()
-- 	child.lua([[ M.jj_status() ]])
-- 	expect.reference_screenshot(child.get_screenshot())
-- end

return T
