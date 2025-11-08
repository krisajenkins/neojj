local Buffer = require("neojj.lib.buffer")
local StatusUI = require("neojj.buffers.status.ui")
local logger = require("neojj.logger")

---@class StatusBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field revision? string Optional revision to show (defaults to working copy)
---@field state table Current repository state
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

-- Singleton instance tracking
local instances = {}

---Create or get existing status buffer for a repository
---@param repo table Repository instance
---@param revision? string Optional revision to show (defaults to working copy)
---@return StatusBuffer status_buffer Status buffer instance
function StatusBuffer.new(repo, revision)
	local repo_key = vim.fs.normalize(repo.dir)
	if revision then
		repo_key = repo_key .. ":" .. revision
	end

	-- Return existing instance if available
	if instances[repo_key] and instances[repo_key]:is_valid() then
		return instances[repo_key]
	end

	local instance = setmetatable({
		repo = repo,
		revision = revision,
		state = {},
		expanded_files = {},
		show_help = false,
	}, StatusBuffer)

	-- Create buffer with fixed name (reuse if exists)
	local buffer_name = revision and ("NeoJJ Status: " .. revision:sub(1, 8)) or "NeoJJ Status"
	local buffer = Buffer.create({
		name = buffer_name,
		filetype = "neojj-status",
		kind = "replace", -- Default to replace current view
		modifiable = false,
		readonly = true,
		cwd = repo.dir,
		context_highlight = true,
		active_item_highlight = true,
		foldmarkers = true,
		disable_line_numbers = true,
		disable_relative_line_numbers = true,
		disable_signs = false,
		spell_check = false,
		mappings = {
			n = {
				["q"] = "<cmd>close<cr>",
				["<c-c>"] = "<cmd>close<cr>",
				["<esc>"] = "<cmd>close<cr>",
			},
		},
		autocmds = {
			{
				event = "BufWinEnter",
				callback = function()
					vim.cmd("setlocal cursorline")
				end,
			},
			{
				event = "BufWinLeave",
				callback = function()
					-- Save cursor position or state if needed
				end,
			},
		},
		render = function()
			-- This will be called during buffer:open()
			-- Return nil here since we'll call refresh separately
			return nil
		end,
		after = function()
			-- Additional setup after buffer is displayed
		end,
	})

	instance.buffer = buffer

	-- Add status-specific key mappings
	instance:_setup_mappings()

	-- Store instance for reuse
	instances[repo_key] = instance

	return instance
end

---Setup status-specific key mappings
function StatusBuffer:_setup_mappings()
	-- Refresh mapping
	self.buffer:map("n", "r", function()
		self:refresh()
	end, { desc = "Refresh status" })

	-- Ctrl-R also refreshes (like NeoGit)
	self.buffer:map("n", "<c-r>", function()
		self:refresh()
	end, { desc = "Refresh status" })

	-- Help mapping
	self.buffer:map("n", "?", function()
		self:toggle_help()
	end, { desc = "Toggle help" })

	-- Diff expansion
	self.buffer:map("n", "<tab>", function()
		self:toggle_file_diff()
	end, { desc = "Toggle file diff" })

	self.buffer:map("n", "<s-tab>", function()
		self:toggle_all_file_diffs()
	end, { desc = "Toggle all file diffs" })

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

	-- Create new change
	self.buffer:map("n", "n", function()
		self:create_new_change()
	end, { desc = "Create new change from current commit" })

	-- Navigation to other views
	self.buffer:map("n", "l", function()
		self:open_log_buffer()
	end, { desc = "Open log view" })

	-- Navigation
	self.buffer:map("n", "j", function()
		self:move_cursor_down()
	end, { desc = "Move cursor down" })

	self.buffer:map("n", "k", function()
		self:move_cursor_up()
	end, { desc = "Move cursor up" })
end

---Get commit data for a specific revision
---@param revision string Revision identifier
---@return table|nil working_copy Working copy data or nil on error
function StatusBuffer:get_revision_data(revision)
	local cli = require("neojj.lib.jj.cli")
	local json_parser = require("neojj.lib.jj.parsers.json_parser")

	-- Get commit data using JSON template
	local log_result =
		cli.log():arg("-r"):arg(revision):option("template", "json(self)"):flag("no-graph"):cwd(self.repo.dir):call()

	if not log_result.success then
		logger.warn("Failed to get revision data: " .. tostring(log_result.stderr))
		return nil
	end

	local log_json, err = json_parser.parse_log_json(log_result.stdout)
	if not log_json then
		logger.warn("Failed to parse revision JSON: " .. tostring(err))
		return nil
	end

	local working_copy = json_parser.json_to_working_copy(log_json)

	-- Get file list from diff
	local diff_result = cli.raw()
		:arg("diff")
		:arg("-r")
		:arg(revision)
		:option("summary", nil)
		:option("color", "never")
		:cwd(self.repo.dir)
		:call()

	if diff_result.success and diff_result.stdout then
		-- Parse diff summary to get file list
		local files = {}
		for line in diff_result.stdout:gmatch("[^\r\n]+") do
			-- Parse lines like "M path/to/file" or "A path/to/file"
			local status, path = line:match("^([MADR])%s+(.+)$")
			if status and path then
				table.insert(files, { status = status, path = path })
			end
		end
		working_copy.modified_files = files
	else
		working_copy.modified_files = {}
	end

	working_copy.conflicts = {}
	working_copy.is_empty = #working_copy.modified_files == 0

	return working_copy
