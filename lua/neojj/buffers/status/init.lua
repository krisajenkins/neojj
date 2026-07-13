local Buffer = require("neojj.lib.buffer")
local StatusUI = require("neojj.buffers.status.ui")
local logger = require("neojj.logger")
local action = require("neojj.lib.jj.action")

---@class StatusBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field revision? string Optional revision to show (defaults to working copy)
---@field state table Current repository state
---@field expanded_files table<string, { diff: string[] }> Cached diff per expanded file, keyed by "<section>:<path>" (absent when collapsed)
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

-- Singleton instance tracking
local instances = {}

---Return the currently-valid status buffer instances tracked by this module.
---
---Lets callers outside this module (e.g. the top-level :JJ describe handler)
---refresh and re-focus an open status view without reaching into the private
---`instances` map or scanning buffers by name.
---@return StatusBuffer[] instances Valid status buffer instances
function StatusBuffer.list_instances()
	local result = {}
	for _, inst in pairs(instances) do
		if inst:is_valid() then
			table.insert(result, inst)
		end
	end
	return result
end

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

	-- Create buffer with a per-repo namespaced name (reuse if exists). Two
	-- different repos must not share the same underlying buffer, otherwise the
	-- second repo's mappings clobber the first's.
	local util = require("neojj.lib.jj.util")
	local id = util.repo_namespace(repo)
	local buffer_name = revision and ("NeoJJ Status (" .. id .. "): " .. revision:sub(1, 8))
		or ("NeoJJ Status (" .. id .. ")")
	local buffer = Buffer.create({
		name = buffer_name,
		filetype = "neojj-status",
		kind = "replace", -- Default to replace current view
		modifiable = false,
		readonly = true,
		-- Stay alive when a drilled-into frame (a file, or another view) replaces
		-- us in the window, so the view stack can reveal us again on pop.
		bufhidden = "hide",
		cwd = repo.dir,
		context_highlight = true,
		active_item_highlight = true,
		foldmarkers = true,
		disable_line_numbers = true,
		disable_relative_line_numbers = true,
		disable_signs = false,
		spell_check = false,
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
		-- Drop the module-level instance when the buffer is wiped so a later
		-- StatusBuffer.new for the same repo rebuilds a fresh instance instead of
		-- handing back one whose underlying buffer is gone.
		on_detach = function()
			instances[repo_key] = nil
			-- Tear the auto-refresh watcher down once no view for this root remains.
			require("neojj.lib.watcher").cleanup(repo:get_root())
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
	-- Pop one frame off the view stack, revealing the view drilled down from
	-- (e.g. the log). Only when this view is the last frame does it close.
	for _, key in ipairs({ "q", "<esc>", "<c-c>" }) do
		self.buffer:map("n", key, function()
			self:go_back()
		end, { desc = "Back (pop view stack) / close status" })
	end

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

	-- Commit: describe @ then jj new (land on a fresh empty working copy)
	self.buffer:map("n", "c", function()
		self:commit_change()
	end, { desc = "Commit change (describe @ + jj new)" })

	-- Create new change
	self.buffer:map("n", "n", function()
		self:create_new_change()
	end, { desc = "Create new change from current commit" })

	-- Run jj fix on the working copy
	self.buffer:map("n", "f", function()
		self:fix()
	end, { desc = "Run jj fix (format working copy)" })

	-- Tug: advance the closest bookmark up to @
	self.buffer:map("n", "t", function()
		self:tug()
	end, { desc = "Tug: advance closest bookmark to @" })

	-- Push to the remote (jj git push)
	self.buffer:map("n", "P", function()
		self:push()
	end, { desc = "Push to remote (jj git push)" })

	-- Pull (fetch) from the remote (jj git fetch)
	self.buffer:map("n", "p", function()
		self:fetch()
	end, { desc = "Pull from remote (jj git fetch)" })

	-- Navigation to other views
	self.buffer:map("n", "l", function()
		self:open_log_buffer()
	end, { desc = "Open log view" })

	self.buffer:map("n", "o", function()
		self:open_oplog_buffer()
	end, { desc = "Open operation log view" })
end

---Get commit data for a specific revision using jj show
---@param revision string Revision identifier
---@return table|nil working_copy Working copy data or nil on error
function StatusBuffer:get_revision_data(revision)
	local cli = require("neojj.lib.jj.cli")

	-- Get commit details with jj show (includes metadata and diffs).
	-- Force git-format diffs so parse_show_output recognises the file headers
	-- regardless of the user's configured default diff format (e.g. color-words).
	local result = cli.show():arg(revision):flag("git"):cwd(self.repo.dir):call_async()

	if not result.success then
		logger.warn("Failed to get revision data: " .. tostring(result.stderr))
		return nil
	end

	-- Parse the show output
	local parsed = self:parse_show_output(result.stdout)

	return parsed
end

---Parse jj show output into working copy data structure
---@param output string Raw jj show output
---@return table working_copy Parsed working copy data
function StatusBuffer:parse_show_output(output)
	local lines = vim.split(output, "\n")
	local working_copy = {
		change_id = nil,
		commit_id = nil,
		description = nil,
		author = nil,
		committer = nil,
		date = nil,
		modified_files = {},
		conflicts = {},
		is_empty = true,
	}
	local files = {}

	local in_diff = false
	local current_file = nil
	local current_file_diff = {}

	for _, line in ipairs(lines) do
		-- Parse commit metadata (before diff starts)
		if not in_diff then
			-- Skip empty lines only before we've started collecting description
			if line == "" and not working_copy.description then
				goto continue
			end
			local change_id = line:match("^Change ID: (%S+)")
			local commit_id = line:match("^Commit ID: (%S+)")
			local author = line:match("^Author%s*:%s*(.+)")
			local committer = line:match("^Committer%s*:%s*(.+)")
			local date = line:match("^[Dd]ate%s*:%s*(.+)")

			if change_id then
				working_copy.change_id = change_id
			elseif commit_id then
				working_copy.commit_id = commit_id
			elseif author then
				working_copy.author = author
			elseif committer then
				working_copy.committer = committer
			elseif date then
				working_copy.date = date
			elseif line:match("^%s*$") and not working_copy.description then -- luacheck: ignore (intentionally empty)
				-- Skip whitespace-only lines before description starts
			elseif line:match("^diff ") then
				-- Start of diff section
				in_diff = true

				-- Extract file path from this first diff line
				local file_path = line:match("^diff %-%-git a/.+ b/(.+)$")
				if file_path then
					current_file = {
						path = file_path,
						status = "M", -- Default to modified
						diff = { line },
					}
					current_file_diff = { line }
					table.insert(files, current_file)
				end
			else
				-- This is description text
				if not working_copy.description then
					working_copy.description = line
				else
					working_copy.description = working_copy.description .. "\n" .. line
				end
			end
		else
			-- We're in the diff section
			local file_path = line:match("^diff %-%-git a/.+ b/(.+)$")
			if file_path then
				-- New file diff starting
				if current_file then
					current_file.diff = current_file_diff
				end
				current_file = {
					path = file_path,
					status = "M",
					diff = { line },
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

	-- Save last file's diff
	if current_file then
		current_file.diff = current_file_diff
	end

	working_copy.modified_files = files
	working_copy.is_empty = #files == 0

	return working_copy
end

---Refresh the status buffer
function StatusBuffer:refresh()
	logger.info("Refreshing status buffer" .. (self.revision and (" for revision: " .. self.revision) or ""))

	if not self.repo:is_jj_repo() then
		self.buffer:render_error("Not a JJ repository")
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
					self.buffer:render_error("Failed to get data for revision: " .. self.revision)
				end)
				return
			end
		else
			-- Refresh repository state for working copy
			local ok, err = self.repo:refresh()
			if not ok then
				vim.schedule(function()
					self.buffer:render_error("Failed to refresh status: " .. tostring(err))
				end)
				return
			end

			-- Get current state
			working_copy = self.repo:get_working_copy()
		end

		self.state = {
			working_copy = working_copy,
		}

		-- Re-fetch cached diffs for any files that are currently expanded so the
		-- rendered diff stays in sync with the freshly-refreshed working copy.
		-- We're already in the async context here, so these calls yield rather
		-- than block the UI thread.
		for key in pairs(self.expanded_files) do
			-- Keys are "<section>:<path>"; strip the section prefix to recover the
			-- bare path get_file_diff expects. Section names never contain a colon,
			-- so splitting on the first colon is unambiguous.
			local path = key:match("^[^:]*:(.*)$") or key
			self.expanded_files[key] = { diff = self:get_file_diff(path) }
		end

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

---Register this view as the top frame of the drill-down view stack.
---
---Called from every display entry point so navigating into the status view
---(from the log, or via `:JJ status`) stacks it as a live frame. Uses the same
---buffer, so revisiting the view moves the existing frame to the top rather
---than duplicating it.
function StatusBuffer:_push_frame()
	-- Arm the external-change watcher for this repo. _push_frame is the single
	-- choke point every display path routes through, and ensure() is idempotent.
	require("neojj.lib.watcher").ensure(self.repo)
	require("neojj.lib.view_stack").push(self.buffer:get_handle(), {
		teardown = function()
			self:close()
		end,
	})
end

---Go back: pop this frame off the view stack, revealing the frame beneath. If
---this view is not the current stack top (an unexpected state), close it.
function StatusBuffer:go_back()
	local view_stack = require("neojj.lib.view_stack")
	local top = view_stack.top()
	if top and top.bufnr == self.buffer:get_handle() then
		view_stack.pop()
	else
		self.buffer:close()
	end
end

---Show the status buffer
---@param kind? string Display mode override
function StatusBuffer:show(kind)
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

---Show the status buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function StatusBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

---Show the status buffer in a new tab
function StatusBuffer:show_tab()
	self.buffer:open("tab")
	self:_push_frame()
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
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.path then
		return
	end

	local file_path = item.path
	-- expanded_files is keyed by "<section>:<path>" so a file that appears in both
	-- the Modified and Conflicts sections toggles independently per section. The
	-- section is stamped onto the item by StatusUI.create_file_item (and onto diff
	-- line items too), so both header and diff-line items reconstruct the key.
	local section = item.section or "modified"
	local key = section .. ":" .. file_path
	local was_expanded = self.expanded_files[key] ~= nil

	if was_expanded then
		-- Collapse: drop the cached diff and re-render immediately.
		self.expanded_files[key] = nil

		-- Find the file's HEADER line so we can restore the cursor there after
		-- re-rendering. Match only header components (item.line == nil): diff lines
		-- carry the same path/section but an item.line, and their positions point
		-- past the shortened buffer once the diff collapses. component_positions is
		-- 0-indexed.
		local target_line = nil
		for line_idx, comp in pairs(self.buffer.component_positions) do
			local comp_item = comp:is_interactive() and comp:get_item()
			if comp_item and comp_item.line == nil and comp_item.path == file_path and comp_item.section == section then
				target_line = line_idx + 1
				break
			end
		end

		self:render()

		if target_line then
			-- Clamp to the now-shorter buffer to avoid "Cursor position outside
			-- buffer" if the target line fell past the end after collapsing.
			local line_count = vim.api.nvim_buf_line_count(self.buffer.handle)
			if target_line > line_count then
				target_line = line_count
			end
			self.buffer:set_cursor(target_line, 0)
		end
	else
		-- Expand: fetch the diff off the UI thread, cache it, then render so the
		-- UI builder only ever reads cached data.
		local async = require("plenary.async")
		async.run(function()
			local diff_lines = self:get_file_diff(file_path)
			vim.schedule(function()
				self.expanded_files[key] = { diff = diff_lines }
				if self.buffer and self.buffer:is_valid() then
					self:render()
				end
			end)
		end)
	end
end

---Toggle all file diffs
function StatusBuffer:toggle_all_file_diffs()
	local any_expanded = next(self.expanded_files) ~= nil

	if any_expanded then
		-- Collapse everything and re-render immediately.
		self.expanded_files = {}
		self:render()
		return
	end

	-- Expand all: gather every (section, path) pair, then fetch and cache each
	-- diff off the UI thread so the UI builder never runs jj during render. Keys
	-- are section-namespaced to match toggle_file_diff and the UI builder.
	local entries = {}
	if self.state.working_copy and self.state.working_copy.modified_files then
		for _, file in ipairs(self.state.working_copy.modified_files) do
			table.insert(entries, { section = "modified", path = file.path })
		end
	end
	if self.state.working_copy and self.state.working_copy.conflicts then
		for _, file in ipairs(self.state.working_copy.conflicts) do
			table.insert(entries, { section = "conflicts", path = file.path })
		end
	end

	if #entries == 0 then
		return
	end

	local async = require("plenary.async")
	async.run(function()
		local cache = {}
		for _, entry in ipairs(entries) do
			cache[entry.section .. ":" .. entry.path] = { diff = self:get_file_diff(entry.path) }
		end
		vim.schedule(function()
			for key, value in pairs(cache) do
				self.expanded_files[key] = value
			end
			if self.buffer and self.buffer:is_valid() then
				self:render()
			end
		end)
	end)
end

---Get diff for a file
---@param file_path string Path to the file
---@return string[] diff_lines Diff lines
function StatusBuffer:get_file_diff(file_path)
	-- First check if we have embedded diff data (from jj show for revisions)
	if self.state.working_copy and self.state.working_copy.modified_files then
		for _, file in ipairs(self.state.working_copy.modified_files) do
			if file.path == file_path and file.diff then
				return file.diff
			end
		end
	end

	-- Fall back to fetching diff via jj diff command (for working copy)
	local cli = require("neojj.lib.jj.cli")

	-- Create a diff command builder
	local builder = cli.raw():arg("diff"):option("color", "never"):flag("git")

	-- Add revision flag if showing a specific revision
	if self.revision then
		builder:arg("-r"):arg(self.revision)
	end

	builder:arg(file_path):cwd(self.repo.dir)

	local result = builder:call_async()

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
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.path then
		return
	end

	-- item.path is relative to the repo root; resolve it against the true root
	-- rather than the ambient cwd (which may differ from where jj lives).
	local root = self.repo:get_root() or self.repo.dir
	local abs_path = root .. "/" .. item.path

	-- Open the file in the current window (the stack window). This replaces the
	-- status view, which stays alive (bufhidden="hide") beneath the new frame.
	local escaped_path = vim.fn.fnameescape(abs_path)
	if item.line then
		-- Jump to specific line (from diff position)
		vim.cmd("edit +" .. item.line .. " " .. escaped_path)
	else
		vim.cmd("edit " .. escaped_path)
	end

	-- Push the file as the top frame. No teardown: it is the user's own file
	-- buffer, so popping back to the status view just navigates away and leaves
	-- it listed. From the file, no-arg `:JJ` returns to the status view.
	require("neojj.lib.view_stack").push(vim.api.nvim_get_current_buf())
end

---Open describe buffer for current commit
function StatusBuffer:describe_current_commit()
	local DescribeBuffer = require("neojj.buffers.describe")

	-- Callbacks fire after describe's submit()/abort() have already closed the
	-- describe view, so we refresh and re-focus the status buffer synchronously
	-- (no timer needed to wait for describe's window to tear down).
	local function on_submit()
		vim.notify("Description updated", vim.log.levels.INFO)
		if self.buffer and self.buffer:is_valid() then
			self:refresh()
			self.buffer:open()
		else
			logger.debug("Status buffer no longer valid, skipping refresh after describe")
		end
	end

	local function on_abort()
		if self.buffer and self.buffer:is_valid() then
			self.buffer:open()
		end
	end

	local revision_to_describe = self.revision or "@"
	local describe_buffer = DescribeBuffer.new(self.repo, revision_to_describe, on_submit, on_abort)
	describe_buffer:show()
end

---Commit the working copy: open the describe buffer for `@`, and once its
---description is submitted run `jj new` so the user lands on a fresh empty
---working copy. Together these two steps ARE `jj commit` (which is exactly
---`jj describe @ --stdin` followed by `jj new`); jj's `commit` subcommand has no
---`--stdin`, so we chain the two commands the describe buffer already speaks
---rather than invoking `jj commit` directly. This is the canonical "finish this
---change" gesture and always targets the working copy `@`.
function StatusBuffer:commit_change()
	local DescribeBuffer = require("neojj.buffers.describe")

	-- After the description is saved (describe @ --stdin has already run and the
	-- describe view has closed), advance onto a fresh empty change with `jj new`,
	-- then refresh and re-focus the status view (mirrors describe_current_commit).
	local function on_submit()
		local cli = require("neojj.lib.jj.cli")
		local async = require("plenary.async")

		async.run(function()
			local result = cli.new():cwd(self.repo.dir):call_async()

			vim.schedule(function()
				if result.success then
					vim.notify("Committed change", vim.log.levels.INFO)
				else
					vim.notify(
						"Failed to create new change: " .. (result.stderr or "Unknown error"),
						vim.log.levels.ERROR
					)
				end

				-- Refresh regardless: `jj describe` already changed the description, so
				-- the view must reflect it even if the following `jj new` failed.
				if self.buffer and self.buffer:is_valid() then
					self:refresh()
					self.buffer:open()
				else
					logger.debug("Status buffer no longer valid, skipping refresh after commit")
				end
			end)
		end)
	end

	local function on_abort()
		if self.buffer and self.buffer:is_valid() then
			self.buffer:open()
		end
	end

	-- Commit only ever operates on the working copy, so describe `@` (not the
	-- pinned revision this view may be showing).
	local describe_buffer = DescribeBuffer.new(self.repo, "@", on_submit, on_abort)
	describe_buffer:show()
end

---Run `jj fix` on the working copy (formats/fixes the `@` change). This always
---targets the working copy and ignores the current revision, matching jj's default.
function StatusBuffer:fix()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").fix(),
		-- jj fix reports its outcome (e.g. "Fixed 0 commits of 3 checked.") on
		-- stderr; surface it, falling back to a generic confirmation.
		success = function(result)
			local message = vim.trim(result.stderr or "")
			return message ~= "" and message or "Ran jj fix"
		end,
		failure = "Failed to run jj fix",
	})
end

---Advance ("tug") the closest bookmark that is an ancestor of `@` up to the
---closest pushable revision at/under `@`. Both revsets are inlined so this works
---regardless of the user's jj config or revset aliases.
function StatusBuffer:tug()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").tug(),
		success = "Tugged bookmark to @",
		failure = "Failed to tug bookmark",
	})
