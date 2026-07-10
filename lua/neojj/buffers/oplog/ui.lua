local Ui = require("neojj.lib.ui")

---@class OplogUI
local OplogUI = {}

---Create the main operation-log UI components
---@param oplog_state table Oplog state with operations and graph data
---@param oplog_buffer? table Oplog buffer instance for interactions
---@return table[] components UI components
function OplogUI.create(oplog_state, oplog_buffer)
	local components = {}

	-- Add header
	table.insert(components, OplogUI.create_header())

	-- Add operation entries
	if oplog_state.raw_lines and #oplog_state.raw_lines > 0 then
		local op_components = OplogUI.create_oplog_components(oplog_state, oplog_buffer)
		for _, component in ipairs(op_components) do
			table.insert(components, component)
		end
	else
		table.insert(components, OplogUI.create_empty_state())
	end

	return components
end

---Create the header component
---@return table component Header component
function OplogUI.create_header()
	return Ui.col({
		Ui.text("JJ Operation Log", { highlight = "NeoJJTitle" }),
		Ui.text("Press ? for help, q to quit", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create oplog components from parsed op-log data
---@param oplog_state table Oplog state with raw lines and parsed data
---@param oplog_buffer? table Oplog buffer instance
---@return table[] components List of UI components
function OplogUI.create_oplog_components(oplog_state, oplog_buffer)
	local components = {}

	for i, line in ipairs(oplog_state.raw_lines) do
		if line == "" then
			table.insert(components, Ui.empty_line())
		else
			local graph_info = oplog_state.graph_data[i]
			local operation = graph_info and graph_info.operation

			if operation then
				-- This is an operation header line
				table.insert(components, OplogUI.create_operation_line(line, operation, oplog_buffer))
			else
				-- This is a description line or graph continuation
				local graph_prefix = graph_info and graph_info.graph
				table.insert(components, OplogUI.create_graph_line(line, graph_prefix))
			end
		end
	end

	return components
end

---Create an operation line component (interactive)
---@param line string The raw line content
---@param operation table Operation data
---@param _oplog_buffer? table Oplog buffer instance
---@return table component Operation line component
function OplogUI.create_operation_line(line, operation, _oplog_buffer)
	-- Separate the graph gutter from the operation info. The parser records the
	-- exact gutter on the operation, so split there deterministically rather
	-- than matching a fixed set of graph glyphs.
	local graph_part = operation.graph or ""
	local op_part = line:sub(#graph_part + 1)

	local row_children = { Ui.text(graph_part, { highlight = "NeoJJOplogGraph" }) }
	for _, comp in ipairs(OplogUI.create_operation_text_components(op_part, operation)) do
		table.insert(row_children, comp)
	end

	return Ui.row(row_children, {
		item = operation,
		interactive = true,
	})
end

---Create highlighted text components for the operation info, colouring each
---metadata field (operation id, user, timestamp) with its own highlight group so
---the columns read distinctly. Fields are located left-to-right by value, mirroring
---the log view's approach; the current operation (@) keeps its bold emphasis on
---the operation id.
---@param op_text string The operation info portion of the line
---@param operation table Operation data with operation_id/user/time_start fields
---@return table[] components List of text components
function OplogUI.create_operation_text_components(op_text, operation)
	local components = {}
	local pos = 1 -- 1-indexed cursor into op_text
	local separator_hl = "NeoJJOplogOperation"

	-- Emit the field `value` with `highlight`, preceded by any gap text (spaces
	-- between fields) rendered with the neutral separator highlight.
	local function emit_field(value, highlight)
		if not value or value == "" then
			return
		end
		local s, e = op_text:find(value, pos, true)
		if not s then
			return
		end
		if s > pos then
			table.insert(components, Ui.text(op_text:sub(pos, s - 1), { highlight = separator_hl }))
		end
		table.insert(components, Ui.text(op_text:sub(s, e), { highlight = highlight }))
		pos = e + 1
	end

	local id_hl = operation.is_current and "NeoJJOplogCurrent" or "NeoJJOplogId"
	emit_field(operation.operation_id, id_hl)
	emit_field(operation.user, "NeoJJOplogUser")
	emit_field(operation.time_start, "NeoJJOplogTime")

	-- Trailing text, if any.
	if pos <= #op_text then
		table.insert(components, Ui.text(op_text:sub(pos), { highlight = separator_hl }))
	end

	-- Fallback: if nothing matched (unexpected line shape), render as one span.
	if #components == 0 then
		table.insert(components, Ui.text(op_text, { highlight = separator_hl }))
	end

	return components
end

---Create a graph line component (non-interactive)
---@param line string The raw line content
---@param graph_prefix? string The graph gutter recorded by the parser
---@return table component Graph line component
function OplogUI.create_graph_line(line, graph_prefix)
	local graph_part, desc_part
	if graph_prefix ~= nil then
		graph_part = graph_prefix
		desc_part = line:sub(#graph_part + 1)
	else
		graph_part, desc_part = line:match("^([│%s]*)(.*)")
		if not graph_part then
			graph_part = ""
			desc_part = line
		end
	end

	return Ui.row({
		Ui.text(graph_part, { highlight = "NeoJJOplogGraph" }),
		Ui.text(desc_part, { highlight = "NeoJJOplogDescription" }),
	})
end

---Create the empty state component
---@return table component Empty state component
function OplogUI.create_empty_state()
	return Ui.col({
		Ui.text("No operations found", { highlight = "NeoJJEmptyState" }),
		Ui.empty_line(),
		Ui.text("The repository has no operation history.", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create help text component
---@return table component Help text component
function OplogUI.create_help()
	return Ui.col({
		Ui.text("NeoJJ Operation Log Help", { highlight = "NeoJJTitle" }),
		Ui.empty_line(),
		Ui.text("Navigation:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  j/k       - Move cursor up/down", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Actions:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  <C-r>     - Refresh operation log", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Enter>   - Show operation details (jj op show)", { highlight = "NeoJJHelpText" }),
		Ui.text("  l         - Open the log view", { highlight = "NeoJJHelpText" }),
		Ui.text("  r         - Restore repo to operation at cursor (jj op restore)", { highlight = "NeoJJHelpText" }),
		Ui.text("  u         - Undo the last operation (jj undo)", { highlight = "NeoJJHelpText" }),
		Ui.text("  y         - Yank operation ID", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Close:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  ?         - Show/hide this help", { highlight = "NeoJJHelpText" }),
		Ui.text("  <C-c>     - Back (pop view stack) / quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Esc>     - Back (pop view stack) / quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  q         - Back (pop view stack) / quit", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Graph symbols:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  @         - Current operation", { highlight = "NeoJJHelpText" }),
		Ui.text("  ○         - Past operation", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

return OplogUI
