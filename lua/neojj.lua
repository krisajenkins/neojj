local jj = require("neojj.lib.jj")
local logger = require("neojj.logger")
local StatusBuffer = require("neojj.buffers.status")
local DescribeBuffer = require("neojj.buffers.describe")
local LogBuffer = require("neojj.buffers.log")
local OplogBuffer = require("neojj.buffers.oplog")
local AnnotateBuffer = require("neojj.buffers.annotate")
local Highlights = require("neojj.highlights")

---@class NeoJJSetupOptions
---@field log_level? number Log level for the logger
---@field log_limit? number Default number of revisions shown in the log view

---@class JjRepo
---@field dir string
---@field state table
---@field modules table
---@field refresh_lock table
---@field refresh function
---@field is_jj_repo function
---@field get_working_copy function
---@field get_root function
---@field get_jj_dir function
---@field get_bookmarks function
---@field get_revisions function

-- WorkingCopy is defined canonically in lua/neojj/lib/jj/types.lua

local M = {}

-- Runtime configuration, seeded with defaults and overridden by setup(). The
-- log view reads log_limit here so a high cap flows through without callers
-- having to pass it every time.
M.config = {
	log_limit = 100,
}

---Setup NeoJJ with the given options
---@param opts? NeoJJSetupOptions Configuration options
function M.setup(opts)
	opts = opts or {}

	-- Validate options up front so misconfiguration (e.g. a string log_level,
	-- which silently breaks the logger's numeric comparisons) fails loudly.
	vim.validate("opts", opts, "table")
	vim.validate("log_level", opts.log_level, "number", true)
	vim.validate("log_limit", opts.log_limit, "number", true)

	if opts.log_level then
		logger.set_level(opts.log_level)
	end

	if opts.log_limit then
		M.config.log_limit = opts.log_limit
	end

	-- Setup highlight groups
	Highlights.setup()

	-- Register the :JJ command. Idempotent: nvim_create_user_command overwrites,
	-- so calling setup() after plugin load is harmless.
	M.create_commands()
end

---Create NeoJJ user commands.
---
---Registered from plugin/neojj.lua on load so the :JJ command works without a
---setup() call, and re-run by setup() for backwards compatibility.
function M.create_commands()
	-- Create unified :JJ command with subcommands
	vim.api.nvim_create_user_command("JJ", function(args)
		local subcommand = args.fargs[1]
		local rest_args = vim.list_slice(args.fargs, 2)

		-- No-arg `:JJ` means "return to the view stack": raise the top NeoJJ view
		-- (log/status/file) from wherever the user is, e.g. a file opened from a
		-- status view.
		if not subcommand then
			M.jj_back()
			return
		end

		if subcommand == "status" then
			local arg1 = rest_args[1]
			local arg2 = rest_args[2]

			-- Determine if arg1 is a split type or change_id
			local split_types = { "horizontal", "vertical", "tab" }
			local is_split = arg1 and vim.tbl_contains(split_types, arg1)

			local change_id, split
			if is_split then
				-- First arg is split type
				change_id = nil
				split = arg1
			else
				-- First arg is change_id (or nil), second is split
				change_id = arg1
				split = arg2
			end

			M.jj_status(nil, change_id, split)
		elseif subcommand == "describe" then
			local revision = rest_args[1] or "@"
			local split = rest_args[2]
			M.jj_describe(nil, revision, split)
		elseif subcommand == "log" then
			-- Accept an optional split type and an optional positional revision
			-- count, in either order: `:JJ log`, `:JJ log 50`,
			-- `:JJ log vertical` or `:JJ log vertical 50`.
			local arg1 = rest_args[1]
			local arg2 = rest_args[2]
			local log_split_types = { "horizontal", "vertical", "tab" }
			local split, limit
			if arg1 and vim.tbl_contains(log_split_types, arg1) then
				split = arg1
				limit = tonumber(arg2)
			else
				limit = tonumber(arg1)
			end
			M.jj_log(nil, split, limit)
		elseif subcommand == "oplog" then
			-- `:JJ oplog [split]` opens the operation log; `:JJ oplog <op_id> [split]`
			-- jumps straight to that operation's op-show view. Disambiguate the first
			-- arg the way `:JJ log` does — a known split keyword is a split, anything
			-- else is an operation id.
			local arg1 = rest_args[1]
			local oplog_split_types = { "horizontal", "vertical", "tab" }
			if arg1 and not vim.tbl_contains(oplog_split_types, arg1) then
				M.jj_opshow(nil, arg1, rest_args[2])
			else
				M.jj_oplog(nil, arg1)
			end
		elseif subcommand == "new" then
			local revision = rest_args[1]
			M.jj_new(nil, revision)
		elseif subcommand == "annotate" then
			local filepath = rest_args[1]
			M.jj_annotate(nil, filepath)
		elseif subcommand == "split" then
			local revision = rest_args[1]
			M.jj_split(nil, revision)
		else
			vim.notify("Unknown JJ subcommand: " .. (subcommand or ""), vim.log.levels.ERROR)
			vim.notify("Available: status, describe, log, oplog, new, annotate, split", vim.log.levels.INFO)
		end
	end, {
		-- "*" (not "+") so a bare `:JJ` is valid and routes to jj_back().
		nargs = "*",
		complete = function(arglead, cmdline, _cursorpos)
			local args = vim.split(cmdline, "%s+")
			local num_args = #args

			-- If we're completing the first argument (subcommand)
			if num_args <= 2 then
				local subcommands = { "status", "describe", "log", "oplog", "new", "annotate", "split" }
				return vim.tbl_filter(function(cmd)
					return vim.startswith(cmd, arglead)
				end, subcommands)
			end

			-- If we're completing split type for status/log/describe
			local subcommand = args[2]
			if subcommand == "status" then
				if num_args == 3 then
					-- Could be change_id or split type
					local splits = { "horizontal", "vertical", "tab" }
					return vim.tbl_filter(function(split)
						return vim.startswith(split, arglead)
					end, splits)
				elseif num_args == 4 then
					-- Third arg is split type (after change_id)
					local splits = { "horizontal", "vertical", "tab" }
					return vim.tbl_filter(function(split)
						return vim.startswith(split, arglead)
					end, splits)
				end
			elseif subcommand == "log" then
				if num_args == 3 then
					local splits = { "horizontal", "vertical", "tab" }
					return vim.tbl_filter(function(split)
						return vim.startswith(split, arglead)
					end, splits)
				end
			elseif subcommand == "oplog" then
				if num_args == 3 then
					local splits = { "horizontal", "vertical", "tab" }
					return vim.tbl_filter(function(split)
						return vim.startswith(split, arglead)
					end, splits)
				end
			elseif subcommand == "describe" then
				-- For describe, second arg could be revision or split
				-- Third arg would be split
				if num_args == 4 then
					local splits = { "horizontal", "vertical", "tab" }
					return vim.tbl_filter(function(split)
						return vim.startswith(split, arglead)
					end, splits)
				end
			end

			return {}
		end,
		desc = "JJ commands (no arg: return to view stack; status, describe, log, oplog, new, annotate, split)",
	})
end

---Return to the NeoJJ view stack.
---
---Bound to the no-arg `:JJ` command. Raises the top stack frame (the most
---recent log/status/file view) from wherever the user is; when already on the
---top frame (e.g. a file opened from a status view), steps back one level.
function M.jj_back()
	require("neojj.lib.view_stack").raise()
end

---Get a JJ repository instance for the given directory
---@param dir? string Directory path (defaults to current working directory)
---@return JjRepo repo Repository instance
function M.get_repo(dir)
	return jj.instance(dir)
end

---Open the JJ status buffer UI
---@param dir? string Directory path (defaults to current working directory)
---@param revision? string Revision to show status for (defaults to working copy)
---@param split? string Split type ("horizontal", "vertical", "tab")
function M.jj_status(dir, revision, split)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local status_buffer = StatusBuffer.new(repo, revision)

	if split == "horizontal" then
		status_buffer:show_split("horizontal")
	elseif split == "vertical" then
		status_buffer:show_split("vertical")
	elseif split == "tab" then
		status_buffer:show_tab()
	else
		status_buffer:show()
	end
end

---Open the JJ describe buffer UI for editing commit description
---@param dir? string Directory path (defaults to current working directory)
---@param revision? string Revision to describe (defaults to @)
---@param split? string Split type ("horizontal", "vertical", "tab")
function M.jj_describe(dir, revision, split)
	revision = revision or "@"
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	-- Re-focus an open status view (if one is visible) after describe tears down.
	-- describe's submit()/abort() now close the describe buffer before invoking
	-- these callbacks, so we act synchronously instead of deferring past the
	-- window teardown with a timer.
	local function refocus_status(status_buffer)
		if not status_buffer then
			return
		end
		local windows = vim.fn.win_findbuf(status_buffer.buffer.handle)
		if #windows > 0 then
			vim.api.nvim_set_current_win(windows[1])
		end
	end

	local function on_submit()
		vim.notify("Description updated for " .. revision, vim.log.levels.INFO)

		-- Refresh and re-focus an open status view, mirroring what the status/log
		-- describe handlers do for their own views.
		local status_buffer = StatusBuffer.list_instances()[1]
		if status_buffer then
			status_buffer:refresh()
			refocus_status(status_buffer)
		end
	end

	local function on_abort()
		refocus_status(StatusBuffer.list_instances()[1])
	end

	local describe_buffer = DescribeBuffer.new(repo, revision, on_submit, on_abort)

	if split == "horizontal" then
		describe_buffer:show_split("horizontal")
	elseif split == "vertical" then
		describe_buffer:show_split("vertical")
	elseif split == "tab" then
		describe_buffer:show_tab()
	else
		describe_buffer:show()
	end
end

---Open the JJ log buffer UI
---@param dir? string Directory path (defaults to current working directory)
---@param split? string Split type ("horizontal", "vertical", "tab")
---@param limit? number Number of revisions to show (defaults to configured log_limit)
function M.jj_log(dir, split, limit)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local log_buffer = LogBuffer.new(repo, { limit = limit or M.config.log_limit })

	if split == "horizontal" then
		log_buffer:show_split("horizontal")
	elseif split == "vertical" then
		log_buffer:show_split("vertical")
	elseif split == "tab" then
		log_buffer:show_tab()
	else
		log_buffer:show()
	end
end

---Open the JJ operation-log buffer UI
---@param dir? string Directory path (defaults to current working directory)
---@param split? string Split type ("horizontal", "vertical", "tab")
function M.jj_oplog(dir, split)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local oplog_buffer = OplogBuffer.new(repo)

	if split == "horizontal" then
		oplog_buffer:show_split("horizontal")
	elseif split == "vertical" then
		oplog_buffer:show_split("vertical")
	elseif split == "tab" then
		oplog_buffer:show_tab()
	else
		oplog_buffer:show()
	end
end

---Open the op-show view for a specific operation (`jj op show <op_id>`). This is
---the same view reached by pressing <CR> on an operation in the oplog; exposing
---it here lets `:JJ oplog <op_id>` jump straight to it.
---@param dir? string Directory to resolve the repo from
---@param op_id string Operation id to show
---@param split? string Optional split type ("horizontal", "vertical", "tab")
function M.jj_opshow(dir, op_id, split)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local OpShowBuffer = require("neojj.buffers.opshow")
	local opshow_buffer = OpShowBuffer.new(repo, op_id)

	if split == "horizontal" then
		opshow_buffer:show_split("horizontal")
	elseif split == "vertical" then
		opshow_buffer:show_split("vertical")
	elseif split == "tab" then
		opshow_buffer:show_tab()
	else
		opshow_buffer:show()
	end
end

---Create a new empty change
---@param dir? string Directory path (defaults to current working directory)
---@param revision? string Revision to create new change after (optional)
function M.jj_new(dir, revision)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		local builder = cli.new():cwd(repo.dir)

		-- Add revision argument if provided
		if revision and revision ~= "" then
			builder:arg(revision)
		end

		local result = builder:call()

		vim.schedule(function()
			if result and result.success then
				vim.notify("Created new change", vim.log.levels.INFO)
				-- Note: Buffers will auto-refresh when user navigates back to them
			else
				local stderr = result and result.stderr or "Unknown error"
				vim.notify("Failed to create new change: " .. stderr, vim.log.levels.ERROR)
			end
		end)
	end)
