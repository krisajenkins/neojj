-- Tests for the status buffer's action wiring (things that are awkward to
-- observe through the full rendered UI). Runs in a child Neovim so real Neovim
-- APIs are available; jj is never actually spawned.
---@type table
local child, new_set = require("tests.helpers.child")()

---@type table
local T = new_set()

--- The commit gesture is `jj commit` expressed as its two real steps, because
--- jj's `commit` subcommand has no `--stdin`: it opens the describe buffer for
--- `@` (which submits via `jj describe @ --stdin`), and on submit runs `jj new`
--- so the user lands on a fresh empty working copy. This asserts the second
--- step is genuinely `jj new` (NOT `jj commit`) and that the status view is
--- refreshed and re-focused afterwards.
T.test_commit_gesture_runs_describe_then_jj_new = function()
	child.lua([[
		expect = require('mini.test').expect

		local captured = {}

		-- Run async bodies and scheduled callbacks synchronously so the whole
		-- commit chain is observable within this test.
		package.loaded['plenary.async'] = { run = function(fn) fn() end }
		vim.schedule = function(cb) cb() end

		-- Spy the jj CLI: real builders (so argv is genuine) but with call_async
		-- stubbed to record the invocation instead of spawning jj.
		local real_cli = require('neojj.lib.jj.cli')
		package.loaded['neojj.lib.jj.cli'] = setmetatable({
			new = function()
				local b = real_cli.new()
				captured.new_args = vim.deepcopy(b.args)
				b.cwd = function(self, dir) captured.new_cwd = dir; return self end
				b.call_async = function() captured.new_called = true; return { success = true } end
				return b
			end,
		}, { __index = real_cli })

		-- Capture the describe buffer's on_submit callback instead of opening a
		-- real describe view.
		package.loaded['neojj.buffers.describe'] = {
			new = function(repo, revision, on_submit, on_abort)
				captured.describe_revision = revision
				captured.on_submit = on_submit
				return { show = function() captured.shown = true end }
			end,
		}

		local StatusBuffer = require('neojj.buffers.status')
		local fake_self = setmetatable({
			repo = { dir = '/fake/repo' },
			revision = 'someothercommit', -- commit must still target @, not this
			buffer = {
				is_valid = function() return true end,
				open = function() captured.opened = true end,
			},
			refresh = function() captured.refreshed = true end,
		}, StatusBuffer)

		StatusBuffer.commit_change(fake_self)

		-- Step 1: describe buffer opened for the working copy '@' (never the
		-- pinned revision), since jj commit only ever operates on @.
		expect.equality(captured.describe_revision, '@')
		expect.equality(captured.shown, true)
		expect.equality(type(captured.on_submit), 'function')

		-- Step 2: simulate the description being submitted -> jj new runs.
		captured.on_submit()

		expect.equality(captured.new_called, true)
		expect.equality(captured.new_cwd, '/fake/repo')
		-- The second step's argv is exactly `jj new` (no revision arg), NOT
		-- `jj commit` (which has no --stdin and would fail at runtime).
		expect.equality(captured.new_args[1], '--color')
		expect.equality(captured.new_args[2], 'never')
		expect.equality(captured.new_args[3], 'new')
		expect.equality(captured.new_args[4], nil)
		for _, a in ipairs(captured.new_args) do
			expect.no_equality(a, 'commit')
		end

		-- The status view is refreshed and re-focused after committing.
		expect.equality(captured.refreshed, true)
		expect.equality(captured.opened, true)

		package.loaded['plenary.async'] = nil
	]])
end

return T
