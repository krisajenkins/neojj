local Ui = require("neojj.lib.ui")

---@class OpShowUI
local OpShowUI = {}

-- Neutral separator highlight for the spaces between fields on a commit row.
local SEP_HL = "NeoJJLogCommit"

---Append an id field split into its unique disambiguating prefix (bright) and
---the remaining, non-unique characters (dimmed) — the same treatment `jj log`
---and the log view give change/commit ids. When jj hands us no usable prefix
---the whole id is highlighted with `prefix_hl`.
---@param children table[] Row children to append to
---@param value string The id text
---@param prefix string? jj's unique disambiguating prefix, if any
---@param prefix_hl string Highlight for the unique prefix (or whole id)
---@param rest_hl string Highlight for the dimmed remainder
local function append_id(children, value, prefix, prefix_hl, rest_hl)
	if value == "" then
		return
	end
	if prefix and prefix ~= "" then
		table.insert(children, Ui.text(value:sub(1, #prefix), { highlight = prefix_hl }))
		table.insert(children, Ui.text(value:sub(#prefix + 1), { highlight = rest_hl }))
	else
		table.insert(children, Ui.text(value, { highlight = prefix_hl }))
	end
end

---Build the operation-header row (id / user / time), reusing the oplog view's
---highlight groups so an op-show header reads like the oplog row it opened from.
---@param el table An "operation" element
---@return table component Row component
function OpShowUI.operation_row(el)
	return Ui.row({
		Ui.text(el.operation_id, { highlight = "NeoJJOplogId" }),
		Ui.text(" ", { highlight = "NeoJJOplogOperation" }),
		Ui.text(el.user, { highlight = "NeoJJOplogUser" }),
		Ui.text(" ", { highlight = "NeoJJOplogOperation" }),
		Ui.text(el.time, { highlight = "NeoJJOplogTime" }),
	})
end

---Build a changed-commit row: the "+"/"-" sign, the change id, the commit id,
---jj's status markers ((conflict)/(empty)/(hidden)) and the description — each
---field with its own highlight, matching the log view.
---@param el table A "commit_change" element
---@return table component Row component
function OpShowUI.commit_row(el)
	local children = {}

	local sign_hl = el.sign == "+" and "NeoJJDiffAdd" or "NeoJJDiffDelete"
	table.insert(children, Ui.text(el.sign, { highlight = sign_hl }))
	table.insert(children, Ui.text(" ", { highlight = SEP_HL }))

	append_id(children, el.change_id, el.change_id_prefix, "NeoJJLogChangeId", "NeoJJLogChangeIdRest")
	-- jj's "/N" change offset disambiguates hidden/divergent commits; render it
	-- attached to the change id (no gap), dimmed like the id's non-unique tail.
	if el.change_offset and el.change_offset ~= "" then
		table.insert(children, Ui.text(el.change_offset, { highlight = "NeoJJLogChangeIdRest" }))
	end
	table.insert(children, Ui.text(" ", { highlight = SEP_HL }))
	append_id(children, el.commit_id, el.commit_id_prefix, "NeoJJLogCommitId", "NeoJJLogCommitIdRest")

	-- Status markers, in jj's order: conflict, then empty, then hidden.
	if el.conflict then
		table.insert(children, Ui.text(" ", { highlight = SEP_HL }))
		table.insert(children, Ui.text("(conflict)", { highlight = "NeoJJConflict" }))
	end
	if el.empty then
		table.insert(children, Ui.text(" ", { highlight = SEP_HL }))
		table.insert(children, Ui.text("(empty)", { highlight = "NeoJJEmpty" }))
	end
	if el.hidden then
		table.insert(children, Ui.text(" ", { highlight = SEP_HL }))
		table.insert(children, Ui.text("(hidden)", { highlight = "NeoJJLogChangeIdRest" }))
	end

	table.insert(children, Ui.text(" ", { highlight = SEP_HL }))
	table.insert(children, Ui.text(el.description, { highlight = "NeoJJLogDescription" }))

	return Ui.row(children)
end

---Build the component tree for parsed `jj op show` output.
---@param elements table[] Elements from opshow_parser.parse
---@return table[] components UI components, one per element
function OpShowUI.create(elements)
	local components = {}

	for _, el in ipairs(elements) do
		if el.kind == "blank" then
			table.insert(components, Ui.empty_line())
		elseif el.kind == "operation" then
			table.insert(components, OpShowUI.operation_row(el))
		elseif el.kind == "commit_change" then
			table.insert(components, OpShowUI.commit_row(el))
		elseif el.kind == "section" then
			table.insert(components, Ui.text(el.text, { highlight = "NeoJJSectionHeader" }))
		else
			-- Operation description / `args:` prose.
			table.insert(components, Ui.text(el.text, { highlight = "NeoJJOplogDescription" }))
		end
	end

	return components
end

return OpShowUI
