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
end

return T
