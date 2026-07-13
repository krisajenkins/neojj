local Ui = require("neojj.lib.ui")

---A positional span emitter for splitting a single line of jj output into
---highlighted text components. Fields are located left-to-right by their
---verbatim value (starting from the previous field's end, so ordering is
---respected), and the whitespace gaps between fields keep a neutral separator
---highlight. Shared by the log and oplog views, whose commit/operation rows are
---built the same way.
---@class SpanEmitter
---@field text string The line text being split into spans
---@field separator_hl string Highlight for gap / trailing / fallback spans
---@field components table[] Accumulated text components
---@field pos integer 1-indexed cursor into `text`
local SpanEmitter = {}
SpanEmitter.__index = SpanEmitter

---Create a positional span emitter over `text`.
---@param text string The line text to split into highlighted spans
---@param separator_hl string Highlight for gap / trailing / fallback spans
---@return SpanEmitter emitter
function SpanEmitter.new(text, separator_hl)
	return setmetatable({
		text = text,
		separator_hl = separator_hl,
		components = {},
		pos = 1,
	}, SpanEmitter)
end

---Emit any gap text (spaces between fields) preceding position `s`, rendered
---with the neutral separator highlight.
---@param s integer 1-indexed position where the next field begins
---@return nil
function SpanEmitter:_emit_gap(s)
	if s > self.pos then
		table.insert(self.components, Ui.text(self.text:sub(self.pos, s - 1), { highlight = self.separator_hl }))
	end
end

---Emit the field `value` with `highlight`, preceded by any gap text. A no-op
---when `value` is empty or cannot be found from the current position.
---@param value string? Field value to locate verbatim
---@param highlight string Highlight group for the field
---@return nil
function SpanEmitter:emit_field(value, highlight)
	if not value or value == "" then
		return
	end
	local s, e = self.text:find(value, self.pos, true)
	if not s then
		return
	end
	self:_emit_gap(s)
	table.insert(self.components, Ui.text(self.text:sub(s, e), { highlight = highlight }))
	self.pos = e + 1
end

---Emit an id field split into its unique disambiguating prefix (bright) and the
---remaining, non-unique characters (dimmed) — the way jj's own log does it.
---`prefix` comes from jj (`id.shortest().prefix()`); when it's absent or not a
---proper leading substring, fall back to highlighting the whole id.
---@param value string? Id value to locate verbatim
---@param prefix string? jj's unique disambiguating prefix, if any
---@param prefix_hl string Highlight for the unique prefix (or whole id)
---@param rest_hl string Highlight for the dimmed remainder
---@return nil
function SpanEmitter:id_field(value, prefix, prefix_hl, rest_hl)
	if not value or value == "" then
		return
	end
	local s, e = self.text:find(value, self.pos, true)
	if not s then
		return
	end
	self:_emit_gap(s)
	if prefix and prefix ~= "" and #prefix < #value and value:sub(1, #prefix) == prefix then
		table.insert(self.components, Ui.text(self.text:sub(s, s + #prefix - 1), { highlight = prefix_hl }))
		table.insert(self.components, Ui.text(self.text:sub(s + #prefix, e), { highlight = rest_hl }))
	else
		table.insert(self.components, Ui.text(self.text:sub(s, e), { highlight = prefix_hl }))
	end
	self.pos = e + 1
end

---Finalize: append any residual trailing text (unexpected line shape) with the
---separator highlight, fall back to a single span when nothing matched, and
---return the accumulated components.
---@return table[] components The emitted text components
function SpanEmitter:finish()
	-- Any residual trailing text (unexpected shape) rendered neutrally.
	if self.pos <= #self.text then
		table.insert(self.components, Ui.text(self.text:sub(self.pos), { highlight = self.separator_hl }))
	end

	-- Fallback: if nothing matched (unexpected line shape), render as one span.
	if #self.components == 0 then
		table.insert(self.components, Ui.text(self.text, { highlight = self.separator_hl }))
	end

	return self.components
end

return SpanEmitter
