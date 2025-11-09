local Buffer = require("neojj.lib.buffer")
local AnnotateUI = require("neojj.buffers.annotate.ui")
local logger = require("neojj.logger")

---@class AnnotateBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field filepath string File path to annotate
---@field source_bufnr number Source buffer number
---@field source_winnr number Source window number
---@field annotate_output? string Raw annotation output
---@field annotations_loaded boolean Whether annotations have been loaded
local AnnotateBuffer = {}
AnnotateBuffer.__index = AnnotateBuffer

---Create a new annotation buffer for a file
---@param repo table Repository instance
---@param filepath string File path to annotate (relative to repo root)
---@param source_bufnr number Source file buffer number
---@return AnnotateBuffer annotate_buffer Annotation buffer instance
function AnnotateBuffer.new(repo, filepath, source_bufnr)
	local instance = setmetatable({
		repo = repo,
		filepath = filepath,
		source_bufnr = source_bufnr,
		source_winnr = vim.fn.bufwinid(source_bufnr),
		annotations_loaded = false,
	}, AnnotateBuffer)

	-- Create buffer with unified factory method
	local buffer = Buffer.create({
		name = "JJ Annotate: " .. filepath,
		filetype = "neojj-annotate",
		kind = "vsplit",
		modifiable = false,
		readonly = true,
		scratch = true,
		cwd = repo.dir,
		disable_line_numbers = true,
		disable_relative_line_numbers = true,
		mappings = {},
		autocmds = {},
		initialize = function()
			-- Load annotations when buffer is initialized
			instance:load_annotations()
		end,
		render = function()
			if instance.annotations_loaded and instance.annotate_output then
				return instance:create_ui_components()
			else
				return nil
			end
		end,
		after = function()
			-- Set up scrollbinding after buffer is displayed
			instance:setup_scrollbind()
		end,
		on_detach = function()
			instance:_cleanup()
		end,
	})

	instance.buffer = buffer
	instance:_setup_mappings()
	instance:_setup_autocmds()

	return instance
end

---Setup key mappings for the annotation buffer
function AnnotateBuffer:_setup_mappings()
	-- Close with q
	self.buffer:map("n", "q", function()
		self:close()
	end, { desc = "Close annotation buffer" })

	-- Close with <c-c>
	self.buffer:map("n", "<c-c>", function()
		self:close()
	end, { desc = "Close annotation buffer" })

	-- Close with <esc>
	self.buffer:map("n", "<esc>", function()
		self:close()
	end, { desc = "Close annotation buffer" })

	-- Open change at cursor with <cr>
	self.buffer:map("n", "<cr>", function()
		self:open_change_at_cursor()
	end, { desc = "Open change" })

	-- Copy change ID at cursor
	self.buffer:map("n", "y", function()
		self:copy_change_id_at_cursor()
	end, { desc = "Copy change ID" })
end

---Setup autocmds for the annotation buffer
function AnnotateBuffer:_setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("neojj_annotate_" .. self.buffer.handle, { clear = true })

	-- Watch for source buffer deletion/close
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		buffer = self.source_bufnr,
		callback = function()
			-- Close annotation buffer when source buffer is closed
			if self.buffer and self.buffer:is_valid() then
				self:close()
			end
		end,
	})

	-- Clean up on buffer unload
	vim.api.nvim_create_autocmd("BufUnload", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			self:_cleanup()
		end,
	})
end

---Setup scrollbinding between annotation buffer and source buffer
function AnnotateBuffer:setup_scrollbind()
	if not self.buffer:is_valid() then
		return
	end

	local annotation_winnr = vim.fn.bufwinid(self.buffer.handle)
	if annotation_winnr == -1 then
		return
	end

	-- Enable scrollbind on both windows
	vim.api.nvim_set_option_value("scrollbind", true, { win = annotation_winnr })

	if vim.api.nvim_win_is_valid(self.source_winnr) then
		vim.api.nvim_set_option_value("scrollbind", true, { win = self.source_winnr })

		-- Sync cursor position
		vim.api.nvim_set_option_value("cursorbind", false, { win = annotation_winnr })
		vim.api.nvim_set_option_value("cursorbind", false, { win = self.source_winnr })
	end

	-- Set window width to 30 columns
	vim.api.nvim_win_set_width(annotation_winnr, 30)
end

---Load annotations from jj file annotate
function AnnotateBuffer:load_annotations()
	local async = require("plenary.async")

	async.run(function()
		local jj_cli = require("neojj.lib.jj.cli")

		local cmd = jj_cli.file():arg("annotate"):arg(self.filepath):cwd(self.repo.dir)

		local result = cmd:call()

		if result.success and result.stdout then
			vim.schedule(function()
				self.annotate_output = result.stdout
				self.annotations_loaded = true
				self:render_components()
			end)
		else
			logger.error("Failed to load annotations: " .. (result.stderr or ""))
			vim.schedule(function()
				self.annotate_output = nil
				self.annotations_loaded = true
				self:render_components()
			end)
		end
	end)
end

---Create UI components for the annotation buffer
---@return table[] components UI components
function AnnotateBuffer:create_ui_components()
	return AnnotateUI.create(self.annotate_output or "")
end

---Render components to the buffer
function AnnotateBuffer:render_components()
	if not self.buffer or not self.buffer:is_valid() then
		return
	end

	local components = self:create_ui_components()
	self.buffer:render(components)
end

---Check if a line is a continuation marker (│ or o)
---@param line string Line content
---@return boolean is_continuation True if line is a continuation marker
local function is_continuation_line(line)
	local trimmed = vim.trim(line)
	return trimmed == "│" or trimmed == "o"
