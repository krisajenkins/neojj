local Buffer = require("neojj.lib.buffer")
local ViewBuffer = require("neojj.lib.view_buffer")
local OpShowUI = require("neojj.buffers.opshow.ui")
local opshow_parser = require("neojj.lib.jj.parsers.opshow_parser")
local logger = require("neojj.logger")
local Separators = require("neojj.lib.jj.separators")

-- Explicit machine-oriented template for the *operation* half of `jj op show`
-- (`-T`), mirroring the log/oplog templates. The operation header is emitted as
-- one "\x1e"-led record whose fields are "\x1f"-separated; the operation's own
-- description and `args:` metadata follow as plain prose lines (no separators),
-- exactly as jj lays them out. See neojj.lib.jj.parsers.opshow_parser.
local OPSHOW_OP_TEMPLATE = table.concat({
	Separators.RECORD_TEMPLATE,
	"self.id().short(12)",
	Separators.UNIT_TEMPLATE,
	"self.user()",
	Separators.UNIT_TEMPLATE,
	'self.time().start().format("%Y-%m-%d %H:%M:%S")',
	'"\\n"',
	'if(self.description() != "", self.description() ++ "\\n", "")',
	'if(self.attributes() != "", self.attributes() ++ "\\n", "")',
}, " ++ ")

-- The "Changed commits:" section of `jj op show` renders each changed commit
-- with the `commit_summary` template, which we override (via `--config`) with an
-- unambiguous "\x1e"/"\x1f"-keyed record so those lines parse the same way the
-- log view's commit rows do. jj still prefixes each line with its own "+ "/"- "
-- op-diff sign, which the parser strips off. Change/commit ids use `shortest(8)`
-- plus `.prefix()` so the UI can brighten the unique prefix and dim the rest.
--
-- The change-offset field mirrors jj's own `format_change_offset`: hidden and
-- divergent commits carry a "/N" suffix (e.g. `ymlkrvkx/1`) that disambiguates
-- which commit of a change is meant; the UI appends it to the change id.
local OPSHOW_COMMIT_TEMPLATE = table.concat({
	Separators.RECORD_TEMPLATE,
	"change_id.shortest(8)",
	Separators.UNIT_TEMPLATE,
	"change_id.shortest(8).prefix()",
	Separators.UNIT_TEMPLATE,
	'if(hidden || divergent, "/" ++ change_offset, "")',
	Separators.UNIT_TEMPLATE,
	"commit_id.shortest(8)",
	Separators.UNIT_TEMPLATE,
	"commit_id.shortest(8).prefix()",
	Separators.UNIT_TEMPLATE,
	'if(empty, "empty", "")',
	Separators.UNIT_TEMPLATE,
	'if(hidden, "hidden", "")',
	Separators.UNIT_TEMPLATE,
	'if(conflict, "conflict", "")',
	Separators.UNIT_TEMPLATE,
	'if(description == "", "(no description set)", description.first_line())',
}, " ++ ")

---@class OpShowBuffer : ViewBuffer
---@field buffer Buffer Buffer instance
---@field repo table Repository instance
---@field op_id string Operation id this view shows
---@field options table Options passed at construction
local OpShowBuffer = setmetatable({}, { __index = ViewBuffer })
OpShowBuffer.__index = OpShowBuffer
OpShowBuffer.frame_name = "op show"
-- Op-show views don't participate in the auto-refresh watcher (their operation
-- id is fixed), so they neither arm nor tear it down.
OpShowBuffer.arms_watcher = false

-- Per (repo, operation) instance tracking. Keyed by the normalized repo dir and
-- the operation id so that op-show views for two different operations (or repos)
-- coexist instead of sharing one instance.
local instances = {}

local function instance_key(repo, op_id)
	return vim.fs.normalize(repo.dir) .. "\x00" .. op_id
end

