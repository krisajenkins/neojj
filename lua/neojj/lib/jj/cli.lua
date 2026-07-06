local async = require("plenary.async")
local Job = require("plenary.job")
local logger = require("neojj.logger")

local Cli = {}
Cli.__index = Cli

-- Generous timeout (ms) for synchronous jj calls. plenary defaults to 5000ms,
-- which is too tight for large repos or a first-run working-copy snapshot.
local SYNC_TIMEOUT_MS = 60000

local function new_builder(cmd)
	local builder = setmetatable({}, Cli)
	builder.cmd = cmd or "jj"
	builder.args = { "--color", "never" }
	builder.options = {}
	builder._env = {}
	return builder
end

function Cli:arg(value)
	table.insert(self.args, value)
	return self
end

function Cli:option(key, value)
	if value then
		table.insert(self.args, "--" .. key)
		table.insert(self.args, value)
	else
		table.insert(self.args, "--" .. key)
	end
	return self
end

function Cli:flag(key)
	table.insert(self.args, "--" .. key)
	return self
end

function Cli:short_flag(key)
	table.insert(self.args, "-" .. key)
	return self
end

function Cli:env(key, value)
	self._env[key] = value
	return self
end

function Cli:cwd(dir)
	self.options.cwd = dir
	return self
end

function Cli:call()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()

	-- Resolve full path for jj command at call time, and fail loudly (rather
	-- than with a raw plenary stack trace) when it isn't on PATH.
	local command = self.cmd
	if command == "jj" then
		local jj_path = vim.fn.exepath("jj")
		if jj_path == "" then
			local msg = "jj executable not found on PATH"
			logger.error(msg)
			vim.notify("NeoJJ: " .. msg, vim.log.levels.ERROR)
			return {
				success = false,
				exit_code = -1,
				stdout = nil,
				stderr = msg,
			}
		end
		command = jj_path
	end

	logger.debug("Executing: " .. command .. " " .. table.concat(cmd_args, " ") .. " (cwd: " .. cwd .. ")")

	-- Guard both Job:new (which raises when the executable is missing) and
	-- job:sync (which raises on timeout) so an infrastructure failure becomes a
	-- normal failure table instead of a stack trace at the user.
	local ok, result = pcall(function()
		local job = Job:new({
			command = command,
			args = cmd_args,
			cwd = cwd,
			-- Only pass env when the caller has actually set variables. plenary's
			-- Job treats any non-nil env table as the *entire* child environment,
			-- so an empty-but-non-nil table would strip PATH, SSH_AUTH_SOCK,
			-- JJ_CONFIG, EDITOR, etc. Passing nil lets the child inherit ours.
			env = next(self._env) and self._env or nil,
		})
		-- plenary's Job:sync(timeout, wait_interval) accepts a timeout; its
		-- bundled type stub omits the params, so silence the false positive.
		---@diagnostic disable-next-line: redundant-parameter
		local stdout = job:sync(SYNC_TIMEOUT_MS)
		return { job = job, stdout = stdout }
	end)

	if not ok then
		local err = tostring(result)
		logger.error("Command failed: " .. err)
		-- Timeouts and spawn failures are infrastructure problems the buffers
		-- can't meaningfully render, so surface them directly to the user.
		if err:match("unable to complete") then
			vim.notify("NeoJJ: jj command timed out after " .. SYNC_TIMEOUT_MS .. "ms", vim.log.levels.WARN)
		else
			vim.notify("NeoJJ: failed to run jj: " .. err, vim.log.levels.ERROR)
		end
		return {
			success = false,
			exit_code = -1,
			stdout = nil,
			stderr = err,
		}
	end

	local job = result.job
	local exit_code = job.code
	local stdout = result.stdout or {}
	local stderr = job:stderr_result() or {}

	local success = exit_code == 0
	local stdout_str = type(stdout) == "table" and table.concat(stdout, "\n") or stdout
	local stderr_str = type(stderr) == "table" and table.concat(stderr, "\n") or stderr

	if not success then
		local error_msg = "Command failed with exit code " .. exit_code
		if stderr_str and stderr_str ~= "" then
			error_msg = error_msg .. ": " .. stderr_str
		end
		logger.error(error_msg)
	end

	return {
		success = success,
		exit_code = exit_code,
		stdout = stdout_str,
		stderr = stderr_str,
	}
end

function Cli:call_async()
	return async.wrap(function(callback)
		local result = self:call()
		callback(result)
	end, 1)()
end

local M = {}

function M.status()
	return new_builder("jj"):arg("status")
end

function M.log()
	return new_builder("jj"):arg("log")
end

function M.bookmark()
	return new_builder("jj"):arg("bookmark")
end

function M.show()
	return new_builder("jj"):arg("show")
end

function M.describe()
	return new_builder("jj"):arg("describe")
end

function M.operation()
	return new_builder("jj"):arg("operation")
end

function M.workspace()
	return new_builder("jj"):arg("workspace")
end

function M.file()
	return new_builder("jj"):arg("file")
end

function M.util()
	return new_builder("jj"):arg("util")
end

function M.debug()
	return new_builder("jj"):arg("debug")
end

function M.config()
	return new_builder("jj"):arg("config")
end

function M.git()
	return new_builder("jj"):arg("git")
end

function M.new()
	return new_builder("jj"):arg("new")
end

function M.raw()
	return new_builder("jj")
end

return M
