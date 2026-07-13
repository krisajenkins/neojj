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

return ViewBuffer
