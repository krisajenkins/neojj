-- Tests for the JjRepo repository abstraction, focused on instance caching and
-- re-detection of repositories initialised after the first :JJ call.
local T = MiniTest.new_set()
local expect = MiniTest.expect

-- Create a fresh, empty temp directory that is NOT inside any jj repository.
-- Uses vim.fn.tempname() for a unique path so the instance cache (keyed by
-- directory) never collides across test runs.
local function make_temp_dir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

T["re-detects a repository initialised after first use"] = function()
	local JjRepo = require("neojj.lib.jj.repository")

	local dir = make_temp_dir()

	-- First lookup: the directory is not (yet) a jj repository.
	local repo = JjRepo.instance(dir)
	expect.equality(repo:is_jj_repo(), false)
	-- setup_modules was a no-op, so the status module is not registered.
	expect.equality(repo.modules.status, nil)

	-- Simulate `jj git init` creating a repository at this path. find_jj_dir
	-- probes for a real `.jj` directory via vim.fn.isdirectory, so creating one
	-- is enough for detection to succeed.
	vim.fn.mkdir(dir .. "/.jj", "p")

	-- Second lookup returns the same cached instance, now re-detected.
	local repo2 = JjRepo.instance(dir)
	expect.equality(repo2, repo)
	expect.equality(repo2:is_jj_repo(), true)
	-- Re-running setup_modules must have registered the status module.
	expect.no_equality(repo2.modules.status, nil)

	-- Clean up the temp directory (and its .jj) so the test stays hermetic.
	vim.fn.delete(dir, "rf")
end

T["reports a detected repository as such"] = function()
	local JjRepo = require("neojj.lib.jj.repository")

	local dir = make_temp_dir()
	vim.fn.mkdir(dir .. "/.jj", "p")

	local repo = JjRepo.instance(dir)
	expect.equality(repo:is_jj_repo(), true)
	expect.no_equality(repo.modules.status, nil)

	vim.fn.delete(dir, "rf")
end

T["instance() caches by directory"] = function()
	local JjRepo = require("neojj.lib.jj.repository")

	local dir_a = make_temp_dir()
	local dir_b = make_temp_dir()

	-- Same directory returns the identical cached table across calls.
	local a1 = JjRepo.instance(dir_a)
	local a2 = JjRepo.instance(dir_a)
	expect.equality(a1, a2)

	-- A different directory gets its own distinct instance.
	local b1 = JjRepo.instance(dir_b)
	expect.no_equality(a1, b1)

	vim.fn.delete(dir_a, "rf")
	vim.fn.delete(dir_b, "rf")
end

T["detect_repository leaves state empty for a non-repo"] = function()
	local JjRepo = require("neojj.lib.jj.repository")

	-- A fresh temp dir with no `.jj` anywhere up its ancestry is not a repo, so
	-- detection must leave root/jj_dir empty rather than latching onto a parent.
	local dir = make_temp_dir()
	local repo = JjRepo.new(dir)

	expect.equality(repo.state.root, "")
	expect.equality(repo.state.jj_dir, "")
	expect.equality(repo:is_jj_repo(), false)

	vim.fn.delete(dir, "rf")
end

T["refresh populates working copy via the mock CLI"] = function()
	local MockCli = dofile("tests/helpers/mock_cli.lua")
	local async = require("plenary.async")
	local JjRepo = require("neojj.lib.jj.repository")

	-- status.lua binds `cli` at require-time, so inject the fixture-backed mock
	-- and force the status module to reload against it. Save and restore the real
	-- modules so later tests in this process are unaffected.
	local saved_cli = package.loaded["neojj.lib.jj.cli"]
	local saved_status = package.loaded["neojj.lib.jj.status"]

	package.loaded["neojj.lib.jj.cli"] = MockCli.create_mock_module()
	package.loaded["neojj.lib.jj.status"] = nil
	MockCli.set_state("initial")
	MockCli.set_fixtures_dir("tests/fixtures/jj-outputs")

	-- A real `.jj` directory makes detect/setup_modules register the status
	-- module; its refresher then drives the mock CLI against the fixtures.
	local dir = make_temp_dir()
	vim.fn.mkdir(dir .. "/.jj", "p")

	local repo = JjRepo.new(dir)
	expect.equality(repo:is_jj_repo(), true)
	expect.no_equality(repo.modules.status, nil)

	-- refresh() acquires an async semaphore, so drive it inside a plenary async
	-- context and wait for completion.
	local done, ok = false, nil
	async.run(function()
		ok = repo:refresh()
		done = true
	end)
	vim.wait(5000, function()
		return done
	end, 20)

	expect.equality(done, true)
	expect.equality(ok, true)

	local wc = repo:get_working_copy()
	expect.equality(type(wc.change_id), "string")
	expect.no_equality(wc.change_id, "")
	-- The initial-status fixture lists a single added file (.gitignore).
	expect.equality(#wc.modified_files, 1)
	expect.equality(wc.modified_files[1].status, "A")
	expect.equality(wc.modified_files[1].path, ".gitignore")

	package.loaded["neojj.lib.jj.cli"] = saved_cli
	package.loaded["neojj.lib.jj.status"] = saved_status
	vim.fn.delete(dir, "rf")
end

return T
