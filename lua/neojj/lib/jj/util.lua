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

return M
