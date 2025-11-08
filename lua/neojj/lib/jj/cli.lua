local async = require("plenary.async")
local Job = require("plenary.job")
local logger = require("neojj.logger")

local Cli = {}
Cli.__index = Cli

local function new_builder(cmd)
	local builder = setmetatable({}, Cli)
	builder.cmd = cmd or "jj"
	builder.args = { "--color", "never" }
	builder.options = {}
	builder.env = {}
	return builder
end

function Cli:arg(value)
	table.insert(self.args, value)
	return self
end

function Cli:args(values)
	vim.list_extend(self.args, values)
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
	self.env[key] = value
	return self
end

function Cli:cwd(dir)
	self.options.cwd = dir
	return self
end

function Cli:call()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()

	-- Resolve full path for jj command at call time
	local command = self.cmd
	if command == "jj" then
		local jj_path = vim.fn.exepath("jj")
		if jj_path ~= "" then
			command = jj_path
		end
	end

	logger.debug("Executing: " .. command .. " " .. table.concat(cmd_args, " ") .. " (cwd: " .. cwd .. ")")

	local job = Job:new({
		command = command,
		args = cmd_args,
		cwd = cwd,
		env = self.env,
	})

	local ok, result = pcall(function()
		return job:sync()
	end)

	if not ok then
		logger.error("Command failed: " .. tostring(result))
		return {
			success = false,
			exit_code = -1,
			stdout = nil,
			stderr = tostring(result),
		}
	end

	local exit_code = job.code
	local stdout = result or {}
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
