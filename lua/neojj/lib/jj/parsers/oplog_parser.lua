---Parser for jj operation-log (`jj op log`) output produced by NeoJJ's explicit
---template.
---
---Like the commit-log parser (see `neojj.lib.jj.parsers.log_parser`), this module
---does NOT parse jj's human-facing default format. Instead the oplog buffer
---requests a machine-oriented template (see `neojj.buffers.oplog.init`) built
---around the same two ASCII control characters:
---
---  * RECORD SEPARATOR  (0x1e, "\30") marks the boundary between the graph
---    gutter that `jj op log` draws on the left and the templated payload. jj
---    never emits this byte in the graph, so splitting on it is unambiguous for
---    any node glyph (`@`, `○`, `│`, …).
---  * UNIT SEPARATOR    (0x1f, "\31") separates the fields inside an operation
---    header payload.
---
---Each operation occupies two templated lines:
---
---  <gutter>\30<op_id>\31<user>\31<time_start>\31<time_end>
---  <gutter>\30<description first line>
---
---A line is recognised as an operation header purely by the presence of a
---payload containing unit separators, never by matching a fixed set of graph
---glyphs. Graph-only connector lines carry no record separator and are preserved
---as gutter for rendering.

local Separators = require("neojj.lib.jj.separators")

local M = {}

---Split a raw op-log line into its graph gutter and templated payload.
---@param line string A single line of jj op log output
---@return string gutter The graph characters drawn to the left of the payload
---@return string|nil payload The templated payload, or nil if the line is graph-only
local function split_gutter(line)
	local gutter, payload = line:match("^(.-)" .. Separators.RECORD .. "(.*)$")
	if gutter == nil then
		-- No record separator: this is a pure graph/connector line.
		return line, nil
	end
	return gutter, payload
end

---Parse jj op log output produced by the NeoJJ oplog template.
---@param output string Raw output from jj op log command
---@return ParsedOpLog parsed Parsed op log with operations, graph data, and raw lines
function M.parse_oplog_output(output)
	---@type OpLogOperation[]
	local operations = {}
	---@type table<integer, OpGraphData>
	local graph_data = {}
	---@type string[]
	local raw_lines = {}

	---@type OpLogOperation|nil
	local current_operation = nil

	local lines = vim.split(output, "\n")

	for i, line in ipairs(lines) do
		if line == "" then
			-- Preserve blank lines positionally so the UI can render them.
			raw_lines[i] = ""
			goto continue
		end

		local gutter, payload = split_gutter(line)

		if payload == nil then
			-- Graph-only connector line: no payload to parse.
			raw_lines[i] = gutter
			graph_data[i] = { graph = gutter, operation = nil }
			goto continue
		end

		if payload:find(Separators.UNIT, 1, true) then
			-- Operation header line: fields are unit-separated.
			local fields = vim.split(payload, Separators.UNIT, { plain = true })
			local operation_id = fields[1] or ""
			local user = fields[2] or ""
			local time_start = fields[3] or ""
			local time_end = fields[4] or ""

			-- The current operation is the one jj marks with `@` in the gutter.
			local is_current = gutter:find("@", 1, true) ~= nil

			---@type OpLogOperation
			current_operation = {
				operation_id = operation_id,
				user = user,
				time_start = time_start,
				time_end = time_end,
				description = "",
				is_current = is_current,
				graph = gutter,
				line_number = i,
			}
			table.insert(operations, current_operation)

			-- Rebuild a clean, control-character-free line for display.
			local display = gutter .. operation_id .. " " .. user .. " " .. time_start
			raw_lines[i] = display

			graph_data[i] = { graph = gutter, operation = current_operation }
		else
			-- Description continuation line: payload is the description text.
			if current_operation and current_operation.description == "" then
				current_operation.description = payload
			end
			raw_lines[i] = gutter .. payload
			graph_data[i] = { graph = gutter, operation = nil }
		end

		::continue::
	end

	---@type ParsedOpLog
	return {
		operations = operations,
		graph_data = graph_data,
		raw_lines = raw_lines,
	}
end

return M
