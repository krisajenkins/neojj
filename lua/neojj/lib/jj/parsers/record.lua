-- Leaf helpers shared by NeoJJ's jj-output parsers (log / oplog / opshow). Each
-- parser drives jj's machine-oriented `--template` output, keyed on the ASCII
-- control bytes in `neojj.lib.jj.separators`; these two helpers are the small
-- pieces of record-decoding logic that every parser needs, hoisted here so they
-- live in one place instead of being copied per parser.

local Separators = require("neojj.lib.jj.separators")

local M = {}

---Split a raw jj-log/oplog line into its graph gutter and templated payload.
---The RECORD separator marks the boundary between the graph gutter jj draws on
---the left and our templated payload; jj never emits that byte in the graph, so
---splitting on it is unambiguous for any node glyph.
---@param line string A single line of jj log / op log output
---@return string gutter The graph characters drawn to the left of the payload
---@return string|nil payload The templated payload, or nil if the line is graph-only
function M.split_gutter(line)
	local gutter, payload = line:match("^(.-)" .. Separators.RECORD .. "(.*)$")
	if gutter == nil then
		-- No record separator: this is a pure graph/connector line.
		return line, nil
	end
	return gutter, payload
end

---Return `prefix` when it is a genuine leading substring of `id` (jj's unique
---disambiguating prefix, and strictly shorter than the id), else nil so the UI
---highlights the whole id.
---@param id string
---@param prefix string?
---@return string?
function M.valid_prefix(id, prefix)
	if prefix and prefix ~= "" and #prefix < #id and id:sub(1, #prefix) == prefix then
		return prefix
	end
	return nil
end

return M
