--- Shared base for NeoJJ's stack-frame buffers (status, log, oplog, opshow).
---
--- These four views share the drill-down view-stack lifecycle: each registers
--- itself as a frame when shown, pops on `go_back`, and exposes the same
--- open/close/handle plumbing. This base owns that plumbing so each concrete
--- buffer only supplies its own construction config, frame metadata and
--- view-specific behaviour. It also owns the per-view singleton bookkeeping and
--- the jj-action wrappers (fix/tug/push/fetch) that the status and log views
--- share.
---
--- Subclasses are wired up like:
---     local ViewBuffer = require("neojj.lib.view_buffer")
---     local StatusBuffer = setmetatable({}, { __index = ViewBuffer })
---     StatusBuffer.__index = StatusBuffer
--- and instances built with `setmetatable(inst, StatusBuffer)`, so method lookup
--- falls through StatusBuffer to ViewBuffer.
---
--- Per-subclass hooks / fields:
---   self.repo             (required) repository instance
---   self.buffer           (required) underlying Buffer, set during `.new()`
---   self.frame_name       noun used in the `q`/`<esc>` mapping description
---   self.arms_watcher     when truthy (default), `_push_frame` arms the file
---                         watcher; opshow opts out
---   self:refresh()        each subclass supplies its own refresh
---   self.push_change_label / self:_push_change_target()
---                         supplied by views that bind `push` (status, log)
---
--- The transient describe/annotate buffers deliberately do NOT extend this base:
--- they are not stack frames and their show/close paths differ fundamentally.
---@class ViewBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field refresh fun(self: ViewBuffer) Subclass-supplied refresh
---@field push_change_label? string Push-target label (views that bind `push`)
---@field _push_change_target? fun(self: ViewBuffer): string|nil Push-target resolver
local ViewBuffer = {}
ViewBuffer.__index = ViewBuffer

-- Frame buffers arm the external-change watcher by default; opshow opts out.
ViewBuffer.arms_watcher = true
-- Fallback noun for the back-key description; every real view overrides this.
ViewBuffer.frame_name = "view"

--- Singleton bookkeeping ---------------------------------------------------------

--- Return the currently-valid instances held in a per-module singleton map.
---
--- Lets callers outside a buffer module (e.g. the auto-refresh watcher, or the
--- top-level `:JJ describe` handler) enumerate open views without reaching into
--- the private `instances` map or scanning buffers by name.
---@param map table<any, table> Map of key -> buffer instance
---@return table[] instances Instances whose underlying buffer is still valid
function ViewBuffer.list_valid(map)
	local result = {}
	for _, inst in pairs(map) do
		if inst:is_valid() then
			table.insert(result, inst)
		end
	end
	return result
end

--- Return the existing valid instance for `key`, or build and record a fresh one.
--- `on_reuse` (optional) runs against the existing instance before it is returned
--- (e.g. to merge freshly-passed options). The factory is responsible for the
--- whole `Buffer.create` config, including an `on_detach` that clears `map[key]`.
---@param map table<any, table> Singleton map to look up / populate
---@param key any Instance key (normalized repo dir, or repo+op composite)
---@param factory fun(): table Builds a fresh instance (and its buffer)
---@param on_reuse? fun(existing: table) Runs when an existing instance is reused
---@return table instance
function ViewBuffer.get_or_create(map, key, factory, on_reuse)
	local existing = map[key]
	if existing and existing:is_valid() then
		if on_reuse then
			on_reuse(existing)
		end
		return existing
	end
	local instance = factory()
	map[key] = instance
	return instance
end

--- View-stack lifecycle ----------------------------------------------------------

--- Register this view as the top frame of the drill-down view stack.
---
--- Called from every display entry point so navigating into a view stacks it as a
--- live frame. Uses the same buffer, so revisiting the view moves the existing
--- frame to the top rather than duplicating it.
function ViewBuffer:_push_frame()
	if self.arms_watcher then
		-- Arm the external-change watcher for this repo. _push_frame is the single
		-- choke point every display path routes through, and ensure() is idempotent.
		require("neojj.lib.watcher").ensure(self.repo)
	end
	require("neojj.lib.view_stack").push(self.buffer:get_handle(), {
		teardown = function()
			self:close()
		end,
	})
end

--- Go back: pop this frame off the view stack, revealing the frame beneath. If
--- this view is not the current stack top (an unexpected state), close it.
function ViewBuffer:go_back()
	local view_stack = require("neojj.lib.view_stack")
	local top = view_stack.top()
	if top and top.bufnr == self.buffer:get_handle() then
		view_stack.pop()
	else
		self.buffer:close()
	end
end

--- Show the buffer, register it as a frame, and refresh.
---@param kind? string Display mode override
function ViewBuffer:show(kind)
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

