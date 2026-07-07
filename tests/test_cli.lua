-- Tests for the jj CLI builder, focused on how it spawns plenary Jobs.
local T = MiniTest.new_set()
local expect = MiniTest.expect

--- Load a fresh copy of the CLI module with plenary.job replaced by a spy.
--- Returns the CLI module plus a table that captures the options passed to
--- the most recent Job:new call.
local function load_cli_with_job_spy()
	local captured = {}

	local mock_job = {}
	mock_job.__index = mock_job

	function mock_job.new(_, opts)
		captured.opts = opts
		local job = setmetatable({ code = 0 }, mock_job)
		return job
	end

	function mock_job:sync()
		return {}
	end

	function mock_job:stderr_result()
		return {}
	end

	local saved_job = package.loaded["plenary.job"]
	local saved_cli = package.loaded["neojj.lib.jj.cli"]

	package.loaded["plenary.job"] = mock_job
	package.loaded["neojj.lib.jj.cli"] = nil

	local Cli = require("neojj.lib.jj.cli")

	local restore = function()
		package.loaded["plenary.job"] = saved_job
		package.loaded["neojj.lib.jj.cli"] = saved_cli
	end

	return Cli, captured, restore
end

--- Assert that two array-like tables are element-for-element equal.
local function expect_args(actual, expected)
	expect.equality(#actual, #expected)
	for i = 1, #expected do
		expect.equality(actual[i], expected[i])
	end
end

-- Contract: every builder starts from the default `--color never` args and the
-- factory function's subcommand, then appends in chain order. These assert the
-- exact argv (captured.opts.args) that reaches plenary.job, which is the real
-- contract downstream tooling depends on.

T["status builder emits the default color args and subcommand"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.status():call()

	expect_args(captured.opts.args, { "--color", "never", "status" })

	restore()
end

T["log builder chains args, options and flags in order"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.log():arg("-r"):arg("@"):option("template", "json(self)"):flag("no-graph"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"log",
		"-r",
		"@",
		"--template",
		"json(self)",
		"--no-graph",
	})

	restore()
end

T["option without a value emits a bare long flag"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.raw():option("version"):call()

	expect_args(captured.opts.args, { "--color", "never", "--version" })

	restore()
end

T["short_flag emits a single-dash flag"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.log():short_flag("n"):arg("10"):call()

	expect_args(captured.opts.args, { "--color", "never", "log", "-n", "10" })

	restore()
end

T["describe builder carries the revision argument"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.describe():arg("abc123"):call()

	expect_args(captured.opts.args, { "--color", "never", "describe", "abc123" })

	restore()
end

T["cwd sets the job's working directory"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.status():cwd("/some/repo/dir"):call()

	expect.equality(captured.opts.cwd, "/some/repo/dir")

	restore()
end

T["call omits env when none is set"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.status():call()

	-- A nil env makes plenary let the child inherit our environment
	-- (PATH, SSH_AUTH_SOCK, JJ_CONFIG, EDITOR, ...) rather than replacing it.
	expect.equality(captured.opts.env, nil)

	restore()
end

T["call passes env when a variable is set"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	local builder = Cli.status()
	builder:env("FOO", "bar")
	builder:call()

	expect.no_equality(captured.opts.env, nil)
	expect.equality(captured.opts.env.FOO, "bar")

	restore()
end

T["call fails gracefully when jj is not on PATH"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	local saved_exepath = vim.fn.exepath
	local saved_notify = vim.notify
	local notified = {}
	vim.fn.exepath = function()
		return ""
	end
	vim.notify = function(msg, level)
		table.insert(notified, { msg = msg, level = level })
	end

	local ok, result = pcall(function()
		return Cli.status():call()
	end)

	vim.fn.exepath = saved_exepath
	vim.notify = saved_notify
	restore()

	-- No raw error should reach the caller...
	expect.equality(ok, true)
	assert(result, "call() must return a failure table rather than nil")
	-- ...instead the standard failure table with a string stderr.
	expect.equality(result.success, false)
	expect.equality(type(result.stderr), "string")
	expect.no_equality(result.stderr, "")
	-- No Job should have been spawned, and the user should be notified.
	expect.equality(captured.opts, nil)
	expect.equality(#notified >= 1, true)
end

return T
