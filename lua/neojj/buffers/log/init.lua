local Buffer = require("neojj.lib.buffer")
local LogUI = require("neojj.buffers.log.ui")
local logger = require("neojj.logger")

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

	-- Navigation
	self.buffer:map("n", "j", function()
		self:move_cursor_down()
	end, { desc = "Move cursor down" })

	self.buffer:map("n", "k", function()
		self:move_cursor_up()
	end, { desc = "Move cursor up" })
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

	logger.info("Log command result - success: " .. tostring(result.success))
	logger.info("Log command stdout length: " .. (result.stdout and #result.stdout or 0))
	if result.stdout then
		logger.info("Log command stdout preview: " .. result.stdout:sub(1, 200))
	end
	if result.stderr then
		logger.info("Log command stderr: " .. result.stderr)
	end

	if not result.success then
		logger.warn("Failed to get log: " .. tostring(result.stderr))
		return {
			revisions = {},
			graph_data = {},
		}
	end

	-- Parse the log output
	local parsed = self:parse_log_output(result.stdout)
	
	-- Sanitize raw_lines to ensure no embedded newlines
	if parsed.raw_lines then
		for i, line in ipairs(parsed.raw_lines) do
			parsed.raw_lines[i] = line:gsub("\n", " "):gsub("\r", "")
		end
	end
	
	logger.info("Parsed log data - revisions: " .. #parsed.revisions .. ", graph_data entries: " .. vim.tbl_count(parsed.graph_data))
	return parsed
end

---Parse jj log output into structured data
---@param output string Raw jj log output
---@return table parsed_data Parsed log data
function LogBuffer:parse_log_output(output)
	local lines = vim.split(output, "\n")
	local revisions = {}
	local graph_data = {}

	local current_revision = nil

	for i, line in ipairs(lines) do
		if line == "" then
			-- Skip empty lines
			goto continue
		end

		-- Check if this is a commit line (starts with @ or ○ and contains commit info)
		local graph_part, commit_info = line:match("^([│@○◆%s├└┤┬┴─┌┐┘]*)(.*)")

		-- Check if this line has commit data (change_id, author, timestamp, commit_id)
		local change_id, author, timestamp, commit_id = nil, nil, nil, nil
		if commit_info and commit_info ~= "" then
			change_id, author, timestamp, commit_id = commit_info:match("^%s*(%S+)%s+(%S+@%S+)%s+([%d%-:T%s]+)%s+(%S+)")
		end

		if change_id and author and timestamp and commit_id then
			-- This is a commit header line with actual commit data
			if current_revision then
				-- Save previous revision
				table.insert(revisions, current_revision)
			end

			current_revision = {
				change_id = change_id,
				author = author,
				timestamp = timestamp,
				commit_id = commit_id,
				description = "",
				graph = graph_part,
				line_number = i,
			}

			-- Store graph information
			graph_data[i] = {
				graph = graph_part,
				revision = current_revision,
			}
		else
			-- This is a description line or graph continuation
			if current_revision then
				local desc_part = line:match("^[│%s]*(.+)")
				if desc_part and desc_part ~= "" then
					-- Only capture the first line of description for metadata
					-- The UI will render all lines from raw_lines anyway
					if current_revision.description == "" then
						current_revision.description = desc_part
					end
					-- Don't concatenate with \n - let UI handle multiline from raw_lines
				end
			end

			-- Store graph line even if no commit info
			if graph_part then
				graph_data[i] = {
					graph = graph_part,
					revision = nil,
				}
			end
		end

		::continue::
	end

	-- Don't forget the last revision
	if current_revision then
		table.insert(revisions, current_revision)
	end

	return {
		revisions = revisions,
		graph_data = graph_data,
		raw_lines = lines,
	}
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
		logger.info("Rendering help with " .. #components .. " components")
	else
		components = LogUI.create(self.state, self)
		logger.info("Rendering log UI with " .. #components .. " components from state with " .. #self.state.revisions .. " revisions")
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

	-- TODO: Implement commit details view
	print("Show details for commit: " .. item.change_id)
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

return LogBuffer
