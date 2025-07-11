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
		self:describe_current_commit()
	end, { desc = "Describe current commit" })

	self.buffer:map("n", "D", function()
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

		-- Render the UI only if buffer is still valid
		vim.schedule(function()
			if self.buffer and self.buffer:is_valid() then
				self:render()
			else
				logger.debug("Status buffer is no longer valid, skipping render")
			end
		end)
	end)
end

---Render the status UI
function StatusBuffer:render()
	if not self.buffer or not self.buffer:is_valid() then
		logger.debug("Cannot render: status buffer is invalid")
		return
	end

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

---Show the status buffer in a new tab
function StatusBuffer:show_tab()
	self.buffer:show_tab()
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

---Open describe buffer for current commit
function StatusBuffer:describe_current_commit()
	local DescribeBuffer = require("neojj.buffers.describe")

	-- Callback to refresh status buffer when description is updated
	local function on_submit()
		vim.notify("Description updated", vim.log.levels.INFO)
		-- Only refresh if the status buffer is still valid
		if self.buffer and self.buffer:is_valid() then
			self:refresh()
			-- Return focus to the status buffer after a short delay to ensure describe buffer closes first
			vim.defer_fn(function()
				if self.buffer and self.buffer:is_valid() then
					self.buffer:show()
				end
			end, 100)
		else
			logger.debug("Status buffer no longer valid, skipping refresh after describe")
		end
	end

	local function on_abort()
		-- Return focus to status buffer on abort as well
		if self.buffer and self.buffer:is_valid() then
			vim.defer_fn(function()
				if self.buffer and self.buffer:is_valid() then
					self.buffer:show()
				end
			end, 100)
		end
	end

	local describe_buffer = DescribeBuffer.new(self.repo, "@", on_submit, on_abort)
	describe_buffer:show()
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