--- Show the buffer in a split.
---@param split_type? string Split type ("horizontal" or "vertical")
function ViewBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

--- Show the buffer in a new tab.
function ViewBuffer:show_tab()
	self.buffer:open("tab")
	self:_push_frame()
	self:refresh()
end

--- Close the buffer.
function ViewBuffer:close()
	self.buffer:close()
end

--- Check whether the underlying buffer is still valid.
---@return boolean valid True if buffer is valid
function ViewBuffer:is_valid()
	return self.buffer:is_valid()
end

--- Get the underlying buffer handle.
---@return number handle Buffer handle
function ViewBuffer:get_handle()
	return self.buffer:get_handle()
end

--- Shared keymap registration ----------------------------------------------------

--- Register the view-stack "back" keys (q / <esc> / <c-c>) shared by every frame.
--- The description noun comes from `self.frame_name`.
function ViewBuffer:_map_back_keys()
	for _, key in ipairs({ "q", "<esc>", "<c-c>" }) do
		self.buffer:map("n", key, function()
			self:go_back()
		end, { desc = "Back (pop view stack) / close " .. self.frame_name })
	end
end

--- Register the shared jj-action keys (f=fix, t=tug, P=push, p=fetch) common to
--- the status and log views.
function ViewBuffer:_map_jj_actions()
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
end

--- Shared jj-action wrappers ------------------------------------------------------

local action = require("neojj.lib.jj.action")

--- Run `jj fix` on the working copy (formats/fixes the `@` change). This always
--- targets the working copy and ignores the current revision/cursor, matching
--- jj's default.
function ViewBuffer:fix()
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

--- Advance ("tug") the closest bookmark that is an ancestor of `@` up to the
--- closest pushable revision at/under `@`. Both revsets are inlined so this works
--- regardless of the user's jj config or revset aliases.
function ViewBuffer:tug()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").tug(),
		success = "Tugged bookmark to @",
		failure = "Failed to tug bookmark",
	})
end

--- Run `jj git push` with the given options, asynchronously. `opts.bookmark`
--- pushes a single named bookmark; `opts.change` pushes/creates a bookmark for a
--- revision (`--change`); neither pushes all tracked bookmarks. Notifies on
--- start, refreshes on success and surfaces stderr (auth errors, bookmark
--- conflicts) on failure.
---@param opts { bookmark?: string, change?: string }
function ViewBuffer:_run_push(opts)
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

--- Push to the remote. Prompts for what to push: all tracked bookmarks, a
--- specific bookmark by name, or a bookmark for "this change" (`--change`). The
--- third choice's label (`self.push_change_label`) and its change target
--- (`self:_push_change_target()`) are supplied per-view: the status view uses its
--- pinned revision (defaulting to `@`), while the log view uses the change under
--- the cursor. A nil target aborts the push (the hook has already notified).
function ViewBuffer:push()
	local choices = {
		"All tracked bookmarks",
		"A specific bookmark...",
		self.push_change_label,
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
			local change = self:_push_change_target()
			if change then
				self:_run_push({ change = change })
			end
		end
	end)
end

--- Fetch from the remote (`jj git fetch`), asynchronously. Notifies on start,
--- refreshes on success and surfaces stderr on failure.
function ViewBuffer:fetch()
	action.run(self, {
		builder = require("neojj.lib.jj.cli").git_fetch(),
		pending = "Fetching from remote...",
		success = "Fetched from remote",
		failure = "Failed to fetch",
	})
end

