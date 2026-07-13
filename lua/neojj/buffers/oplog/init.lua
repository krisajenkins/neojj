local Buffer = require("neojj.lib.buffer")
local OplogUI = require("neojj.buffers.oplog.ui")
local logger = require("neojj.logger")
local oplog_parser = require("neojj.lib.jj.parsers.oplog_parser")
local Separators = require("neojj.lib.jj.separators")

-- Explicit machine-oriented template for `jj op log`, mirroring the commit-log
-- template (see neojj.buffers.log.init). Rather than parse jj's fragile
-- human-facing output, we ask for an unambiguous layout keyed on two ASCII
-- control characters (see neojj.lib.jj.parsers.oplog_parser for the full
-- contract):
--   "\x1e" (RECORD SEPARATOR) marks the boundary between jj's graph gutter and
--          our payload. jj never emits this byte in the graph, so splitting on
--          it is unambiguous for any node glyph (@, ○, │, …).
--   "\x1f" (UNIT SEPARATOR) separates the fields within an operation header.
-- Each operation spans two lines: a header record and a description record. The
-- graph gutter is kept so the gutter still renders.
local OPLOG_TEMPLATE = table.concat({
	Separators.RECORD_TEMPLATE,
	"self.id().short(12)",
	Separators.UNIT_TEMPLATE,
	"self.user()",
	Separators.UNIT_TEMPLATE,
	'self.time().start().format("%Y-%m-%d %H:%M:%S")',
	Separators.UNIT_TEMPLATE,
	'self.time().end().format("%Y-%m-%d %H:%M:%S")',
	'"\\n"',
	Separators.RECORD_TEMPLATE,
	'if(self.description() == "", "(no description)", self.description().first_line())',
	'"\\n"',
}, " ++ ")

---@class OplogBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field state table Current oplog state
---@field options table Oplog options (e.g. limit) passed at construction
local OplogBuffer = {}
OplogBuffer.__index = OplogBuffer

-- Per-repo instance tracking. Keyed by the normalized repo dir so that oplog
-- views for two different repos coexist instead of sharing one instance.
local instances = {}

---Return the currently-valid oplog buffer instances tracked by this module.
---
---Lets callers outside this module (e.g. the auto-refresh watcher) fan a
---refresh out to open oplog views without reaching into the private `instances`
---map or scanning buffers by name.
---@return OplogBuffer[] instances Valid oplog buffer instances
function OplogBuffer.list_instances()
	local result = {}
	for _, inst in pairs(instances) do
		if inst:is_valid() then
			table.insert(result, inst)
		end
	end
	return result
end

---Create or get existing oplog buffer
---@param repo table Repository instance
---@param options? table Oplog options
---@return OplogBuffer oplog_buffer Oplog buffer instance
function OplogBuffer.new(repo, options)
	options = options or {}

	local repo_key = vim.fs.normalize(repo.dir)

	-- Return existing instance if available for this repo
	if instances[repo_key] and instances[repo_key]:is_valid() then
		instances[repo_key].options = vim.tbl_extend("force", instances[repo_key].options or {}, options or {})
		return instances[repo_key]
	end

	local new_instance = setmetatable({
		repo = repo,
		state = {
			operations = {},
			graph_data = {},
		},
		options = options,
		show_help = false,
	}, OplogBuffer)

	-- Create buffer with a per-repo namespaced name (reuse if exists).
	local util = require("neojj.lib.jj.util")
	local buffer = Buffer.create({
		name = "NeoJJ Operation Log (" .. util.repo_namespace(repo) .. ")",
		filetype = "neojj-oplog",
		kind = "replace",
		modifiable = false,
		readonly = true,
		-- Stay alive when a drilled-into frame replaces us in the window, so the
		-- view stack can reveal us again on pop.
		bufhidden = "hide",
		cwd = repo.dir,
		context_highlight = true,
		active_item_highlight = true,
		foldmarkers = false,
		disable_line_numbers = true,
		disable_relative_line_numbers = true,
		disable_signs = false,
		spell_check = false,
		autocmds = {
			{
				event = "BufWinEnter",
				callback = function()
					vim.cmd("setlocal cursorline")
				end,
			},
		},
		render = function()
			return nil
		end,
		-- Drop the module-level instance when the buffer is wiped so a later
		-- OplogBuffer.new for the same repo rebuilds a fresh instance.
		on_detach = function()
			instances[repo_key] = nil
			-- Tear the auto-refresh watcher down once no view for this root remains.
			require("neojj.lib.watcher").cleanup(repo:get_root())
		end,
	})

	new_instance.buffer = buffer

	new_instance:_setup_mappings()

	instances[repo_key] = new_instance

	return new_instance
