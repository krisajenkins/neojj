-- Filesystem watcher that auto-refreshes open NeoJJ views when the repository
-- changes externally (a `jj` command run in another terminal, a colleague's
-- `jj git fetch`, etc.) — the equivalent of neogit watching `.git`.
--
-- WHAT WE WATCH. Not a single file but the DIRECTORY `<jj_dir>/repo/op_heads/
-- heads/`. jj records the current operation as a zero-byte file named after the
-- operation id inside `heads/`; every operation deletes the old file and creates
-- a fresh one. Watching that directory and firing on the create/rename churn of
-- its immediate children is therefore a reliable "the repo moved" signal.
--
-- CAVEATS (encoded here so they don't get rediscovered the hard way):
--   1. NeoJJ's own jj commands (push/fetch/new/commit/fix/tug/bookmark/undo/…)
--      also mutate op_heads, so they will trip this watcher on top of the
--      explicit refresh their handlers already do. That is benign: refresh is
--      debounced here, idempotent, and serialized by JjRepo.refresh_lock, so a
--      redundant fire just coalesces into a no-op.
--   2. `recursive = false` is correct and required — we only care about the
--      immediate children of `heads/`, never a subtree.
--   3. fs_event delivers no reliable "renamed-to" filename across platforms, so
--      we never parse the event filename: any event means "repo changed; go
--      re-query", and we simply fan out a refresh.
local util = require("neojj.lib.jj.util")
local logger = require("neojj.logger")

-- Match the existing vim.loop usage in cli.lua / the main neojj module, while
-- preferring the modern vim.uv alias when present.
local uv = vim.uv or vim.loop

local M = {}

-- Active watchers, keyed by repo root. Each entry is
--   { fs_handle?, poll_handle?, timer, dir }
-- exactly one of fs_handle / poll_handle is set depending on the backend chosen.
local watchers = {}

-- Debounce window: collapse a burst of create/rename events (jj rewrites several
-- files per operation) into a single refresh.
local DEBOUNCE_MS = 150
-- fs_poll cadence for the polling fallback backend.
local POLL_INTERVAL_MS = 2000

-- Guard so the VimLeavePre cleanup autocmd is only registered once.
local vimleave_hooked = false

-- The three buffer modules that expose `list_instances()`. Required lazily to
-- avoid a load-time require cycle (each buffer lazily requires this module from
-- its `_push_frame` / `on_detach`).
local function buffer_modules()
	return {
		require("neojj.buffers.status"),
		require("neojj.buffers.log"),
		require("neojj.buffers.oplog"),
	}
end

---Resolve the `op_heads/heads` directory to watch for a repository, or nil when
---it can't be watched (missing, or a jj-workspace layout we can't resolve).
---@param repo table Repository instance (responds to `get_jj_dir`)
---@return string? dir Absolute path to the op-heads directory, or nil
local function resolve_op_heads_dir(repo)
	local jj_dir = repo:get_jj_dir()
	if not jj_dir or jj_dir == "" then
		return nil
	end

	-- Normally `<jj_dir>/repo` is a directory. In a jj *workspace* (and some
	-- colocated layouts) `.jj/repo` is instead a FILE whose contents point at the
	-- real repository directory; follow that indirection when we see it.
	local repo_dir = util.path_join(jj_dir, "repo")
	if vim.fn.isdirectory(repo_dir) == 0 and vim.fn.filereadable(repo_dir) == 1 then
		local lines = vim.fn.readfile(repo_dir)
		local target = lines and lines[1] and vim.trim(lines[1])
		if target and target ~= "" then
			repo_dir = target
		end
	end

	local heads = util.path_join(repo_dir, "op_heads", "heads")
	if vim.fn.isdirectory(heads) == 1 then
		return heads
	end
	return nil
end

---Fan a refresh out to every valid open NeoJJ view whose repo root matches the
---changed root. refresh() is itself async, guarded by is_valid(), and serialized
---by JjRepo.refresh_lock, so duplicate/concurrent fires are safe.
---@param root string Repo root whose views should refresh
local function dispatch(root)
	for _, mod in ipairs(buffer_modules()) do
		if type(mod.list_instances) == "function" then
			for _, inst in ipairs(mod.list_instances()) do
				if inst:is_valid() and inst.repo and inst.repo:get_root() == root then
					-- Auto-refresh: refresh() logs nothing, so fs churn stays quiet.
					inst:refresh()
				end
			end
		end
	end
end

---Build the libuv event callback for a given root. The callback runs inside the
---libuv loop where Neovim API calls are ILLEGAL, so it does no work beyond
---(re)arming the debounce timer, whose expiry fires `dispatch` via
---`vim.schedule_wrap` (mandatory — that is what hops back onto the main loop).
---@param root string
---@param entry table The watcher entry (holds the debounce timer)
---@return function callback
local function make_callback(root, entry)
	return function(err, _fname, _events)
		if err then
			-- A transient error shouldn't tear the watcher down; just log it.
			logger.debug("watcher event error for " .. root .. ": " .. tostring(err))
		end
		entry.timer:stop()
		entry.timer:start(
			DEBOUNCE_MS,
			0,
			vim.schedule_wrap(function()
				dispatch(root)
			end)
		)
	end
