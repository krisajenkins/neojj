local Ui = require("neojj.lib.ui")

---@class LogUI
local LogUI = {}

---Create the main log UI components
---@param log_state table Log state with revisions and graph data
---@param log_buffer? table Log buffer instance for interactions
---@return table[] components UI components
function LogUI.create(log_state, log_buffer)
	local components = {}

	-- Add header
	table.insert(components, LogUI.create_header())

	-- Add log entries
	if log_state.raw_lines and #log_state.raw_lines > 0 then
		local log_components = LogUI.create_log_components(log_state, log_buffer)
		for _, component in ipairs(log_components) do
			table.insert(components, component)
		end
	else
		table.insert(components, LogUI.create_empty_state())
	end

	return components
end

---Create the header component
---@return table component Header component
function LogUI.create_header()
	return Ui.col({
		Ui.text("JJ Log", { highlight = "NeoJJTitle" }),
		Ui.text("Press ? for help, q to quit", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create log components from parsed log data
---@param log_state table Log state with raw lines and parsed data
---@param log_buffer? table Log buffer instance
---@return table[] components List of UI components
function LogUI.create_log_components(log_state, log_buffer)
	local components = {}

	-- Process each line from the raw log output
	for i, line in ipairs(log_state.raw_lines) do
		if line == "" then
			-- Add empty line as-is
			table.insert(components, Ui.empty_line())
		else
			-- Check if this line has associated revision data
			local graph_info = log_state.graph_data[i]
			local revision = graph_info and graph_info.revision

			if revision then
				-- This is a commit header line
				table.insert(components, LogUI.create_commit_line(line, revision, log_buffer))
			else
				-- This is a description line or graph continuation
				table.insert(components, LogUI.create_graph_line(line))
			end
		end
	end

	return components
end

---Create a commit line component (interactive)
---@param line string The raw line content
---@param revision table Revision data
---@param log_buffer? table Log buffer instance
---@return table component Commit line component
function LogUI.create_commit_line(line, revision, log_buffer)
	-- Parse the line to separate graph and commit info
	local graph_part, commit_part = line:match("^([│@○◆%s├└┤┬┴─┌┐┘]*)(.*)")

	if not graph_part or not commit_part then
		-- Fallback: treat whole line as commit info
		graph_part = ""
		commit_part = line
	end

	-- Check if this is the working copy (current head) by looking for @ in the graph
	local is_current_head = revision.graph and revision.graph:match("@") ~= nil
	local commit_highlight = is_current_head and "NeoJJLogCurrentHead" or "NeoJJLogCommit"

	-- Create the header row
	local header_row = Ui.row({
		Ui.text(LogUI.highlight_graph(graph_part), { highlight = "NeoJJLogGraph" }),
		Ui.text(LogUI.highlight_commit_info(commit_part, revision), { highlight = commit_highlight }),
	}, {
		item = revision,
		interactive = true,
	})

	-- Check if this revision is expanded
	local is_expanded = log_buffer
		and log_buffer.expanded_revisions
		and log_buffer.expanded_revisions[revision.change_id]

	if is_expanded then
		-- Fetch and render expanded details
		local details = log_buffer:get_revision_details(revision.change_id)
		local expanded_components = LogUI.create_expanded_details(details, graph_part)

		return Ui.col({
			header_row,
			Ui.col(expanded_components),
		})
	end

	return header_row
end

---Create expanded details components (description + stats)
---@param details table Details with description and stats arrays
---@param graph_prefix string Graph prefix for indentation
---@return table[] components Expanded detail components
function LogUI.create_expanded_details(details, graph_prefix)
	local components = {}
	-- Create an indent that continues the graph visually
	local indent = string.rep(" ", #graph_prefix)

	-- Add description lines
	for _, line in ipairs(details.description or {}) do
		table.insert(components, Ui.text(indent .. line, { highlight = "NeoJJLogDescription" }))
	end

	-- Add separator if we have both description and stats
	if #(details.description or {}) > 0 and #(details.stats or {}) > 0 then
		table.insert(components, Ui.empty_line())
	end

	-- Add stats lines with highlighting
	for _, line in ipairs(details.stats or {}) do
		local highlight = "NeoJJLogStats"
		-- Summary line gets different highlighting
		if line:match("^%d+ files? changed") then
			highlight = "NeoJJLogStatsSummary"
		end
		table.insert(components, Ui.text(indent .. line, { highlight = highlight }))
	end

	return components
end

---Create a graph line component (non-interactive)
---@param line string The raw line content
---@return table component Graph line component
function LogUI.create_graph_line(line)
	-- Parse the line to separate graph and description
	local graph_part, desc_part = line:match("^([│%s]*)(.*)")

	if not graph_part then
		graph_part = ""
		desc_part = line
	end

	return Ui.row({
		Ui.text(LogUI.highlight_graph(graph_part), { highlight = "NeoJJLogGraph" }),
		Ui.text(desc_part, { highlight = "NeoJJLogDescription" }),
	})
end

---Apply highlighting to graph characters
---@param graph_text string Graph portion of the line
---@return string highlighted_graph Graph text with highlighting hints
function LogUI.highlight_graph(graph_text)
	-- Keep graph text as-is but return with highlighting information
	-- The actual highlighting will be applied by the renderer
	return graph_text
end

---Apply highlighting to commit information
---@param commit_text string Commit info portion
---@param revision table Revision data
---@return string highlighted_commit Commit text with highlighting
function LogUI.highlight_commit_info(commit_text, revision)
	-- For now, return as-is. We could enhance this later to highlight
	-- specific parts like change ID, author, timestamp differently
	return commit_text
end

---Get highlight group for graph characters
---@param char string Single graph character
---@return string highlight_group Highlight group name
function LogUI.get_graph_highlight(char)
	-- Map specific graph characters to highlight groups
	local char_map = {
		["@"] = "NeoJJLogWorkingCopy", -- Working copy marker
		["○"] = "NeoJJLogCommit", -- Regular commit
		["◆"] = "NeoJJLogImmutable", -- Immutable commit
		["│"] = "NeoJJLogGraphLine", -- Vertical line
		["├"] = "NeoJJLogGraphLine", -- Branch/merge
		["└"] = "NeoJJLogGraphLine", -- Branch end
		["┤"] = "NeoJJLogGraphLine", -- Branch join
		["┬"] = "NeoJJLogGraphLine", -- Split
		["┴"] = "NeoJJLogGraphLine", -- Join
		["─"] = "NeoJJLogGraphLine", -- Horizontal line
		["┌"] = "NeoJJLogGraphLine", -- Corner
		["┐"] = "NeoJJLogGraphLine", -- Corner
		["┘"] = "NeoJJLogGraphLine", -- Corner
	}

	return char_map[char] or "NeoJJLogGraph"
end

---Create enhanced graph display with character-level highlighting
---@param graph_text string Graph portion of line
---@return table component Enhanced graph component
function LogUI.create_enhanced_graph(graph_text)
	-- Split graph text into individual characters for fine-grained highlighting
	local graph_components = {}

	for i = 1, #graph_text do
		local char = graph_text:sub(i, i)
		local highlight = LogUI.get_graph_highlight(char)
		table.insert(graph_components, Ui.text(char, { highlight = highlight }))
	end

	return Ui.row(graph_components)
end

---Create the empty state component
---@return table component Empty state component
function LogUI.create_empty_state()
	return Ui.col({
		Ui.text("No commits found", { highlight = "NeoJJEmptyState" }),
		Ui.empty_line(),
		Ui.text("The repository has no commits or the log query returned no results.", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create help text component
---@return table component Help text component
function LogUI.create_help()
	return Ui.col({
		Ui.text("NeoJJ Log Help", { highlight = "NeoJJTitle" }),
		Ui.empty_line(),
		Ui.text("Navigation:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  j/k       - Move cursor up/down", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Tab>     - Toggle revision details", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Enter>   - Show commit details", { highlight = "NeoJJHelpText" }),
		Ui.text("  d         - Show commit diff", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Actions:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  n         - Create new change after cursor", { highlight = "NeoJJHelpText" }),
		Ui.text("  r         - Refresh log", { highlight = "NeoJJHelpText" }),
		Ui.text("  s         - Open status view", { highlight = "NeoJJHelpText" }),
		Ui.text("  q         - Quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  <Esc>     - Quit", { highlight = "NeoJJHelpText" }),
		Ui.text("  ?         - Show/hide this help", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
		Ui.text("Graph symbols:", { highlight = "NeoJJSectionHeader" }),
		Ui.text("  @         - Working copy commit", { highlight = "NeoJJHelpText" }),
		Ui.text("  ○         - Regular commit", { highlight = "NeoJJHelpText" }),
		Ui.text("  ◆         - Immutable commit", { highlight = "NeoJJHelpText" }),
		Ui.text("  │├└┤┬┴─   - Graph connections", { highlight = "NeoJJHelpText" }),
		Ui.empty_line(),
	})
end

---Create a test log UI for development
---@return table[] components UI components for testing
function LogUI.create_test_ui()
	-- Create sample log data that looks like real jj log output
	local test_log_state = {
		raw_lines = {
			"@  sqmvkywl krisajenkins@gmail.com 2025-07-14 21:06:06 f35b8f36",
			"│  Adding jj log support.",
			"○  knsrwpnn krisajenkins@gmail.com 2025-07-14 20:58:50 1e062938",
			"│  Implementing more status page functions - help/fold/reverse fold.",
			"○  qysrkqoy krisajenkins@gmail.com 2025-07-14 14:46:13 9ff01605",
			'│  Adding "open file" handling from the status page, and fixing a warning message.',
			"○  pkosquwz krisajenkins@gmail.com 2025-07-14 14:46:02 d4818d0b",
			"│  Reorganising the markdown docs we're gathering.",
		},
		graph_data = {
			[1] = {
				graph = "@  ",
				revision = {
					change_id = "sqmvkywl",
					author = "krisajenkins@gmail.com",
					timestamp = "2025-07-14 21:06:06",
					commit_id = "f35b8f36",
					description = "Adding jj log support.",
					line_number = 1,
				},
			},
			[2] = { graph = "│  ", revision = nil },
			[3] = {
				graph = "○  ",
				revision = {
					change_id = "knsrwpnn",
					author = "krisajenkins@gmail.com",
					timestamp = "2025-07-14 20:58:50",
					commit_id = "1e062938",
					description = "Implementing more status page functions - help/fold/reverse fold.",
					line_number = 3,
				},
			},
			[4] = { graph = "│  ", revision = nil },
			[5] = {
				graph = "○  ",
				revision = {
					change_id = "qysrkqoy",
					author = "krisajenkins@gmail.com",
					timestamp = "2025-07-14 14:46:13",
					commit_id = "9ff01605",
					description = 'Adding "open file" handling from the status page, and fixing a warning message.',
					line_number = 5,
				},
			},
			[6] = { graph = "│  ", revision = nil },
			[7] = {
				graph = "○  ",
				revision = {
					change_id = "pkosquwz",
					author = "krisajenkins@gmail.com",
					timestamp = "2025-07-14 14:46:02",
					commit_id = "d4818d0b",
					description = "Reorganising the markdown docs we're gathering.",
					line_number = 7,
				},
			},
			[8] = { graph = "│  ", revision = nil },
		},
	}

	return LogUI.create(test_log_state)
end

return LogUI
