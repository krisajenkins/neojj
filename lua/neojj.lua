local jj = require("neojj.lib.jj")
local logger = require("neojj.logger")
local StatusBuffer = require("neojj.buffers.status")
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

return M
