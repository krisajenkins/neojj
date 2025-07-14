local Buffer = require("neojj.lib.buffer")
local logger = require("neojj.logger")

---@class DescribeBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field revision? string Revision to describe (defaults to @)
---@field on_submit? function Callback when description is submitted
---@field on_abort? function Callback when description is aborted
local DescribeBuffer = {}
DescribeBuffer.__index = DescribeBuffer

---Create a new describe buffer for editing JJ commit descriptions
---@param repo table Repository instance
---@param revision? string Revision to describe (defaults to @)
---@param on_submit? function Callback when description is submitted
---@param on_abort? function Callback when description is aborted
---@return DescribeBuffer describe_buffer Describe buffer instance
function DescribeBuffer.new(repo, revision, on_submit, on_abort)
	revision = revision or "@"

	local buffer = Buffer.new({
		name = "JJ Describe: " .. revision,
		filetype = "jjdescribe",
		modifiable = true,
		readonly = false,
		scratch = false,
	})

	local instance = setmetatable({
		buffer = buffer,
		repo = repo,
		revision = revision,
		on_submit = on_submit,
		on_abort = on_abort,
	}, DescribeBuffer)

	-- Add describe-specific key mappings
	instance:_setup_mappings()
	instance:_setup_autocmds()

	return instance
end

---Setup describe-specific key mappings
function DescribeBuffer:_setup_mappings()
	-- Submit description (normal mode) - like git commit
	self.buffer:map("n", "<C-s>", function()
		self:submit()
	end, { desc = "Submit description" })

	-- Submit description (insert mode) - like git commit
	self.buffer:map("i", "<C-s>", function()
		vim.cmd.stopinsert()
		self:submit()
	end, { desc = "Submit description" })

	-- Submit with Ctrl+C Ctrl+C (like git commit and neogit)
	self.buffer:map("n", "<C-c><C-c>", function()
		self:submit()
	end, { desc = "Submit description" })

	self.buffer:map("i", "<C-c><C-c>", function()
		vim.cmd.stopinsert()
		self:submit()
	end, { desc = "Submit description" })

	-- Abort with Ctrl+C Ctrl+Q (like neogit)
	self.buffer:map("n", "<C-c><C-q>", function()
		self:abort()
	end, { desc = "Abort description" })

	self.buffer:map("i", "<C-c><C-q>", function()
		vim.cmd.stopinsert()
		self:abort()
	end, { desc = "Abort description" })

	-- Standard vim-like save and quit
	self.buffer:map("n", "ZZ", function()
		self:submit()
	end, { desc = "Save and submit" })

	self.buffer:map("n", "ZQ", function()
		self:abort()
	end, { desc = "Quit without saving" })

	-- Close with q
	self.buffer:map("n", "q", function()
		self:close_with_confirmation()
	end, { desc = "Close (with confirmation if modified)" })
end

---Setup autocmds for the describe buffer
function DescribeBuffer:_setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("neojj_describe_" .. self.buffer.handle, { clear = true })

	-- Auto-start insert mode
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			-- Start in insert mode if buffer is empty
			local line_count = vim.api.nvim_buf_line_count(self.buffer.handle)
			if line_count == 1 then
				local first_line = vim.api.nvim_buf_get_lines(self.buffer.handle, 0, 1, false)[1]
				if first_line == "" then
					vim.schedule(function()
						vim.cmd("startinsert")
					end)
				end
			end
		end,
	})

	-- Handle :w and :wq commands (like git commit messages)
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			self:submit()
		end,
	})

	-- Handle :q! to abort
	vim.api.nvim_create_autocmd("QuitPre", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			-- Check if this is a forced quit (:q!) vs normal quit (:q)
			-- For now, we'll treat all quits as potential submits unless modified
			if vim.api.nvim_get_option_value("modified", { buf = self.buffer.handle }) then
				self:submit()
			else
				self:abort()
			end
		end,
	})

	-- Clean up on buffer unload
	vim.api.nvim_create_autocmd("BufUnload", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			self:_cleanup()
		end,
	})
end

