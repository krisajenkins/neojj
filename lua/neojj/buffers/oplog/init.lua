local Buffer = require("neojj.lib.buffer")
local ViewBuffer = require("neojj.lib.view_buffer")
local action = require("neojj.lib.jj.action")
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

---@class OplogBuffer : ViewBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field state table Current oplog state
---@field options table Oplog options (e.g. limit) passed at construction
local OplogBuffer = setmetatable({}, { __index = ViewBuffer })
OplogBuffer.__index = OplogBuffer
OplogBuffer.frame_name = "oplog"

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
	return ViewBuffer.list_valid(instances)
end

---Create or get existing oplog buffer
---@param repo table Repository instance
---@param options? table Oplog options
---@return OplogBuffer oplog_buffer Oplog buffer instance
function OplogBuffer.new(repo, options)
	options = options or {}

	local repo_key = vim.fs.normalize(repo.dir)

	return ViewBuffer.get_or_create(instances, repo_key, function()
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

		return new_instance
	end, function(existing)
		existing.options = vim.tbl_extend("force", existing.options or {}, options or {})
	end)
end

---Setup oplog-specific key mappings
function OplogBuffer:_setup_mappings()
	-- Pop one frame off the view stack, revealing the view drilled down from.
	self:_map_back_keys()

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

-- Lifecycle plumbing (_push_frame, go_back, show, show_split, show_tab, close)
-- is inherited from ViewBuffer.

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

	action.run(self, {
		builder = require("neojj.lib.jj.cli").op_restore():arg(op_id),
		success = function()
			return "Restored to operation " .. op_id
		end,
		failure = "Failed to restore operation",
	})
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

	action.run(self, {
		builder = require("neojj.lib.jj.cli").undo(),
		success = "Undid the last operation",
		failure = "Failed to undo",
	})
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

-- is_valid / get_handle are inherited from ViewBuffer.

return OplogBuffer
