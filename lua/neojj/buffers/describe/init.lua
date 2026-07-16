local Buffer = require("neojj.lib.buffer")
local DescribeUI = require("neojj.buffers.describe.ui")
local logger = require("neojj.logger")

---@class DescribeBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field revision? string Revision to describe (defaults to @)
---@field on_submit? function Callback when description is submitted
---@field on_abort? function Callback when description is aborted
---@field submitting? boolean Re-entry guard while a submit job is in flight
---@field static_components? fun(): table[] Pre-filled components (skips async load)
---@field perform_write? fun(message: string): table Custom submit action (defaults to `jj describe`)
---@field success_message? string Notification shown on a successful submit
local DescribeBuffer = {}
DescribeBuffer.__index = DescribeBuffer

---Overrides that turn the describe buffer into a general write-to-submit
---commit-message editor (used for jj's squash combine-descriptions flow).
---@class DescribeBufferOpts
---@field components? fun(): table[] Static components to pre-fill (skips async load)
---@field perform_write? fun(message: string): table Custom submit action
---@field name? string Buffer name
---@field success_message? string Notification shown on a successful submit

---Create a new describe buffer for editing JJ commit descriptions.
---
---By default this loads the revision's current description and, on submit,
---writes it back with `jj describe`. Passing `opts` turns it into a general
---"write-to-submit" commit-message editor, reused for jj's squash
---combine-descriptions flow (see ViewBuffer:squash):
---  * `opts.components` — static UI components to pre-fill (skips the async
---    description load). Used verbatim, including any `JJ:` guidance lines
---    (which `get_description_from_buffer` strips on submit, matching jj's own
---    editor convention).
---  * `opts.perform_write` — run inside the submit async context instead of
---    `jj describe --stdin`; returns a result table `{ success, stderr }`. Lets
---    the caller run e.g. `jj squash -m`.
---  * `opts.name` — buffer name (defaults to `JJ Describe: <revision>`).
---  * `opts.success_message` — notification shown on a successful submit.
---@param repo table Repository instance
---@param revision? string Revision to describe (defaults to @)
---@param on_submit? function Callback when description is submitted
---@param on_abort? function Callback when description is aborted
---@param opts? DescribeBufferOpts Optional message-editor overrides
---@return DescribeBuffer describe_buffer Describe buffer instance
function DescribeBuffer.new(repo, revision, on_submit, on_abort, opts)
	revision = revision or "@"
	opts = opts or {}

	local instance = setmetatable({
		repo = repo,
		revision = revision,
		on_submit = on_submit,
		on_abort = on_abort,
		static_components = opts.components,
		perform_write = opts.perform_write,
		success_message = opts.success_message or "Description updated",
	}, DescribeBuffer)

	-- Create buffer with unified factory method
	local buffer = Buffer.create({
		name = opts.name or ("JJ Describe: " .. revision),
		filetype = "neojj-describe",
		kind = "split", -- Default to split view
		modifiable = true,
		readonly = false,
		scratch = false,
		cwd = repo.dir,
		disable_line_numbers = false,
		disable_relative_line_numbers = true,
		spell_check = true,
		mappings = {}, -- Will be added via _setup_mappings
		autocmds = {}, -- Will be added via _setup_autocmds
		initialize = function()
			-- Static content is rendered by the render callback below; only the
			-- description-loading variant needs its async fetch kicked off here.
			if not instance.static_components then
				instance:load_current_description()
			end
		end,
		render = function()
			if instance.static_components then
				return instance.static_components()
			elseif instance.description_loaded then
				return instance:create_ui_components()
			else
				return nil
			end
		end,
		after = function()
			-- Pre-filled content counts as "modified" after the initial render;
			-- clear it so a bare :q aborts cleanly (rather than prompting) and the
			-- render-skip-if-modified guard behaves.
			if instance.static_components and instance.buffer and instance.buffer:is_valid() then
				vim.api.nvim_set_option_value("modified", false, { buf = instance.buffer.handle })
			end
		end,
		on_detach = function()
			-- Cleanup when buffer is closed
			instance:_cleanup()
		end,
	})

	instance.buffer = buffer
	-- Static content is ready immediately; the async variant flips this once its
	-- description has loaded.
	instance.description_loaded = opts.components ~= nil
	instance.current_description = ""
	instance.submitting = false

	-- Buffer.create() gives every buffer 'buftype=nofile', but a 'nofile'
	-- buffer refuses :w/:wq with E382 and never fires BufWriteCmd. Use
	-- 'acwrite' so writes are routed through our BufWriteCmd handler, giving
	-- this buffer git-commit-style "write to submit" behaviour.
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buffer.handle })

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

	-- Handle :w and :wq commands (like git commit messages).
	-- Clear the 'modified' flag around submit() so that a following QuitPre
	-- (e.g. from :wq) does not observe a modified buffer and fire a second,
	-- racing submit path. submit() also guards against re-entry as a backstop.
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			self:submit()
			if self.buffer and self.buffer:is_valid() then
				vim.api.nvim_set_option_value("modified", false, { buf = self.buffer.handle })
			end
		end,
	})

	-- Handle quit commands (:q, :q!, ZQ, etc.).
	-- Quitting never auto-submits: a user who quits is bailing out, and forcing
	-- a submit on :q! would silently overwrite the commit description. We always
	-- discard (abort). Submitting is only ever done explicitly via :w/:wq/ZZ/<C-s>.
	vim.api.nvim_create_autocmd("QuitPre", {
		group = augroup,
		buffer = self.buffer.handle,
		callback = function()
			self:abort()
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
	-- Re-entry guard: :wq can fire both BufWriteCmd and QuitPre, and impatient
	-- users can trigger multiple submits. Without this guard we would launch
	-- several concurrent `jj describe --stdin` jobs racing each other.
	if self.submitting then
		logger.debug("Ignoring re-entrant submit for revision: " .. self.revision)
		return
	end
	self.submitting = true

	logger.info("Submitting description for revision: " .. self.revision)

	-- Get the description text, filtering out help comments
	local description = self:get_description_from_buffer()

	-- Execute the write (jj describe by default, or a caller-supplied action)
	local async = require("plenary.async")

	async.run(function()
		local result
		if self.perform_write then
			result = self.perform_write(description)
		else
			result = self:_default_write(description)
		end

		if result.success then
			logger.info("Description updated successfully")
			vim.schedule(function()
				-- Clear the guard so a later, legitimate submit can proceed.
				self.submitting = false
				vim.notify(self.success_message, vim.log.levels.INFO)
				-- Close the describe buffer BEFORE invoking on_submit. Tearing down
				-- the describe window first lets callers refresh and re-focus their
				-- originating view synchronously, rather than deferring past
				-- describe's window teardown with a timer. Mirrors abort(), which
				-- already closes before invoking its callback.
				if self.buffer and self.buffer:is_valid() then
					self.buffer:close()
				end
				-- Call the callback after the buffer has closed
				if self.on_submit then
					-- Wrap the callback in pcall to prevent errors from crashing
					local success, err = pcall(self.on_submit)
					if not success then
						logger.error("Error in on_submit callback: " .. tostring(err))
					end
				end
			end)
		else
			logger.error("Failed to update description: " .. (result.stderr or ""))
			vim.schedule(function()
				-- Clear the guard so the user can retry after a failed submit.
				self.submitting = false
				vim.notify("Failed to update description: " .. (result.stderr or ""), vim.log.levels.ERROR)
			end)
		end
	end)
end

---Default submit action: write the description back with `jj describe --stdin`.
---Runs inside submit()'s async context; returns a result table. Overridden per
---instance via `opts.perform_write` (e.g. the squash flow runs `jj squash -m`).
---@param description string The description text to write
---@return table result `{ success, exit_code, stdout, stderr }`
function DescribeBuffer:_default_write(description)
	-- Pass the description via stdin using plenary Job directly.
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

	return {
		success = ok and job.code == 0,
		exit_code = job.code or -1,
		stdout = ok and table.concat(stdout or {}, "\n") or "",
		stderr = ok and table.concat(job:stderr_result() or {}, "\n") or tostring(stdout),
	}
end

---Abort the description editing
function DescribeBuffer:abort()
	-- A write-quit (`:wq`/`:x`) fires BufWriteCmd (submit) and then QuitPre
	-- (abort) in sequence, so a *successful* submit would otherwise be followed
	-- by a spurious abort — logging "Aborting…" and running on_abort even though
	-- the write went through. If a submit is in flight, that submit owns the
	-- close/callback; don't abort over the top of it.
	if self.submitting then
		return
	end

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
		local json_parser = require("neojj.lib.jj.parsers.json_parser")

		local cmd = jj_cli.log():option("revisions", self.revision):option("template", "json(self)"):flag("no-graph")

		local result = cmd:call()

		if result and result.success and result.stdout then
			local log_json, err = json_parser.parse_log_json(result.stdout)
			if log_json then
				vim.schedule(function()
					self.current_description = log_json.description or ""
					self.description_loaded = true
					self:render_components()
				end)
			else
				logger.warn("Failed to parse description JSON: " .. tostring(err))
				vim.schedule(function()
					self.current_description = ""
					self.description_loaded = true
					self:render_components()
				end)
			end
		else
			logger.warn("Could not load current description: " .. (result and result.stderr or ""))
			vim.schedule(function()
				self.current_description = ""
				self.description_loaded = true
				self:render_components()
			end)
		end
	end)
end

---Create UI components for the describe buffer
---@return table[] components UI components
function DescribeBuffer:create_ui_components()
	return DescribeUI.create(self.current_description)
end

---Render components to the buffer
function DescribeBuffer:render_components()
	if not self.buffer or not self.buffer:is_valid() then
		return
	end

	-- Don't clobber user input. load_current_description() runs async and its
	-- render can land after the user has already started typing (the buffer
	-- opens empty and schedules startinsert). If the buffer is already
	-- modified, the user has typed something, so bail out rather than
	-- overwriting their text with the loaded description and force-resetting
	-- 'modified'. The freshly-opened, unmodified case still renders normally.
	if vim.api.nvim_get_option_value("modified", { buf = self.buffer.handle }) then
		logger.debug("Skipping describe render: buffer already modified by user")
		return
	end

	local components = self:create_ui_components()
	self.buffer:render(components)

	-- Reset modified flag so the help text doesn't count as changes
	vim.api.nvim_set_option_value("modified", false, { buf = self.buffer.handle })
end

---Get the description text from buffer (excluding help text)
---@return string description The current description text
function DescribeBuffer:get_description_from_buffer()
	local lines = vim.api.nvim_buf_get_lines(self.buffer.handle, 0, -1, false)
	local description_lines = {}

	for _, line in ipairs(lines) do
		-- Skip help comments. We only strip our own "JJ:"-prefixed help lines
		-- (matching jj's own editor convention) so legitimate description lines
		-- such as Markdown headings ("# Overview") or issue refs ("#123 ...")
		-- survive the round-trip intact.
		if not line:match("^JJ:") then
			table.insert(description_lines, line)
		end
	end

	-- Remove trailing empty lines
	while #description_lines > 0 and description_lines[#description_lines] == "" do
		table.remove(description_lines)
	end

	return table.concat(description_lines, "\n")
end

---Show the describe buffer
---@param kind? string Display mode override
function DescribeBuffer:show(kind)
	self.buffer:open(kind)
end

---Show the describe buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function DescribeBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
end

---Show the describe buffer in a new tab
function DescribeBuffer:show_tab()
	self.buffer:open("tab")
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
