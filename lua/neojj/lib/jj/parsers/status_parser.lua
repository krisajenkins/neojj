---Parser for jj status command output
---
---This module provides pure parsing functions for jj status output.
---All functions take string input and return structured data with no side effects.

local M = {}

---Parse working copy information from jj status output
---@param lines string[] Output lines from jj status command
---@return WorkingCopy Parsed working copy information
function M.parse_working_copy_info(lines)
	---@type WorkingCopy
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
				---@type ModifiedFile
				local modified_file = {
					status = status,
					path = file,
				}
				table.insert(working_copy.modified_files, modified_file)
				working_copy.is_empty = false
			end
		elseif line:match("^C ") then
			local file = line:match("^C (.+)")
			if file then
				---@type Conflict
				local conflict = {
					path = file,
				}
				table.insert(working_copy.conflicts, conflict)
			end
		end
	end

	return working_copy
end

return M
