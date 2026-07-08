-- Tests for neojj.lib.watcher: the filesystem watcher that auto-refreshes open
-- NeoJJ views when the repo changes externally.
--
-- These are deliberately deterministic (no timing/debounce assertions): they
-- exercise the watcher's public lifecycle (arm / idempotency / skip / stop /
-- cleanup), the op_heads path resolution (including the jj-workspace file
-- indirection), and the `list_instances()` seams that dispatch fans out over.
-- The debounce + fan-out plumbing itself is stock libuv/vim.schedule_wrap and is
-- left unasserted to avoid a flaky, clock-dependent test.
local expect = MiniTest.expect

local watcher = require("neojj.lib.watcher")

-- Reset watcher state between tests so a leftover watcher can't skew active_count.
local T = MiniTest.new_set({
	hooks = {
		post_case = function()
			watcher.stop_all()
		end,
	},
})

local function make_temp()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

-- A repo with a real `<root>/.jj/repo/op_heads/heads/` directory present.
local function repo_with_op_heads()
	local root = make_temp()
	local heads = root .. "/.jj/repo/op_heads/heads"
	vim.fn.mkdir(heads, "p")
	local repo = {
		get_root = function()
			return root
		end,
		get_jj_dir = function()
			return root .. "/.jj"
		end,
	}
	return repo, root
end

T["ensure"] = MiniTest.new_set()

T["ensure"]["arms a watcher when op_heads/heads exists"] = function()
	local repo = repo_with_op_heads()
	expect.equality(watcher.active_count(), 0)
	watcher.ensure(repo)
	expect.equality(watcher.active_count(), 1)
end

T["ensure"]["is idempotent per root"] = function()
	local repo = repo_with_op_heads()
	watcher.ensure(repo)
	watcher.ensure(repo)
	watcher.ensure(repo)
	expect.equality(watcher.active_count(), 1)
end

T["ensure"]["skips when op_heads/heads is absent"] = function()
	-- A .jj exists but without the op_heads/heads directory (nothing to watch).
	local root = make_temp()
	vim.fn.mkdir(root .. "/.jj/repo", "p")
	local repo = {
		get_root = function()
			return root
		end,
		get_jj_dir = function()
			return root .. "/.jj"
		end,
	}
	watcher.ensure(repo)
	expect.equality(watcher.active_count(), 0)
end

T["ensure"]["ignores a repo without a root"] = function()
	watcher.ensure({
		get_root = function()
			return ""
		end,
		get_jj_dir = function()
			return ""
		end,
	})
	expect.equality(watcher.active_count(), 0)
end

T["ensure"]["follows a jj-workspace .jj/repo file indirection"] = function()
	-- In a jj workspace, `.jj/repo` is a FILE whose contents point at the real
	-- repository directory; the watcher must follow it to find op_heads/heads.
	local root = make_temp()
	vim.fn.mkdir(root .. "/.jj", "p")
	local real = make_temp()
	vim.fn.mkdir(real .. "/op_heads/heads", "p")
	vim.fn.writefile({ real }, root .. "/.jj/repo")

	local repo = {
		get_root = function()
			return root
		end,
		get_jj_dir = function()
			return root .. "/.jj"
		end,
	}
	watcher.ensure(repo)
	expect.equality(watcher.active_count(), 1)
end

T["stop"] = MiniTest.new_set()

T["stop"]["disposes a single watcher"] = function()
	local repo, root = repo_with_op_heads()
	watcher.ensure(repo)
	expect.equality(watcher.active_count(), 1)
	watcher.stop(root)
	expect.equality(watcher.active_count(), 0)
end

T["stop"]["is a no-op for an unknown root"] = function()
	expect.no_error(function()
		watcher.stop("/no/such/root")
	end)
end

T["stop_all"] = MiniTest.new_set()

T["stop_all"]["clears every watcher"] = function()
	local a = repo_with_op_heads()
	local b = repo_with_op_heads()
	watcher.ensure(a)
	watcher.ensure(b)
	expect.equality(watcher.active_count(), 2)
	watcher.stop_all()
	expect.equality(watcher.active_count(), 0)
end

T["cleanup"] = MiniTest.new_set()

T["cleanup"]["stops the watcher when no view references the root"] = function()
	-- With no NeoJJ buffers open, list_instances() is empty for every type, so a
	-- cleanup call after the last view detaches should tear the watcher down.
	local repo, root = repo_with_op_heads()
	watcher.ensure(repo)
	expect.equality(watcher.active_count(), 1)
	watcher.cleanup(root)
	expect.equality(watcher.active_count(), 0)
end

T["cleanup"]["keeps the watcher while a view still references the root"] = function()
	local repo, root = repo_with_op_heads()
	watcher.ensure(repo)

	-- Stub one buffer module so a view still references this root; cleanup must
	-- leave the watcher alone. Restore the real module afterwards.
	local key = "neojj.buffers.log"
	local saved = package.loaded[key]
	package.loaded[key] = {
		list_instances = function()
			return {
				{
					is_valid = function()
						return true
					end,
					repo = {
						get_root = function()
							return root
						end,
					},
				},
			}
		end,
	}

	watcher.cleanup(root)
	package.loaded[key] = saved

	expect.equality(watcher.active_count(), 1)
end

T["list_instances"] = MiniTest.new_set()

T["list_instances"]["exists on log and oplog buffers and starts empty"] = function()
	local LogBuffer = require("neojj.buffers.log")
	local OplogBuffer = require("neojj.buffers.oplog")
	expect.equality(type(LogBuffer.list_instances), "function")
	expect.equality(type(OplogBuffer.list_instances), "function")
	expect.equality(type(LogBuffer.list_instances()), "table")
	expect.equality(type(OplogBuffer.list_instances()), "table")
end

return T
