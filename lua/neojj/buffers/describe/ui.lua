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
---@param text string Header text
---@return table component Section header component
function DescribeUI.create_help_header()
	return Ui.text("# Commands:", { highlight = "NeoJJDescribeSection" })
end

---Create a help line for a command with proper highlighting
---@param command string The command text
---@param description string Description of what the command does
---@return table component Help command component
function DescribeUI.create_help_command(command, description)
	return Ui.row({
		Ui.text("#   ", { highlight = "NeoJJDescribeComment" }),
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
		Ui.text("#   ", { highlight = "NeoJJDescribeComment" }),
		Ui.text(keybinding, { highlight = "NeoJJDescribeKeybinding" }),
		Ui.text("   - " .. description, { highlight = "NeoJJDescribeComment" }),
	})
end

---Parse a line of text and apply appropriate highlighting
---@param line string Line of text to parse
---@return table component Parsed component with highlighting
function DescribeUI.parse_line(line)
	-- Check if it's a comment line
	if line:match("^#") then
		-- Check for different comment types
		if line:match("^# [A-Z][a-z]*:$") then
			-- Section header
			return Ui.text(line, { highlight = "NeoJJDescribeSection" })
		elseif line:match("<[^>]+>") then
			-- Contains keybindings
			return DescribeUI.parse_keybinding_line(line)
		elseif line:match(":[a-zA-Z!]+") then
			-- Contains commands
			return DescribeUI.parse_command_line(line)
		else
			-- Regular comment
			return Ui.text(line, { highlight = "NeoJJDescribeComment" })
		end
	else
		-- Regular description text
		return Ui.text(line)
	end
end

---Parse a line containing keybindings
---@param line string Line containing keybindings
---@return table component Parsed keybinding line
function DescribeUI.parse_keybinding_line(line)
	local parts = {}
	local pos = 1

	while pos <= #line do
		-- Find next keybinding
		local kb_start, kb_end = line:find("<[^>]+>", pos)

		if kb_start then
			-- Add text before keybinding
			if kb_start > pos then
				local before_text = line:sub(pos, kb_start - 1)
				table.insert(parts, Ui.text(before_text, { highlight = "NeoJJDescribeComment" }))
			end

			-- Add keybinding
			local keybinding = line:sub(kb_start, kb_end)
			table.insert(parts, Ui.text(keybinding, { highlight = "NeoJJDescribeKeybinding" }))

			pos = kb_end + 1
		else
			-- Add remaining text
			local remaining = line:sub(pos)
			if remaining ~= "" then
				table.insert(parts, Ui.text(remaining, { highlight = "NeoJJDescribeComment" }))
			end
			break
		end
	end

	return Ui.row(parts)
end

---Parse a line containing commands
---@param line string Line containing commands
---@return table component Parsed command line
function DescribeUI.parse_command_line(line)
	local parts = {}
	local pos = 1

	while pos <= #line do
		-- Find next command
		local cmd_start, cmd_end = line:find(":[a-zA-Z!]+", pos)

		if cmd_start then
			-- Add text before command
			if cmd_start > pos then
				local before_text = line:sub(pos, cmd_start - 1)
				table.insert(parts, Ui.text(before_text, { highlight = "NeoJJDescribeComment" }))
			end

			-- Add command
			local command = line:sub(cmd_start, cmd_end)
			table.insert(parts, Ui.text(command, { highlight = "NeoJJDescribeCommand" }))

			pos = cmd_end + 1
		else
			-- Add remaining text
			local remaining = line:sub(pos)
			if remaining ~= "" then
				table.insert(parts, Ui.text(remaining, { highlight = "NeoJJDescribeComment" }))
			end
			break
		end
	end

	return Ui.row(parts)
end

---Create a test UI for describe buffer (used in tests)
---@return table[] components Test describe UI components
function DescribeUI.create_test_ui()
	local test_description = "Update component system\n\nAdd support for nested components and improve rendering."
	return DescribeUI.create(test_description)
end

return DescribeUI