end

---Setup oplog-specific key mappings
function OplogBuffer:_setup_mappings()
	-- Pop one frame off the view stack, revealing the view drilled down from.
	for _, key in ipairs({ "q", "<esc>", "<c-c>" }) do
		self.buffer:map("n", key, function()
			self:go_back()
		end, { desc = "Back (pop view stack) / close oplog" })
	end

	-- Drill into the operation at cursor (jj op show <op_id>).
	self.buffer:map("n", "<cr>", function()
		self:show_operation_at_cursor()
	end, { desc = "Show operation details (jj op show)" })

	-- Restore to the operation at cursor. `r` is the restore key here (unlike the
	-- commit log where `r` refreshes); refresh is on <C-r>.
	self.buffer:map("n", "r", function()
		self:restore_operation_at_cursor()
	end, { desc = "Restore repo to operation at cursor" })

	-- Undo the last operation.
	self.buffer:map("n", "u", function()
		self:undo()
	end, { desc = "Undo the last operation (jj undo)" })

	-- Ctrl-R refreshes (r is restore in this buffer).
	self.buffer:map("n", "<c-r>", function()
		self:refresh()
	end, { desc = "Refresh operation log" })

	-- Yank operation ID.
	self.buffer:map("n", "y", function()
		self:yank_operation_id_at_cursor()
	end, { desc = "Yank operation ID" })

	-- Open the commit log view.
	self.buffer:map("n", "l", function()
		self:open_log()
	end, { desc = "Open the log view" })

	-- Help mapping.
	self.buffer:map("n", "?", function()
		self:toggle_help()
	end, { desc = "Toggle help" })
end

---Open the commit log view, keeping this oplog view on the stack beneath it.
function OplogBuffer:open_log()
	local LogBuffer = require("neojj.buffers.log")
	LogBuffer.new(self.repo):show()
end

---Refresh the oplog buffer
function OplogBuffer:refresh()
	logger.info("Refreshing oplog buffer")

	if not self.repo:is_jj_repo() then
		self.buffer:render_error("Not a JJ repository")
		return
	end

	local async = require("plenary.async")

	async.run(function()
		local oplog_data = self:get_oplog_data()

		self.state = {
			operations = oplog_data.operations,
			graph_data = oplog_data.graph_data,
			raw_lines = oplog_data.raw_lines,
		}

		vim.schedule(function()
			if self.buffer and self.buffer:is_valid() then
				self:render()
			else
				logger.debug("Oplog buffer is no longer valid, skipping render")
			end
		end)
	end)
end