end

---Run `jj git push` with the given options, asynchronously. `opts.bookmark`
---pushes a single named bookmark; `opts.change` pushes/creates a bookmark for a
---revision (`--change`); neither pushes all tracked bookmarks. Notifies on
---start, refreshes on success and surfaces stderr (auth errors, bookmark
---conflicts) on failure.
---@param opts { bookmark?: string, change?: string }
function StatusBuffer:_run_push(opts)
	local builder = require("neojj.lib.jj.cli").git_push()
	if opts.bookmark then
		builder:option("bookmark", opts.bookmark)
	elseif opts.change then
		builder:option("change", opts.change)
	end

	action.run(self, {
		builder = builder,
		pending = "Pushing to remote...",
		success = "Pushed to remote",
		failure = "Failed to push",
	})
end

---Push to the remote. Prompts for what to push: all tracked bookmarks, a
---specific bookmark by name, or a bookmark for this view's change (`--change`,
---defaulting to the working copy `@` when no revision is pinned).
function StatusBuffer:push()
	local choices = {
		"All tracked bookmarks",
		"A specific bookmark...",
		"This change (--change)",
	}

	vim.ui.select(choices, { prompt = "jj git push:" }, function(_, idx)
		if not idx then
			return
		end
		if idx == 1 then
			self:_run_push({})
		elseif idx == 2 then
			vim.ui.input({ prompt = "Bookmark name: " }, function(name)
				if not name or name == "" then
					return
				end
				self:_run_push({ bookmark = name })
			end)
		elseif idx == 3 then
			self:_run_push({ change = self.revision or "@" })
		end
	end)
end

---Fetch from the remote (`jj git fetch`), asynchronously. Notifies on start,
---refreshes on success and surfaces stderr on failure.
function StatusBuffer:fetch()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").git_fetch(),
		pending = "Fetching from remote...",
		success = "Fetched from remote",
		failure = "Failed to fetch",
	})
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

---Open operation-log buffer while keeping status buffer context
function StatusBuffer:open_oplog_buffer()
	local OplogBuffer = require("neojj.buffers.oplog")

	-- Get or create oplog buffer (singleton pattern)
	local oplog_buffer = OplogBuffer.new(self.repo)

	-- Show and refresh the oplog buffer
	oplog_buffer:show()
end

---Create a new change from the current commit
function StatusBuffer:create_new_change()
	-- Create new change from the current revision (or working copy if no revision specified)
	local builder = require("neojj.lib.jj.cli").new()
	if self.revision then
		builder:arg(self.revision)
	end

	action.run(self, {
		builder = builder,
		success = "Created new change",
		failure = "Failed to create new change",
	})
end

return StatusBuffer
