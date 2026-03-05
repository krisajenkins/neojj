---Parser for jj log command output (with ASCII graph)
---
---This module provides pure parsing functions for jj log graph output.
---All functions take string input and return structured data with no side effects.

local M = {}

---Parse jj log output with ASCII graph visualization
---@param output string Raw output from jj log command
---@return ParsedLog Parsed log with revisions, graph data, and raw lines
function M.parse_log_output(output)
	local lines = vim.split(output, "\n")
	---@type LogRevision[]
	local revisions = {}
	---@type table<integer, GraphData>
	local graph_data = {}

	---@type LogRevision|nil
	local current_revision = nil

	for i, line in ipairs(lines) do
		if line == "" then
			-- Skip empty lines
			goto continue
		end

		-- Check if this is a commit line (starts with @ or ○ and contains commit info)
		local graph_part, commit_info = line:match("^([│@○◆%s├└┤┬┴─┌┐┘]*)(.*)")

		-- Check if this line has commit data (change_id, author, timestamp, commit_id)
		local change_id, author, date_part, time_part, rest = nil, nil, nil, nil, nil
		if commit_info and commit_info ~= "" then
			change_id, author, date_part, time_part, rest =
				commit_info:match("^%s*(%S+)%s+(%S+@%S+)%s+(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%s+(.*)")
		end

		if change_id and author and date_part and time_part and rest then
			-- Parse the rest: everything before the last word is bookmarks, last word is commit_id
			local words = vim.split(rest, "%s+", { trimempty = true })
			local commit_id = words[#words]
			local bookmarks = {}
			for w = 1, #words - 1 do
				table.insert(bookmarks, words[w])
			end

			-- This is a commit header line with actual commit data
			if current_revision then
				-- Save previous revision
				table.insert(revisions, current_revision)
			end

			---@type LogRevision
			current_revision = {
				change_id = change_id,
				author = author,
				timestamp = date_part .. " " .. time_part,
				commit_id = commit_id,
				bookmarks = bookmarks,
				description = "",
				graph = graph_part,
				line_number = i,
			}

			-- Store graph information
			---@type GraphData
			graph_data[i] = {
				graph = graph_part,
				revision = current_revision,
			}
		else
			-- This is a description line or graph continuation
			if current_revision then
				local desc_part = line:match("^[│@○◆%s├└┤┬┴─┌┐┘╮╯╭╰]*(.+)")
				if desc_part and desc_part ~= "" then
					-- Only capture the first line of description for metadata
					-- The UI will render all lines from raw_lines anyway
					if current_revision.description == "" then
						current_revision.description = desc_part
					end
					-- Don't concatenate with \n - let UI handle multiline from raw_lines
				end
			end

			-- Store graph line even if no commit info
			if graph_part then
				---@type GraphData
				graph_data[i] = {
					graph = graph_part,
					revision = nil,
				}
			end
		end

		::continue::
	end

	-- Don't forget the last revision
	if current_revision then
		table.insert(revisions, current_revision)
	end

	---@type ParsedLog
	return {
		revisions = revisions,
		graph_data = graph_data,
		raw_lines = lines,
	}
end

return M
