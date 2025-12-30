local Buffer = require("neojj.lib.buffer")
local LogUI = require("neojj.buffers.log.ui")
local logger = require("neojj.logger")
local log_parser = require("neojj.lib.jj.parsers.log_parser")

---@class LogBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field state table Current log state
local LogBuffer = {}
LogBuffer.__index = LogBuffer

-- Singleton instance
local instance = nil

---Create or get existing log buffer
---@param repo table Repository instance
---@param options? table Log options
---@return LogBuffer log_buffer Log buffer instance
function LogBuffer.new(repo, options)
	options = options or {}

	-- Return existing instance if available and for same repo
	if instance and instance:is_valid() and instance.repo.dir == repo.dir then
		-- Update options on existing instance
		instance.options = options
		return instance
	end

	local new_instance = setmetatable({
		repo = repo,
		state = {
			revisions = {},
			graph_data = {},
		},
		options = options,
		show_help = false,
		expanded_revisions = {},
	}, LogBuffer)

	-- Create buffer with fixed name (reuse if exists)
	local buffer = Buffer.create({
		name = "NeoJJ Log",
		filetype = "neojj-log",
		kind = "replace", -- Default to replace current view
		modifiable = false,
		readonly = true,
		cwd = repo.dir,
		context_highlight = true,
		active_item_highlight = true,
		foldmarkers = false,
		disable_line_numbers = true,
		disable_relative_line_numbers = true,
		disable_signs = false,
		spell_check = false,
		mappings = {
			n = {
				["q"] = "<cmd>bdelete<cr>",
				["<c-c>"] = "<cmd>bdelete<cr>",
				["<esc>"] = "<cmd>bdelete<cr>",
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

	new_instance.buffer = buffer

	-- Add log-specific key mappings
	new_instance:_setup_mappings()

	-- Store as singleton instance
	instance = new_instance

	return new_instance
end

---Setup log-specific key mappings
function LogBuffer:_setup_mappings()
	-- Refresh mapping
	self.buffer:map("n", "r", function()
		self:refresh()
	end, { desc = "Refresh log" })

	-- Ctrl-R also refreshes
	self.buffer:map("n", "<c-r>", function()
		self:refresh()
	end, { desc = "Refresh log" })

	-- Help mapping
	self.buffer:map("n", "?", function()
		self:toggle_help()
	end, { desc = "Toggle help" })

	-- Show commit details
	self.buffer:map("n", "<cr>", function()
		self:show_commit_at_cursor()
	end, { desc = "Show commit details" })

	-- Show diff for commit
	self.buffer:map("n", "d", function()
		self:show_diff_at_cursor()
	end, { desc = "Show commit diff" })

	-- Navigation to other views
	self.buffer:map("n", "s", function()
		self:open_status_buffer()
	end, { desc = "Open status view" })

	-- Create new change
	self.buffer:map("n", "n", function()
		self:create_new_change()
	end, { desc = "Create new change after cursor" })

	-- Navigation
	self.buffer:map("n", "j", function()
		self:move_cursor_down()
	end, { desc = "Move cursor down" })

	self.buffer:map("n", "k", function()
		self:move_cursor_up()
	end, { desc = "Move cursor up" })

	-- Toggle expanded details
	self.buffer:map("n", "<tab>", function()
		self:toggle_revision_expanded()
	end, { desc = "Toggle revision details" })
end

---Refresh the log buffer
function LogBuffer:refresh()
	logger.info("Refreshing log buffer")

	if not self.repo:is_jj_repo() then
		self:render_error("Not a JJ repository")
		return
	end

	local async = require("plenary.async")

	async.run(function()
		-- Get log data
		local log_data = self:get_log_data()

		self.state = {
			revisions = log_data.revisions,
			graph_data = log_data.graph_data,
			raw_lines = log_data.raw_lines,
		}

		-- Render the UI only if buffer is still valid
		vim.schedule(function()
			if self.buffer and self.buffer:is_valid() then
				self:render()
			else
				logger.debug("Log buffer is no longer valid, skipping render")
			end
		end)
	end)
end

---Get log data from jj
---@return table log_data Log data with revisions and graph info
function LogBuffer:get_log_data()
	local cli = require("neojj.lib.jj.cli")

	-- Get log with default template, no color, limited to reasonable amount
	local limit = self.options.limit or 10
	local revisions = self.options.revisions or "::"

	local builder = cli.log():short_flag("r"):arg(revisions):option("limit", tostring(limit)):cwd(self.repo.dir)

	local result = builder:call()

	logger.debug("Log command result - success: " .. tostring(result.success))
	logger.debug("Log command stdout length: " .. (result.stdout and #result.stdout or 0))
	if result.stdout then
		logger.debug("Log command stdout preview: " .. result.stdout:sub(1, 200))
	end
	if result.stderr then
		logger.debug("Log command stderr: " .. result.stderr)
	end

	if not result.success then
		logger.warn("Failed to get log: " .. tostring(result.stderr))
		return {
			revisions = {},
			graph_data = {},
		}
	end

	-- Parse the log output
	local parsed = log_parser.parse_log_output(result.stdout)

	-- Sanitize raw_lines to ensure no embedded newlines
	if parsed.raw_lines then
		for i, line in ipairs(parsed.raw_lines) do
			parsed.raw_lines[i] = line:gsub("\n", " "):gsub("\r", "")
		end
	end

	logger.debug(
		"Parsed log data - revisions: "
			.. #parsed.revisions
			.. ", graph_data entries: "
			.. vim.tbl_count(parsed.graph_data)
	)
	return parsed
end

---Render the log UI
function LogBuffer:render()
	if not self.buffer or not self.buffer:is_valid() then
		logger.debug("Cannot render: log buffer is invalid")
		return
	end

	local components
	if self.show_help then
		components = { LogUI.create_help() }
		logger.debug("Rendering help with " .. #components .. " components")
	else
		components = LogUI.create(self.state, self)
		logger.debug(
			"Rendering log UI with "
				.. #components
				.. " components from state with "
				.. #self.state.revisions
				.. " revisions"
		)
	end

	self.buffer:render(components)
end

---Render an error message
---@param message string Error message
function LogBuffer:render_error(message)
	local Ui = require("neojj.lib.ui")
	local components = {
		Ui.text("Error: " .. message, { highlight = "ErrorMsg" }),
		Ui.empty_line(),
		Ui.text("Press q to quit", { highlight = "NeoJJHelpText" }),
	}
	self.buffer:render(components)
end

---Show the log buffer
---@param kind? string Display mode override
function LogBuffer:show(kind)
	self.buffer:open(kind)
	self:refresh()
end

---Show the log buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function LogBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:refresh()
end

---Show the log buffer in a new tab
function LogBuffer:show_tab()
	self.buffer:open("tab")
	self:refresh()
end

---Close the log buffer
function LogBuffer:close()
	self.buffer:close()
end

---Toggle help display
function LogBuffer:toggle_help()
	self.show_help = not self.show_help
	self:render()
end

---Show commit details at cursor
function LogBuffer:show_commit_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.change_id then
		return
	end

	-- Open status view for this commit
	local StatusBuffer = require("neojj.buffers.status")
	local status_buffer = StatusBuffer.new(self.repo, item.change_id)
	status_buffer:show()
end

---Show diff for commit at cursor
function LogBuffer:show_diff_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.change_id then
		return
	end

	-- TODO: Implement diff view
	print("Show diff for commit: " .. item.change_id)
end

---Move cursor down
function LogBuffer:move_cursor_down()
	local line, col = unpack(self.buffer:get_cursor())
	local line_count = vim.api.nvim_buf_line_count(self.buffer.handle)

	if line < line_count then
		self.buffer:set_cursor(line + 1, col)
	end
end

---Move cursor up
function LogBuffer:move_cursor_up()
	local line, col = unpack(self.buffer:get_cursor())

	if line > 1 then
		self.buffer:set_cursor(line - 1, col)
	end
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function LogBuffer:is_valid()
	return self.buffer:is_valid()
end

---Get buffer handle
---@return number handle Buffer handle
function LogBuffer:get_handle()
	return self.buffer:get_handle()
end

---Open status buffer while keeping log buffer context
function LogBuffer:open_status_buffer()
	local StatusBuffer = require("neojj.buffers.status")

	-- Get or create status buffer (singleton pattern)
	local status_buffer = StatusBuffer.new(self.repo)

	-- Show and refresh the status buffer
	status_buffer:show()
end

---Create a new change after the commit at cursor
function LogBuffer:create_new_change()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		vim.notify("No commit at cursor", vim.log.levels.WARN)
		return
	end

	local item = component:get_item()
	if not item or not item.change_id then
		vim.notify("No commit at cursor", vim.log.levels.WARN)
		return
	end

	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		-- Create new change after the selected revision
		local builder = cli.new():arg(item.change_id):cwd(self.repo.dir)
		local result = builder:call()

		vim.schedule(function()
			if result.success then
				vim.notify("Created new change after " .. item.change_id:sub(1, 8), vim.log.levels.INFO)
				-- Refresh the log buffer
				self:refresh()
			else
				vim.notify("Failed to create new change: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
			end
		end)
	end)
end

---Toggle expanded state for revision at cursor
function LogBuffer:toggle_revision_expanded()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.change_id then
		return
	end

	local change_id = item.change_id
	local was_expanded = self.expanded_revisions[change_id] or false
	self.expanded_revisions[change_id] = not was_expanded

	-- Find the line number to restore cursor to when collapsing
	local target_line = nil
	if was_expanded then
		for line_idx, comp in pairs(self.buffer.component_positions or {}) do
			if comp:is_interactive() and comp:get_item() and comp:get_item().change_id == change_id then
				target_line = line_idx + 1 -- Convert to 1-indexed
				break
			end
		end
	end

	self:render()

	-- Restore cursor to the commit line if we collapsed
	if target_line then
		self.buffer:set_cursor(target_line, 0)
	end
end

---Get detailed info for a revision (description + stats)
---@param change_id string The change ID to get details for
---@return table details Table with description and stats lines
function LogBuffer:get_revision_details(change_id)
	local cli = require("neojj.lib.jj.cli")

	-- Get log with stats for this specific revision
	local builder = cli.log():short_flag("r"):arg(change_id):flag("stat"):flag("no-graph"):cwd(self.repo.dir)
	local result = builder:call()

	if not result.success then
		logger.warn("Failed to get revision details: " .. tostring(result.stderr))
		return { description = {}, stats = {} }
	end

	-- Parse the output
	local lines = vim.split(result.stdout, "\n")
	local description = {}
	local stats = {}
	local in_stats = false

	-- Skip the first line (commit header) and parse the rest
	for i = 2, #lines do
		local line = lines[i]
		-- Stats lines typically contain | and +/- characters, or are the summary line
		if line:match("|.*[%+%-]") or line:match("^%d+ files? changed") then
			in_stats = true
			table.insert(stats, line)
		elseif not in_stats and line ~= "" then
			table.insert(description, line)
		end
	end

	return { description = description, stats = stats }
end

return LogBuffer
