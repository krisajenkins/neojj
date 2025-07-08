---@type table
local expect = MiniTest.expect

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
			child.o.columns = 120

			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ M = require('neojj') ]])
			child.lua([[ M.setup() ]])

			-- Helper function to create test data
			child.lua([=[
				function create_test_repo_state()
					return {
						working_copy = {
							change_id = "kmkuslsqnxux",
							commit_id = "abc123def456789",
							description = "Test commit for UI development",
							author = { name = "Test User", email = "test@example.com" },
							modified_files = {
								{ status = "M", path = "src/main.lua" },
								{ status = "A", path = "src/ui.lua" },
								{ status = "D", path = "old_file.lua" }
							},
							conflicts = {
								{ path = "conflicted.lua" }
							},
							is_empty = false
						}
					}
				end
			]=])
		end,
		---Post-test cleanup
		---@return nil
		post_once = child.stop,
	},
})

---Test UI component creation
---@return nil
T.test_ui_components = function()
	child.lua([[
		local Ui = require('neojj.lib.ui')
		local Component = require('neojj.lib.ui.component')

		-- Test basic component creation
		local text_comp = Ui.text("Hello World")
		expect(Component.is_component(text_comp)).to_be(true)
		expect(text_comp:get_tag()).to_be("Text")
		expect(text_comp:get_value()).to_be("Hello World")

		-- Test column component
		local col_comp = Ui.col({ text_comp })
		expect(Component.is_component(col_comp)).to_be(true)
		expect(col_comp:get_tag()).to_be("Col")
		expect(#col_comp:get_children()).to_be(1)

		-- Test row component
		local row_comp = Ui.row({ text_comp })
		expect(Component.is_component(row_comp)).to_be(true)
		expect(row_comp:get_tag()).to_be("Row")
		expect(#row_comp:get_children()).to_be(1)
	]])
end

---Test UI rendering
---@return nil
T.test_ui_rendering = function()
	child.lua([[
		local Ui = require('neojj.lib.ui')
		local Renderer = require('neojj.lib.ui.renderer')

		-- Create a simple component tree
		local components = {
			Ui.text("Title", { highlight = "Title" }),
			Ui.col({
				Ui.text("Line 1"),
				Ui.text("Line 2")
			})
		}

		-- Create a test buffer
		local buffer = vim.api.nvim_create_buf(false, true)

		-- Render components
		Renderer.render_to_buffer(buffer, components)

		-- Check buffer content
		local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
		expect(#lines).to_be_greater_than(0)
		expect(lines[1]).to_be("Title")

		-- Clean up
		vim.api.nvim_buf_delete(buffer, { force = true })
	]])
end

---Test status UI creation
---@return nil
T.test_status_ui = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')

		-- Create test UI
		local repo_state = create_test_repo_state()
		local components = StatusUI.create(repo_state)

		-- Verify components were created
		expect(#components).to_be_greater_than(0)

		-- Test helper function
		local test_components = StatusUI.create_test_ui()
		expect(#test_components).to_be_greater_than(0)
	]])
end

---Test buffer management
---@return nil
T.test_buffer_management = function()
	child.lua([[
		local Buffer = require('neojj.lib.buffer')

		-- Create a test buffer
		local buffer = Buffer.new({
			name = "test-buffer",
			filetype = "test",
			modifiable = false
		})

		-- Test buffer properties
		expect(buffer:is_valid()).to_be(true)
		expect(buffer:get_name()).to_be("test-buffer")

		-- Test rendering
		local Ui = require('neojj.lib.ui')
		local components = {
			Ui.text("Test content")
		}
		buffer:render(components)

		-- Verify content
		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		expect(#lines).to_be_greater_than(0)

		-- Clean up
		buffer:close()
	]])
end

---Test highlight groups
---@return nil
T.test_highlights = function()
	child.lua([[
		local Highlights = require('neojj.highlights')

		-- Setup highlights
		Highlights.setup()

		-- Test file status highlight mapping
		local hl = Highlights.get_file_status_highlight("M")
		expect(hl).to_be("NeoJJFileModified")

		local hl2 = Highlights.get_file_status_highlight("A")
		expect(hl2).to_be("NeoJJFileAdded")

		local hl3 = Highlights.get_file_status_highlight("C")
		expect(hl3).to_be("NeoJJConflict")
	]])
end

---Integration test for JJ status UI display
---@return nil
T.test_jj_status_ui_display = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Create test status buffer
		local buffer = Buffer.create_status("Test JJ Status")

		-- Create test UI components
		local components = StatusUI.create_test_ui()

		-- Render to buffer
		buffer:render(components)

		-- Show buffer
		buffer:show()

		-- Verify buffer is displayed
		local current_buf = vim.api.nvim_get_current_buf()
		expect(current_buf).to_be(buffer:get_handle())

		-- Verify content
		local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
		expect(#lines).to_be_greater_than(5) -- Should have header + sections

		-- Clean up
		buffer:close()
	]])
end

---Screenshot reference test for status UI
---@return nil
T.test_status_ui_screenshot = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Create test status buffer
		local buffer = Buffer.create_status("JJ Status")

		-- Create test UI with known data
		local components = StatusUI.create_test_ui()

		-- Render to buffer
		buffer:render(components)

		-- Show buffer
		buffer:show()

		-- Set a consistent window size
		vim.api.nvim_win_set_width(0, 80)
		vim.api.nvim_win_set_height(0, 30)

		-- Position cursor at the top
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	]])

	-- Take screenshot for reference
	expect.reference_screenshot(child.get_screenshot(), {
		path = "tests/screenshots/status_ui.txt",
	})
end

---Test empty status display
---@return nil
T.test_empty_status_display = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Create empty repo state
		local empty_repo_state = {
			working_copy = {
				change_id = "kmkuslsqnxux",
				commit_id = "abc123def456789",
				description = "Empty working copy",
				author = { name = "Test User", email = "test@example.com" },
				modified_files = {},
				conflicts = {},
				is_empty = true
			}
		}

		-- Create test status buffer
		local buffer = Buffer.create_status("JJ Status - Empty")

		-- Create UI with empty state
		local components = StatusUI.create(empty_repo_state)

		-- Render to buffer
		buffer:render(components)

		-- Show buffer
		buffer:show()

		-- Verify content includes empty state message
		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		local content = table.concat(lines, "\n"):lower()
		expect(content:find("no changes")).to_be_not_nil()

		-- Clean up
		buffer:close()
	]])
end

---Test component folding options
---@return nil
T.test_component_folding = function()
	child.lua([[
		local Ui = require('neojj.lib.ui')
		local Component = require('neojj.lib.ui.component')

		-- Test foldable component
		local section = Ui.section("Test Section", {
			Ui.text("Item 1"),
			Ui.text("Item 2")
		}, {
			folded = true,
			foldable = true
		})

		expect(section:is_foldable()).to_be(true)
		expect(section:is_folded()).to_be(true)
		expect(section:get_section()).to_be("test_section")

		-- Test non-foldable component
		local text = Ui.text("Simple text")
		expect(text:is_foldable()).to_be(false)
		expect(text:is_folded()).to_be(false)
	]])
end

return T
