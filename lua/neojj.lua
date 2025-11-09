local jj = require("neojj.lib.jj")
local logger = require("neojj.logger")
local StatusBuffer = require("neojj.buffers.status")
local DescribeBuffer = require("neojj.buffers.describe")
local LogBuffer = require("neojj.buffers.log")
local AnnotateBuffer = require("neojj.buffers.annotate")
local Highlights = require("neojj.highlights")

---@class NeoJJSetupOptions
---@field log_level? number Log level for the logger

---@class JjRepo
---@field dir string
---@field state table
---@field modules table
---@field refresh_lock table
---@field refresh function
---@field is_jj_repo function
---@field get_working_copy function

---@class WorkingCopy
---@field change_id? string
---@field commit_id? string
---@field description string
---@field author { name: string, email: string }
---@field modified_files { status: string, path: string }[]
---@field conflicts { path: string }[]
---@field is_empty boolean

local M = {}

---Setup NeoJJ with the given options
---@param opts? NeoJJSetupOptions Configuration options
function M.setup(opts)
	opts = opts or {}

	if opts.log_level then
		logger.set_level(opts.log_level)
	end

	-- Setup highlight groups
	Highlights.setup()

	-- Create unified :JJ command with subcommands
	vim.api.nvim_create_user_command("JJ", function(args)
		local subcommand = args.fargs[1]
		local rest_args = vim.list_slice(args.fargs, 2)

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
			local split = rest_args[1]
			M.jj_log(nil, split)
		elseif subcommand == "new" then
			local revision = rest_args[1]
			M.jj_new(nil, revision)
		elseif subcommand == "annotate" then
			local filepath = rest_args[1]
			M.jj_annotate(nil, filepath)
		else
			vim.notify("Unknown JJ subcommand: " .. (subcommand or ""), vim.log.levels.ERROR)
			vim.notify("Available: status, describe, log, new, annotate", vim.log.levels.INFO)
		end
	end, {
		nargs = "+",
		complete = function(arglead, cmdline, _cursorpos)
			local args = vim.split(cmdline, "%s+")
			local num_args = #args

			-- If we're completing the first argument (subcommand)
			if num_args <= 2 then
				local subcommands = { "status", "describe", "log", "new", "annotate" }
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
		desc = "JJ commands (status, describe, log, new, annotate)",
	})
end

---Get a JJ repository instance for the given directory
---@param dir? string Directory path (defaults to current working directory)
---@return JjRepo repo Repository instance
function M.get_repo(dir)
	return jj.instance(dir)
end

---Display the status of a JJ repository (legacy text-based)
---@param dir? string Directory path (defaults to current working directory)
function M.status(dir)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		print("Not a jj repository")
		return
	end

	local async = require("plenary.async")

	async.run(function()
		repo:refresh()

		---@type WorkingCopy
		local wc = repo:get_working_copy()
		print("Working Copy:\n")
		print("  Change ID: " .. (wc.change_id or "unknown"))
		print("  Commit ID: " .. (wc.commit_id or "unknown"))
		print("  Description: " .. (wc.description or ""))
		print("  Author: " .. wc.author.name .. " <" .. wc.author.email .. ">\n")

		if #wc.modified_files > 0 then
			print("\nModified files:\n")
			for _, file in ipairs(wc.modified_files) do
				print("  " .. file.status .. " " .. file.path)
			end
		end

		if #wc.conflicts > 0 then
			print("\nConflicts:\n")
			for _, conflict in ipairs(wc.conflicts) do
				print("  C " .. conflict.path)
			end
		end

		if wc.is_empty then
			print("\nNo changes in working copy\n")
		end
	end)
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

	-- Callback to refresh status buffer if it exists
	local function on_submit()
		vim.notify("Description updated for " .. revision, vim.log.levels.INFO)

		-- Look for any open status buffers and refresh/focus them
		local status_buffers = vim.tbl_filter(function(buf)
			if not vim.api.nvim_buf_is_valid(buf) then
				return false
			end
			local name = vim.api.nvim_buf_get_name(buf)
			return name:match("JJ Status") ~= nil
		end, vim.api.nvim_list_bufs())

		if #status_buffers > 0 then
			-- Focus the first status buffer found
			local status_buf = status_buffers[1]
			local windows = vim.fn.win_findbuf(status_buf)
			if #windows > 0 then
				vim.defer_fn(function()
					vim.api.nvim_set_current_win(windows[1])
				end, 100)
			end
		end
	end

	local function on_abort()
		-- Look for any open status buffers and focus them on abort too
		local status_buffers = vim.tbl_filter(function(buf)
			if not vim.api.nvim_buf_is_valid(buf) then
				return false
			end
			local name = vim.api.nvim_buf_get_name(buf)
			return name:match("JJ Status") ~= nil
		end, vim.api.nvim_list_bufs())

		if #status_buffers > 0 then
			-- Focus the first status buffer found
			local status_buf = status_buffers[1]
			local windows = vim.fn.win_findbuf(status_buf)
			if #windows > 0 then
				vim.defer_fn(function()
					vim.api.nvim_set_current_win(windows[1])
				end, 100)
			end
		end
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
function M.jj_log(dir, split)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local log_buffer = LogBuffer.new(repo)

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
			if result.success then
				vim.notify("Created new change", vim.log.levels.INFO)
				-- Note: Buffers will auto-refresh when user navigates back to them
			else
				vim.notify("Failed to create new change: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
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

	-- If no filepath provided, use the current buffer's file
	if not filepath or filepath == "" then
		local current_file = vim.api.nvim_buf_get_name(0)
		if current_file == "" then
			vim.notify("No file to annotate. Provide a filename or open a file.", vim.log.levels.ERROR)
			return
		end

		-- Make filepath relative to repo root
		local repo_dir = repo.dir
		if current_file:sub(1, #repo_dir) == repo_dir then
			filepath = current_file:sub(#repo_dir + 2) -- +2 to skip the directory separator
		else
			vim.notify("Current file is not in the repository", vim.log.levels.ERROR)
			return
		end
	end

	local source_bufnr = vim.api.nvim_get_current_buf()

	-- If the source file is not already open, open it
	local full_path = repo.dir .. "/" .. filepath
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

return M
