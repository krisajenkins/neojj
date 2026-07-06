local async = require("plenary.async")
local logger = require("neojj.logger")
local util = require("neojj.lib.jj.util")

local JjRepo = {}
JjRepo.__index = JjRepo

local instances = {}

local function empty_state()
	return {
		root = "",
		jj_dir = "",
		working_copy = {
			change_id = nil,
			commit_id = nil,
			description = "",
			author = { name = "", email = "" },
			parent_ids = {},
			modified_files = {},
			conflicts = {},
			is_empty = true,
		},
		bookmarks = {
			local_bookmarks = {},
			remote_bookmarks = {},
			conflicted = {},
		},
		revisions = { items = {} },
		operation_log = { items = {} },
		conflicts = { items = {} },
		remotes = { items = {} },
	}
end

function JjRepo.new(dir)
	local repo = setmetatable({}, JjRepo)
	repo.dir = dir or vim.fn.getcwd()
	repo.state = empty_state()
	repo.modules = {}
	repo.refresh_lock = async.control.Semaphore.new(1)

	repo:detect_repository()
	repo:setup_modules()

	return repo
end

function JjRepo.instance(dir)
	local cwd = dir or vim.fn.getcwd()

	if not instances[cwd] then
		instances[cwd] = JjRepo.new(cwd)
	end

	return instances[cwd]
end

function JjRepo:register_module(name, module)
	if self.modules[name] then
		return -- Already registered
	end
	self.modules[name] = module
end

---Refresh repository state by running every registered module refresher.
---Must be called from within a plenary async context (it acquires an async
---semaphore). Returns a success/error signal so callers (e.g. the status
---buffer) can surface failures instead of silently rendering stale state.
---@return boolean success True when every module refreshed successfully
---@return string? error Error message describing the first failure
function JjRepo:refresh()
	local permit = self.refresh_lock:acquire()

	-- pcall returns: ok, then whatever the inner function returned. The inner
	-- function returns `true` on success or `false, err` on a module failure.
	local ok, success, err = pcall(function()
		logger.debug("Refreshing repository state for: " .. self.dir)

		for name, module in pairs(self.modules) do
			if module.refresh then
				logger.debug("Refreshing module: " .. name)
				local module_ok, module_err = module.refresh(self)
				if module_ok == false then
					return false, module_err
				end
			end
		end

		logger.debug("Repository refresh completed")
		return true
	end)

	permit:forget()

	if not ok then
		-- pcall caught a runtime error; `success` holds the error message.
		local err_msg = tostring(success)
		logger.error("Repository refresh failed: " .. err_msg)
		return false, err_msg
	end

	if not success then
		-- The failing module already logged the specifics; just propagate.
		return false, err
	end

	return true
end

function JjRepo:get_root()
	return self.state.root
end

function JjRepo:get_jj_dir()
	return self.state.jj_dir
end

function JjRepo:is_jj_repo()
	return self.state.jj_dir ~= ""
end

function JjRepo:get_working_copy()
	return self.state.working_copy
end

function JjRepo:get_bookmarks()
	return self.state.bookmarks
end

function JjRepo:get_revisions()
	return self.state.revisions
end

function JjRepo:get_operation_log()
	return self.state.operation_log
end

function JjRepo:get_conflicts()
	return self.state.conflicts
end

function JjRepo:get_remotes()
	return self.state.remotes
end

function JjRepo:detect_repository()
	local root, jj_dir = util.find_jj_dir(self.dir)

	if root and jj_dir then
		self.state.root = root
		self.state.jj_dir = jj_dir
		logger.debug("Detected jj repository: root=" .. root .. ", jj_dir=" .. jj_dir)
	else
		logger.debug("No jj repository detected in: " .. self.dir)
	end
end

function JjRepo:setup_modules()
	if self:is_jj_repo() then
		local status = require("neojj.lib.jj.status")
		status.setup(self)
	end
end

return JjRepo
