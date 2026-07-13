local M = {}

--- Run a jj cli builder asynchronously against a view's repo, handling the
--- async.run → call_async → vim.schedule(notify + refresh) boilerplate shared
--- by every jj action on the status and log views. Duck-typed on `view`: needs
--- `view.repo.dir` and `view:refresh()`.
---@param view table  -- StatusBuffer | LogBuffer
---@param opts { builder: table, pending?: string, failure: string, success: string|fun(result: table): string }
function M.run(view, opts)
	local async = require("plenary.async")
	if opts.pending then
		vim.notify(opts.pending, vim.log.levels.INFO)
	end
	async.run(function()
		local result = opts.builder:cwd(view.repo.dir):call_async()
		vim.schedule(function()
			if result.success then
				local msg = type(opts.success) == "function" and opts.success(result) or opts.success
				vim.notify(msg, vim.log.levels.INFO)
				view:refresh()
			else
				vim.notify(opts.failure .. ": " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
			end
		end)
	end)
end

return M
