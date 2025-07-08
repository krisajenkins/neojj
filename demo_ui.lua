#!/usr/bin/env nvim -l

-- Demo script to show the NeoJJ status UI
-- Run with: nvim -l tests/demo_ui.lua

package.path = package.path .. ";./lua/?.lua"

local StatusUI = require("neojj.buffers.status.ui")
local Buffer = require("neojj.lib.buffer")
local Highlights = require("neojj.highlights")

-- Setup highlights
Highlights.setup()

-- Create test buffer
local buffer = Buffer.create_status("JJ Status Demo")

-- Create demo UI with rich content
local demo_repo_state = {
	working_copy = {
		change_id = "kmkuslsqnxux",
		commit_id = "abc123def456789abcdef",
		description = "Implement NeoJJ status UI with component system",
		author = { name = "Demo User", email = "demo@neojj.dev" },
		modified_files = {
			{ status = "M", path = "lua/neojj.lua" },
			{ status = "A", path = "lua/neojj/lib/ui/component.lua" },
			{ status = "A", path = "lua/neojj/lib/ui/init.lua" },
			{ status = "A", path = "lua/neojj/lib/ui/renderer.lua" },
			{ status = "A", path = "lua/neojj/lib/buffer.lua" },
			{ status = "A", path = "lua/neojj/buffers/status/init.lua" },
			{ status = "A", path = "lua/neojj/buffers/status/ui.lua" },
			{ status = "A", path = "lua/neojj/highlights.lua" },
			{ status = "M", path = "tests/test_main.lua" },
			{ status = "A", path = "tests/test_simple.lua" },
			{ status = "A", path = "tests/test_integration.lua" },
		},
		conflicts = {},
		is_empty = false,
	},
}

local components = StatusUI.create(demo_repo_state)

-- Show the buffer
buffer:render(components)
buffer:show()

-- Print some info
print("NeoJJ Status UI Demo")
print("===================")
print("• Component-based UI system ✓")
print("• Buffer management ✓")
print("• Rendering system ✓")
print("• Highlighting ✓")
print("• Section folding support ✓")
print("• File status display ✓")
print("")
print("Press 'q' to quit, 'r' to refresh, '?' for help")
print("Navigation: j/k to move, <Tab> to toggle folds")
print("")

-- Wait for user input
vim.fn.getchar()
