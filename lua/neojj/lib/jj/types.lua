---@meta

---Author information
---@class Author
---@field name string Author's name
---@field email string Author's email address

---A modified file in the working copy
---@class ModifiedFile
---@field status string File status: "M" (modified), "A" (added), "D" (deleted), "R" (renamed), "C" (copied), "?" (untracked)
---@field path string File path relative to repository root
---@field old_path? string Original path for renamed/copied files

---A conflicted file
---@class Conflict
---@field path string File path relative to repository root
---@field sides? integer Number of conflict sides (e.g. 2 for a 2-sided conflict)
---@field annotation? string Human-readable conflict annotation (e.g. "2-sided conflict")

---Working copy information from jj status
---@class WorkingCopy
---@field change_id string|nil Change ID of the working copy
---@field commit_id string|nil Commit ID of the working copy
---@field description string Commit description
---@field author Author Author information
---@field parent_ids string[] List of parent commit IDs
---@field modified_files ModifiedFile[] List of modified files
---@field conflicts Conflict[] List of conflicted files
---@field is_empty boolean Whether the working copy has no changes
---@field empty boolean jj's own emptiness flag for the working-copy commit (parsed from its "(empty)" marker; unlike is_empty, true even for an empty conflicted merge)

---A single revision from jj log
---@class LogRevision
---@field change_id string Change ID
---@field author string Author email
---@field timestamp string Timestamp string
---@field commit_id string Commit ID
---@field change_id_prefix string|nil jj's unique disambiguating prefix of change_id (leading substring), if known
---@field commit_id_prefix string|nil jj's unique disambiguating prefix of commit_id (leading substring), if known
---@field description string First line of description
---@field bookmarks string[] Bookmark names pointing to this revision
---@field tags string[] Tag names pointing to this revision
---@field conflict boolean Whether this revision has conflicts
---@field empty boolean Whether this revision is empty (jj's own emptiness flag)
---@field graph string ASCII graph prefix for this revision
---@field line_number integer Line number in the output where this revision appears

---Graph data for a single line in log output
---@class GraphData
---@field graph string ASCII graph characters for this line
---@field revision LogRevision|nil The revision at this line (nil for graph continuation lines)
---@field empty_marker boolean|nil True when this is a description line prefixed with jj's "(empty)" marker

---Parsed log output
---@class ParsedLog
---@field revisions LogRevision[] List of all revisions
---@field graph_data table<integer, GraphData> Map of line number to graph data
---@field raw_lines string[] Raw output lines

---A single operation from jj op log
---@class OpLogOperation
---@field operation_id string Operation ID (abbreviated)
---@field user string User who performed the operation
---@field time_start string Operation start timestamp
---@field time_end string Operation end timestamp
---@field description string First line of the operation description
---@field is_current boolean Whether this is the current operation (@)
---@field graph string ASCII graph prefix for this operation
---@field line_number integer Line number in the output where this operation appears

---Graph data for a single line in op-log output
---@class OpGraphData
---@field graph string ASCII graph characters for this line
---@field operation OpLogOperation|nil The operation at this line (nil for continuation lines)

---Parsed op-log output
---@class ParsedOpLog
---@field operations OpLogOperation[] List of all operations
---@field graph_data table<integer, OpGraphData> Map of line number to graph data
---@field raw_lines string[] Raw output lines

---JSON output from jj log (using json(self) template)
---@class JjLogJson
---@field change_id string Change ID
---@field commit_id string Commit ID
---@field description string Full commit description
---@field author JjAuthorJson Author information from JSON
---@field committer JjAuthorJson Committer information from JSON
---@field working_copy boolean Whether this is the working copy
---@field current_operation boolean Whether this is from the current operation
---@field immutable boolean Whether this commit is immutable
---@field parents string[] Parent commit IDs
---@field predecessors string[] Predecessor change IDs
---@field bookmarks string[] Bookmarks pointing to this commit
---@field tags string[] Tags on this commit
---@field git_refs string[] Git refs pointing to this commit
---@field divergent boolean Whether this change is divergent
---@field hidden boolean Whether this commit is hidden
---@field conflict boolean Whether this commit has conflicts

---Author/committer information from jj JSON output
---@class JjAuthorJson
---@field name string Author name
---@field email string Author email
---@field timestamp JjTimestampJson Timestamp information

---Timestamp from jj JSON output
---@class JjTimestampJson
---@field timestamp string ISO 8601 timestamp
---@field tz_offset integer Timezone offset in minutes

local M = {}

return M
