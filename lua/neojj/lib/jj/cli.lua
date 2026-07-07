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

-- Resolve the command to an absolute path, failing loudly (rather than with a
-- raw plenary stack trace) when jj isn't on PATH. Returns the resolved command
-- on success, or (nil, failure_table) when jj is missing.
local function resolve_command(cmd)
	if cmd ~= "jj" then
		return cmd
	end

	-- vim.fn.exepath takes a single {name} argument; LLS's bundled vim stub
	-- mistypes it as zero-arg, so silence that false positive.
	---@diagnostic disable-next-line: redundant-parameter
	local jj_path = vim.fn.exepath("jj")
	if jj_path == "" then
		local msg = "jj executable not found on PATH"
		logger.error(msg)
		vim.notify("NeoJJ: " .. msg, vim.log.levels.ERROR)
		return nil, {
			success = false,
			exit_code = -1,
			stdout = nil,
			stderr = msg,
		}
	end

	return jj_path
end

-- Build the structured result table from a finished job. `stdout` may be passed
-- in (the synchronous path gets it back from job:sync); otherwise it's read
-- from the job's recorded stdout (the async path).
local function build_result(job, stdout)
	local exit_code = job.code
	stdout = stdout or job:result() or {}
	local stderr = job:stderr_result() or {}

	local success = exit_code == 0
	local stdout_str = type(stdout) == "table" and table.concat(stdout, "\n") or stdout
	local stderr_str = type(stderr) == "table" and table.concat(stderr, "\n") or stderr

	if not success then
		local error_msg = "Command failed with exit code " .. tostring(exit_code)
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

function Cli:call()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()

	-- Resolve full path for jj command at call time, and fail loudly (rather
	-- than with a raw plenary stack trace) when it isn't on PATH.
	local command, failure = resolve_command(self.cmd)
	if not command then
		return failure
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

	return build_result(result.job, result.stdout)
end

-- Genuinely asynchronous variant of :call(). When invoked inside a plenary
-- async context (async.run / async.void) it yields the coroutine until the jj
-- process exits, so the UI thread is never blocked. Its public contract matches
-- :call(): it returns the same structured result table.
function Cli:call_async()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()
	-- Snapshot the env guard before we leave the builder's method context.
	local env = next(self._env) and self._env or nil

	local command, failure = resolve_command(self.cmd)
	if command then
		logger.debug("Executing (async): " .. command .. " " .. table.concat(cmd_args, " ") .. " (cwd: " .. cwd .. ")")
	end

	return async.wrap(function(callback)
		-- jj missing on PATH: resolve_command already notified, so hand back the
		-- standard failure table.
		if not command then
			callback(failure)
			return
		end

		local finished = false
		---@type uv.uv_timer_t?
		local timer = nil

		local function close_timer()
			if timer and not timer:is_closing() then
				timer:stop()
				timer:close()
			end
			timer = nil
		end

		-- Every path below is scheduled onto the main loop, so these callbacks
		-- run serially and the `finished` guard is race-free. It also ensures we
		-- only ever resume the coroutine once.
		local function finish(result)
			if finished then
				return
			end
			finished = true
			close_timer()
			callback(result)
		end

		local job = Job:new({
			command = command,
			args = cmd_args,
			cwd = cwd,
			env = env,
		})

		job:add_on_exit_callback(vim.schedule_wrap(function()
			finish(build_result(job))
		end))

		-- Match :call()'s timeout semantics with a one-shot timer, since an
		-- async Job has no built-in sync timeout.
		timer = vim.loop.new_timer()
		if timer then
			timer:start(
				SYNC_TIMEOUT_MS,
				0,
				vim.schedule_wrap(function()
					if finished then
						return
					end
					logger.error("Command timed out after " .. SYNC_TIMEOUT_MS .. "ms")
					vim.notify("NeoJJ: jj command timed out after " .. SYNC_TIMEOUT_MS .. "ms", vim.log.levels.WARN)
					finish({
						success = false,
						exit_code = -1,
						stdout = nil,
						stderr = "jj command timed out after " .. SYNC_TIMEOUT_MS .. "ms",
					})
				end)
			)
		end

		-- Job:start can raise on spawn failure; surface it as a failure table
		-- rather than a stack trace.
		local ok, err = pcall(function()
			job:start()
		end)
		if not ok then
			local msg = tostring(err)
			logger.error("Command failed: " .. msg)
			vim.notify("NeoJJ: failed to run jj: " .. msg, vim.log.levels.ERROR)
			finish({
				success = false,
				exit_code = -1,
				stdout = nil,
				stderr = msg,
			})
		end
	end, 1)()
end

local M = {}

function M.status()
	return new_builder("jj"):arg("status")
end

function M.log()
	return new_builder("jj"):arg("log")
end

function M.show()
	return new_builder("jj"):arg("show")
end

function M.describe()
	return new_builder("jj"):arg("describe")
end

function M.file()
	return new_builder("jj"):arg("file")
end

function M.new()
	return new_builder("jj"):arg("new")
end

function M.fix()
	return new_builder("jj"):arg("fix")
end

function M.raw()
	return new_builder("jj")
end

return M
