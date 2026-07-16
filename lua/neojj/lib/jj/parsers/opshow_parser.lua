-- Parser for `jj op show`, rendered with NeoJJ's explicit machine template (see
-- neojj.buffers.opshow.init for the template contract). Rather than parse jj's
-- colourful human output, we ask jj to key its output on two ASCII control
-- characters so every field is unambiguous — the same trick the log and oplog
-- parsers use:
--   "\x1e" (RECORD SEPARATOR) leads a machine record. jj never emits this byte
--          naturally, so a line starting with it is our operation-header record,
--          and a "+ "/"- " op-diff line whose payload begins with it is one of
--          our templated changed-commit records.
--   "\x1f" (UNIT SEPARATOR) separates the fields within a record.
--
-- `jj op show` output is a mix of records we template and chrome jj prints
-- itself (the "Changed commits:" / "Changed working copy …:" section headers and
-- the leading "+"/"-" diff signs). We classify each line into one of a handful
-- of element kinds that the UI knows how to colour.

local Separators = require("neojj.lib.jj.separators")
local Record = require("neojj.lib.jj.parsers.record")

local M = {}

---Parse the field body of a templated changed-commit record (everything after
---the leading "\x1e").
---@param body string
---@return table commit Structured commit-change fields
local function parse_commit_record(body)
	local f = vim.split(body, Separators.UNIT, { plain = true })
	local change_id = f[1] or ""
	local commit_id = f[4] or ""
	return {
		change_id = change_id,
		change_id_prefix = Record.valid_prefix(change_id, f[2]),
		-- "/N" suffix for hidden/divergent commits (jj's change offset), or "".
		change_offset = f[3] or "",
		commit_id = commit_id,
		commit_id_prefix = Record.valid_prefix(commit_id, f[5]),
		empty = (f[6] or "") == "empty",
		hidden = (f[7] or "") == "hidden",
		conflict = (f[8] or "") == "conflict",
		description = f[9] or "",
	}
end

---Parse templated `jj op show` output into an ordered list of elements.
---
---Each element is one of:
---  { kind = "operation",     operation_id, user, time }
---  { kind = "description",   text }   -- the operation's description / args prose
---  { kind = "section",       text }   -- a "Changed …:" header jj prints
---  { kind = "commit_change", sign = "+"|"-", change_id, change_id_prefix,
---                            change_offset, commit_id, commit_id_prefix,
---                            empty, hidden, conflict, description }
---  { kind = "blank" }
---@param output string Raw stdout from the templated `jj op show` call
---@return table[] elements
function M.parse(output)
	local elements = {}

	for _, line in ipairs(vim.split(output or "", "\n", { plain = true })) do
		if line == "" then
			table.insert(elements, { kind = "blank" })
		elseif line:sub(1, 1) == Separators.RECORD then
			-- Operation-header record.
			local f = vim.split(line:sub(2), Separators.UNIT, { plain = true })
			table.insert(elements, {
				kind = "operation",
				operation_id = f[1] or "",
				user = f[2] or "",
				time = f[3] or "",
			})
		elseif (line:sub(1, 2) == "+ " or line:sub(1, 2) == "- ") and line:sub(3, 3) == Separators.RECORD then
			-- Op-diff changed-commit record: a jj "+"/"- " sign, then our record.
			local commit = parse_commit_record(line:sub(4))
			commit.kind = "commit_change"
			commit.sign = line:sub(1, 1)
			table.insert(elements, commit)
		elseif line:match("^Changed ") then
			table.insert(elements, { kind = "section", text = line })
		else
			-- The operation's own description / `args:` metadata prose.
			table.insert(elements, { kind = "description", text = line })
		end
	end

	return elements
end

return M
