local Buffer = require("neojj.lib.buffer")
local LogUI = require("neojj.buffers.log.ui")
local logger = require("neojj.logger")
local log_parser = require("neojj.lib.jj.parsers.log_parser")
local Separators = require("neojj.lib.jj.separators")
local action = require("neojj.lib.jj.action")

-- Explicit machine-oriented template for `jj log`. Rather than parse jj's
-- fragile human-facing output, we ask for an unambiguous layout keyed on two
-- ASCII control characters (see neojj.lib.jj.parsers.log_parser for the full
-- contract):
--   "\x1e" (RECORD SEPARATOR) marks the boundary between jj's graph gutter and
--          our payload. jj never emits this byte in the graph, so splitting on
--          it is unambiguous for any node glyph (@, ○, ◆, ×, curved corners …).
--   "\x1f" (UNIT SEPARATOR) separates the fields within a commit header.
-- Each commit spans two lines: a header record and a description record. The
-- graph (`--graph`) gutter is kept so the gutter still renders.
--
-- The change and commit ids use `shortest(8)`, not `short(8)`: `shortest`
-- returns the same 8-char text but lets us also ask jj for its *unique
-- disambiguating prefix* via `.prefix()`. We emit that prefix as two extra
-- trailing fields so the UI can brighten the unique prefix and dim the rest —
-- the same trick `jj log` itself uses — without computing the prefix ourselves.
-- The prefix fields are appended last so older captured fixtures (which lack
-- them) still parse; the parser treats them as optional. A final `empty` field
-- (jj's own emptiness flag) is appended after them for the same reason: keeping
-- it last preserves backward-compat with fixtures captured before it existed.
-- A `tags` field (jj's tag names for the commit) is likewise appended last, for
-- the same backward-compat reason.
--
-- Field order within the header record:
--   change_id, author, timestamp, bookmarks, commit_id, conflict,
--   change_id_prefix, commit_id_prefix, empty, tags
local LOG_TEMPLATE = table.concat({
	Separators.RECORD_TEMPLATE,
	"change_id.shortest(8)",
	Separators.UNIT_TEMPLATE,
	"author.email()",
	Separators.UNIT_TEMPLATE,
	'committer.timestamp().local().format("%Y-%m-%d %H:%M:%S")',
	Separators.UNIT_TEMPLATE,
	-- Use the `bookmarks` keyword (not `local_bookmarks`) so jj applies its
	-- native tracking decorations: a bookmark ahead of / differing from its
	-- remote renders as `name*`, and a remote-tracking bookmark shown on the
	-- commit it points to renders as `name@remote`. jj's default string form of
	-- the `bookmarks` list joins entries with a single space, and bookmark and
	-- remote names never contain spaces, so the parser can split the field on
	-- whitespace without colliding with the `*` / `@` decoration characters.
	"bookmarks",
	Separators.UNIT_TEMPLATE,
	"commit_id.shortest(8)",
	Separators.UNIT_TEMPLATE,
	'if(conflict, "conflict", "")',
	Separators.UNIT_TEMPLATE,
	"change_id.shortest(8).prefix()",
	Separators.UNIT_TEMPLATE,
	"commit_id.shortest(8).prefix()",
	Separators.UNIT_TEMPLATE,
	'if(empty, "empty", "")',
	Separators.UNIT_TEMPLATE,
	-- Tag names on this commit. Like `bookmarks`, jj's default string form joins
	-- entries with a single space, and tag names never contain spaces, so the
	-- parser can split the field on whitespace.
	"tags",
	'"\\n"',
	Separators.RECORD_TEMPLATE,
	'if(description.first_line() == "", "(no description set)", description.first_line())',
	'"\\n"',
}, " ++ ")

-- Local bookmark names carried on a revision, with jj's display decorations
-- stripped: a trailing "*" marks "ahead of / differs from remote", and
-- "name@remote" entries are remote-tracking refs. `jj bookmark delete/rename`
-- operate on plain local names, so drop the remote-tracking entries and the "*".
local function local_bookmark_names(item)
	local names = {}
	for _, bookmark in ipairs((item and item.bookmarks) or {}) do
		if not bookmark:find("@", 1, true) then
			table.insert(names, (bookmark:gsub("%*$", "")))
		end
	end
	return names
end

---@class LogBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field state table Current log state
---@field options table Log options (e.g. revset/limit) passed at construction
---@field expanded_revisions table<string, { description: string[], stats: string[] }> Cached details per expanded revision, keyed by change id (absent when collapsed)
local LogBuffer = {}
LogBuffer.__index = LogBuffer

-- Per-repo instance tracking. Keyed by the normalized repo dir so that log
-- views for two different repos coexist instead of sharing one instance (and
-- one underlying buffer).
local instances = {}

---Return the currently-valid log buffer instances tracked by this module.
---
---Lets callers outside this module (e.g. the auto-refresh watcher) fan a
---refresh out to open log views without reaching into the private `instances`
---map or scanning buffers by name.
---@return LogBuffer[] instances Valid log buffer instances
function LogBuffer.list_instances()
	local result = {}
	for _, inst in pairs(instances) do
		if inst:is_valid() then
			table.insert(result, inst)
		end
	end
	return result
end

---Create or get existing log buffer
---@param repo table Repository instance
---@param options? table Log options
---@return LogBuffer log_buffer Log buffer instance
function LogBuffer.new(repo, options)
	options = options or {}

	local repo_key = vim.fs.normalize(repo.dir)

	-- Return existing instance if available for this repo
	if instances[repo_key] and instances[repo_key]:is_valid() then
		-- Merge (rather than replace) options on the existing instance so that a
		-- reuse which omits a previously-configured limit/revset keeps the old
		-- value instead of silently discarding it.
		instances[repo_key].options = vim.tbl_extend("force", instances[repo_key].options or {}, options or {})
		return instances[repo_key]
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

	-- Create buffer with a per-repo namespaced name (reuse if exists). Two
	-- different repos must not share the same underlying buffer.
	local util = require("neojj.lib.jj.util")
	local buffer = Buffer.create({
		name = "NeoJJ Log (" .. util.repo_namespace(repo) .. ")",
		filetype = "neojj-log",
		kind = "replace", -- Default to replace current view
		modifiable = false,
		readonly = true,
		-- Stay alive when a drilled-into frame (a change's status view) replaces us
		-- in the window, so the view stack can reveal us again on pop.
		bufhidden = "hide",
		cwd = repo.dir,
		context_highlight = true,
		active_item_highlight = true,
		foldmarkers = false,
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
		-- LogBuffer.new for the same repo rebuilds a fresh instance instead of
		-- handing back one whose underlying buffer is gone.
		on_detach = function()
			instances[repo_key] = nil
			-- Tear the auto-refresh watcher down once no view for this root remains.
			require("neojj.lib.watcher").cleanup(repo:get_root())
		end,
	})

	new_instance.buffer = buffer

	-- Add log-specific key mappings
	new_instance:_setup_mappings()

	-- Store instance for reuse
	instances[repo_key] = new_instance

	return new_instance
end

---Setup log-specific key mappings
function LogBuffer:_setup_mappings()
	-- Pop one frame off the view stack, revealing the view drilled down from.
	-- Only when this view is the last frame does it close.
	for _, key in ipairs({ "q", "<esc>", "<c-c>" }) do
		self.buffer:map("n", key, function()
			self:go_back()
		end, { desc = "Back (pop view stack) / close log" })
	end

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

	-- Describe commit at cursor
	self.buffer:map("n", "d", function()
		self:describe_commit_at_cursor()
	end, { desc = "Describe commit" })

	-- Navigation to other views
	self.buffer:map("n", "s", function()
		self:open_status_buffer()
	end, { desc = "Open status view" })

	self.buffer:map("n", "o", function()
		self:open_oplog_buffer()
	end, { desc = "Open operation log view" })

	-- Create new change
	self.buffer:map("n", "n", function()
		self:create_new_change()
	end, { desc = "Create new change after cursor" })

	-- Edit change (make it the working copy)
	self.buffer:map("n", "e", function()
		self:edit_change()
	end, { desc = "Edit change at cursor (make it the working copy)" })

	-- Run jj fix on the working copy
	self.buffer:map("n", "f", function()
		self:fix()
	end, { desc = "Run jj fix (format working copy)" })

	-- Tug: advance the closest bookmark up to @
	self.buffer:map("n", "t", function()
		self:tug()
	end, { desc = "Tug: advance closest bookmark to @" })

	-- Bookmark management menu (create/move/delete/rename/track/untrack)
	self.buffer:map("n", "b", function()
		self:bookmark_menu()
	end, { desc = "Bookmark management" })

	-- Push to the remote (jj git push)
	self.buffer:map("n", "P", function()
		self:push()
	end, { desc = "Push to remote (jj git push)" })

	-- Pull (fetch) from the remote (jj git fetch)
	self.buffer:map("n", "p", function()
		self:fetch()
	end, { desc = "Pull from remote (jj git fetch)" })

	-- Yank change ID
	self.buffer:map("n", "y", function()
		self:yank_change_id_at_cursor()
	end, { desc = "Yank change ID" })

	-- Toggle expanded details
	self.buffer:map("n", "<tab>", function()
		self:toggle_revision_expanded()
	end, { desc = "Toggle revision details" })
end

---Refresh the log buffer
function LogBuffer:refresh()
	logger.info("Refreshing log buffer")

	if not self.repo:is_jj_repo() then
		self.buffer:render_error("Not a JJ repository")
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

		-- Re-fetch cached details for any revisions that are currently expanded so
		-- the rendered detail stays in sync with the refreshed log. We're already
		-- in the async context here, so these calls yield rather than block.
		for change_id in pairs(self.expanded_revisions) do
			self.expanded_revisions[change_id] = self:get_revision_details(change_id)
		end

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

	-- Get log with default template, no color. The limit normally flows from
	-- setup()'s configured log_limit; the literal here is only a final safety
	-- net for direct LogBuffer.new callers that pass no options.
	local limit = self.options.limit or 100
	local revisions = self.options.revisions or "::"

	local builder = cli.log()
		:short_flag("r")
		:arg(revisions)
		:option("limit", tostring(limit))
		:option("template", LOG_TEMPLATE)
		:cwd(self.repo.dir)

	local result = builder:call_async()

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

---Register this view as the top frame of the drill-down view stack.
---
---Called from every display entry point so navigating into the log view (from
---a status view, or via `:JJ log`) stacks it as a live frame. Uses the same
---buffer, so revisiting the view moves the existing frame to the top rather
---than duplicating it.
function LogBuffer:_push_frame()
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
function LogBuffer:go_back()
	local view_stack = require("neojj.lib.view_stack")
	local top = view_stack.top()
	if top and top.bufnr == self.buffer:get_handle() then
		view_stack.pop()
	else
		self.buffer:close()
	end
end

---Show the log buffer
---@param kind? string Display mode override
function LogBuffer:show(kind)
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

---Show the log buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function LogBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

---Show the log buffer in a new tab
function LogBuffer:show_tab()
	self.buffer:open("tab")
	self:_push_frame()
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
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		return
	end

	-- Open status view for this commit
	local StatusBuffer = require("neojj.buffers.status")
	local status_buffer = StatusBuffer.new(self.repo, item.change_id)
	status_buffer:show()
end

---Describe commit at cursor
function LogBuffer:describe_commit_at_cursor()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		return
	end

	local DescribeBuffer = require("neojj.buffers.describe")

	-- Callbacks fire after describe's submit()/abort() have already closed the
	-- describe view, so we refresh and re-focus the log synchronously (no timer).
	local function on_submit()
		vim.notify("Description updated", vim.log.levels.INFO)
		if self.buffer and self.buffer:is_valid() then
			self:refresh()
			self.buffer:open()
		end
	end

	local function on_abort()
		if self.buffer and self.buffer:is_valid() then
			self.buffer:open()
		end
	end

	local describe_buffer = DescribeBuffer.new(self.repo, item.change_id, on_submit, on_abort)
	describe_buffer:show()
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

---Open operation-log buffer while keeping log buffer context
function LogBuffer:open_oplog_buffer()
	local OplogBuffer = require("neojj.buffers.oplog")

	-- Get or create oplog buffer (singleton pattern)
	local oplog_buffer = OplogBuffer.new(self.repo)

	-- Show and refresh the oplog buffer
	oplog_buffer:show()
end

---Create a new change after the commit at cursor
function LogBuffer:create_new_change()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		vim.notify("No commit at cursor", vim.log.levels.WARN)
		return
	end

	-- Create new change after the selected revision
	action.run(self, {
		builder = require("neojj.lib.jj.cli").new():arg(item.change_id),
		success = function()
			return "Created new change after " .. item.change_id:sub(1, 8)
		end,
		failure = "Failed to create new change",
	})
end

---Edit the change at cursor, making it the working copy (jj's checkout)
function LogBuffer:edit_change()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		vim.notify("No commit at cursor", vim.log.levels.WARN)
		return
	end

	-- Make the selected revision the working copy
	action.run(self, {
		builder = require("neojj.lib.jj.cli").edit():arg(item.change_id),
		success = function()
			return "Now editing " .. item.change_id:sub(1, 8)
		end,
		failure = "Failed to edit change",
	})
end

---Run `jj fix` on the working copy (formats/fixes the `@` change). This always
---targets the working copy and ignores the cursor, matching jj's default.
function LogBuffer:fix()
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
function LogBuffer:tug()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").tug(),
		success = "Tugged bookmark to @",
		failure = "Failed to tug bookmark",
	})
end

---Run a prepared `jj bookmark …` builder asynchronously, notifying and
---refreshing on success and surfacing stderr on failure. Modeled on
---`LogBuffer:_run_push`. The builder must already have its cwd/args set; we wrap
---`call_async` in its own `async.run` because the callers fire from
---`vim.ui.select`/`vim.ui.input` callbacks, which run outside any async context.
---@param builder table A cli.bookmark_* builder ready to call
---@param success_msg string Notification shown on success
function LogBuffer:_run_bookmark(builder, success_msg)
	local async = require("plenary.async")

	async.run(function()
		local result = builder:call_async()

		vim.schedule(function()
			if result.success then
				vim.notify(success_msg, vim.log.levels.INFO)
				self:refresh()
			else
				vim.notify("Bookmark operation failed: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
			end
		end)
	end)
end

---Fetch the list of local bookmark names (one per line) and hand them to
---`callback` on the main loop. Wraps the async jj call so `vim.ui.*` callbacks
---can request a name list without being inside an async context themselves.
---@param callback fun(names: string[])
function LogBuffer:_fetch_bookmark_names(callback)
	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		local result = cli.bookmark_list():option("template", 'name ++ "\\n"'):cwd(self.repo.dir):call_async()

		vim.schedule(function()
			if not result.success then
				vim.notify("Failed to list bookmarks: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
				callback({})
				return
			end

			local names = {}
			for _, line in ipairs(vim.split(result.stdout or "", "\n")) do
				local name = vim.trim(line)
				if name ~= "" then
					table.insert(names, name)
				end
			end
			callback(names)
		end)
	end)
end

---Open the bookmark-management menu for the change under the cursor. Wraps
---`jj bookmark create/move/delete/rename/track/untrack` behind a `vim.ui.select`
---prompt so bookmarks can be prepared for a push without leaving the log view.
function LogBuffer:bookmark_menu()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		vim.notify("No commit at cursor", vim.log.levels.WARN)
		return
	end
	local change_id = item.change_id

	local choices = {
		"Create bookmark here",
		"Move bookmark here",
		"Delete bookmark",
		"Rename bookmark",
		"Track remote bookmark",
		"Untrack remote bookmark",
	}

	vim.ui.select(choices, { prompt = "jj bookmark:" }, function(_, idx)
		if not idx then
			return
		end
		if idx == 1 then
			self:_bookmark_create(change_id)
		elseif idx == 2 then
			self:_bookmark_move(change_id)
		elseif idx == 3 then
			self:_bookmark_delete(item)
		elseif idx == 4 then
			self:_bookmark_rename()
		elseif idx == 5 then
			self:_bookmark_track()
		elseif idx == 6 then
			self:_bookmark_untrack()
		end
	end)
end

---Create a new bookmark on the given revision (`jj bookmark create`).
---@param change_id string Revision the bookmark should point at
function LogBuffer:_bookmark_create(change_id)
	local cli = require("neojj.lib.jj.cli")

	vim.ui.input({ prompt = "New bookmark name: " }, function(name)
		if not name or name == "" then
			return
		end
		self:_run_bookmark(
			cli.bookmark_create():arg(name):option("revision", change_id):cwd(self.repo.dir),
			"Created bookmark " .. name
		)
	end)
end

---Move an existing bookmark onto the given revision (`jj bookmark move`).
---The target is passed with `--to`; unlike `jj bookmark create`, `move` has no
---`--revision`/`-r` alias. `--allow-backwards` lets the bookmark move to an
---ancestor as well as forward.
---@param change_id string Revision the bookmark should move to
function LogBuffer:_bookmark_move(change_id)
	local cli = require("neojj.lib.jj.cli")

	self:_fetch_bookmark_names(function(names)
		if #names == 0 then
			vim.notify("No bookmarks to move", vim.log.levels.WARN)
			return
		end
		vim.ui.select(names, { prompt = "Move which bookmark here?" }, function(name)
			if not name then
				return
			end
			self:_run_bookmark(
				cli.bookmark_move():arg(name):option("to", change_id):flag("allow-backwards"):cwd(self.repo.dir),
				"Moved bookmark " .. name
			)
		end)
	end)
end

---Delete a bookmark (`jj bookmark delete`). Offers the bookmarks on the cursor
---revision first (the common case) and otherwise falls back to the full list.
---@param item table Revision under the cursor
function LogBuffer:_bookmark_delete(item)
	local cli = require("neojj.lib.jj.cli")

	local function pick_and_delete(names)
		if #names == 0 then
			vim.notify("No bookmarks to delete", vim.log.levels.WARN)
			return
		end
		vim.ui.select(names, { prompt = "Delete which bookmark?" }, function(name)
			if not name then
				return
			end
			self:_run_bookmark(cli.bookmark_delete():arg(name):cwd(self.repo.dir), "Deleted bookmark " .. name)
		end)
	end

	local cursor_names = local_bookmark_names(item)
	if #cursor_names > 0 then
		pick_and_delete(cursor_names)
	else
		self:_fetch_bookmark_names(pick_and_delete)
	end
end

---Rename an existing bookmark (`jj bookmark rename`).
function LogBuffer:_bookmark_rename()
	local cli = require("neojj.lib.jj.cli")

	self:_fetch_bookmark_names(function(names)
		if #names == 0 then
			vim.notify("No bookmarks to rename", vim.log.levels.WARN)
			return
		end
		vim.ui.select(names, { prompt = "Rename which bookmark?" }, function(old_name)
			if not old_name then
				return
			end
			vim.ui.input({ prompt = "New name for " .. old_name .. ": " }, function(new_name)
				if not new_name or new_name == "" then
					return
				end
				self:_run_bookmark(
					cli.bookmark_rename():arg(old_name):arg(new_name):cwd(self.repo.dir),
					"Renamed bookmark " .. old_name .. " -> " .. new_name
				)
			end)
		end)
	end)
end

---Track a remote bookmark (`jj bookmark track name@remote`). Prompts for the
---fully-qualified `name@remote` ref, since that pairing is what jj expects.
function LogBuffer:_bookmark_track()
	local cli = require("neojj.lib.jj.cli")

	vim.ui.input({ prompt = "Track remote bookmark (name@remote): " }, function(ref)
		if not ref or ref == "" then
			return
		end
		self:_run_bookmark(cli.bookmark_track():arg(ref):cwd(self.repo.dir), "Tracking " .. ref)
	end)
end

---Untrack a remote bookmark (`jj bookmark untrack name@remote`).
function LogBuffer:_bookmark_untrack()
	local cli = require("neojj.lib.jj.cli")

	vim.ui.input({ prompt = "Untrack remote bookmark (name@remote): " }, function(ref)
		if not ref or ref == "" then
			return
		end
		self:_run_bookmark(cli.bookmark_untrack():arg(ref):cwd(self.repo.dir), "Untracked " .. ref)
	end)
end

---Run `jj git push` with the given options, asynchronously. `opts.bookmark`
---pushes a single named bookmark; `opts.change` pushes/creates a bookmark for a
---revision (`--change`); neither pushes all tracked bookmarks. Notifies on
---start, refreshes on success and surfaces stderr (auth errors, bookmark
---conflicts) on failure.
---@param opts { bookmark?: string, change?: string }
function LogBuffer:_run_push(opts)
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
---specific bookmark by name, or a bookmark for the change at the cursor
---(`--change`).
function LogBuffer:push()
	local choices = {
		"All tracked bookmarks",
		"A specific bookmark...",
		"Change at cursor (--change)",
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
			local item = self.buffer:get_item_at_cursor()
			if not item or not item.change_id then
				vim.notify("No commit at cursor", vim.log.levels.WARN)
				return
			end
			self:_run_push({ change = item.change_id })
		end
	end)
end

---Fetch from the remote (`jj git fetch`), asynchronously. Notifies on start,
---refreshes on success and surfaces stderr on failure.
function LogBuffer:fetch()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").git_fetch(),
		pending = "Fetching from remote...",
		success = "Fetched from remote",
		failure = "Failed to fetch",
	})
end

---Yank the change ID of the commit at cursor
function LogBuffer:yank_change_id_at_cursor()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		vim.notify("No commit at cursor", vim.log.levels.WARN)
		return
	end

	vim.fn.setreg("+", item.change_id)
	vim.notify("Copied change ID: " .. item.change_id, vim.log.levels.INFO)
end

---Toggle expanded state for revision at cursor
function LogBuffer:toggle_revision_expanded()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.change_id then
		return
	end

	local change_id = item.change_id
	-- expanded_revisions maps a change id to its cached details
	-- ({ description, stats }) while expanded, and holds nil while collapsed.
	local was_expanded = self.expanded_revisions[change_id] ~= nil

	if was_expanded then
		-- Collapse: drop the cached details and re-render immediately.
		self.expanded_revisions[change_id] = nil

		-- Find the commit line so we can restore the cursor after collapsing.
		local target_line = nil
		for line_idx, comp in pairs(self.buffer.component_positions or {}) do
			if comp:is_interactive() and comp:get_item() and comp:get_item().change_id == change_id then
				target_line = line_idx + 1 -- Convert to 1-indexed
				break
			end
		end

		self:render()

		if target_line then
			self.buffer:set_cursor(target_line, 0)
		end
	else
		-- Expand: fetch the details off the UI thread, cache them, then render so
		-- the UI builder only ever reads cached data.
		local async = require("plenary.async")
		async.run(function()
			local details = self:get_revision_details(change_id)
			vim.schedule(function()
				self.expanded_revisions[change_id] = details
				if self.buffer and self.buffer:is_valid() then
					self:render()
				end
			end)
		end)
	end
end

---Get detailed info for a revision (description + stats)
---@param change_id string The change ID to get details for
---@return { description: string[], stats: string[] } details Table with description and stats lines
function LogBuffer:get_revision_details(change_id)
	local cli = require("neojj.lib.jj.cli")

	-- Get log with stats for this specific revision
	local builder = cli.log():short_flag("r"):arg(change_id):flag("stat"):flag("no-graph"):cwd(self.repo.dir)
	local result = builder:call_async()

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
