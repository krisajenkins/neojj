---@class Highlights
local Highlights = {}

---Default highlight groups for NeoJJ
local default_highlights = {
	-- General UI
	NeoJJTitle = { link = "Title" },
	NeoJJHelpText = { link = "Comment" },
	NeoJJEmptyState = { link = "Comment" },

	-- Section headers
	NeoJJSectionHeader = { link = "Function" },

	-- File status indicators
	NeoJJFileStatus = { link = "Type" },
	NeoJJFilePath = { link = "String" },

	-- Commit information
	NeoJJLabel = { link = "Label" },
	NeoJJChangeId = { link = "Number" },
	NeoJJCommitId = { link = "Identifier" },
	NeoJJDescription = { link = "String" },
	NeoJJAuthor = { link = "String" },

	-- Conflicts
	NeoJJConflict = { link = "Error" },

	-- Bookmarks (for future use)
	NeoJJBookmarkMarker = { link = "Special" },
	NeoJJBookmarkName = { link = "Function" },
	NeoJJBookmarkArrow = { link = "Operator" },

	-- File status specific colors
	NeoJJFileAdded = { link = "DiffAdd" },
	NeoJJFileModified = { link = "DiffChange" },
	NeoJJFileDeleted = { link = "DiffDelete" },
	NeoJJFileRenamed = { link = "DiffText" },
	NeoJJFileUntracked = { link = "Comment" },

	-- Interactive elements
	NeoJJCursor = { link = "CursorLine" },
	NeoJJSelected = { link = "Visual" },

	-- Folds
	NeoJJFolded = { link = "Folded" },
	NeoJJFoldMarker = { link = "FoldColumn" },

	-- Describe buffer specific
	NeoJJDescribeComment = { link = "Comment" },
	NeoJJDescribeKeybinding = { link = "Special" },
	NeoJJDescribeCommand = { link = "Statement" },
	NeoJJDescribeSection = { link = "Function" },

	-- Diff display
	NeoJJDiffAdd = { link = "DiffAdd" },
	NeoJJDiffDelete = { link = "DiffDelete" },
	NeoJJDiffContext = { link = "Normal" },
	NeoJJDiffHunk = { link = "DiffText" },
	NeoJJDiffFile = { link = "DiffFile" },
	NeoJJDiffIndex = { link = "Comment" },
	NeoJJDiffOldFile = { link = "DiffDelete" },
	NeoJJDiffNewFile = { link = "DiffAdd" },
	NeoJJDiffNoNewline = { link = "WarningMsg" },
	NeoJJDiffBinary = { link = "Comment" },
	NeoJJDiffRename = { link = "DiffText" },
	NeoJJDiffMode = { link = "DiffText" },
	NeoJJDiffSimilarity = { link = "Comment" },
	NeoJJDiffGitHeader = { link = "PreProc" },
	NeoJJDiffRange = { link = "DiffText" },

	-- Log display
	NeoJJLogGraph = { link = "Special" },
	NeoJJLogGraphLine = { link = "Comment" },
	NeoJJLogWorkingCopy = { link = "DiffAdd" },
	NeoJJLogCommit = { link = "Normal" },
	NeoJJLogImmutable = { link = "Constant" },
	NeoJJLogDescription = { link = "String" },
}

---Apply default highlights
function Highlights.setup()
	for group, opts in pairs(default_highlights) do
		vim.api.nvim_set_hl(0, group, opts)
	end
end

---Get highlight group for file status
---@param status string File status (A, M, D, R, etc.)
---@return string highlight_group Highlight group name
function Highlights.get_file_status_highlight(status)
	local status_map = {
		A = "NeoJJFileAdded",
		M = "NeoJJFileModified",
		D = "NeoJJFileDeleted",
		R = "NeoJJFileRenamed",
		["?"] = "NeoJJFileUntracked",
		C = "NeoJJConflict",
	}

	return status_map[status] or "NeoJJFileStatus"
end

---Check if highlight group exists
---@param group string Highlight group name
---@return boolean exists True if group exists
function Highlights.group_exists(group)
	local exists = false
	vim.api.nvim_exec2("silent! highlight " .. group, {
		output = false,
		on_output = function(_, data)
			if data and data ~= "" then
				exists = true
			end
		end,
	})
	return exists
end

---Create a custom highlight group
---@param group string Highlight group name
---@param opts table Highlight options
function Highlights.create_group(group, opts)
	vim.api.nvim_set_hl(0, group, opts)
end

---Link a highlight group to another
---@param group string Source highlight group
---@param target string Target highlight group
function Highlights.link_group(group, target)
	vim.api.nvim_set_hl(0, group, { link = target })
end

return Highlights
