local Ui = require("neojj.lib.ui")

---@class StatusUI
local StatusUI = {}

---Create the main status UI components
---@param repo_state table Repository state from JJ
---@return table[] components UI components
function StatusUI.create(repo_state)
	local components = {}

	-- Add header
	table.insert(components, StatusUI.create_header())

	-- Add working copy information
	if repo_state.working_copy then
		table.insert(components, StatusUI.create_working_copy_section(repo_state.working_copy))
	end

	-- Add modified files section
	if repo_state.working_copy and repo_state.working_copy.modified_files then
		table.insert(components, StatusUI.create_modified_files_section(repo_state.working_copy.modified_files))
	end

	-- Add conflicts section
	if repo_state.working_copy and repo_state.working_copy.conflicts then
		table.insert(components, StatusUI.create_conflicts_section(repo_state.working_copy.conflicts))
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

---Create the working copy section
---@param working_copy table Working copy information
---@return table component Working copy section
function StatusUI.create_working_copy_section(working_copy)
	return Ui.section("Working Copy", {
		Ui.commit_info(
			working_copy.change_id or "unknown",
			working_copy.commit_id or "unknown",
			working_copy.description or "",
			working_copy.author or { name = "unknown", email = "unknown" }
		),
	}, {
		folded = false,
		section = "working_copy",
	})
end

---Create the modified files section
---@param modified_files table[] List of modified files
---@return table component Modified files section
function StatusUI.create_modified_files_section(modified_files)
	if #modified_files == 0 then
		return Ui.empty_line()
	end

	local file_items = {}
	for _, file in ipairs(modified_files) do
		table.insert(
			file_items,
			Ui.file_item(file.status, file.path, {
				item = file,
				interactive = true,
			})
		)
	end

	return Ui.section("Modified Files", file_items, {
		folded = false,
		section = "modified_files",
	})
end

---Create the conflicts section
---@param conflicts table[] List of conflicted files
---@return table component Conflicts section
function StatusUI.create_conflicts_section(conflicts)
	if #conflicts == 0 then
		return Ui.empty_line()
	end

	local conflict_items = {}
	for _, conflict in ipairs(conflicts) do
		table.insert(
			conflict_items,
			Ui.file_item("C", conflict.path, {
				item = conflict,
				interactive = true,
				highlight = "NeoJJConflict",
			})
		)
	end

	return Ui.section("Conflicts", conflict_items, {
		folded = false,
		section = "conflicts",
	})
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
		Ui.text("  <Tab>   - Toggle fold", { highlight = "NeoJJHelpText" }),
		Ui.text("  <S-Tab> - Toggle fold (reverse)", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Actions:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  r       - Refresh status", { highlight = "NeoJJHelpText" }),
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
