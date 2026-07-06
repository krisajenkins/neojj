local Ui = require("neojj.lib.ui")

---@class DescribeUI
local DescribeUI = {}

---Create the describe buffer UI components
---@param description string The commit description text
---@return table[] components UI components
function DescribeUI.create(description)
	local components = {}

	-- Parse description content
	if description and description ~= "" then
		local description_lines = vim.split(description, "\n")
		for _, line in ipairs(description_lines) do
			table.insert(components, Ui.text(line))
		end
	end

	-- Add help section
	local help_components = DescribeUI.create_help_section()
	for _, component in ipairs(help_components) do
		table.insert(components, component)
	end

	return components
end

---Create the help section with syntax highlighting
---@return table[] components Help section components
function DescribeUI.create_help_section()
	return {
		Ui.empty_line(),
		DescribeUI.create_help_header(),
		DescribeUI.create_help_command(":w or :wq", "Submit description"),
		DescribeUI.create_help_keybinding("<C-c><C-c>", "Submit description"),
		DescribeUI.create_help_keybinding("<C-c><C-q>", "Abort"),
		DescribeUI.create_help_keybinding("ZZ", "Submit description"),
		DescribeUI.create_help_keybinding("ZQ", "Abort"),
		DescribeUI.create_help_command("q", "Close with confirmation"),
	}
end

---Create a section header with proper highlighting
---@return table component Section header component
function DescribeUI.create_help_header()
	return Ui.text("JJ: Commands:", { highlight = "NeoJJDescribeSection" })
end

---Create a help line for a command with proper highlighting
---@param command string The command text
---@param description string Description of what the command does
---@return table component Help command component
function DescribeUI.create_help_command(command, description)
	return Ui.row({
		Ui.text("JJ:   ", { highlight = "NeoJJDescribeComment" }),
		Ui.text(command, { highlight = "NeoJJDescribeCommand" }),
		Ui.text("    - " .. description, { highlight = "NeoJJDescribeComment" }),
	})
end

---Create a help line for a keybinding with proper highlighting
---@param keybinding string The keybinding text
---@param description string Description of what the keybinding does
---@return table component Help keybinding component
function DescribeUI.create_help_keybinding(keybinding, description)
	return Ui.row({
		Ui.text("JJ:   ", { highlight = "NeoJJDescribeComment" }),
		Ui.text(keybinding, { highlight = "NeoJJDescribeKeybinding" }),
		Ui.text("   - " .. description, { highlight = "NeoJJDescribeComment" }),
	})
end

return DescribeUI
