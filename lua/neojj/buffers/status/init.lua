local Buffer = require("neojj.lib.buffer")
local ViewBuffer = require("neojj.lib.view_buffer")
local StatusUI = require("neojj.buffers.status.ui")
local logger = require("neojj.logger")
local action = require("neojj.lib.jj.action")

---@class StatusBuffer : ViewBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field revision? string Optional revision to show (defaults to working copy)
---@field state table Current repository state
---@field expanded_files table<string, { diff: string[] }> Cached diff per expanded file, keyed by "<section>:<path>" (absent when collapsed)
local StatusBuffer = setmetatable({}, { __index = ViewBuffer })
StatusBuffer.__index = StatusBuffer
StatusBuffer.frame_name = "status"
-- Third `jj git push` menu choice: the status view pushes a bookmark for this
-- view's change (see StatusBuffer:_push_change_target).
StatusBuffer.push_change_label = "This change (--change)"

-- Singleton instance tracking
local instances = {}

---Return the currently-valid status buffer instances tracked by this module.
---
---Lets callers outside this module (e.g. the top-level :JJ describe handler)
---refresh and re-focus an open status view without reaching into the private
---`instances` map or scanning buffers by name.
---@return StatusBuffer[] instances Valid status buffer instances
function StatusBuffer.list_instances()
	return ViewBuffer.list_valid(instances)
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

	return ViewBuffer.get_or_create(instances, repo_key, function()
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

		return instance
	end)
end

---Setup status-specific key mappings
function StatusBuffer:_setup_mappings()
	-- Pop one frame off the view stack, revealing the view drilled down from
	-- (e.g. the log). Only when this view is the last frame does it close.
	self:_map_back_keys()

	-- Refresh mappings (`r` and Ctrl-R, like NeoGit). Logged here, at the manual
	-- entry point, so watcher-driven auto-refreshes (which call refresh()
	-- directly) stay quiet.
	local function manual_refresh()
		logger.info("Refreshing status buffer" .. (self.revision and (" for revision: " .. self.revision) or ""))
		self:refresh()
	end
	self.buffer:map("n", "r", manual_refresh, { desc = "Refresh status" })
	self.buffer:map("n", "<c-r>", manual_refresh, { desc = "Refresh status" })

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

	-- Squash @ into its parent (confirms first)
	self.buffer:map("n", "S", function()
		self:squash()
	end, { desc = "Squash @ into parent" })

	-- Rebase @ onto a chosen destination
	self.buffer:map("n", "R", function()
		self:rebase()
	end, { desc = "Rebase @ onto a change" })

	-- Discard the file under the cursor, or restore all changes (confirms first)
	self.buffer:map("n", "x", function()
		self:restore()
	end, { desc = "Discard file changes / restore all (jj restore)" })

	-- Shared jj-action keys: f=fix, t=tug, P=push, p=fetch.
	self:_map_jj_actions()

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

---Refresh the status buffer. Fired both manually (the `r`/`<c-r>` keys) and
---automatically (the filesystem watcher), so it stays silent — the manual key
---handlers log "Refreshing …" so routine auto-refreshes don't flood the log.
function StatusBuffer:refresh()
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

-- Lifecycle plumbing (_push_frame, go_back, show, show_split, show_tab, close)
-- is inherited from ViewBuffer.

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

	-- Side-by-side mode: route <tab> to two adjacent floats in native diff mode
	-- instead of expanding the diff inline. The float pair is transient (not a
	-- view-stack frame), mirroring the inline toggle.
	if require("neojj").config.diff.inline == false then
		require("neojj.buffers.status.diff_float").open(self.repo, self.revision, item.path, item.status)
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
	-- Toggle-all only makes sense for the inline expansion; there is no
	-- side-by-side equivalent (we only float one file pair at a time).
	if require("neojj").config.diff.inline == false then
		vim.notify("Toggle-all is only available in inline diff mode", vim.log.levels.INFO)
		return
	end

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

-- fix / tug / _run_push / push / fetch and the is_valid / get_handle accessors
-- are inherited from ViewBuffer. push() calls the hook below for its "this
-- change" target.

---Resolve the change the `--change` push option targets: this view's pinned
---revision, or the working copy `@` when no revision is pinned. Never nil.
---@return string change_id
function StatusBuffer:_push_change_target()
	return self.revision or "@"
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

---Squash the working copy `@` into its parent (`jj squash`). Confirms first,
---since squashing moves all of `@`'s changes into the parent and can leave `@`
---empty. This is the staging-area replacement: the single most common jj
---operation. Always targets the working copy, ignoring any pinned revision.
function StatusBuffer:squash()
	vim.ui.select({ "Yes", "No" }, { prompt = "Squash @ into parent?" }, function(choice)
		if choice ~= "Yes" then
			return
		end
		-- Bare squash: `@` into its parent. If both carry a description, _run_squash
		-- opens jj's combine editor natively (see ViewBuffer:_run_squash).
		self:_run_squash({})
	end)
end

---Rebase the working copy `@` onto a destination. Delegates to the shared
---`ViewBuffer:_rebase`, which prompts for the source mode (-s/-r/-b) and a
---destination picked from a fuzzy picker. Always rebases `@`.
function StatusBuffer:rebase()
	self:_rebase("@", "@")
end

---Discard working-copy changes via `jj restore`. On a file item under the
---cursor, restores just that path; otherwise restores everything in the view's
---revision. Confirms first (undoable via `jj undo`). Targets the pinned
---revision, or `@` when none is pinned.
function StatusBuffer:restore()
	local rev = self.revision or "@"
	local item = self.buffer:get_item_at_cursor()
	if item and item.path then
		if vim.fn.confirm("Discard changes to " .. item.path .. "?", "&Yes\n&No", 2) ~= 1 then
			return
		end
		action.run(self, {
			builder = require("neojj.lib.jj.cli").restore():option("changes-in", rev):arg(item.path),
			success = "Discarded changes to " .. item.path,
			failure = "Failed to discard " .. item.path,
		})
	else
		if vim.fn.confirm("Discard ALL changes in " .. rev .. "?", "&Yes\n&No", 2) ~= 1 then
			return
		end
		action.run(self, {
			builder = require("neojj.lib.jj.cli").restore():option("changes-in", rev),
			success = "Discarded all changes in " .. rev,
			failure = "Failed to discard changes",
		})
	end
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