---Create or get an existing op-show buffer for an operation.
---@param repo table Repository instance
---@param op_id string Operation id to show (from `jj op show <op_id>`)
---@param options? table Options
---@return OpShowBuffer opshow_buffer Op-show buffer instance
function OpShowBuffer.new(repo, op_id, options)
	options = options or {}

	local key = instance_key(repo, op_id)

	return ViewBuffer.get_or_create(instances, key, function()
		local new_instance = setmetatable({
			repo = repo,
			op_id = op_id,
			options = options,
		}, OpShowBuffer)

		local util = require("neojj.lib.jj.util")
		local buffer = Buffer.create({
			name = "NeoJJ Operation " .. op_id .. " (" .. util.repo_namespace(repo) .. ")",
			filetype = "neojj-opshow",
			kind = "replace",
			modifiable = false,
			readonly = true,
			-- Stay alive when a drilled-into frame replaces us in the window, so the
			-- view stack can reveal us again on pop.
			bufhidden = "hide",
			cwd = repo.dir,
			context_highlight = true,
			foldmarkers = false,
			disable_line_numbers = true,
			disable_relative_line_numbers = true,
			disable_signs = false,
			spell_check = false,
			render = function()
				return nil
			end,
			-- Drop the module-level instance when the buffer is wiped so a later
			-- OpShowBuffer.new for the same operation rebuilds a fresh instance.
			on_detach = function()
				instances[key] = nil
			end,
		})

		new_instance.buffer = buffer

		new_instance:_setup_mappings()

		return new_instance
	end)
end

---Setup op-show-specific key mappings
function OpShowBuffer:_setup_mappings()
	-- Pop one frame off the view stack, revealing the view drilled down from.
	self:_map_back_keys()

	self.buffer:map("n", "<c-r>", function()
		self:refresh()
	end, { desc = "Refresh operation view" })

	-- Open the commit log view.
	self.buffer:map("n", "l", function()
		self:open_log()
	end, { desc = "Open the log view" })
end

---Open the commit log view, keeping this op-show view on the stack beneath it.
function OpShowBuffer:open_log()
	local LogBuffer = require("neojj.buffers.log")
	LogBuffer.new(self.repo):show()
end

---Refresh the op-show buffer
function OpShowBuffer:refresh()
	logger.info("Refreshing op-show buffer for operation " .. self.op_id)

	if not self.repo:is_jj_repo() then
		self.buffer:render_error("Not a JJ repository")
		return
	end

	local cli = require("neojj.lib.jj.cli")
	local async = require("plenary.async")

	async.run(function()
		local result = cli
			.op_show()
			:flag("no-graph")
			:option("template", OPSHOW_OP_TEMPLATE)
			-- TOML literal string (single quotes): the template has double quotes
			-- but no single quotes, and plenary passes argv directly so there is no
			-- shell to escape for.
			:option(
				"config",
				"templates.commit_summary='" .. OPSHOW_COMMIT_TEMPLATE .. "'"
			)
			:arg(self.op_id)
			:cwd(self.repo.dir)
			:call_async()

		vim.schedule(function()
			if not (self.buffer and self.buffer:is_valid()) then
				logger.debug("Op-show buffer is no longer valid, skipping render")
				return
			end

			if not result.success then
				self.buffer:render_error("Failed to show operation: " .. (result.stderr or "Unknown error"))
				return
			end

			self:render(result.stdout or "")
		end)
	end)
end

---Render the op-show output as read-only, per-field highlighted lines.
---@param output string The raw (templated) `jj op show` output
function OpShowBuffer:render(output)
	if not self.buffer or not self.buffer:is_valid() then
		logger.debug("Cannot render: op-show buffer is invalid")
		return
	end

	self.buffer:render(OpShowUI.create(opshow_parser.parse(output)))
end

-- Lifecycle plumbing (_push_frame, go_back, show, show_split, show_tab, close,
-- is_valid, get_handle) is inherited from ViewBuffer. Op-show sets
-- `arms_watcher = false`, so its inherited _push_frame skips the file watcher.

return OpShowBuffer