---Get op-log data from jj
---@return table oplog_data Oplog data with operations and graph info
function OplogBuffer:get_oplog_data()
	local cli = require("neojj.lib.jj.cli")

	local limit = self.options.limit or 100

	local builder = cli.op_log():option("limit", tostring(limit)):option("template", OPLOG_TEMPLATE):cwd(self.repo.dir)

	local result = builder:call_async()

	logger.debug("Op log command result - success: " .. tostring(result.success))
	if result.stderr then
		logger.debug("Op log command stderr: " .. result.stderr)
	end

	if not result.success then
		logger.warn("Failed to get op log: " .. tostring(result.stderr))
		return {
			operations = {},
			graph_data = {},
			raw_lines = {},
		}
	end

	local parsed = oplog_parser.parse_oplog_output(result.stdout)

	-- Sanitize raw_lines to ensure no embedded newlines
	if parsed.raw_lines then
		for i, line in ipairs(parsed.raw_lines) do
			parsed.raw_lines[i] = line:gsub("\n", " "):gsub("\r", "")
		end
	end

	logger.debug("Parsed oplog data - operations: " .. #parsed.operations)
	return parsed
end

---Render the oplog UI
function OplogBuffer:render()
	if not self.buffer or not self.buffer:is_valid() then
		logger.debug("Cannot render: oplog buffer is invalid")
		return
	end

	local components
	if self.show_help then
		components = { OplogUI.create_help() }
	else
		components = OplogUI.create(self.state, self)
	end

	self.buffer:render(components)
end

---Register this view as the top frame of the drill-down view stack.
function OplogBuffer:_push_frame()
	-- Arm the external-change watcher for this repo. _push_frame is the single
	-- choke point every display path routes through, and ensure() is idempotent.
	require("neojj.lib.watcher").ensure(self.repo)
	require("neojj.lib.view_stack").push(self.buffer:get_handle(), {
		teardown = function()
			self:close()
		end,
	})
end

---Go back: pop this frame off the view stack, revealing the frame beneath.
function OplogBuffer:go_back()
	local view_stack = require("neojj.lib.view_stack")
	local top = view_stack.top()
	if top and top.bufnr == self.buffer:get_handle() then
		view_stack.pop()
	else
		self.buffer:close()
	end
end

---Show the oplog buffer
---@param kind? string Display mode override
function OplogBuffer:show(kind)
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

---Show the oplog buffer in a split
---@param split_type? string Split type ("horizontal" or "vertical")
function OplogBuffer:show_split(split_type)
	local kind = split_type == "vertical" and "vsplit" or "split"
	self.buffer:open(kind)
	self:_push_frame()
	self:refresh()
end

---Show the oplog buffer in a new tab
function OplogBuffer:show_tab()
	self.buffer:open("tab")
	self:_push_frame()
	self:refresh()
end

---Close the oplog buffer
function OplogBuffer:close()
	self.buffer:close()
end

---Toggle help display
function OplogBuffer:toggle_help()
	self.show_help = not self.show_help
	self:render()
end

---Restore the repository to the operation at the cursor (jj op restore).
function OplogBuffer:restore_operation_at_cursor()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.operation_id then
		vim.notify("No operation at cursor", vim.log.levels.WARN)
		return
	end

	local op_id = item.operation_id
	local prompt = "Restore repository to operation " .. op_id .. "?"
	local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
	if choice ~= 1 then
		return
	end

	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		local result = cli.op_restore():arg(op_id):cwd(self.repo.dir):call_async()

		vim.schedule(function()
			if result.success then
				vim.notify("Restored to operation " .. op_id, vim.log.levels.INFO)
				self:refresh()
			else
				vim.notify("Failed to restore operation: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
			end
		end)
	end)
end

---Drill into the operation at the cursor, opening a new op-show view
---(equivalent to `jj op show <op_id>`) as a fresh view-stack frame.
function OplogBuffer:show_operation_at_cursor()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.operation_id then
		vim.notify("No operation at cursor", vim.log.levels.WARN)
		return
	end

	local OpShowBuffer = require("neojj.buffers.opshow")
	OpShowBuffer.new(self.repo, item.operation_id):show()
end

---Undo the last operation (jj undo).
function OplogBuffer:undo()
	local choice = vim.fn.confirm("Undo the last operation?", "&Yes\n&No", 2)
	if choice ~= 1 then
		return
	end

	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		local result = cli.undo():cwd(self.repo.dir):call_async()

		vim.schedule(function()
			if result.success then
				vim.notify("Undid the last operation", vim.log.levels.INFO)
				self:refresh()
			else
				vim.notify("Failed to undo: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
			end
		end)
	end)
end

---Yank the operation ID at the cursor.
function OplogBuffer:yank_operation_id_at_cursor()
	local item = self.buffer:get_item_at_cursor()
	if not item or not item.operation_id then
		vim.notify("No operation at cursor", vim.log.levels.WARN)
		return
	end

	vim.fn.setreg("+", item.operation_id)
	vim.notify("Copied operation ID: " .. item.operation_id, vim.log.levels.INFO)
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function OplogBuffer:is_valid()
	return self.buffer:is_valid()
end

---Get buffer handle
---@return number handle Buffer handle
function OplogBuffer:get_handle()
	return self.buffer:get_handle()
end

return OplogBuffer
