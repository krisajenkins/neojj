local Component = require("neojj.lib.ui.component")

---@class Ui
local Ui = {}

---Create a column (vertical container)
---@param children table[] List of child components
---@param options? table Component options
---@return table component Column component
function Ui.col(children, options)
	return Component.new(function(props)
		return {
			tag = "Col",
			children = children or {},
			options = options or {},
			value = props.value,
		}
	end)()
end

---Create a row (horizontal container)
---@param children table[] List of child components
---@param options? table Component options
---@return table component Row component
function Ui.row(children, options)
	return Component.new(function(props)
		return {
			tag = "Row",
			children = children or {},
			options = options or {},
			value = props.value,
		}
	end)()
end

---Create a text component
---@param value string Text content
---@param options? table Component options
---@return table component Text component
function Ui.text(value, options)
	return Component.new(function(props)
		return {
			tag = "Text",
			children = {},
			options = options or {},
			value = value or "",
		}
	end)()
end

---Create an empty line component
---@return table component Empty line component
function Ui.empty_line()
	return Ui.text("", {})
end

---Create a section header component
---@param title string Section title
---@param count? number Optional item count
---@param options? table Component options
---@return table component Section header component
function Ui.section_header(title, count, options)
	local display_title = title
	if count and count > 0 then
		display_title = title .. " (" .. count .. ")"
	end

	return Ui.text(
		display_title,
		vim.tbl_extend("force", options or {}, {
			highlight = "NeoJJSectionHeader",
		})
	)
end

---Create a file item component
---@param status string File status (A, M, D, etc.)
---@param path string File path
---@param options? table Component options
---@return table component File item component
function Ui.file_item(status, path, options)
	return Ui.row({
		Ui.text(status, { highlight = "NeoJJFileStatus" }),
		Ui.text(" "),
		Ui.text(path, { highlight = "NeoJJFilePath" }),
	}, options)
end

---Create a commit info component
---@param change_id string Change ID
---@param commit_id string Commit ID
---@param description string Commit description
---@param author table Author information
---@param options? table Component options
---@return table component Commit info component
function Ui.commit_info(change_id, commit_id, description, author, options)
	return Ui.col({
		Ui.row({
			Ui.text("Change ID: ", { highlight = "NeoJJLabel" }),
			Ui.text(change_id, { highlight = "NeoJJChangeId" }),
		}),
		Ui.row({
			Ui.text("Commit ID: ", { highlight = "NeoJJLabel" }),
			Ui.text(commit_id, { highlight = "NeoJJCommitId" }),
		}),
		Ui.row({
			Ui.text("Description: ", { highlight = "NeoJJLabel" }),
			Ui.text(description, { highlight = "NeoJJDescription" }),
		}),
		Ui.row({
			Ui.text("Author: ", { highlight = "NeoJJLabel" }),
			Ui.text(author.name .. " <" .. author.email .. ">", { highlight = "NeoJJAuthor" }),
		}),
	}, options)
end

---Create a section component
---@param title string Section title
---@param items table[] Section items
---@param options? table Component options
---@return table component Section component
function Ui.section(title, items, options)
	local section_options = vim.tbl_extend("force", options or {}, {
		foldable = true,
		section = title:lower():gsub("%s+", "_"),
	})

	local children = {
		Ui.section_header(title, #items),
	}

	if not section_options.folded then
		for _, item in ipairs(items) do
			table.insert(children, item)
		end
	end

	table.insert(children, Ui.empty_line())

	return Ui.col(children, section_options)
end

-- Tagged component constructors for convenience
---Create a tagged col constructor
---@param tag string Component tag
---@return function constructor Tagged col constructor
function Ui.tagged_col(tag)
	return function(children, options)
		local opts = vim.tbl_extend("force", options or {}, { tag = tag })
		return Ui.col(children, opts)
	end
end

---Create a tagged row constructor
---@param tag string Component tag
---@return function constructor Tagged row constructor
function Ui.tagged_row(tag)
	return function(children, options)
		local opts = vim.tbl_extend("force", options or {}, { tag = tag })
		return Ui.row(children, opts)
	end
end

---Create a tagged text constructor
---@param tag string Component tag
---@return function constructor Tagged text constructor
function Ui.tagged_text(tag)
	return function(value, options)
		local opts = vim.tbl_extend("force", options or {}, { tag = tag })
		return Ui.text(value, opts)
	end
end

return Ui
