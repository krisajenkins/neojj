local Ui = require("neojj.lib.ui")

---@class StatusUI
local StatusUI = {}

---Create the main status UI components
---@param repo_state table Repository state from JJ
---@param expanded_files? table Expanded files state
---@param status_buffer? table Status buffer instance for diff access
---@return table[] components UI components
function StatusUI.create(repo_state, expanded_files, status_buffer)
	local components = {}
	expanded_files = expanded_files or {}

	-- Add header
	table.insert(components, StatusUI.create_header())

	-- Add working copy information
	if repo_state.working_copy then
		-- Determine section title based on whether we're showing a specific revision
		local is_working_copy = not status_buffer or not status_buffer.revision
		table.insert(components, StatusUI.create_working_copy_section(repo_state.working_copy, is_working_copy))
	end

	-- Add modified files section
	if repo_state.working_copy and repo_state.working_copy.modified_files then
		table.insert(
			components,
			StatusUI.create_modified_files_section(
				repo_state.working_copy.modified_files,
				expanded_files,
				status_buffer
			)
		)
	end

	-- Add conflicts section
	if repo_state.working_copy and repo_state.working_copy.conflicts then
		table.insert(
			components,
			StatusUI.create_conflicts_section(repo_state.working_copy.conflicts, expanded_files, status_buffer)
		)
	end

	-- Add empty state message if no changes
	if repo_state.working_copy and repo_state.working_copy.is_empty then
		table.insert(components, StatusUI.create_empty_state())
	end

	return components
end

