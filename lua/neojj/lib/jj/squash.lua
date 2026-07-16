local Ui = require("neojj.lib.ui")

--- Helpers for the squash combine-descriptions flow. When `jj squash` folds a
--- source revision into a destination and BOTH carry a description, jj opens an
--- editor pre-filled with both messages so you can combine them. jj's editor is
--- a blocking subprocess we cannot drive, so NeoJJ reproduces that buffer
--- natively (see ViewBuffer:squash) and passes the edited result back with
--- `jj squash --message`.
local M = {}

--- Build the combine-descriptions editor content, mirroring jj's own squash
--- editor. `JJ:`-prefixed lines are guidance and are stripped on submit (by
--- DescribeBuffer:get_description_from_buffer); the two descriptions —
--- destination first, then source, separated by a blank line — are the editable
--- payload that becomes the combined commit message.
---@param opts { dest_description: string, source_description: string, dest_change_id: string, files: string[] }
---@return table[] components UI components for the editor buffer
function M.build_combine_components(opts)
	local components = {}

	local function jj_line(text)
		table.insert(components, Ui.text(text, { highlight = "NeoJJDescribeComment" }))
	end
	local function payload(text)
		for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
			table.insert(components, Ui.text(line))
		end
	end

	jj_line("JJ: Enter a description for the combined commit.")
	jj_line("JJ: Description from the destination commit:")
	payload(opts.dest_description)
	table.insert(components, Ui.empty_line())
	jj_line("JJ: Description from source commit:")
	payload(opts.source_description)
	-- Trailing blank: separates the payload from the JJ: comment block below and
	-- is trimmed off on submit, so the combined message ends at the source text.
	table.insert(components, Ui.empty_line())
	jj_line("JJ: Change ID: " .. (opts.dest_change_id or ""))
	jj_line("JJ: This commit contains the following changes:")
	for _, summary in ipairs(opts.files or {}) do
		jj_line("JJ:     " .. summary)
	end
	jj_line("JJ:")
	jj_line('JJ: Lines starting with "JJ:" (like this one) will be removed.')

	return components
end

return M
