---Parser utilities for jj JSON output
---
---This module provides utilities for parsing JSON output from jj commands.
---All functions are pure and have no side effects.

local M = {}

---Parse JSON output from jj log command
---@param json_str string JSON string from jj log -T 'json(self)'
---@return JjLogJson|nil Parsed JSON data, or nil on error
---@return string|nil Error message if parsing failed
function M.parse_log_json(json_str)
	local ok, result = pcall(vim.json.decode, json_str)
	if not ok then
		return nil, "Failed to parse JSON: " .. tostring(result)
	end

	-- Validate that we have the expected structure
	if type(result) ~= "table" then
		return nil, "Expected JSON object, got " .. type(result)
	end

	-- Type assertion for LuaLS
	---@type JjLogJson
	local log_data = result

	return log_data, nil
end

---Convert JjLogJson to WorkingCopy format
---@param log_json JjLogJson Parsed JSON from jj log
---@return WorkingCopy Working copy information
function M.json_to_working_copy(log_json)
	---@type WorkingCopy
	local working_copy = {
		change_id = log_json.change_id,
		commit_id = log_json.commit_id,
		description = log_json.description or "",
		author = {
			name = log_json.author and log_json.author.name or "",
			email = log_json.author and log_json.author.email or "",
		},
		parent_ids = log_json.parents or {},
		modified_files = {},
		conflicts = {},
		is_empty = true, -- Will be determined by status parsing
	}

	return working_copy
end

---Parse a single line of JSON output (for commands that output one JSON object per line)
---@param output string Multi-line output where each line is a JSON object
---@return JjLogJson[] Array of parsed JSON objects
---@return string[] Array of error messages (empty if all succeeded)
function M.parse_json_lines(output)
	local lines = vim.split(output, "\n")
	---@type JjLogJson[]
	local results = {}
	---@type string[]
	local errors = {}

	for i, line in ipairs(lines) do
		if line ~= "" then
			local json_data, err = M.parse_log_json(line)
			if json_data then
				table.insert(results, json_data)
			else
				table.insert(errors, string.format("Line %d: %s", i, err))
			end
		end
	end

	return results, errors
end

return M
