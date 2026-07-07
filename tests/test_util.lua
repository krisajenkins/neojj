-- Tests for the pure(ish) helpers in neojj.lib.jj.util: filesystem-walking
-- repository detection, path joining, and the repo namespace derivation.
local T = MiniTest.new_set()
local expect = MiniTest.expect

local util = require("neojj.lib.jj.util")

-- Create a fresh, empty temp directory outside any jj repository.
local function make_temp_dir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

T["path_join"] = MiniTest.new_set()

T["path_join"]["joins parts with a slash"] = function()
	expect.equality(util.path_join("a", "b", "c"), "a/b/c")
end

T["path_join"]["collapses duplicate separators"] = function()
	-- A trailing slash on one part and a leading slash on the next must not
	-- produce a doubled separator.
	expect.equality(util.path_join("a/", "/b"), "a/b")
	expect.equality(util.path_join("a", "", "b"), "a/b")
	expect.equality(util.path_join("a///b", "c"), "a/b/c")
end

T["path_join"]["preserves a leading absolute slash"] = function()
	-- Only *duplicate* slashes collapse; a single leading slash stays.
	expect.equality(util.path_join("/root", "sub"), "/root/sub")
end

T["path_join"]["handles a single part"] = function()
	expect.equality(util.path_join("solo"), "solo")
end

T["find_jj_dir"] = MiniTest.new_set()

T["find_jj_dir"]["walks up to the nearest .jj ancestor"] = function()
	-- Build root/.jj and a nested working directory; detection from the nested
	-- dir must climb to the root and report both root and .jj paths.
	local root = make_temp_dir()
	vim.fn.mkdir(root .. "/.jj", "p")
	local nested = root .. "/a/b/c"
	vim.fn.mkdir(nested, "p")

	local found_root, jj_dir = util.find_jj_dir(nested)
	expect.equality(found_root, root)
	expect.equality(jj_dir, root .. "/.jj")

	vim.fn.delete(root, "rf")
end

T["find_jj_dir"]["returns nil outside any repository"] = function()
	local dir = make_temp_dir()

	local found_root, jj_dir = util.find_jj_dir(dir)
	expect.equality(found_root, nil)
	expect.equality(jj_dir, nil)

	vim.fn.delete(dir, "rf")
end

T["is_jj_repo"] = MiniTest.new_set()

T["is_jj_repo"]["is true for a directory with a .jj"] = function()
	local dir = make_temp_dir()
	vim.fn.mkdir(dir .. "/.jj", "p")

	expect.equality(util.is_jj_repo(dir), true)

	vim.fn.delete(dir, "rf")
end

T["is_jj_repo"]["is false for a bare directory"] = function()
	local dir = make_temp_dir()

	expect.equality(util.is_jj_repo(dir), false)

	vim.fn.delete(dir, "rf")
end

T["file_exists / dir_exists"] = MiniTest.new_set()

T["file_exists / dir_exists"]["distinguish files, dirs and absences"] = function()
	local dir = make_temp_dir()
	local file = dir .. "/note.txt"
	local fd = assert(io.open(file, "w"))
	fd:write("hello\n")
	fd:close()

	expect.equality(util.file_exists(file), true)
	expect.equality(util.dir_exists(dir), true)

	-- A file is not a directory, and a directory is not a readable file.
	expect.equality(util.dir_exists(file), false)
	expect.equality(util.file_exists(dir), false)

	-- Missing paths are neither.
	expect.equality(util.file_exists(dir .. "/nope.txt"), false)
	expect.equality(util.dir_exists(dir .. "/nope"), false)

	vim.fn.delete(dir, "rf")
end

T["repo_namespace"] = MiniTest.new_set()

T["repo_namespace"]["derives basename plus a stable hash"] = function()
	local repo = {
		get_root = function()
			return "/foo/bar/myproject"
		end,
	}

	local id = util.repo_namespace(repo)

	-- Format is "<basename>-<6 hex chars>", deterministic for a given root.
	expect.equality(id:match("^myproject%-%x%x%x%x%x%x$") ~= nil, true)
	expect.equality(util.repo_namespace(repo), id)
end

T["repo_namespace"]["distinguishes same-basename repos in different paths"] = function()
	local a = {
		get_root = function()
			return "/home/alice/work/app"
		end,
	}
	local b = {
		get_root = function()
			return "/home/bob/work/app"
		end,
	}

	-- Both share the basename "app" but must not collide, thanks to the
	-- path-derived hash suffix.
	expect.no_equality(util.repo_namespace(a), util.repo_namespace(b))
end

T["repo_namespace"]["falls back to repo.dir when get_root is absent"] = function()
	local repo = { dir = "/some/where/fallback" }

	local id = util.repo_namespace(repo)
	expect.equality(id:match("^fallback%-%x%x%x%x%x%x$") ~= nil, true)
end

return T
