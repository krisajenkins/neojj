local Ui = require("neojj.lib.ui")

---@class AnnotateUI
local AnnotateUI = {}

---Strip ANSI color codes from a string
---@param str string String with ANSI codes
---@return string clean String without ANSI codes
local function strip_ansi(str)
	-- Pattern matches ANSI escape sequences
	return str:gsub("\27%[[%d;]*m", "")
end

---Parse a single line from jj file annotate output
---@param line string Raw annotate line with ANSI codes
---@return table|nil parsed Parsed annotation data or nil if invalid
function AnnotateUI.parse_annotate_line(line)
	local clean_line = strip_ansi(line)

	-- Format: <change_id> <author> <timestamp> <line_num>: <content>
	-- Example: kznzoynu krisajen 2025-07-11 09:21:52    1: {
	local pattern = "^(%S+)%s+(%S+)%s+(%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d)%s+%d+:"

	local change_id, author, timestamp = clean_line:match(pattern)

	if change_id and author and timestamp then
		-- Extract just the date part (YYYY-MM-DD) for display
		local date = timestamp:match("^(%d%d%d%d%-%d%d%-%d%d)")

		return {
			change_id = change_id,
			author = author,
			date = date,
			full_timestamp = timestamp,
		}
	end

	return nil
end

---Collapse consecutive identical change IDs with ASCII art
---@param annotations table[] Array of parsed annotation data
---@return table[] collapsed Collapsed annotations with continuation markers
function AnnotateUI.collapse_annotations(annotations)
	if not annotations or #annotations == 0 then
		return {}
	end

	local collapsed = {}
	local i = 1

	while i <= #annotations do
		local current = annotations[i]
		local change_id = current.change_id

		-- Find the range of consecutive identical change IDs
		local start_idx = i
		local end_idx = i

		while end_idx < #annotations and annotations[end_idx + 1].change_id == change_id do
			end_idx = end_idx + 1
		end

		-- If this is a single line (no repetition), just add it
		if start_idx == end_idx then
			table.insert(collapsed, {
				type = "full",
				change_id = current.change_id,
				author = current.author,
				date = current.date,
			})
		else
			-- This is a run of identical change IDs
			-- First line: show full info
			table.insert(collapsed, {
				type = "full",
				change_id = current.change_id,
				author = current.author,
				date = current.date,
			})

			-- Middle lines: show continuation character
			for j = start_idx + 1, end_idx - 1 do
				table.insert(collapsed, {
					type = "continuation",
				})
			end

			-- Last line: show end marker
			table.insert(collapsed, {
				type = "end_marker",
			})
		end

		i = end_idx + 1
	end

	return collapsed
end

---Format an annotation line for display (30 columns)
---@param annotation table Collapsed annotation data
---@return string formatted Formatted line for display
function AnnotateUI.format_annotation(annotation)
	if annotation.type == "full" then
		-- Format: "change_id author date"
		-- Example: "kznzoynu krisaje 2025-07-11"
		-- Target width: 30 characters
		local change_id = annotation.change_id:sub(1, 8) -- Take first 8 chars
		local author = annotation.author:sub(1, 7) -- Max 7 chars (shortened for 30 col width)
		local date = annotation.date

		-- Fixed format: 8 + 1 + 7 + 1 + 10 = 27 chars
		return string.format("%-8s %-7s %s", change_id, author, date)
	elseif annotation.type == "continuation" then
		return "│"
	elseif annotation.type == "end_marker" then
		return "o"
	end

	return ""
end

---Create UI components from jj file annotate output
---@param annotate_output string Raw output from jj file annotate
---@return table[] components UI components for display
function AnnotateUI.create(annotate_output)
	local components = {}

	if not annotate_output or annotate_output == "" then
		table.insert(components, Ui.text("No annotations available", { highlight = "Comment" }))
		return components
	end

	-- Parse all lines
	local annotations = {}
	for line in annotate_output:gmatch("[^\r\n]+") do
		local parsed = AnnotateUI.parse_annotate_line(line)
		if parsed then
			table.insert(annotations, parsed)
		end
	end

	-- Collapse consecutive identical change IDs
	local collapsed = AnnotateUI.collapse_annotations(annotations)

	-- Create UI components
	for _, annotation in ipairs(collapsed) do
		local formatted = AnnotateUI.format_annotation(annotation)
		local highlight = "Comment"

		if annotation.type == "full" then
			highlight = "Normal"
		elseif annotation.type == "continuation" or annotation.type == "end_marker" then
			highlight = "Comment"
		end

		table.insert(components, Ui.text(formatted, { highlight = highlight }))
	end

	return components
end

return AnnotateUI
