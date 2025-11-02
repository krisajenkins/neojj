local cli = require("neojj.lib.jj.cli")
local logger = require("neojj.logger")
local status_parser = require("neojj.lib.jj.parsers.status_parser")
local json_parser = require("neojj.lib.jj.parsers.json_parser")

local M = {}

---Refresh repository status
---@param repo table Repository instance
function M.refresh(repo)
	logger.debug("Refreshing status for repository: " .. repo.dir)

	-- Get status output (no template support, must parse with regex)
	local result = cli.status():cwd(repo.dir):call()

	if not result.success then
		logger.error("Failed to get status: " .. tostring(result.stderr))
		return
	end

	local lines = vim.split(result.stdout, "\n")
	repo.state.working_copy = status_parser.parse_working_copy_info(lines)

	-- Get working copy details via JSON template
	local show_result = cli.log()
		:arg("-r")
		:arg("@")
		:option("template", "json(self)")
		:flag("no-graph")
		:cwd(repo.dir)
		:call()

	if show_result.success and show_result.stdout then
		local log_json, err = json_parser.parse_log_json(show_result.stdout)
		if log_json then
			-- Merge JSON data into working_copy (preserving modified_files from status)
			local modified_files = repo.state.working_copy.modified_files
			local conflicts = repo.state.working_copy.conflicts
			local is_empty = repo.state.working_copy.is_empty

			repo.state.working_copy = json_parser.json_to_working_copy(log_json)
			repo.state.working_copy.modified_files = modified_files
			repo.state.working_copy.conflicts = conflicts
			repo.state.working_copy.is_empty = is_empty
		else
			logger.warn("Failed to parse working copy JSON: " .. tostring(err))
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