end

---Try to arm a libuv handle's `start`, tolerating both the "raises" and the
---"returns nil, err" failure conventions across luv versions.
---@param start_fn function Zero-arg closure that calls handle:start(...)
---@return boolean ok True when the watch was armed
local function arm(start_fn)
	local ok, res = pcall(start_fn)
	-- luv's fs_event_start / fs_poll_start return 0 on success, or a failure
	-- signal (nil + errname) otherwise.
	return ok and res == 0
end

---Ensure a watcher exists for `repo`'s root. Idempotent: a second call for a
---root that is already watched is a no-op.
---@param repo table Repository instance
function M.ensure(repo)
	if not repo or type(repo.get_root) ~= "function" then
		return
	end
	local root = repo:get_root()
	if not root or root == "" then
		return
	end
	if watchers[root] then
		return
	end

	local dir = resolve_op_heads_dir(repo)
	if not dir then
		logger.debug("watcher: no op_heads/heads directory for " .. root .. "; auto-refresh disabled")
		return
	end

	local timer = uv.new_timer()
	if not timer then
		return
	end
	local entry = { timer = timer, dir = dir }
	watchers[root] = entry
	local cb = make_callback(root, entry)

	-- BACKEND CHOICE. On macOS, fs_event (kqueue/FSEvents) can silently stop
	-- delivering after the watched directory's entries are replaced — and jj
	-- deletes the old op-head file and creates a new one on *every* operation, so
	-- that failure mode is guaranteed here. Rather than stop()/re-start() the
	-- handle on each event, we simply prefer the fs_poll backend on macOS, which
	-- is robust against inode churn. Elsewhere fs_event is cheap and reliable, so
	-- we use it and fall back to polling only if it can't be armed.
	local use_poll = vim.fn.has("mac") == 1

	if not use_poll then
		local fs_handle = uv.new_fs_event()
		-- recursive = false: we only watch the immediate children of heads/.
		if fs_handle and arm(function()
			return fs_handle:start(dir, { recursive = false }, cb)
		end) then
			entry.fs_handle = fs_handle
		else
			if fs_handle then
				pcall(function()
					fs_handle:close()
				end)
			end
			use_poll = true
		end
	end

	if use_poll then
		local poll_handle = uv.new_fs_poll()
		if poll_handle and arm(function()
			return poll_handle:start(dir, POLL_INTERVAL_MS, cb)
		end) then
			entry.poll_handle = poll_handle
		else
			if poll_handle then
				pcall(function()
					poll_handle:close()
				end)
			end
			-- Neither backend could be armed; drop the half-built entry.
			pcall(function()
				timer:close()
			end)
			watchers[root] = nil
			logger.debug("watcher: failed to arm any fs watch for " .. root)
			return
		end
	end

	-- Stop every watcher when Neovim exits (registered once, lazily).
	if not vimleave_hooked then
		vimleave_hooked = true
		vim.api.nvim_create_autocmd("VimLeavePre", {
			callback = function()
				M.stop_all()
			end,
		})
	end

	logger.debug("watcher: watching " .. dir .. " (" .. (entry.fs_handle and "fs_event" or "fs_poll") .. ")")
end

---Stop and dispose of the watcher for a root, if any.
---@param root string
function M.stop(root)
	local entry = watchers[root]
	if not entry then
		return
	end
	watchers[root] = nil
	for _, key in ipairs({ "fs_handle", "poll_handle", "timer" }) do
		local handle = entry[key]
		if handle then
			pcall(function()
				handle:stop()
			end)
			pcall(function()
				handle:close()
			end)
		end
	end
end

---Stop the watcher for a root if no open NeoJJ view still uses it. Call after a
---buffer detaches (once it has removed itself from its own instances table).
---@param root string
function M.cleanup(root)
	if not watchers[root] then
		return
	end
	for _, mod in ipairs(buffer_modules()) do
		if type(mod.list_instances) == "function" then
			for _, inst in ipairs(mod.list_instances()) do
				if inst.repo and inst.repo:get_root() == root then
					return -- still in use by an open view
				end
			end
		end
	end
	M.stop(root)
end

---Stop every active watcher (used on VimLeavePre). Removing the current key
---during a `pairs` traversal is permitted in Lua.
function M.stop_all()
	for root in pairs(watchers) do
		M.stop(root)
	end
end

---Test/introspection helper: how many watchers are currently active.
---@return number count
function M.active_count()
	return vim.tbl_count(watchers)
end

return M