end

---Open the JJ annotate buffer for a file
---@param dir? string Directory path (defaults to current working directory)
---@param filepath? string File path to annotate (defaults to current file)
function M.jj_annotate(dir, filepath)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	-- Use the true repository root, not repo.dir (which is Neovim's cwd at first
	-- use and may sit above/below the actual root). Normalise via fs_realpath so
	-- symlinked paths (e.g. /tmp vs /private/tmp on macOS) compare equal.
	local root = repo:get_root() or repo.dir
	root = vim.loop.fs_realpath(root) or root

	-- If no filepath provided, use the current buffer's file
	if not filepath or filepath == "" then
		local current_file = vim.api.nvim_buf_get_name(0)
		if current_file == "" then
			vim.notify("No file to annotate. Provide a filename or open a file.", vim.log.levels.ERROR)
			return
		end
		current_file = vim.loop.fs_realpath(current_file) or current_file

		-- Make filepath relative to the repo root, anchoring the prefix test with
		-- a trailing separator so /a/bc does not match a root of /a/b.
		local root_prefix = root .. "/"
		if current_file:sub(1, #root_prefix) == root_prefix then
			filepath = current_file:sub(#root_prefix + 1)
		else
			vim.notify("Current file is not in the repository", vim.log.levels.ERROR)
			return
		end
	end

	local source_bufnr = vim.api.nvim_get_current_buf()

	-- If the source file is not already open, open it
	local full_path = root .. "/" .. filepath
	if vim.api.nvim_buf_get_name(source_bufnr) ~= full_path then
		-- Find or create buffer for the file
		local existing_bufs = vim.tbl_filter(function(buf)
			return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == full_path
		end, vim.api.nvim_list_bufs())

		if #existing_bufs > 0 then
			source_bufnr = existing_bufs[1]
		else
			-- Open the file
			vim.cmd("edit " .. vim.fn.fnameescape(full_path))
			source_bufnr = vim.api.nvim_get_current_buf()
		end
	end

	local annotate_buffer = AnnotateBuffer.new(repo, filepath, source_bufnr)
	annotate_buffer:show()
end

---Open a terminal to interactively split a commit
---@param dir? string Directory path (defaults to current working directory)
---@param revision? string Revision to split (defaults to @)
function M.jj_split(dir, revision)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local args = { "jj", "split" }
	if revision and revision ~= "" then
		table.insert(args, "-r")
		table.insert(args, revision)
	end

	-- Launch the terminal rooted at the repo root via cwd, rather than mutating
	-- the window's local directory with :lcd (which was never restored). The
	-- argv form also avoids shell-quoting the revset. enew gives jobstart a fresh
	-- buffer to convert into the terminal, mirroring the old :terminal behaviour.
	vim.cmd("enew")
	vim.fn.jobstart(args, { cwd = repo:get_root() or repo.dir, term = true })
	vim.cmd("startinsert")
end

return M
