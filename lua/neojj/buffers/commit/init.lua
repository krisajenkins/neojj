local Buffer = require("neojj.lib.buffer")
local CommitUI = require("neojj.buffers.commit.ui")
local logger = require("neojj.logger")

---@class CommitBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field commit_id string Commit identifier
---@field state table Current commit state
local CommitBuffer = {}
CommitBuffer.__index = CommitBuffer

-- Singleton instance
local instance = nil

---Create or get existing commit buffer
---@param repo table Repository instance
---@param commit_id string Commit identifier (change_id or commit_id)
---@param options? table Commit options
---@return CommitBuffer commit_buffer Commit buffer instance
function CommitBuffer.new(repo, commit_id, options)
	options = options or {}

	-- Return existing instance if available and for same repo/commit
	if instance and instance:is_valid() and instance.repo.dir == repo.dir and instance.commit_id == commit_id then
		-- Update options on existing instance
		instance.options = options
		return instance
	end

	local new_instance = setmetatable({
		repo = repo,
		commit_id = commit_id,
		state = {
			commit_data = {},
			files = {},
			diff_data = {},
		},
		options = options,
		show_help = false,
		expanded_files = {},
	}, CommitBuffer)

	-- Create buffer with fixed name pattern
	local buffer_name = "NeoJJ Commit: " .. commit_id:sub(1, 8)
	local buffer = Buffer.create({
		name = buffer_name,
		filetype = "neojj-commit",
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

	-- Add commit-specific key mappings
	new_instance:_setup_mappings()

	-- Store as singleton instance
	instance = new_instance

	return new_instance
end

---Setup commit-specific key mappings
function CommitBuffer:_setup_mappings()
	-- Refresh mapping
	self.buffer:map("n", "r", function()
		self:refresh()
	end, { desc = "Refresh commit" })

	-- Ctrl-R also refreshes
	self.buffer:map("n", "<c-r>", function()
		self:refresh()
	end, { desc = "Refresh commit" })

	-- Help mapping
	self.buffer:map("n", "?", function()
		self:toggle_help()
	end, { desc = "Toggle help" })

	-- Open file at cursor
	self.buffer:map("n", "<cr>", function()
		self:open_file_at_cursor()
	end, { desc = "Open file" })

	-- Toggle diff for file at cursor
	self.buffer:map("n", "<tab>", function()
		self:toggle_diff_at_cursor()
	end, { desc = "Toggle file diff" })

	-- Toggle all file diffs
	self.buffer:map("n", "<s-tab>", function()
		self:toggle_all_file_diffs()
	end, { desc = "Toggle all file diffs" })

	-- Show full diff
	self.buffer:map("n", "d", function()
		self:show_full_diff()
	end, { desc = "Show full diff" })

	-- Navigation back to log
	self.buffer:map("n", "b", function()
		self:back_to_log()
	end, { desc = "Back to log" })

	-- Navigation to other views
	self.buffer:map("n", "s", function()
		self:open_status_buffer()
	end, { desc = "Open status view" })

	self.buffer:map("n", "l", function()
		self:open_log_buffer()
	end, { desc = "Open log view" })

	-- Enhanced navigation
	self.buffer:map("n", "j", function()
		self:move_cursor_down()
	end, { desc = "Move cursor down" })

	self.buffer:map("n", "k", function()
		self:move_cursor_up()
	end, { desc = "Move cursor up" })
end

---Refresh the commit buffer
function CommitBuffer:refresh()
	logger.info("Refreshing commit buffer for commit: " .. self.commit_id)

	if not self.repo:is_jj_repo() then
		self:render_error("Not a JJ repository")
		return
	end

	local async = require("plenary.async")

	async.run(function()
		-- Get commit data
		local commit_data = self:get_commit_data()

		self.state = {
			commit_data = commit_data.commit_data,
			files = commit_data.files,
			diff_data = commit_data.diff_data,
		}

		-- Render the UI only if buffer is still valid
		vim.schedule(function()
			if self.buffer and self.buffer:is_valid() then
				self:render()
			else
				logger.debug("Commit buffer is no longer valid, skipping render")
			end
		end)
	end)
end

---Get commit data from jj show
---@return table commit_data Commit data with metadata, files, and diff
function CommitBuffer:get_commit_data()
	local cli = require("neojj.lib.jj.cli")

	-- Get commit details with jj show
	local result = cli.show()
		:arg(self.commit_id)
		:cwd(self.repo.dir)
		:call()

	logger.debug("Commit show command result - success: " .. tostring(result.success))
	logger.debug("Commit show stdout length: " .. (result.stdout and #result.stdout or 0))
	if result.stdout then
		logger.debug("Commit show stdout preview: " .. result.stdout:sub(1, 200))
	end
	if result.stderr then
		logger.debug("Commit show stderr: " .. result.stderr)
	end

	if not result.success then
		logger.warn("Failed to get commit data: " .. tostring(result.stderr))
		return {
			commit_data = {},
			files = {},
			diff_data = {},
		}
	end

	-- Parse the show output
	local parsed = self:parse_show_output(result.stdout)

	logger.debug(
		"Parsed commit data - files: "
			.. #parsed.files
			.. ", diff lines: "
			.. #parsed.diff_data
	)
	return parsed
end

---Parse jj show output into structured data
---@param output string Raw jj show output
---@return table parsed_data Parsed commit data
function CommitBuffer:parse_show_output(output)
	local lines = vim.split(output, "\n")
	local commit_data = {}
	local files = {}
	local diff_data = {}

	local in_diff = false
	local current_file = nil
	local current_file_diff = {}

	for i, line in ipairs(lines) do
		if line == "" then
			-- Skip empty lines in header, but preserve in diff
			if in_diff then
				table.insert(diff_data, line)
				if current_file then
					table.insert(current_file_diff, line)
				end
			end
			goto continue
		end

		-- Parse commit metadata (before diff starts)
		if not in_diff then
			-- Extract commit metadata
			local change_id = line:match("^Change ID: (%S+)")
			local commit_id = line:match("^Commit ID: (%S+)")
			local author = line:match("^Author: (.+)")
			local committer = line:match("^Committer: (.+)")
			local timestamp = line:match("^Date: (.+)")

			if change_id then
				commit_data.change_id = change_id
			elseif commit_id then
				commit_data.commit_id = commit_id
			elseif author then
				commit_data.author = author
			elseif committer then
				commit_data.committer = committer
			elseif timestamp then
				commit_data.date = timestamp
			elseif line:match("^%s*$") then -- luacheck: ignore 542
				-- Skip empty lines
			elseif line:match("^diff ") then
				-- Start of diff section
				in_diff = true
				table.insert(diff_data, line)
			else
				-- This might be description text
				if not commit_data.description then
					commit_data.description = line
				else
					commit_data.description = commit_data.description .. "\n" .. line
				end
			end
		else
			-- We're in the diff section
			table.insert(diff_data, line)

			-- Track file changes
			local file_path = line:match("^diff %-%-git a/.+ b/(.+)$")
			if file_path then
				-- New file diff starting
				if current_file then
					-- Save previous file's diff
					current_file.diff = current_file_diff
				end
				current_file = {
					path = file_path,
					status = "M", -- Default to modified, will be refined
				}
				current_file_diff = { line }
				table.insert(files, current_file)
			elseif current_file then
				table.insert(current_file_diff, line)

				-- Detect file status from diff headers
				if line:match("^new file mode") then
					current_file.status = "A"
				elseif line:match("^deleted file mode") then
					current_file.status = "D"
				elseif line:match("^rename from") then
					current_file.status = "R"
				end
			end
		end

		::continue::
	end

	-- Don't forget the last file's diff
	if current_file then
		current_file.diff = current_file_diff
	end

	return {
		commit_data = commit_data,
		files = files,
		diff_data = diff_data,
	}
end

---Render the commit UI
function CommitBuffer:render()
	if not self.buffer or not self.buffer:is_valid() then
		logger.debug("Cannot render: commit buffer is invalid")
		return
	end

	local components
	if self.show_help then
		components = { CommitUI.create_help() }
		logger.debug("Rendering help with " .. #components .. " components")
	else
		components = CommitUI.create(self.state, self.expanded_files, self)
		logger.debug(
			"Rendering commit UI with "
				.. #components
				.. " components from state with "
				.. #self.state.files
				.. " files"
		)
	end

	self.buffer:render(components)
end

---Render an error message
---@param message string Error message
function CommitBuffer:render_error(message)
	local Ui = require("neojj.lib.ui")
	local components = {
		Ui.text("Error: " .. message, { highlight = "ErrorMsg" }),
		Ui.empty_line(),
		Ui.text("Press q to quit", { highlight = "NeoJJHelpText" }),
	}
	self.buffer:render(components)
end

---Show the commit buffer
---@param kind? string Display mode override
function CommitBuffer:show(kind)
	self.buffer:open(kind)
	self:refresh()
end

---Show the commit buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function CommitBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:refresh()
end

---Show the commit buffer in a new tab
function CommitBuffer:show_tab()
	self.buffer:open("tab")
	self:refresh()
end

---Close the commit buffer
function CommitBuffer:close()
	self.buffer:close()
end

---Toggle help display
function CommitBuffer:toggle_help()
	self.show_help = not self.show_help
	self:render()
end

---Open file at cursor
function CommitBuffer:open_file_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.path then
		return
	end

	-- Open file in new buffer
	local file_path = self.repo.dir .. "/" .. item.path
	vim.cmd("edit " .. vim.fn.fnameescape(file_path))
end

---Toggle diff display for file at cursor
function CommitBuffer:toggle_diff_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if not component or not component:is_interactive() then
		return
	end

	local item = component:get_item()
	if not item or not item.path then
		return
	end

	-- Toggle expanded state for this file
	local file_path = item.path
	self.expanded_files = self.expanded_files or {}
	self.expanded_files[file_path] = not (self.expanded_files[file_path] or false)

	-- Re-render to show/hide diff
	self:render()
end

---Toggle all file diffs
function CommitBuffer:toggle_all_file_diffs()
	if not self.state.files then
		return
	end

	-- Check if any files are currently expanded
	local any_expanded = false
	for _, file in ipairs(self.state.files) do
		if self.expanded_files[file.path] then
			any_expanded = true
			break
		end
	end

	-- If any are expanded, collapse all. Otherwise, expand all.
	local new_state = not any_expanded
	for _, file in ipairs(self.state.files) do
		self.expanded_files[file.path] = new_state
	end

	-- Re-render to show/hide all diffs
	self:render()
end

---Show full diff in separate buffer
function CommitBuffer:show_full_diff()
	-- TODO: Implement full diff view
	print("Show full diff for commit: " .. self.commit_id)
end

---Navigate back to log view
function CommitBuffer:back_to_log()
	local LogBuffer = require("neojj.buffers.log")
	local log_buffer = LogBuffer.new(self.repo)
	log_buffer:show()
end

---Move cursor down
function CommitBuffer:move_cursor_down()
	local line, col = unpack(self.buffer:get_cursor())
	local line_count = vim.api.nvim_buf_line_count(self.buffer.handle)

	if line < line_count then
		self.buffer:set_cursor(line + 1, col)
	end
end

---Move cursor up
function CommitBuffer:move_cursor_up()
	local line, col = unpack(self.buffer:get_cursor())

	if line > 1 then
		self.buffer:set_cursor(line - 1, col)
	end
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function CommitBuffer:is_valid()
	return self.buffer:is_valid()
end

---Get buffer handle
---@return number handle Buffer handle
function CommitBuffer:get_handle()
	return self.buffer:get_handle()
end

---Open status buffer while keeping commit buffer context
function CommitBuffer:open_status_buffer()
	local StatusBuffer = require("neojj.buffers.status")
	local status_buffer = StatusBuffer.new(self.repo)
	status_buffer:show()
end

---Open log buffer while keeping commit buffer context
function CommitBuffer:open_log_buffer()
	local LogBuffer = require("neojj.buffers.log")
	local log_buffer = LogBuffer.new(self.repo)
	log_buffer:show()
end

return CommitBuffer
