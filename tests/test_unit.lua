local expect = MiniTest.expect

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			-- Set up runtime path for telescope
			vim.cmd([[ set rtp+=deps/plenary.nvim ]])

			-- Load the module fresh for each test
			package.loaded["neojj"] = nil
			M = require("neojj")
		end,
	},
})

T["Simple test"] = function()
	expect.equality(1, 1)
end

return T
