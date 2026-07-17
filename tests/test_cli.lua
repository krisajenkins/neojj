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

T["git_push builder emits the git push subcommand"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.git_push():call()

	expect_args(captured.opts.args, { "--color", "never", "git", "push" })

	restore()
end

T["git_push builder carries a --bookmark option"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.git_push():option("bookmark", "main"):call()

	expect_args(captured.opts.args, { "--color", "never", "git", "push", "--bookmark", "main" })

	restore()
end

T["git_push builder carries a --change option"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.git_push():option("change", "@"):call()

	expect_args(captured.opts.args, { "--color", "never", "git", "push", "--change", "@" })

	restore()
end

T["git_fetch builder emits the git fetch subcommand"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.git_fetch():call()

	expect_args(captured.opts.args, { "--color", "never", "git", "fetch" })

	restore()
end

T["squash builder emits the bare squash subcommand"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.squash():call()

	expect_args(captured.opts.args, { "--color", "never", "squash" })

	restore()
end

T["squash builder carries a --from option"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.squash():option("from", "abc123"):call()

	expect_args(captured.opts.args, { "--color", "never", "squash", "--from", "abc123" })

	restore()
end

T["squash builder carries --from and --into options"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.squash():option("from", "abc123"):option("into", "def456"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"squash",
		"--from",
		"abc123",
		"--into",
		"def456",
	})

	restore()
end

T["rebase builder emits the bare rebase subcommand"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.rebase():call()

	expect_args(captured.opts.args, { "--color", "never", "rebase" })

	restore()
end

T["rebase builder carries --source and --destination options"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.rebase():option("source", "abc123"):option("destination", "def456"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"rebase",
		"--source",
		"abc123",
		"--destination",
		"def456",
	})

	restore()
end

T["rebase builder carries --revisions and --destination options"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.rebase():option("revisions", "abc123"):option("destination", "def456"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"rebase",
		"--revisions",
		"abc123",
		"--destination",
		"def456",
	})

	restore()
end

T["rebase builder carries --branch and --destination options"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.rebase():option("branch", "abc123"):option("destination", "def456"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"rebase",
		"--branch",
		"abc123",
		"--destination",
		"def456",
	})

	restore()
end

T["abandon builder carries the revision argument"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.abandon():arg("abc123"):call()

	expect_args(captured.opts.args, { "--color", "never", "abandon", "abc123" })

	restore()
end

T["restore builder scopes changes to a revision"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.restore():option("changes-in", "@"):call()

	expect_args(captured.opts.args, { "--color", "never", "restore", "--changes-in", "@" })

	restore()
end

T["restore builder targets a single path"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.restore():option("changes-in", "@"):arg("src/file.lua"):call()

	expect_args(captured.opts.args, { "--color", "never", "restore", "--changes-in", "@", "src/file.lua" })

	restore()
end

T["bookmark_create builder targets a revision"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.bookmark_create():arg("feature"):option("revision", "abc123"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"bookmark",
		"create",
		"feature",
		"--revision",
		"abc123",
	})

	restore()
end

T["bookmark_move builder allows backwards moves onto a revision"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	-- `jj bookmark move` takes `--to` for its target; unlike `create` it has no
	-- `--revision`/`-r` alias, so the move menu must use `--to`.
	Cli.bookmark_move():arg("main"):option("to", "abc123"):flag("allow-backwards"):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"bookmark",
		"move",
		"main",
		"--to",
		"abc123",
		"--allow-backwards",
	})

	restore()
end

T["bookmark_delete builder carries the bookmark name"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.bookmark_delete():arg("feature"):call()

	expect_args(captured.opts.args, { "--color", "never", "bookmark", "delete", "feature" })

	restore()
end

T["bookmark_rename builder carries old and new names"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.bookmark_rename():arg("old"):arg("new"):call()

	expect_args(captured.opts.args, { "--color", "never", "bookmark", "rename", "old", "new" })

	restore()
end

T["bookmark_track builder carries a name@remote ref"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.bookmark_track():arg("main@origin"):call()

	expect_args(captured.opts.args, { "--color", "never", "bookmark", "track", "main@origin" })

	restore()
end

T["bookmark_untrack builder carries a name@remote ref"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.bookmark_untrack():arg("main@origin"):call()

	expect_args(captured.opts.args, { "--color", "never", "bookmark", "untrack", "main@origin" })

	restore()
end

T["bookmark_list builder emits a name template"] = function()
	local Cli, captured, restore = load_cli_with_job_spy()

	Cli.bookmark_list():option("template", 'name ++ "\\n"'):call()

	expect_args(captured.opts.args, {
		"--color",
		"never",
		"bookmark",
		"list",
		"--template",
		'name ++ "\\n"',
	})

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
