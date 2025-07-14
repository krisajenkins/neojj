local Ui = require("neojj.lib.ui")

---@class CommitUI
local CommitUI = {}

---Create the main commit UI components
---@param commit_state table Commit state with commit data, files, and diff
---@param expanded_files table Table of expanded file paths
---@param commit_buffer? table Commit buffer instance for interactions
---@return table[] components UI components
function CommitUI.create(commit_state, expanded_files, commit_buffer)
	local components = {}

	-- Add header
	table.insert(components, CommitUI.create_header(commit_state.commit_data))

	-- Add metadata section
	table.insert(components, CommitUI.create_metadata_section(commit_state.commit_data))

	-- Add files section with individual file diffs
	if commit_state.files and #commit_state.files > 0 then
		table.insert(components, CommitUI.create_files_section(commit_state.files, expanded_files, commit_buffer))
	end

	-- Add empty state if no data
	if (not commit_state.files or #commit_state.files == 0) and
	   (not commit_state.diff_data or #commit_state.diff_data == 0) then
		table.insert(components, CommitUI.create_empty_state())
	end

	return components
end

---Create the header component
---@param commit_data table Commit metadata
---@return table component Header component
function CommitUI.create_header(commit_data)
	local commit_id = commit_data.change_id or commit_data.commit_id or "unknown"
	local short_id = commit_id:sub(1, 8)

	return Ui.col({
		Ui.text("JJ Commit: " .. short_id, { highlight = "NeoJJTitle" }),
		Ui.text("Press ? for help, q to quit", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create metadata section
---@param commit_data table Commit metadata
---@return table component Metadata section component
function CommitUI.create_metadata_section(commit_data)
	local metadata_items = {}

	-- Change ID
	if commit_data.change_id then
		table.insert(metadata_items, Ui.text("Change ID: " .. commit_data.change_id, { highlight = "NeoJJChangeId" }))
	end

	-- Commit ID
	if commit_data.commit_id then
		table.insert(metadata_items, Ui.text("Commit ID: " .. commit_data.commit_id, { highlight = "NeoJJCommitId" }))
	end

	-- Author
	if commit_data.author then
		table.insert(metadata_items, Ui.text("Author: " .. commit_data.author, { highlight = "NeoJJAuthor" }))
	end

	-- Committer (if different from author)
	if commit_data.committer and commit_data.committer ~= commit_data.author then
		table.insert(metadata_items, Ui.text("Committer: " .. commit_data.committer, { highlight = "NeoJJCommitter" }))
	end

	-- Date
	if commit_data.date then
		table.insert(metadata_items, Ui.text("Date: " .. commit_data.date, { highlight = "NeoJJTimestamp" }))
	end

	-- Description
	if commit_data.description then
		table.insert(metadata_items, Ui.empty_line())
		table.insert(metadata_items, Ui.text("Description:", { highlight = "NeoJJSectionHeader" }))

		-- Split description into lines and indent
		local desc_lines = vim.split(commit_data.description, "\n")
		for _, line in ipairs(desc_lines) do
			table.insert(metadata_items, Ui.text("  " .. line, { highlight = "NeoJJDescription" }))
		end
	end

	table.insert(metadata_items, Ui.empty_line())

	return Ui.col(metadata_items)
end

---Create files section
---@param files table List of files with their changes
---@param expanded_files table Table of expanded file paths
---@param commit_buffer? table Commit buffer instance
---@return table component Files section component
function CommitUI.create_files_section(files, expanded_files, commit_buffer)
	local files_items = {}

	-- Section header
	local file_count = #files
	local header_text = "Files changed (" .. file_count .. "):"
	table.insert(files_items, Ui.text(header_text, { highlight = "NeoJJSectionHeader" }))

	-- File list with individual diffs
	for _, file in ipairs(files) do
		-- Add file item
		table.insert(files_items, CommitUI.create_file_item(file, commit_buffer))

		-- Add file diff if expanded
		if expanded_files and expanded_files[file.path] and file.diff then
			table.insert(files_items, CommitUI.create_file_diff_section(file.diff))
		end
	end

	table.insert(files_items, Ui.empty_line())

	return Ui.col(files_items)
end

---Create a file item component (interactive)
---@param file table File data with path and status
---@param commit_buffer? table Commit buffer instance
---@return table component File item component
function CommitUI.create_file_item(file, commit_buffer)
	local status_char = CommitUI.get_file_status_char(file.status)
	local status_highlight = CommitUI.get_file_status_highlight(file.status)

	return Ui.row({
		Ui.text("  " .. status_char .. "  ", { highlight = status_highlight }),
		Ui.text(file.path, { highlight = "NeoJJFilePath" }),
	}, {
		item = file,
		interactive = true,
	})
end

---Create a file-specific diff section
---@param diff_lines table List of diff lines for a single file
---@return table component File diff section component
function CommitUI.create_file_diff_section(diff_lines)
	local diff_items = {}

	-- Add each diff line with proper indentation
	for _, line in ipairs(diff_lines) do
		table.insert(diff_items, Ui.text("    " .. line, { highlight = CommitUI.get_diff_line_highlight(line) }))
	end

	return Ui.col(diff_items)
end

---Create diff section (for full diff display)
---@param diff_data table Raw diff lines
---@param commit_buffer? table Commit buffer instance
---@return table component Diff section component
function CommitUI.create_diff_section(diff_data, commit_buffer)
	local diff_items = {}

	-- Section header
	table.insert(diff_items, Ui.text("Diff:", { highlight = "NeoJJSectionHeader" }))

	-- Diff content
	for _, line in ipairs(diff_data) do
		table.insert(diff_items, CommitUI.create_diff_line(line))
	end

	return Ui.col(diff_items)
end

---Create a diff line component with appropriate highlighting
---@param line string Single diff line
---@return table component Diff line component
function CommitUI.create_diff_line(line)
	local highlight = CommitUI.get_diff_line_highlight(line)
	return Ui.text(line, { highlight = highlight })
end

---Get file status character
---@param status string File status (A, M, D, R, etc.)
---@return string char Status character
function CommitUI.get_file_status_char(status)
	local status_chars = {
		["A"] = "A", -- Added
		["M"] = "M", -- Modified
		["D"] = "D", -- Deleted
		["R"] = "R", -- Renamed
		["C"] = "C", -- Copied
		["U"] = "U", -- Unmerged
		["T"] = "T", -- Type changed
	}
	return status_chars[status] or "?"
end

---Get file status highlight group
---@param status string File status
---@return string highlight_group Highlight group name
function CommitUI.get_file_status_highlight(status)
	local status_highlights = {
		["A"] = "NeoJJFileStatusAdded",
		["M"] = "NeoJJFileStatusModified",
		["D"] = "NeoJJFileStatusDeleted",
		["R"] = "NeoJJFileStatusRenamed",
		["C"] = "NeoJJFileStatusCopied",
		["U"] = "NeoJJFileStatusUnmerged",
		["T"] = "NeoJJFileStatusTypeChanged",
	}
	return status_highlights[status] or "NeoJJFileStatusUnknown"
end

---Get diff line highlight group
---@param line string Diff line
---@return string highlight_group Highlight group name
function CommitUI.get_diff_line_highlight(line)
	-- Diff header lines
	if line:match("^diff ") then
		return "NeoJJDiffHeader"
	elseif line:match("^index ") then
		return "NeoJJDiffIndex"
	elseif line:match("^%-%-%- ") or line:match("^%+%+%+ ") then
		return "NeoJJDiffFile"
	elseif line:match("^@@ ") then
		return "NeoJJDiffHunk"
	elseif line:match("^new file mode") or line:match("^deleted file mode") then
		return "NeoJJDiffMode"
	elseif line:match("^rename from") or line:match("^rename to") then
		return "NeoJJDiffRename"
	-- Diff content lines
	elseif line:match("^%+") then
		return "NeoJJDiffAdd"
	elseif line:match("^%-") then
		return "NeoJJDiffDelete"
	elseif line:match("^ ") then
		return "NeoJJDiffContext"
	else
		return "NeoJJDiffText"
	end
end

---Create the empty state component
---@return table component Empty state component
function CommitUI.create_empty_state()
	return Ui.col({
		Ui.text("No changes found", { highlight = "NeoJJEmptyState" }),
		Ui.empty_line(),
		Ui.text("This commit has no file changes or the diff could not be loaded.", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create help text component
---@return table component Help text component
function CommitUI.create_help()
	return Ui.col({
		Ui.text("NeoJJ Commit View Help", { highlight = "NeoJJTitle" }),
		Ui.empty_line(),
		Ui.text("Navigation:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  j/k         - Move cursor up/down", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Enter>     - Open file at cursor", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Tab>       - Toggle file diff", { highlight = "NeoJJHelpText" }),
		Ui.text("  d           - Show full diff", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Actions:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  r           - Refresh commit", { highlight = "NeoJJHelpText" }),
		Ui.text("  b           - Back to log", { highlight = "NeoJJHelpText" }),
		Ui.text("  s           - Open status view", { highlight = "NeoJJHelpText" }),
		Ui.text("  l           - Open log view", { highlight = "NeoJJHelpText" }),
		Ui.text("  q           - Quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Esc>       - Quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  ?           - Show/hide this help", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("File statuses:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  A           - Added", { highlight = "NeoJJHelpText" }),
		Ui.text("  M           - Modified", { highlight = "NeoJJHelpText" }),
		Ui.text("  D           - Deleted", { highlight = "NeoJJHelpText" }),
		Ui.text("  R           - Renamed", { highlight = "NeoJJHelpText" }),
		Ui.text("  C           - Copied", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Diff colors:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  +           - Added lines", { highlight = "NeoJJHelpText" }),
		Ui.text("  -           - Deleted lines", { highlight = "NeoJJHelpText" }),
		Ui.text("  @@ @@       - Hunk headers", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create a test commit UI for development
---@return table[] components UI components for testing
function CommitUI.create_test_ui()
	-- Create sample commit data that looks like real jj show output
	local test_commit_state = {
		commit_data = {
			change_id = "sqmvkywl",
			commit_id = "f35b8f36",
			author = "krisajenkins@gmail.com",
			date = "2025-07-14 21:06:06",
			description = "Adding jj log support.\n\nThis commit adds the initial implementation of the log buffer\nand UI components for displaying commit history.",
		},
		files = {
			{
				path = "lua/neojj/buffers/log/init.lua",
				status = "A",
			},
			{
				path = "lua/neojj/buffers/log/ui.lua",
				status = "A",
			},
			{
				path = "lua/neojj/commands.lua",
				status = "M",
			},
		},
		diff_data = {
			"diff --git a/lua/neojj/buffers/log/init.lua b/lua/neojj/buffers/log/init.lua",
			"new file mode 100644",
			"index 0000000..1234567",
			"--- /dev/null",
			"+++ b/lua/neojj/buffers/log/init.lua",
			"@@ -0,0 +1,10 @@",
			"+local Buffer = require(\"neojj.lib.buffer\")",
			"+local LogUI = require(\"neojj.buffers.log.ui\")",
			"+local logger = require(\"neojj.logger\")",
			"+",
			"+local LogBuffer = {}",
			"+LogBuffer.__index = LogBuffer",
			"+",
			"+function LogBuffer.new(repo, options)",
			"+    -- Implementation here",
			"+end",
			"",
			"diff --git a/lua/neojj/commands.lua b/lua/neojj/commands.lua",
			"index abc123..def456 100644",
			"--- a/lua/neojj/commands.lua",
			"+++ b/lua/neojj/commands.lua",
			"@@ -15,6 +15,12 @@",
			" function M.setup()",
			"     vim.api.nvim_create_user_command(\"JJStatus\", M.status, {})",
			"     vim.api.nvim_create_user_command(\"JJDescribe\", M.describe, {})",
			"+    vim.api.nvim_create_user_command(\"JJLog\", M.log, {})",
			"+end",
			"+",
			"+function M.log()",
			"+    local LogBuffer = require(\"neojj.buffers.log\")",
			"+    local log_buffer = LogBuffer.new(Repository.current())",
			"+    log_buffer:show()",
			" end",
			"",
			" return M",
		},
	}

	return CommitUI.create(test_commit_state)
end

return CommitUI
