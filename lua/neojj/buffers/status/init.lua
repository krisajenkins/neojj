local Buffer = require("neojj.lib.buffer")
local StatusUI = require("neojj.buffers.status.ui")
local logger = require("neojj.logger")

---@class StatusBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field state table Current repository state
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

---Create a new status buffer
---@param repo table Repository instance
---@return StatusBuffer status_buffer Status buffer instance
function StatusBuffer.new(repo)
	local buffer = Buffer.create_status("JJ Status")

	local instance = setmetatable({
		buffer = buffer,
		repo = repo,
		state = {},
	}, StatusBuffer)

	-- Add status-specific key mappings
	instance:_setup_mappings()

	return instance
end

---Setup status-specific key mappings
function StatusBuffer:_setup_mappings()
	-- Refresh mapping
	self.buffer:map("n", "r", function()
		self:refresh()
	end, { desc = "Refresh status" })

	-- Help mapping
	self.buffer:map("n", "g?", function()
		self:toggle_help()
	end, { desc = "Toggle help" })

	-- Fold toggling
	self.buffer:map("n", "<tab>", function()
		self:toggle_fold()
	end, { desc = "Toggle fold" })

	self.buffer:map("n", "<s-tab>", function()
		self:toggle_fold_reverse()
	end, { desc = "Toggle fold (reverse)" })

	-- File actions (for future implementation)
	self.buffer:map("n", "<cr>", function()
		self:open_file_at_cursor()
	end, { desc = "Open file" })

	self.buffer:map("n", "d", function()
		self:diff_file_at_cursor()
	end, { desc = "Show diff" })

	-- Navigation
	self.buffer:map("n", "j", function()
		self:move_cursor_down()
	end, { desc = "Move cursor down" })

	self.buffer:map("n", "k", function()
		self:move_cursor_up()
	end, { desc = "Move cursor up" })
end

---Refresh the status buffer
function StatusBuffer:refresh()
	logger.info("Refreshing status buffer")

	if not self.repo:is_jj_repo() then
		self:render_error("Not a JJ repository")
		return
	end

	local async = require("plenary.async")

	async.run(function()
		-- Refresh repository state
		self.repo:refresh()

		-- Get current state
		local working_copy = self.repo:get_working_copy()

		self.state = {
			working_copy = working_copy,
		}

		-- Render the UI
		self:render()
	end)
end

---Render the status UI
function StatusBuffer:render()
	local components = StatusUI.create(self.state)
	self.buffer:render(components)
end

---Render an error message
---@param message string Error message
function StatusBuffer:render_error(message)
	local Ui = require("neojj.lib.ui")
	local components = {
		Ui.text("Error: " .. message, { highlight = "ErrorMsg" }),
		Ui.empty_line(),
		Ui.text("Press q to quit", { highlight = "NeoJJHelpText" }),
	}
	self.buffer:render(components)
end

---Show the status buffer
function StatusBuffer:show()
	self.buffer:show()
	self:refresh()
end

---Show the status buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function StatusBuffer:show_split(split_type)
	self.buffer:show_split(split_type)
	self:refresh()
end

---Close the status buffer
function StatusBuffer:close()
	self.buffer:close()
end

---Toggle help display
function StatusBuffer:toggle_help()
	-- TODO: Implement help toggle
	print("Help toggle not yet implemented")
end

---Toggle fold at cursor
function StatusBuffer:toggle_fold()
	-- TODO: Implement fold toggling
	print("Fold toggle not yet implemented")
end

---Toggle fold in reverse direction
function StatusBuffer:toggle_fold_reverse()
	-- TODO: Implement reverse fold toggling
	print("Reverse fold toggle not yet implemented")
end

---Open file at cursor
function StatusBuffer:open_file_at_cursor()
	-- TODO: Implement file opening
	print("File opening not yet implemented")
end

---Show diff for file at cursor
function StatusBuffer:diff_file_at_cursor()
	-- TODO: Implement diff display
	print("Diff display not yet implemented")
end

---Move cursor down
function StatusBuffer:move_cursor_down()
	local line, col = unpack(self.buffer:get_cursor())
	local line_count = vim.api.nvim_buf_line_count(self.buffer.handle)

	if line < line_count then
		self.buffer:set_cursor(line + 1, col)
	end
end

---Move cursor up
function StatusBuffer:move_cursor_up()
	local line, col = unpack(self.buffer:get_cursor())

	if line > 1 then
		self.buffer:set_cursor(line - 1, col)
	end
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function StatusBuffer:is_valid()
	return self.buffer:is_valid()
end

---Get buffer handle
---@return number handle Buffer handle
function StatusBuffer:get_handle()
	return self.buffer:get_handle()
end

return StatusBuffer
