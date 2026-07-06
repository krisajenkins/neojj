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

	-- jj emits an "unresolved conflicts" warning block on stdout, e.g.:
	--   Warning: There are unresolved conflicts at these paths:
	--   src/config.lua    2-sided conflict
	-- We track whether we're inside that block so the annotated path lines are
	-- parsed as conflicts rather than falling through to the file-status branches.
	local in_conflicts = false

	for _, line in ipairs(lines) do
		if in_conflicts then
			-- "<path><spaces>N-sided conflict"
			local conflict_path, sides = line:match("^(.-)%s%s+(%d+)%-sided conflict%s*$")
			if conflict_path and conflict_path ~= "" then
				---@type Conflict
				local conflict = {
					path = conflict_path,
					sides = tonumber(sides),
					annotation = sides .. "-sided conflict",
				}
				table.insert(working_copy.conflicts, conflict)
				working_copy.is_empty = false
				goto continue
			else
				-- Anything that isn't a conflict path line ends the block; fall
				-- through so the current line is processed normally.
				in_conflicts = false
			end
		end

		if line:match("^Warning: There are unresolved conflicts") then
			in_conflicts = true
		elseif line:match("^Working copy ") then
			-- Handle both formats:
			-- "Working copy : qpvuntsm ..."
			-- "Working copy  (@) : wwqvwtzo ..."
			local change_id = line:match("Working copy%s+%(@%)%s*:%s*(%w+)") or line:match("Working copy%s*:%s*(%w+)")
			if change_id then
				working_copy.change_id = change_id
			end
		elseif line:match("^Parent") then
			-- Handle both formats:
			-- "Parent: rlvkpnrz ..."
			-- "Parent commit (@-): okpkknwl ..."
			local parent_id = line:match("Parent%s+commit%s+%(@%-%)%s*:%s*(%w+)") or line:match("Parent%s*:%s*(%w+)")
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
		elseif line:match("^R ") then
			-- Handle renames in two formats:
			-- 1. "R {old_path => new_path}" - complete paths in braces
			-- 2. "R {old_dir => new_dir}/filename" - directories in braces, filename after
			local rename_info = line:match("^R (.+)")
			if rename_info then
				-- Try to match format with suffix after braces: {old => new}/suffix
				local old_prefix, new_prefix, suffix = rename_info:match("^{(.-)%s*=>%s*(.-)}(.+)$")
				if old_prefix and new_prefix and suffix then
					-- Format 2: directories in braces, filename after
					local old_path = old_prefix .. suffix
					local new_path = new_prefix .. suffix
					---@type ModifiedFile
					local modified_file = {
						status = "R",
						path = new_path,
						old_path = old_path,
					}
					table.insert(working_copy.modified_files, modified_file)
					working_copy.is_empty = false
				else
					-- Try format 1: complete paths in braces
					local old_path, new_path = rename_info:match("^{(.-)%s*=>%s*(.-)}$")
					if old_path and new_path then
						---@type ModifiedFile
						local modified_file = {
							status = "R",
							path = new_path,
							old_path = old_path,
						}
						table.insert(working_copy.modified_files, modified_file)
						working_copy.is_empty = false
					end
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
			-- "C" under "Working copy changes:" is a COPIED file (not a conflict).
			-- jj formats it like a rename: "C {source => dest}" (with an optional
			-- suffix after the braces), or occasionally as a bare path.
			local copy_info = line:match("^C (.+)")
			if copy_info then
				local old_prefix, new_prefix, suffix = copy_info:match("^{(.-)%s*=>%s*(.-)}(.+)$")
				local old_path, new_path
				if old_prefix and new_prefix and suffix then
					old_path = old_prefix .. suffix
					new_path = new_prefix .. suffix
				else
					old_path, new_path = copy_info:match("^{(.-)%s*=>%s*(.-)}$")
				end
				if not new_path then
					-- Bare path form: "C path"
					new_path = copy_info
					old_path = nil
				end
				---@type ModifiedFile
				local modified_file = {
					status = "C",
					path = new_path,
					old_path = old_path,
				}
				table.insert(working_copy.modified_files, modified_file)
				working_copy.is_empty = false
			end
		elseif line:match("^%? ") then
			-- Untracked path under "Untracked paths:"
			local file = line:match("^%? (.+)")
			if file then
				---@type ModifiedFile
				local modified_file = {
					status = "?",
					path = file,
				}
				table.insert(working_copy.modified_files, modified_file)
				working_copy.is_empty = false
			end
		end

		::continue::
	end

	return working_copy
end

return M
