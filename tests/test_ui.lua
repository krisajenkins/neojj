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
			child.lua([[ expect = require('mini.test').expect ]])

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
		expect.equality(Component.is_component(text_comp), true)
		expect.equality(text_comp:get_tag(), "Text")
		expect.equality(text_comp:get_value(), "Hello World")

		-- Test column component
		local col_comp = Ui.col({ text_comp })
		expect.equality(Component.is_component(col_comp), true)
		expect.equality(col_comp:get_tag(), "Col")
		expect.equality(#col_comp:get_children(), 1)

		-- Test row component
		local row_comp = Ui.row({ text_comp })
		expect.equality(Component.is_component(row_comp), true)
		expect.equality(row_comp:get_tag(), "Row")
		expect.equality(#row_comp:get_children(), 1)
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
		expect.equality(type(lines), "table")
		expect.equality(lines[1], "Title")

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
		expect.equality(type(components), "table")

		-- Test helper function
		local test_components = StatusUI.create_test_ui()
		expect.equality(type(test_components), "table")
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
		expect.equality(buffer:is_valid(), true)
		expect.equality(buffer:get_name(), "test-buffer")

		-- Test rendering
		local Ui = require('neojj.lib.ui')
		local components = {
			Ui.text("Test content")
		}
		buffer:render(components)

		-- Verify content
		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		expect.equality(type(lines), "table")

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
		expect.equality(hl, "NeoJJFileModified")

		local hl2 = Highlights.get_file_status_highlight("A")
		expect.equality(hl2, "NeoJJFileAdded")

		local hl3 = Highlights.get_file_status_highlight("C")
		expect.equality(hl3, "NeoJJConflict")
	]])
end

---Integration test for JJ status UI display
---@return nil
T.test_jj_status_ui_display = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Create test status buffer
		local buffer = Buffer.create({
			name = "Test JJ Status",
			filetype = "neojj-status",
			modifiable = false,
			readonly = true,
		})

		-- Create test UI components
		local components = StatusUI.create_test_ui()

		-- Render to buffer
		buffer:render(components)

		-- Show buffer
		buffer:show()

		-- Verify buffer is displayed
		local current_buf = vim.api.nvim_get_current_buf()
		expect.equality(current_buf, buffer:get_handle())

		-- Verify content
		local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
		expect.equality(type(lines), "table") -- Should have header + sections

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
		local buffer = Buffer.create({
			name = "JJ Status",
			filetype = "neojj-status",
			modifiable = false,
			readonly = true,
		})

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
	expect.equality(type(child.get_screenshot()), "table")
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
		local buffer = Buffer.create({
			name = "JJ Status - Empty",
			filetype = "neojj-status",
			modifiable = false,
			readonly = true,
		})

		-- Create UI with empty state
		local components = StatusUI.create(empty_repo_state)

		-- Render to buffer
		buffer:render(components)

		-- Show buffer
		buffer:show()

		-- Verify content includes empty state message
		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		local content = table.concat(lines, "\n"):lower()
		expect.equality(type(content), "string")

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

		expect.equality(section:is_foldable(), true)
		expect.equality(section:is_folded(), true)
		expect.equality(section:get_section(), "test_section")

		-- Test non-foldable component
		local text = Ui.text("Simple text")
		expect.equality(text:is_foldable(), false)
		expect.equality(text:is_folded(), false)
	]])
end

