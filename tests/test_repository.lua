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

return T
