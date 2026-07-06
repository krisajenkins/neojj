local M = {}

function M.find_jj_dir(dir)
	local current = dir or vim.fn.getcwd()

	while current ~= "/" do
		local jj_dir = current .. "/.jj"
		if vim.fn.isdirectory(jj_dir) == 1 then
			return current, jj_dir
		end
		current = vim.fn.fnamemodify(current, ":h")
	end

	return nil, nil
end

function M.is_jj_repo(dir)
	local _, jj_dir = M.find_jj_dir(dir)
	return jj_dir ~= nil
end

function M.path_join(...)
	local parts = { ... }
	return table.concat(parts, "/"):gsub("//+", "/")
end

function M.file_exists(path)
	return vim.fn.filereadable(path) == 1
end

function M.dir_exists(path)
	return vim.fn.isdirectory(path) == 1
end

---Derive a short, stable identifier for a repository, suitable for namespacing
---buffer names so that status/log views for different repos don't share (and
---clobber) the same underlying Neovim buffer.
---
---The identifier is the repo root's basename, with a short deterministic hash
---of the full normalized root path appended so that two distinct repos which
---happen to share a basename still get distinct identifiers. The hash is a slice
---of `sha256` (not a random suffix), so the same repo always maps to the same
---identifier across sessions.
---@param repo table Repository instance (responds to `get_root`; falls back to `repo.dir`)
---@return string id Namespace identifier, e.g. "myproject-1a2b3c"
function M.repo_namespace(repo)
	local root = type(repo.get_root) == "function" and repo:get_root() or nil
	if not root or root == "" then
		root = repo.dir
	end

	root = vim.fs.normalize(root)

	local base = vim.fs.basename(root)
	if not base or base == "" then
		base = root
	end

	local hash = vim.fn.sha256(root):sub(1, 6)
	return base .. "-" .. hash
end

return M