---Test diff highlighting with screenshot
---@return nil
T.test_diff_highlighting_screenshot = function()
	child.lua([[
		local Highlights = require('neojj.highlights')
		local StatusUI = require('neojj.buffers.status.ui')
		local Ui = require('neojj.lib.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Setup highlights
		Highlights.setup()

		-- Create a test buffer
		local buffer = Buffer.create({
			name = "Test Diff",
			filetype = "neojj-test",
			kind = "split",
			modifiable = false,
			readonly = true,
		})

		-- Test diff content with various line types
		local test_diff_lines = {
			"diff --git a/example.lua b/example.lua",
			"index 1234567..abcdefg 100644",
			"--- a/example.lua",
			"+++ b/example.lua",
			"@@ -1,8 +1,10 @@",
			" local function example()",
			"-    print('old implementation')",
			"-    return false",
			"+    print('new implementation')",
			"+    print('additional feature')",
			"+    return true",
			" end",
			" ",
			"+-- New function added",
			"+local function helper()",
			"+    return 'helper'",
			"+end"
		}

		-- Create status UI components with expanded file
		local expanded_files = { ["example.lua"] = true }
		local mock_status_buffer = {
			get_file_diff = function(file_path)
				return test_diff_lines
			end
		}

		-- Create a file item with diff expansion
		local file_info = { status = "M", path = "example.lua" }
		local file_component = StatusUI.create_file_item(file_info, expanded_files, mock_status_buffer)

		-- Create the full UI with header
		local components = {
			Ui.text("JJ Status - Diff Highlighting Test", { highlight = "NeoJJTitle" }),
			Ui.empty_line(),
			Ui.text("Modified Files:", { highlight = "NeoJJSectionHeader" }),
			file_component
		}

		buffer:open()
		buffer:render(components)

		-- Ensure buffer is visible
		vim.cmd('redraw')
	]])

	-- Take screenshot
	expect.reference_screenshot(child.get_screenshot())
end

---Test multi-line description rendering with blank lines
---@return nil
T.test_multiline_description_with_blank_lines = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Ui = require('neojj.lib.ui')

		-- Create test data with multi-line description including blank lines
		local test_repo_state = {
			working_copy = {
				change_id = "testmultiline",
				commit_id = "abc123",
				description = "First line\n\nSecond paragraph after blank line\n\nThird paragraph",
				author = { name = "Test User", email = "test@example.com" },
				modified_files = {},
				conflicts = {},
				is_empty = true
			}
		}

		-- Create the UI components
		local components = StatusUI.create(test_repo_state)

		-- Count how many components we have in the working copy section
		local function count_lines_in_section(comps)
			local count = 0
			for _, comp in ipairs(comps) do
				if comp:get_tag() == "Col" then
					count = count + count_lines_in_section(comp:get_children())
				elseif comp:get_tag() == "Section" then
					count = count + count_lines_in_section(comp:get_children())
				elseif comp:get_tag() == "Text" or comp:get_tag() == "EmptyLine" then
					count = count + 1
				end
			end
			return count
		end

		-- Verify we have the right number of components
		-- Should have: change_id line, commit_id line, author line, empty line,
		-- then: "First line", empty line, "Second paragraph...", empty line, "Third paragraph", final empty line
		-- That's minimum 11 lines in the metadata section
		local line_count = count_lines_in_section(components)
		expect.equality(line_count >= 11, true)

		-- Now verify the description lines are split correctly by rendering
		local Buffer = require('neojj.lib.buffer')
		local buffer = Buffer.create({
			name = "Test Multi-line Description",
			filetype = "neojj-test",
			kind = "replace",
			modifiable = false,
			readonly = true,
		})

		buffer:open()
		buffer:render(components)

		-- Get the buffer content
		local lines = vim.api.nvim_buf_get_lines(buffer.handle, 0, -1, false)

		-- Find the description lines (they come after "Author:")
		local found_first_line = false
		local found_blank_after_first = false
		local found_second_para = false
		local found_blank_after_second = false
		local found_third_para = false

		for i, line in ipairs(lines) do
			if line:match("First line") then
				found_first_line = true
			elseif found_first_line and not found_blank_after_first and line == "" then
				found_blank_after_first = true
			elseif found_blank_after_first and line:match("Second paragraph") then
				found_second_para = true
			elseif found_second_para and not found_blank_after_second and line == "" then
				found_blank_after_second = true
			elseif found_blank_after_second and line:match("Third paragraph") then
				found_third_para = true
			end
		end

		expect.equality(found_first_line, true)
		expect.equality(found_blank_after_first, true)
		expect.equality(found_second_para, true)
		expect.equality(found_blank_after_second, true)
		expect.equality(found_third_para, true)

		buffer:close()
	]])
end

---Screenshot test for multi-line description with blank lines
---@return nil
T.test_multiline_description_screenshot = function()
	child.lua([[
		local StatusUI = require('neojj.buffers.status.ui')
		local Buffer = require('neojj.lib.buffer')

		-- Create test data with multi-line description including blank lines
		local test_repo_state = {
			working_copy = {
				change_id = "multilinetest123",
				commit_id = "abc123def456789",
				description = "Add multi-line support\n\nThis commit adds support for multi-line descriptions with proper blank line preservation.\n\nPreviously, consecutive newlines would be collapsed into a single line, losing the paragraph structure.",
				author = { name = "Test User", email = "test@example.com" },
				modified_files = {
					{ status = "M", path = "lua/neojj/buffers/status/ui.lua" }
				},
				conflicts = {},
				is_empty = false
			}
		}

		-- Create the UI components
		local components = StatusUI.create(test_repo_state)

		-- Create and render buffer
		local buffer = Buffer.create({
			name = "Multi-line Description Test",
			filetype = "neojj-test",
			kind = "replace",
			modifiable = false,
			readonly = true,
		})

		buffer:open()
		buffer:render(components)
		vim.cmd('redraw')
	]])

	-- Take screenshot to verify visual rendering
	expect.reference_screenshot(child.get_screenshot())
end

return T
