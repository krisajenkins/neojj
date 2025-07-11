local cli = require("neojj.lib.jj.cli")
local logger = require("neojj.logger")

local M = {}

local function parse_working_copy_info(lines)
	local working_copy = {
		change_id = nil,
		commit_id = nil,
		description = "",
		author = { name = "", email = "" },
		parent_ids = {},
		modified_files = {},
		conflicts = {},
		is_empty = true,
	}

	for _, line in ipairs(lines) do
		if line:match("^Working copy ") then
			local change_id = line:match("Working copy : (%w+)")
			if change_id then
				working_copy.change_id = change_id
			end
		elseif line:match("^Parent: ") then
			local parent_id = line:match("Parent: (%w+)")
			if parent_id then
				table.insert(working_copy.parent_ids, parent_id)
			end
		elseif line:match("^Author: ") then
			local author_info = line:match("Author: (.+)")
			if author_info then
				local name, email = author_info:match("([^<]+)%s*<([^>]+)>")
				if name and email then
					working_copy.author.name = vim.trim(name)
					working_copy.author.email = vim.trim(email)
				end
			end
		elseif line:match("^M ") or line:match("^A ") or line:match("^D ") then
			local status, file = line:match("^([MAD]) (.+)")
			if status and file then
				table.insert(working_copy.modified_files, {
					status = status,
					path = file,
				})
				working_copy.is_empty = false
			end
		elseif line:match("^C ") then
			local file = line:match("^C (.+)")
			if file then
				table.insert(working_copy.conflicts, {
					path = file,
				})
			end
		end
	end

	return working_copy
end

function M.refresh(repo)
	logger.debug("Refreshing status for repository: " .. repo.dir)

	local result = cli.status():cwd(repo.dir):call()

	if not result.success then
		logger.error("Failed to get status: " .. tostring(result.stderr))
		return
	end

	local lines = vim.split(result.stdout, "\n")
	repo.state.working_copy = parse_working_copy_info(lines)

	local show_result = cli.log()
		:arg("-r")
		:arg("@")
		:option("template", 'change_id ++ "\\n" ++ commit_id ++ "\\n" ++ description')
		:flag("no-graph")
		:cwd(repo.dir)
		:call()

	if show_result.success and show_result.stdout then
		local show_lines = vim.split(show_result.stdout, "\n")
		if #show_lines >= 3 then
			repo.state.working_copy.change_id = show_lines[1]
			repo.state.working_copy.commit_id = show_lines[2]
			repo.state.working_copy.description = table.concat(vim.list_slice(show_lines, 3), "\n")
		end
	else
		logger.warn("Failed to get working copy details: " .. tostring(show_result.stderr))
	end

	logger.debug("Status refresh completed")
end

function M.setup(repo)
	repo:register_module("status", M)
end

return M
