local JjRepo = require("neojj.lib.jj.repository")

local M = {}

function M.instance(dir)
	return JjRepo.instance(dir)
end

function M.new(dir)
	return JjRepo.new(dir)
end

return M
