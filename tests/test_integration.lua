---Integration test for JJ status UI
---@type table
local T = MiniTest.new_set()

---Test complete JJ status UI flow
---@return nil
T.test_full_status_ui = function()
	local StatusUI = require("neojj.buffers.status.ui")
	local Buffer = require("neojj.lib.buffer")

	-- Create test status buffer
	local buffer = Buffer.create({
		name = "JJ Status Test",
		filetype = "neojj-status",
		modifiable = false,
		readonly = true,
	})

	-- Create test UI components
	local components = StatusUI.create_test_ui()

	-- Render to buffer
	buffer:render(components)

	-- Verify buffer content
	local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)

	if #lines == 0 then
		error("Buffer should have content")
	end

	-- Check for expected content
	local content = table.concat(lines, "\n")
	if not content:find("JJ Status") then
		error("Buffer should contain 'JJ Status' header")
	end

	if not content:find("Working Copy") then
		error("Buffer should contain 'Working Copy' section")
	end

	if not content:find("Modified Files") then
		error("Buffer should contain 'Modified Files' section")
	end

	-- Clean up
	buffer:close()

	print("✓ Full status UI integration works")
end

---Test rendering system
---@return nil
T.test_rendering_system = function()
	local Ui = require("neojj.lib.ui")
	local Renderer = require("neojj.lib.ui.renderer")

	-- Create components
	local components = {
		Ui.text("Title", { highlight = "Title" }),
		Ui.col({
			Ui.text("Line 1"),
			Ui.text("Line 2"),
			Ui.row({
				Ui.text("Col A"),
				Ui.text("Col B"),
			}),
		}),
	}

	-- Create test buffer
	local buffer = vim.api.nvim_create_buf(false, true)

	-- Render components
	Renderer.render_to_buffer(buffer, components)

	-- Check buffer content
	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

	if #lines < 3 then
		error("Buffer should have at least 3 lines")
	end

	if lines[1] ~= "Title" then
		error("First line should be 'Title'")
	end

	if not lines[2] or lines[2]:find("Line 1") == nil then
		error("Second line should contain 'Line 1'")
	end

	-- Clean up
	vim.api.nvim_buf_delete(buffer, { force = true })

	print("✓ Rendering system works")
end

---Test component hierarchy
---@return nil
T.test_component_hierarchy = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Create nested structure
	local nested = Ui.col({
		Ui.text("Header"),
		Ui.section("Test Section", {
			Ui.file_item("M", "test.lua"),
			Ui.file_item("A", "new.lua"),
		}),
	})

	-- Verify structure
	if not Component.is_component(nested) then
		error("Nested structure should be a component")
	end

	if nested:get_tag() ~= "Col" then
		error("Root should be a Col component")
	end

	local children = nested:get_children()
	if #children ~= 2 then
		error("Root should have 2 children")
	end

	-- Check section
	local section = children[2]
	if not Component.is_component(section) then
		error("Section should be a component")
	end

	if not section:is_foldable() then
		error("Section should be foldable")
	end

	print("✓ Component hierarchy works")
end

---Test folding functionality
---@return nil
T.test_folding = function()
	local Ui = require("neojj.lib.ui")

	-- Create foldable section
	local section = Ui.section("Foldable Section", {
		Ui.text("Item 1"),
		Ui.text("Item 2"),
	}, {
		folded = true,
	})

	if not section:is_foldable() then
		error("Section should be foldable")
	end

	if not section:is_folded() then
		error("Section should be folded")
	end

	if section:get_section() ~= "foldable_section" then
		error("Section name should be normalized")
	end

	print("✓ Folding functionality works")
end

---Test file status highlighting
---@return nil
T.test_file_status_highlighting = function()
	local Highlights = require("neojj.highlights")
	local Ui = require("neojj.lib.ui")

	-- Setup highlights
	Highlights.setup()

	-- Create file items with different statuses
	Ui.file_item("M", "modified.lua")
	Ui.file_item("A", "added.lua")
	Ui.file_item("D", "deleted.lua")

	-- Test highlight mapping
	local hl_m = Highlights.get_file_status_highlight("M")
	local hl_a = Highlights.get_file_status_highlight("A")
	local hl_d = Highlights.get_file_status_highlight("D")

	if hl_m ~= "NeoJJFileModified" then
		error("Modified file highlight incorrect")
	end

	if hl_a ~= "NeoJJFileAdded" then
		error("Added file highlight incorrect")
	end

	if hl_d ~= "NeoJJFileDeleted" then
		error("Deleted file highlight incorrect")
	end

	print("✓ File status highlighting works")
end

return T