---Create the header component
---@return table component Header component
function StatusUI.create_header()
	return Ui.col({
		Ui.text("JJ Status", { highlight = "NeoJJTitle" }),
		Ui.text("Press ? for help, q to quit", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create the working copy section with full metadata
---@param working_copy table Working copy information
---@param is_working_copy? boolean True if showing working copy, false for specific revision
---@return table component Working copy section
function StatusUI.create_working_copy_section(working_copy, is_working_copy)
	local metadata_items = {}
	local section_title = is_working_copy and "Working Copy" or "Commit"

	-- Change ID
	if working_copy.change_id then
		table.insert(metadata_items, Ui.text("Change ID: " .. working_copy.change_id, { highlight = "NeoJJChangeId" }))
	end

	-- Commit ID
	if working_copy.commit_id then
		table.insert(metadata_items, Ui.text("Commit ID: " .. working_copy.commit_id, { highlight = "NeoJJCommitId" }))
	end

	-- Author
	if working_copy.author then
		-- Handle both string format (from jj show) and table format (from jj status)
		local author_str
		if type(working_copy.author) == "table" then
			author_str = working_copy.author.name .. " <" .. working_copy.author.email .. ">"
		else
			author_str = working_copy.author
		end
		table.insert(metadata_items, Ui.text("Author: " .. author_str, { highlight = "NeoJJAuthor" }))
	end

	-- Committer (if different from author)
	if working_copy.committer and working_copy.committer ~= working_copy.author then
		table.insert(metadata_items, Ui.text("Committer: " .. working_copy.committer, { highlight = "NeoJJCommitter" }))
	end

	-- Date
	if working_copy.date then
		table.insert(metadata_items, Ui.text("Date: " .. working_copy.date, { highlight = "NeoJJDate" }))
	end

	table.insert(metadata_items, Ui.empty_line())

	-- Description (full, not just first line)
	if working_copy.description then
		-- Split description by newlines, preserving blank lines
		local lines = vim.split(working_copy.description, "\n", { plain = true })
		for _, line in ipairs(lines) do
			if line == "" then
				table.insert(metadata_items, Ui.empty_line())
			else
				table.insert(metadata_items, Ui.text(line, { highlight = "NeoJJDescription" }))
			end
		end
		-- Note: Section component adds empty line at end automatically
	end

	return Ui.section(section_title, metadata_items, {
		section = "working_copy",
	})
end

---Create the modified files section
---@param modified_files table[] List of modified files
---@param expanded_files? table Expanded files state
---@param status_buffer? table Status buffer instance for diff access
---@return table component Modified files section
function StatusUI.create_modified_files_section(modified_files, expanded_files, status_buffer)
	if #modified_files == 0 then
		return Ui.empty_line()
	end

	expanded_files = expanded_files or {}
	local file_items = {}
	for _, file in ipairs(modified_files) do
		table.insert(file_items, StatusUI.create_file_item(file, expanded_files, status_buffer))
	end

	return Ui.section("Modified Files", file_items, {
		section = "modified_files",
	})
end

---Create the conflicts section
---@param conflicts table[] List of conflicted files
---@param expanded_files? table Expanded files state
---@param status_buffer? table Status buffer instance for diff access
---@return table component Conflicts section
function StatusUI.create_conflicts_section(conflicts, expanded_files, status_buffer)
	if #conflicts == 0 then
		return Ui.empty_line()
	end

	expanded_files = expanded_files or {}
	local conflict_items = {}
	for _, conflict in ipairs(conflicts) do
		-- Create conflict file item with "C" status
		local conflict_file = {
			status = "C",
			path = conflict.path,
		}
		table.insert(conflict_items, StatusUI.create_file_item(conflict_file, expanded_files, status_buffer))
	end

	return Ui.section("Conflicts", conflict_items, {
		section = "conflicts",
	})
end

---Create a file item with optional diff expansion
---@param file table File information {status, path}
---@param expanded_files table Expanded files state
---@param status_buffer? table Status buffer instance for diff access
---@return table component File item component
function StatusUI.create_file_item(file, expanded_files, status_buffer)
	local children = {
		Ui.file_item(file.status, file.path, {
			item = file,
			interactive = true,
			highlight = file.status == "C" and "NeoJJConflict" or nil,
		}),
	}

	-- Add diff content if file is expanded
	if expanded_files[file.path] and status_buffer then
		local diff_lines = status_buffer:get_file_diff(file.path)
		local diff_components = StatusUI.create_diff_components(diff_lines, file.path)

		if #diff_components > 0 then
			table.insert(children, Ui.col(diff_components))
		end
	end

	return Ui.col(children)
end

---Get highlight group for a diff line
---@param line string Diff line content
---@param file_path? string File path for syntax-aware highlighting
---@return string|nil highlight Highlight group name or nil
function StatusUI.get_diff_highlight(line, file_path)
	-- Empty lines
	if line == "" then
		return nil
	end

	-- Git diff headers
	if line:match("^diff --git ") then
		return "NeoJJDiffGitHeader"
	elseif line:match("^diff ") then
		return "NeoJJDiffFile"
	end

	-- File mode and similarity info
	if
		line:match("^old mode ")
		or line:match("^new mode ")
		or line:match("^deleted file mode ")
		or line:match("^new file mode ")
	then
		return "NeoJJDiffMode"
	elseif line:match("^similarity index ") or line:match("^dissimilarity index ") then
		return "NeoJJDiffSimilarity"
	elseif
		line:match("^rename from ")
		or line:match("^rename to ")
		or line:match("^copy from ")
		or line:match("^copy to ")
	then
		return "NeoJJDiffRename"
	end

	-- Index line
	if line:match("^index ") then
		return "NeoJJDiffIndex"
	end

	-- Binary files
	if line:match("^Binary files .* differ$") or line:match("^GIT binary patch$") then
		return "NeoJJDiffBinary"
	end

	-- File headers (--- and +++)
	if line:match("^%-%-%- ") then
		return "NeoJJDiffOldFile"
	elseif line:match("^%+%+%+ ") then
		return "NeoJJDiffNewFile"
	end

	-- Hunk headers (@@)
	if line:match("^@@ ") then
		return "NeoJJDiffHunk"
	end

	-- Range indicators (for context)
	if line:match("^@@.*@@") then
		return "NeoJJDiffRange"
	end

	-- Added lines (start with +)
	if line:match("^%+") then
		return "NeoJJDiffAdd"
	end

	-- Deleted lines (start with -)
	if line:match("^%-") then
		return "NeoJJDiffDelete"
	end

	-- No newline at end of file
	if line:match("^\\ No newline at end of file") then
		return "NeoJJDiffNoNewline"
	end

	-- Context lines (lines that start with space or have no prefix in unified diff)
	-- These are unchanged lines shown for context
	if line:match("^ ") then
		return "NeoJJDiffContext"
	end

	-- Default to context for any other line
	return "NeoJJDiffContext"
end

---Create enhanced diff components with syntax-aware highlighting
---@param diff_lines string[] List of diff lines
---@param file_path string File path for syntax detection
---@return table[] components List of UI components
function StatusUI.create_diff_components(diff_lines, file_path)
	local components = {}

	for _, line in ipairs(diff_lines) do
		local highlight = StatusUI.get_diff_highlight(line, file_path)
		local enhanced_component = StatusUI.create_enhanced_diff_line(line, highlight, file_path)
		table.insert(components, enhanced_component)
	end

	return components
end

---Create an enhanced diff line with better highlighting
---@param line string Diff line content
---@param base_highlight string|nil Base highlight group
---@param file_path string File path for syntax detection
---@return table component UI component for the diff line
function StatusUI.create_enhanced_diff_line(line, base_highlight, file_path)
	-- Handle special formatting for different diff line types
	local prefix = "  "
	local content = line

	-- Special handling for hunk headers to make them more readable
	if base_highlight == "NeoJJDiffHunk" then
		-- Extract line numbers from hunk header for better readability
		local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
		if old_start and new_start then
			-- Format: @@ -old_start,old_count +new_start,new_count @@
			local old_range = old_count and old_count ~= "" and (old_start .. "," .. old_count) or old_start
			local new_range = new_count and new_count ~= "" and (new_start .. "," .. new_count) or new_start
			content = "@@ -"
				.. old_range
				.. " +"
				.. new_range
				.. " @@"
				.. line:match("@@ %-?%d+,?%d* %+?%d+,?%d* @@(.*)$")
		end
	elseif base_highlight == "NeoJJDiffAdd" then
		-- Ensure added lines are visually distinct
		prefix = "+ "
	elseif base_highlight == "NeoJJDiffDelete" then
		-- Ensure deleted lines are visually distinct
		prefix = "- "
	elseif base_highlight == "NeoJJDiffContext" then
		-- Context lines get a subtle prefix
		prefix = "  "
	elseif base_highlight == "NeoJJDiffBinary" then
		-- Binary file indicators
		prefix = "  "
		content = "Binary file"
	elseif base_highlight == "NeoJJDiffNoNewline" then
		-- No newline warnings
		prefix = "  "
		content = "⚠ " .. content
	else
		-- Default formatting for headers and other line types
		prefix = "  "
	end

	return Ui.text(prefix .. content, { highlight = base_highlight })
end

---Create the empty state component
---@return table component Empty state component
function StatusUI.create_empty_state()
	return Ui.col({
		Ui.text("No changes in working copy", { highlight = "NeoJJEmptyState" }),
		Ui.empty_line(),
		Ui.text("The working copy is clean and matches the current revision.", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create a bookmarks section (for future enhancement)
---@param bookmarks table[] List of bookmarks
---@return table component Bookmarks section
function StatusUI.create_bookmarks_section(bookmarks)
	if #bookmarks == 0 then
		return Ui.empty_line()
	end

	local bookmark_items = {}
	for _, bookmark in ipairs(bookmarks) do
		table.insert(
			bookmark_items,
			Ui.row({
				Ui.text("* ", { highlight = "NeoJJBookmarkMarker" }),
				Ui.text(bookmark.name, { highlight = "NeoJJBookmarkName" }),
				Ui.text(" -> ", { highlight = "NeoJJBookmarkArrow" }),
				Ui.text(bookmark.target, { highlight = "NeoJJCommitId" }),
			}, {
				item = bookmark,
				interactive = true,
			})
		)
	end

	return Ui.section("Bookmarks", bookmark_items, {
		folded = true,
		section = "bookmarks",
	})
end

---Create a recent commits section (for future enhancement)
---@param commits table[] List of recent commits
---@return table component Recent commits section
function StatusUI.create_recent_commits_section(commits)
	if #commits == 0 then
		return Ui.empty_line()
	end

	local commit_items = {}
	for _, commit in ipairs(commits) do
		table.insert(
			commit_items,
			Ui.row({
				Ui.text(commit.change_id:sub(1, 8), { highlight = "NeoJJChangeId" }),
				Ui.text(" ", {}),
				Ui.text(commit.description or "", { highlight = "NeoJJDescription" }),
			}, {
				item = commit,
				interactive = true,
			})
		)
	end

	return Ui.section("Recent Commits", commit_items, {
		folded = true,
		section = "recent_commits",
	})
end

---Create help text component
---@return table component Help text component
function StatusUI.create_help()
	return Ui.col({
		Ui.text("NeoJJ Status Help", { highlight = "NeoJJTitle" }),
		Ui.empty_line(),
		Ui.text("Navigation:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  j/k     - Move cursor up/down", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Tab>   - Toggle file diff", { highlight = "NeoJJHelpText" }),
		Ui.text("  <S-Tab> - Toggle all file diffs", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Actions:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  n       - Create new change from current commit", { highlight = "NeoJJHelpText" }),
		Ui.text("  r       - Refresh status", { highlight = "NeoJJHelpText" }),
		Ui.text("  d       - Describe current commit", { highlight = "NeoJJHelpText" }),
		Ui.text("  D       - Show diff for file at cursor", { highlight = "NeoJJHelpText" }),
		Ui.text("  l       - Open log view", { highlight = "NeoJJHelpText" }),
		Ui.text("  q       - Quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Esc>   - Quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  ?       - Show/hide this help", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create a minimal status UI for testing
---@return table[] components UI components for testing
function StatusUI.create_test_ui()
	local test_repo_state = {
		working_copy = {
			change_id = "kmkuslsqnxux",
			commit_id = "abc123def456",
			description = "Test commit for UI development",
			author = { name = "Test User", email = "test@example.com" },
			modified_files = {
				{ status = "M", path = "src/main.lua" },
				{ status = "A", path = "src/ui.lua" },
				{ status = "D", path = "old_file.lua" },
			},
			conflicts = {
				{ path = "conflicted.lua" },
			},
			is_empty = false,
		},
	}

	return StatusUI.create(test_repo_state)
end

return StatusUI