end

---Get the change ID at the current cursor position
---@return string|nil change_id Change ID at cursor or nil
function AnnotateBuffer:get_change_id_at_cursor()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(self.buffer.handle, cursor_line - 1, cursor_line, false)

	if #lines == 0 then
		return nil
	end

	local line = lines[1]

	-- Check if it's a continuation marker
	if is_continuation_line(line) then
		-- Search backwards for the full annotation
		for i = cursor_line - 1, 1, -1 do
			local prev_lines = vim.api.nvim_buf_get_lines(self.buffer.handle, i - 1, i, false)
			if #prev_lines > 0 then
				local prev_line = prev_lines[1]
				-- Check if this is a full annotation line (not a continuation)
				if not is_continuation_line(prev_line) then
					-- Extract change ID (first word)
					local change_id = prev_line:match("^(%S+)")
					return change_id
				end
			end
		end
	else
		-- Extract change ID from the current line (first word)
		local change_id = line:match("^(%S+)")
		return change_id
	end

	return nil
end

---Open the change at cursor in a new buffer
function AnnotateBuffer:open_change_at_cursor()
	local change_id = self:get_change_id_at_cursor()

	if not change_id then
		vim.notify("No change ID at cursor", vim.log.levels.WARN)
		return
	end

	-- Save current window (annotation buffer)
	local annotation_winnr = vim.api.nvim_get_current_win()

	-- Find if there's already a status buffer window open
	local existing_status_winnr = nil
	for _, winnr in ipairs(vim.api.nvim_list_wins()) do
		local bufnr = vim.api.nvim_win_get_buf(winnr)
		if vim.api.nvim_buf_is_valid(bufnr) then
			local bufname = vim.api.nvim_buf_get_name(bufnr)
			if bufname:match("NeoJJ Status") then
				existing_status_winnr = winnr
				break
			end
		end
	end

	-- Switch to the source window so the status buffer opens there (not in the narrow annotation buffer)
	if vim.api.nvim_win_is_valid(self.source_winnr) then
		vim.api.nvim_set_current_win(self.source_winnr)
	end

	-- Use the StatusBuffer to show the change
	local StatusBuffer = require("neojj.buffers.status")
	local status_buffer = StatusBuffer.new(self.repo, change_id)

	if existing_status_winnr then
		-- If a status buffer is already open, just switch to it and refresh
		vim.api.nvim_set_current_win(existing_status_winnr)
		status_buffer.buffer:open("replace")
		status_buffer:refresh()
	else
		-- Otherwise, open in a new horizontal split
		status_buffer:show_split("horizontal")
	end

	-- Return focus to annotation buffer
	if vim.api.nvim_win_is_valid(annotation_winnr) then
		vim.api.nvim_set_current_win(annotation_winnr)
	end
end

---Copy the change ID at cursor to clipboard
function AnnotateBuffer:copy_change_id_at_cursor()
	local change_id = self:get_change_id_at_cursor()

	if not change_id then
		vim.notify("No change ID at cursor", vim.log.levels.WARN)
		return
	end

	-- Copy to clipboard (using + register for system clipboard)
	vim.fn.setreg("+", change_id)
	vim.notify("Copied change ID: " .. change_id, vim.log.levels.INFO)
end

---Show the annotation buffer
function AnnotateBuffer:show()
	-- First, ensure the source buffer is visible in a window
	local source_wins = vim.fn.win_findbuf(self.source_bufnr)
	if #source_wins == 0 then
		-- Open the source file in the current window
		vim.api.nvim_set_current_buf(self.source_bufnr)
		self.source_winnr = vim.api.nvim_get_current_win()
	else
		self.source_winnr = source_wins[1]
	end

	-- Switch to the source window before opening the annotation buffer
	vim.api.nvim_set_current_win(self.source_winnr)

	-- Open the annotation buffer as a vsplit
	self.buffer:open("vsplit")

	-- Move the annotation window to the left
	local annotation_winnr = vim.fn.bufwinid(self.buffer.handle)
	if annotation_winnr ~= -1 then
		vim.api.nvim_set_current_win(annotation_winnr)
		vim.cmd("wincmd H") -- Move to far left
		-- Set window width to 30 columns
		vim.api.nvim_win_set_width(annotation_winnr, 30)
		-- Return focus to source window
		vim.api.nvim_set_current_win(self.source_winnr)
	end
end

---Close the annotation buffer
function AnnotateBuffer:close()
	-- Disable scrollbind on source window
	if vim.api.nvim_win_is_valid(self.source_winnr) then
		vim.api.nvim_set_option_value("scrollbind", false, { win = self.source_winnr })
	end

	if self.buffer and self.buffer:is_valid() then
		self.buffer:close()
	end
end

---Clean up resources
function AnnotateBuffer:_cleanup()
	-- Disable scrollbind on source window if it still exists
	if vim.api.nvim_win_is_valid(self.source_winnr) then
		pcall(vim.api.nvim_set_option_value, "scrollbind", false, { win = self.source_winnr })
	end

	-- Clear the augroup
	pcall(vim.api.nvim_del_augroup_by_name, "neojj_annotate_" .. self.buffer.handle)
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function AnnotateBuffer:is_valid()
	return self.buffer:is_valid()
end

---Get buffer handle
---@return number handle Buffer handle
function AnnotateBuffer:get_handle()
	return self.buffer:get_handle()
end

return AnnotateBuffer
