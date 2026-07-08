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
	NeoJJFileCopied = { link = "DiffText" },
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
	NeoJJDiffFile = { link = "diffFile" },
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
	NeoJJLogBookmark = { link = "Keyword" },
	NeoJJLogGraph = { link = "Special" },
	NeoJJLogGraphLine = { link = "Comment" },
	NeoJJLogWorkingCopy = { link = "DiffAdd" },
	NeoJJLogCommit = { link = "Normal" },
	NeoJJLogCurrentHead = { bold = true }, -- Current head (working copy) in bold
	NeoJJLogImmutable = { link = "Constant" },
	NeoJJLogDescription = { link = "String" },
	-- Log metadata fields (differentiated so each column reads distinctly)
	NeoJJLogChangeId = { link = "Identifier" },
	NeoJJLogAuthor = { link = "String" },
	NeoJJLogTimestamp = { link = "Comment" },
	NeoJJLogCommitId = { link = "Special" },
	NeoJJLogStats = { link = "Comment" },
	NeoJJLogStatsSummary = { link = "Number" },

	-- Operation-log display
	NeoJJOplogGraph = { link = "Special" },
	NeoJJOplogOperation = { link = "Normal" },
	NeoJJOplogCurrent = { bold = true }, -- Current operation (@) in bold
	NeoJJOplogId = { link = "Number" },
	NeoJJOplogUser = { link = "String" },
	NeoJJOplogTime = { link = "Comment" },
	NeoJJOplogDescription = { link = "String" },
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
		C = "NeoJJFileCopied",
	}

	return status_map[status] or "NeoJJFileStatus"
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