--- Squash one revision into another, reproducing jj's combine-descriptions
--- editor natively when needed. `opts.from`/`opts.into` are revsets:
---   * from=nil, into=nil   → bare `jj squash` (working copy `@` into its parent)
---   * from=<rev>           → squash `<rev>` into its parent
---   * from=<rev>, into=<t>  → squash `<rev>` into `<t>`
---
--- When the source and destination BOTH carry a (differing) description, jj
--- would open $EDITOR to merge them — which hangs under our non-interactive
--- call path. We instead open a native message buffer pre-filled with jj's
--- template (see neojj.lib.jj.squash) and run `jj squash --message <edited>`.
--- Otherwise (at most one description, or the two match) a plain squash is
--- non-interactive and runs directly. Refreshes the view on success.
---@param opts { from?: string, into?: string }
function ViewBuffer:_run_squash(opts)
	opts = opts or {}
	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")
	local json_parser = require("neojj.lib.jj.parsers.json_parser")
	local squash = require("neojj.lib.jj.squash")

	local from, into = opts.from, opts.into
	local eff_from = from or "@"
	local eff_into = into or (eff_from .. "-")
	local label = from and from:sub(1, 8) or "@"

	-- Build the squash command. The bare status-view case (no `from`) stays
	-- `jj squash`, which jj resolves to `@` into `@-`. Once `from` is given we
	-- must ALSO pass `--into`: jj defaults `--into` to `@` (the working copy),
	-- not the source's parent, so `jj squash --from <rev>` alone would squash
	-- into `@` rather than into `<rev>-`. `eff_into` is `into` when given, else
	-- `<from>-`. A non-nil `message` adds `--message`, which also stops jj
	-- opening its editor.
	local function build_builder(message)
		local builder = cli.squash()
		if from then
			builder:option("from", from)
			builder:option("into", eff_into)
		end
		if message ~= nil then
			builder:option("message", message)
		end
		return builder:cwd(self.repo.dir)
	end

	local function run_plain(message)
		action.run(self, {
			builder = build_builder(message),
			success = "Squashed " .. label,
			failure = "Failed to squash",
		})
	end

	async.run(function()
		-- Fetch source + destination metadata. The destination revset can resolve
		-- to several commits (a merge's parents), so parse them all.
		local function fetch_metas(revset)
			local result = cli.log()
				:option("revisions", revset)
				:option("template", 'json(self) ++ "\\n"')
				:flag("no-graph")
				:cwd(self.repo.dir)
				:call_async()
			if not result.success then
				return nil, result.stderr
			end
			return json_parser.parse_json_lines(result.stdout or "")
		end

		local source_metas, src_err = fetch_metas(eff_from)
		local source = source_metas and source_metas[1]
		if not source then
			vim.schedule(function()
				vim.notify("Failed to read squash source: " .. (src_err or "unknown"), vim.log.levels.ERROR)
			end)
			return
		end
		-- jj's `description` keyword yields the text with its trailing newline;
		-- strip it so a whitespace-only description reads as empty and the combine
		-- template doesn't gain a stray blank line between the two messages.
		local function clean(desc)
			return (tostring(desc or ""):gsub("%s+$", ""))
		end

		local source_desc = clean(source.description)

		local dest_metas = fetch_metas(eff_into) or {}
		local dest_desc = ""
		local dest_change_id = dest_metas[1] and dest_metas[1].change_id or eff_into
		for _, d in ipairs(dest_metas) do
			if clean(d.description) ~= "" then
				dest_desc = clean(d.description)
				dest_change_id = d.change_id or dest_change_id
				break
			end
		end

		-- jj opens its combine editor only when source AND destination both carry
		-- a description. If at most one does, a plain squash is safe. If both are
		-- identical, jj reuses that text without an editor — we pass it via
		-- --message to stay non-interactive.
		if source_desc == "" or dest_desc == "" then
			vim.schedule(function()
				run_plain(nil)
			end)
			return
		end
		if source_desc == dest_desc then
			vim.schedule(function()
				run_plain(dest_desc)
			end)
			return
		end

		-- Both described and differing → reproduce jj's editor natively. Gather
		-- the combined change list (union of the two commits' file summaries) for
		-- the informational JJ: block.
		local function summary_files(revset)
			local result =
				cli.raw():arg("diff"):option("revisions", revset):flag("summary"):cwd(self.repo.dir):call_async()
			local out = {}
			if result.success then
				for _, line in ipairs(vim.split(result.stdout or "", "\n")) do
					if vim.trim(line) ~= "" then
						table.insert(out, line)
					end
				end
			end
			return out
		end
		local function path_of(summary)
			return summary:match("^%S+%s+(.*)$") or summary
		end
		local seen, files = {}, {}
		for _, revset in ipairs({ eff_into, eff_from }) do
			for _, line in ipairs(summary_files(revset)) do
				local path = path_of(line)
				if not seen[path] then
					seen[path] = true
					table.insert(files, line)
				end
			end
		end
		table.sort(files, function(a, b)
			return path_of(a) < path_of(b)
		end)

		vim.schedule(function()
			local components = squash.build_combine_components({
				dest_description = dest_desc,
				source_description = source_desc,
				dest_change_id = dest_change_id,
				files = files,
			})

			local function on_submit()
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

			local DescribeBuffer = require("neojj.buffers.describe")
			local editor = DescribeBuffer.new(self.repo, eff_into, on_submit, on_abort, {
				name = "JJ Squash: " .. label .. " → " .. dest_change_id,
				components = function()
					return components
				end,
				success_message = "Squashed " .. label,
				perform_write = function(message)
					local result = build_builder(message):call_async()
					return { success = result.success, stderr = result.stderr }
				end,
			})
			editor:show()
		end)
	end)
end

--- Rebase commits onto a destination (`jj rebase`). `opts.mode_key` selects which
--- set of commits moves: "source" (-s, the source plus its descendants),
--- "revisions" (-r, that revision only) or "branch" (-b, the whole branch).
--- `opts.source` is the revision to move and `opts.dest` where it lands.
---
--- Rebase never opens an editor, so unlike squash there is no combine flow: a
--- post-rebase conflict still exits 0, so the normal success+refresh path is
--- correct and conflicts need no special-casing.
---@param opts { mode_key: string, source: string, dest: string, label: string }
function ViewBuffer:_run_rebase(opts)
	local builder =
		require("neojj.lib.jj.cli").rebase():option(opts.mode_key, opts.source):option("destination", opts.dest)

	action.run(self, {
		builder = builder,
		pending = "Rebasing...",
		success = "Rebased " .. opts.label .. " onto " .. opts.dest,
		failure = "Failed to rebase",
	})
end

--- Fetch the commits a rebase could target and hand them to `callback` on the
--- main loop as a list of `{ commit_id, change_id, summary }` tables. Wraps the
--- async `jj log` call so `vim.ui.*` callbacks can request the list without being
--- inside an async context. Adapted from `LogBuffer:_fetch_mutable_commits`, but
--- deliberately NOT restricted to `mutable()`: rebase destinations are often
--- immutable (e.g. `main`), so we run jj's default log revset with no
--- `--revisions` option. `exclude_change_id` omits the rebase source.
---@param exclude_change_id string? Short change id to omit (the rebase source)
---@param callback fun(commits: { commit_id: string, change_id: string, summary: string }[])
function ViewBuffer:_fetch_rebase_targets(exclude_change_id, callback)
	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	-- Tab-separated fields, one commit per line: short commit id, short change
	-- id, description summary. Commit/change ids and a first-line summary never
	-- contain tabs, so the parser can split on "\t" unambiguously.
	local template = table.concat({
		"commit_id.shortest(8)",
		'"\\t"',
		"change_id.shortest(8)",
		'"\\t"',
		'if(description.first_line() == "", "(no description set)", description.first_line())',
		'"\\n"',
	}, " ++ ")

	async.run(function()
		local result = cli.log():flag("no-graph"):option("template", template):cwd(self.repo.dir):call_async()

		vim.schedule(function()
			if not result.success then
				vim.notify(
					"Failed to list rebase targets: " .. (result.stderr or "Unknown error"),
					vim.log.levels.ERROR
				)
				callback({})
				return
			end

			-- `jj log` lists newest-first (matching the log view, top = newest). Most
			-- vim.ui.select backends (telescope/snacks/fzf-lua) anchor the prompt at
			-- the bottom and render the first entry there, which would put the newest
			-- commit at the bottom. Build the list oldest-first (reversed) so those
			-- pickers show newest at the top, matching the log view.
			local commits = {}
			for _, line in ipairs(vim.split(result.stdout or "", "\n")) do
				if vim.trim(line) ~= "" then
					local commit_id, change_id, summary = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
					if commit_id and change_id ~= exclude_change_id then
						table.insert(commits, 1, { commit_id = commit_id, change_id = change_id, summary = summary })
					end
				end
			end
			callback(commits)
		end)
	end)
end

--- Rebase `source` onto a destination chosen interactively. First prompts for
--- which set of commits to move (-s/-r/-b, defaulting to -s), then picks a
--- destination from a fuzzy picker over the repo's commits. The `source`/`label`
--- pair is supplied per-view: the status view rebases the working copy (`@`), the
--- log view the change under the cursor. Safe to invoke from `vim.ui.*` callbacks
--- (which run outside any async context). Refreshes on success.
---@param source string Revision to rebase (the source)
---@param label string Short label for the source, used in prompts/messages
function ViewBuffer:_rebase(source, label)
	local mode_choices = {
		{ text = "Source + descendants (-s)", mode_key = "source" },
		{ text = "This revision only (-r)", mode_key = "revisions" },
		{ text = "Whole branch (-b)", mode_key = "branch" },
	}

	vim.ui.select(mode_choices, {
		prompt = "jj rebase " .. label .. ":",
		format_item = function(choice)
			return choice.text
		end,
	}, function(mode)
		if not mode then
			return
		end

		self:_fetch_rebase_targets(source, function(commits)
			if #commits == 0 then
				vim.notify("No other commits to rebase onto", vim.log.levels.WARN)
				return
			end
			vim.ui.select(commits, {
				prompt = "Rebase " .. label .. " onto:",
				format_item = function(commit)
					return commit.commit_id .. "  " .. commit.summary
				end,
			}, function(commit)
				if commit then
					self:_run_rebase({
						mode_key = mode.mode_key,
						source = source,
						dest = commit.commit_id,
						label = label,
					})
				end
			end)
		end)
	end)
end

return ViewBuffer
