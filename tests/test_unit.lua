-- Hermetic repository test: exercises the real JjRepo abstraction against a
-- throwaway jj repo created in a temp directory. Unlike a mock-CLI test, this
-- shells out to the real `jj` binary, so it depends on `jj` being on PATH.
--
-- Identity is pinned via JJ_USER/JJ_EMAIL (inherited by the jj subprocess, since
-- cli.lua passes no explicit env) so assertions are host-independent: we never
-- assert on the local developer's author name/email.

---@type table
local expect = MiniTest.expect

---@type table
local async = require("plenary.async")

-- Per-case scratch state, populated by pre_case and torn down by post_case.
local ctx = {}

---@type table
local T = MiniTest.new_set({
	hooks = {
		---Create a hermetic jj repo in a temp dir with a single added file.
		---@return nil
		pre_case = function()
			vim.cmd([[ set rtp+=deps/plenary.nvim ]])

			-- Deterministic identity so author fields never depend on the host.
			ctx.saved_user = vim.env.JJ_USER
			ctx.saved_email = vim.env.JJ_EMAIL
			vim.env.JJ_USER = "Test User"
			vim.env.JJ_EMAIL = "test@example.com"

			-- Unique temp dir; the JjRepo instance cache is keyed by directory,
			-- so a fresh path avoids collisions across cases/runs.
			ctx.dir = vim.fn.tempname()
			vim.fn.mkdir(ctx.dir, "p")

			-- Initialise a real jj repo and write a file to the working copy.
			vim.fn.system({ "jj", "git", "init", ctx.dir })
			local fd = assert(io.open(ctx.dir .. "/hello.txt", "w"))
			fd:write("hello world\n")
			fd:close()
		end,

		---Remove the temp repo and restore the identity environment.
		---@return nil
		post_case = function()
			if ctx.dir then
				vim.fn.delete(ctx.dir, "rf")
			end
			vim.env.JJ_USER = ctx.saved_user
			vim.env.JJ_EMAIL = ctx.saved_email
			ctx = {}
		end,
	},
})

---A freshly initialised temp directory is recognised as a jj repository, and a
---refresh populates the working copy with the file we wrote.
---@return nil
T["refresh reports working copy from a real jj repo"] = function()
	local JjRepo = require("neojj.lib.jj.repository")

	local repo = JjRepo.new(ctx.dir)
	expect.equality(repo:is_jj_repo(), true)

	-- refresh() acquires an async semaphore, so it must run inside a plenary
	-- async context. Drive it via async.run and wait for completion (mirrors how
	-- the buffers refresh; see neojj.lua's async.run usage).
	local done, ok, err = false, nil, nil
	async.run(function()
		ok, err = repo:refresh()
		done = true
	end)
	vim.wait(10000, function()
		return done
	end, 20)

	expect.equality(done, true)
	expect.equality(ok, true, err)

	local wc = repo:get_working_copy()

	-- change_id is a random, host-independent identifier: assert it exists.
	expect.equality(type(wc.change_id), "string")
	expect.no_equality(wc.change_id, "")

	-- The written file must surface as a modified (added) file.
	local found
	for _, file in ipairs(wc.modified_files) do
		if file.path == "hello.txt" then
			found = file
		end
	end
	expect.no_equality(found, nil)
	expect.equality(found.status, "A")
end

return T