---Submit the description
function DescribeBuffer:submit()
	logger.info("Submitting description for revision: " .. self.revision)

	-- Get the description text, filtering out help comments
	local lines = vim.api.nvim_buf_get_lines(self.buffer.handle, 0, -1, false)
	local description_lines = {}

	for _, line in ipairs(lines) do
		-- Skip help comments and empty lines at the end
		if not line:match("^#") then
			table.insert(description_lines, line)
		end
	end

	-- Remove trailing empty lines
	while #description_lines > 0 and description_lines[#description_lines] == "" do
		table.remove(description_lines)
	end

	local description = table.concat(description_lines, "\n")

	-- Execute jj describe command
	local async = require("plenary.async")

	async.run(function()
		-- We need to pass the description via stdin using plenary Job directly
		local Job = require("plenary.job")
		local job = Job:new({
			command = "jj",
			args = { "--color", "never", "describe", self.revision, "--stdin" },
			cwd = self.repo.dir,
			writer = description,
		})

		local ok, stdout = pcall(function()
			return job:sync()
		end)

		local result = {
			success = ok and job.code == 0,
			exit_code = job.code or -1,
			stdout = ok and table.concat(stdout or {}, "\n") or "",
			stderr = ok and table.concat(job:stderr_result() or {}, "\n") or tostring(stdout),
		}

		if result.success then
			logger.info("Description updated successfully")
			vim.schedule(function()
				vim.notify("Description updated", vim.log.levels.INFO)
				-- Call the callback before closing the buffer
				if self.on_submit then
					-- Wrap the callback in pcall to prevent errors from crashing
					local success, err = pcall(self.on_submit)
					if not success then
						logger.error("Error in on_submit callback: " .. tostring(err))
					end
				end
				-- Close buffer after callback
				if self.buffer and self.buffer:is_valid() then
					self.buffer:close()
				end
			end)
		else
			logger.error("Failed to update description: " .. (result.stderr or ""))
			vim.schedule(function()
				vim.notify("Failed to update description: " .. (result.stderr or ""), vim.log.levels.ERROR)
			end)
		end
	end)
end

---Abort the description editing
function DescribeBuffer:abort()
	logger.info("Aborting description for revision: " .. self.revision)

	self.buffer:close()
	if self.on_abort then
		self.on_abort()
	end
end

---Close with confirmation if buffer is modified
function DescribeBuffer:close_with_confirmation()
	if vim.api.nvim_get_option_value("modified", { buf = self.buffer.handle }) then
		local choice = vim.fn.confirm("Save changes?", "&Yes\n&No\n&Cancel", 1)
		if choice == 1 then
			self:submit()
		elseif choice == 2 then
			self:abort()
		end
		-- If choice == 3 (Cancel), do nothing
	else
		self:abort()
	end
end

---Load existing description for the revision
function DescribeBuffer:load_current_description()
	local async = require("plenary.async")

	async.run(function()
		local jj_cli = require("neojj.lib.jj.cli")
		local cmd = jj_cli.log():option("revisions", self.revision):option("template", "description"):flag("no-graph")

		local result = cmd:call()

		if result.success and result.stdout then
			local description = vim.trim(result.stdout)
			vim.schedule(function()
				if description ~= "" then
					local lines = vim.split(description, "\n")
					vim.api.nvim_buf_set_lines(self.buffer.handle, 0, -1, false, lines)
				end
				self:_add_help_text()
			end)
		else
			logger.warn("Could not load current description: " .. (result.stderr or ""))
			vim.schedule(function()
				self:_add_help_text()
			end)
		end
	end)
end

---Add help text to the buffer explaining keybindings
function DescribeBuffer:_add_help_text()
	-- Get current content
	local lines = vim.api.nvim_buf_get_lines(self.buffer.handle, 0, -1, false)

	-- Add help text as comments
	local help_lines = {
		"",
		"# Commands:",
		"#   :w or :wq    - Submit description",
		"#   <C-c><C-c>   - Submit description",
		"#   <C-c><C-q>   - Abort",
		"#   ZZ           - Submit description",
		"#   ZQ           - Abort",
		"#   q            - Close with confirmation",
	}

	-- Append help text
	vim.list_extend(lines, help_lines)
	vim.api.nvim_buf_set_lines(self.buffer.handle, 0, -1, false, lines)

	-- Reset modified flag so the help text doesn't count as changes
	vim.api.nvim_set_option_value("modified", false, { buf = self.buffer.handle })
end

---Show the describe buffer
function DescribeBuffer:show()
	self.buffer:show()
	self:load_current_description()
end

---Show the describe buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function DescribeBuffer:show_split(split_type)
	self.buffer:show_split(split_type)
	self:load_current_description()
end

---Show the describe buffer in a new tab
function DescribeBuffer:show_tab()
	self.buffer:show_tab()
	self:load_current_description()
end

---Close the describe buffer
function DescribeBuffer:close()
	self.buffer:close()
end

---Clean up resources
function DescribeBuffer:_cleanup()
	-- Nothing to clean up anymore since we use stdin instead of temp files
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function DescribeBuffer:is_valid()
	return self.buffer:is_valid()
end

---Get buffer handle
---@return number handle Buffer handle
function DescribeBuffer:get_handle()
	return self.buffer:get_handle()
end

return DescribeBuffer
