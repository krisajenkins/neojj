local jj = require("neojj.lib.jj")
local logger = require("neojj.logger")
local StatusBuffer = require("neojj.buffers.status")
local DescribeBuffer = require("neojj.buffers.describe")
local LogBuffer = require("neojj.buffers.log")
local CommitBuffer = require("neojj.buffers.commit")
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

	-- Create user commands
	vim.api.nvim_create_user_command("JJStatus", function(args)
		local split = args.args ~= "" and args.args or nil
		M.jj_status(nil, split)
	end, {
		nargs = "?",
		complete = function()
			return { "horizontal", "vertical", "tab" }
		end,
		desc = "Open JJ status buffer",
	})

	vim.api.nvim_create_user_command("JJDescribe", function(args)
		local revision = args.args ~= "" and args.args or "@"
		local split = nil -- TODO: Add split support for describe if needed
		M.jj_describe(nil, revision, split)
	end, {
		nargs = "?",
		desc = "Open JJ describe buffer for editing commit description",
	})

	vim.api.nvim_create_user_command("JJLog", function(args)
		local split = args.args ~= "" and args.args or nil
		M.jj_log(nil, split)
	end, {
		nargs = "?",
		complete = function()
			return { "horizontal", "vertical", "tab" }
		end,
		desc = "Open JJ log buffer",
	})

	vim.api.nvim_create_user_command("JJCommit", function(args)
		local parts = vim.split(args.args, " ")
		local commit_id = parts[1]
		local split = parts[2]

		if not commit_id or commit_id == "" then
			vim.notify("Usage: JJCommit <commit_id> [split_type]", vim.log.levels.ERROR)
			return
		end

		M.jj_commit(nil, commit_id, split)
	end, {
		nargs = "+",
		complete = function()
			return { "horizontal", "vertical", "tab" }
		end,
		desc = "Open JJ commit buffer for specific commit",
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
---@param split? string Split type ("horizontal", "vertical", "tab")
function M.jj_status(dir, split)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local status_buffer = StatusBuffer.new(repo)

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

---Open the JJ commit buffer UI for a specific commit
---@param dir? string Directory path (defaults to current working directory)
---@param commit_id string Commit identifier (change_id or commit_id)
---@param split? string Split type ("horizontal", "vertical", "tab")
function M.jj_commit(dir, commit_id, split)
	local repo = M.get_repo(dir)
	if not repo:is_jj_repo() then
		vim.notify("Not a jj repository", vim.log.levels.ERROR)
		return
	end

	local commit_buffer = CommitBuffer.new(repo, commit_id)

	if split == "horizontal" then
		commit_buffer:show_split("horizontal")
	elseif split == "vertical" then
		commit_buffer:show_split("vertical")
	elseif split == "tab" then
		commit_buffer:show_tab()
	else
		commit_buffer:show()
	end
end

return M
