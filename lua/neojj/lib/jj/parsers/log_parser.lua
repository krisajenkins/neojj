---Parser for jj log command output produced by NeoJJ's explicit template.
---
---This module provides pure parsing functions for jj log graph output. It does
---NOT parse jj's human-facing default format; instead the log buffer requests a
---machine-oriented template (see `neojj.buffers.log.init`) built around two
---ASCII control characters:
---
---  * RECORD SEPARATOR  (0x1e, "\30") marks the boundary between the graph
---    gutter that `jj log` draws on the left and the templated payload. Because
---    jj never emits this byte as part of the graph, splitting on it is
---    unambiguous: any glyph can appear in the gutter (`@`, `○`, `◆`, `×`,
---    `├`, `─`, `╮`, `╯`, `╭`, `╰`, …) without confusing commit detection.
---  * UNIT SEPARATOR    (0x1f, "\31") separates the fields inside a commit
---    header payload.
---
---Each commit occupies two templated lines:
---
---  <gutter>\30<change_id>\31<author>\31<timestamp>\31<bookmarks>\31<commit_id>\31<conflict>\31<change_id_prefix>\31<commit_id_prefix>
---  <gutter>\30<description first line>
---
---The two trailing `*_prefix` fields carry jj's unique disambiguating prefix for
---the change and commit ids (from `id.shortest(8).prefix()`), so the UI can
---brighten the prefix and dim the rest without recomputing it. They are optional:
---older fixtures captured before this template lack them, and the parser then
---leaves the prefixes empty (the UI falls back to highlighting the whole id).
---
---A line is recognised as a commit header purely by the presence of a payload
---containing unit separators, never by matching a fixed set of graph glyphs.
---Graph-only connector lines (e.g. `├─╮`) carry no record separator and are
---preserved as gutter for rendering.

local M = {}

local RECORD_SEP = "\30" -- 0x1e, separates graph gutter from templated payload
local UNIT_SEP = "\31" -- 0x1f, separates fields within a header payload

---Split a raw log line into its graph gutter and templated payload.
---@param line string A single line of jj log output
---@return string gutter The graph characters drawn to the left of the payload
---@return string|nil payload The templated payload, or nil if the line is graph-only
local function split_gutter(line)
	local gutter, payload = line:match("^(.-)" .. RECORD_SEP .. "(.*)$")
	if gutter == nil then
		-- No record separator: this is a pure graph/connector line.
		return line, nil
	end
	return gutter, payload
end

---Parse jj log output produced by the NeoJJ log template.
---@param output string Raw output from jj log command
---@return ParsedLog parsed Parsed log with revisions, graph data, and raw lines
function M.parse_log_output(output)
	---@type LogRevision[]
	local revisions = {}
	---@type table<integer, GraphData>
	local graph_data = {}
	---@type string[]
	local raw_lines = {}

	---@type LogRevision|nil
	local current_revision = nil

	local lines = vim.split(output, "\n")

	for i, line in ipairs(lines) do
		if line == "" then
			-- Preserve blank lines positionally so the UI can render them.
			raw_lines[i] = ""
			goto continue
		end

		local gutter, payload = split_gutter(line)

		if payload == nil then
			-- Graph-only connector line (e.g. "├─╮"): no payload to parse.
			raw_lines[i] = gutter
			graph_data[i] = { graph = gutter, revision = nil }
			goto continue
		end

		if payload:find(UNIT_SEP, 1, true) then
			-- Commit header line: fields are unit-separated.
			local fields = vim.split(payload, UNIT_SEP, { plain = true })
			local change_id = fields[1] or ""
			local author = fields[2] or ""
			local timestamp = fields[3] or ""
			local bookmarks_field = fields[4] or ""
			local commit_id = fields[5] or ""
			local conflict = (fields[6] or "") == "conflict"
			-- Optional trailing fields: jj's unique disambiguating prefixes. Only
			-- keep a prefix when it is a genuine leading substring of the id (and
			-- shorter than it), so the UI can safely split the id into
			-- bright-prefix + dim-rest; otherwise leave it nil for whole-id
			-- highlighting.
			local change_id_prefix = fields[7]
			if
				not (
					change_id_prefix
					and change_id_prefix ~= ""
					and change_id:sub(1, #change_id_prefix) == change_id_prefix
				)
			then
				change_id_prefix = nil
			end
			local commit_id_prefix = fields[8]
			if
				not (
					commit_id_prefix
					and commit_id_prefix ~= ""
					and commit_id:sub(1, #commit_id_prefix) == commit_id_prefix
				)
			then
				commit_id_prefix = nil
			end

			local bookmarks = vim.split(bookmarks_field, "%s+", { trimempty = true })

			---@type LogRevision
			current_revision = {
				change_id = change_id,
				author = author,
				timestamp = timestamp,
				commit_id = commit_id,
				change_id_prefix = change_id_prefix,
				commit_id_prefix = commit_id_prefix,
				bookmarks = bookmarks,
				conflict = conflict,
				description = "",
				graph = gutter,
				line_number = i,
			}
			table.insert(revisions, current_revision)

			-- Rebuild a clean, control-character-free line for display. The
			-- order (change_id author timestamp [bookmarks] commit_id) keeps
			-- the bookmark-highlighting logic in log/ui.lua working, which
			-- locates bookmarks between the timestamp and commit_id substrings.
			local display = gutter .. change_id .. " " .. author .. " " .. timestamp
			if bookmarks_field ~= "" then
				display = display .. " " .. bookmarks_field
			end
			display = display .. " " .. commit_id
			if conflict then
				display = display .. " (conflict)"
			end
			raw_lines[i] = display

			graph_data[i] = { graph = gutter, revision = current_revision }
		else
			-- Description continuation line: payload is the description text.
			if current_revision and current_revision.description == "" then
				current_revision.description = payload
			end
			raw_lines[i] = gutter .. payload
			graph_data[i] = { graph = gutter, revision = nil }
		end

		::continue::
	end

	---@type ParsedLog
	return {
		revisions = revisions,
		graph_data = graph_data,
		raw_lines = raw_lines,
	}
end

return M