end

---Refresh the status buffer
function StatusBuffer:refresh()
	logger.info("Refreshing status buffer" .. (self.revision and (" for revision: " .. self.revision) or ""))

	if not self.repo:is_jj_repo() then
		self:render_error("Not a JJ repository")
		return
	end

	local async = require("plenary.async")

	async.run(function()
		local working_copy

		if self.revision then
			-- Get data for specific revision
			working_copy = self:get_revision_data(self.revision)
			if not working_copy then
				vim.schedule(function()
					self:render_error("Failed to get data for revision: " .. self.revision)
				end)
				return
			end
		else
			-- Refresh repository state for working copy
			self.repo:refresh()

			-- Get current state
			working_copy = self.repo:get_working_copy()
		end

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

	local components
	if self.show_help then
		components = { StatusUI.create_help() }
	else
		components = StatusUI.create(self.state, self.expanded_files, self)
	end

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
---@param kind? string Display mode override
function StatusBuffer:show(kind)
	self.buffer:open(kind)
	self:refresh()
end

---Show the status buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function StatusBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:refresh()
end

---Show the status buffer in a new tab
function StatusBuffer:show_tab()
	self.buffer:open("tab")
	self:refresh()
end

---Close the status buffer
function StatusBuffer:close()
	self.buffer:close()
end

---Toggle help display
function StatusBuffer:toggle_help()
	self.show_help = not self.show_help
	self:render()
end

---Toggle file diff at cursor
function StatusBuffer:toggle_file_diff()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.path then
		return
	end

	local file_path = item.path
	local was_expanded = self.expanded_files[file_path] or false
	self.expanded_files[file_path] = not was_expanded

	-- If we're collapsing, we need to find the line where this file item starts
	-- so we can restore the cursor there after re-rendering
	local target_line = nil
	if was_expanded then
		-- Find the line number of the file item component
		-- The component_positions map uses 0-indexed line numbers
		for line_idx, comp in pairs(self.buffer.component_positions) do
			if comp:is_interactive() and comp:get_item() and comp:get_item().path == file_path then
				-- Convert to 1-indexed for cursor positioning
				target_line = line_idx + 1
				break
			end
		end
	end

	self:render()

	-- Restore cursor to the file item line if we collapsed
	if target_line then
		self.buffer:set_cursor(target_line, 0)
	end
end

---Toggle all file diffs
function StatusBuffer:toggle_all_file_diffs()
	local any_expanded = false
	for _, expanded in pairs(self.expanded_files) do
		if expanded then
			any_expanded = true
			break
		end
	end

	-- If any are expanded, collapse all. Otherwise, expand all.
	local new_state = not any_expanded

	-- Get all file paths from the current state
	if self.state.working_copy and self.state.working_copy.modified_files then
		for _, file in ipairs(self.state.working_copy.modified_files) do
			self.expanded_files[file.path] = new_state
		end
	end

	if self.state.working_copy and self.state.working_copy.conflicts then
		for _, file in ipairs(self.state.working_copy.conflicts) do
			self.expanded_files[file.path] = new_state
		end
	end

	self:render()
end

---Get diff for a file
---@param file_path string Path to the file
---@return string[] diff_lines Diff lines
function StatusBuffer:get_file_diff(file_path)
	local cli = require("neojj.lib.jj.cli")

	-- Create a diff command builder
	local builder = cli.raw():arg("diff"):option("color", "never"):flag("git")

	-- Add revision flag if showing a specific revision
	if self.revision then
		builder:arg("-r"):arg(self.revision)
	end

	builder:arg(file_path):cwd(self.repo.dir)

	local result = builder:call()

	if not result.success then
		logger.warn("Failed to get diff for file: " .. file_path .. " - " .. tostring(result.stderr))
		return { "Failed to get diff: " .. tostring(result.stderr) }
	end

	-- Split output into lines
	local lines = vim.split(result.stdout, "\n")
	-- Remove empty last line if present
	if #lines > 0 and lines[#lines] == "" then
		table.remove(lines, #lines)
	end

	return lines
end

---Open file at cursor
function StatusBuffer:open_file_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.path then
		return
	end

	-- Open the file in the current window
	vim.cmd("edit " .. vim.fn.fnameescape(item.path))
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
					self.buffer:open()
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
					self.buffer:open()
				end
			end, 100)
		end
	end

	local revision_to_describe = self.revision or "@"
	local describe_buffer = DescribeBuffer.new(self.repo, revision_to_describe, on_submit, on_abort)
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

---Open log buffer while keeping status buffer context
function StatusBuffer:open_log_buffer()
	local LogBuffer = require("neojj.buffers.log")

	-- Get or create log buffer (singleton pattern)
	local log_buffer = LogBuffer.new(self.repo)

	-- Show and refresh the log buffer
	log_buffer:show()
end

---Create a new change from the current commit
function StatusBuffer:create_new_change()
	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		-- Create new change from the current revision (or working copy if no revision specified)
		local builder = cli.new():cwd(self.repo.dir)
		if self.revision then
			builder:arg(self.revision)
		end
		local result = builder:call()

		vim.schedule(function()
			if result.success then
				vim.notify("Created new change", vim.log.levels.INFO)
				-- Refresh the status buffer
				self:refresh()
			else
				vim.notify("Failed to create new change: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
			end
		end)
	end)
end

return StatusBuffer
