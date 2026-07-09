local MiniTest = require("mini.test")
local T = MiniTest.new_set()
local expect = MiniTest.expect

local log_parser = require("neojj.lib.jj.parsers.log_parser")

local function read_fixture(filename)
	local path = "tests/fixtures/jj-outputs/" .. filename
	local file = io.open(path, "r")
	if not file then
		error("Could not open fixture file: " .. path)
	end
	local content = file:read("*all")
	file:close()
	return content
end

T["parse_log_output"] = MiniTest.new_set()

T["parse_log_output"]["parses simple linear history"] = function()
	local output = read_fixture("log-graph-simple.txt")
	local result = log_parser.parse_log_output(output)

	-- Should have 4 revisions
	expect.equality(#result.revisions, 4)

	-- Check first revision (working copy)
	local rev1 = result.revisions[1]
	expect.equality(rev1.change_id, "qpvuntsm")
	expect.equality(rev1.author, "jane@example.com")
	expect.equality(rev1.timestamp, "2024-03-15 10:30:42")
	expect.equality(rev1.commit_id, "230dd059")
	expect.equality(rev1.description, "Update README with examples")
	expect.equality(rev1.graph, "@  ")
	expect.equality(rev1.conflict, false)
	expect.equality(#rev1.bookmarks, 0)

	-- Check second revision
	local rev2 = result.revisions[2]
	expect.equality(rev2.change_id, "rlvkpnrz")
	expect.equality(rev2.author, "john@example.com")
	expect.equality(rev2.commit_id, "2443ea76")
	expect.equality(rev2.description, "Add initial implementation")

	-- Check that graph data is tracked
	expect.equality(type(result.graph_data), "table")
	-- The first line should have graph data with the revision
	expect.equality(result.graph_data[1].revision, rev1)
end

T["parse_log_output"]["parses the root commit"] = function()
	local output = read_fixture("log-graph-simple.txt")
	local result = log_parser.parse_log_output(output)

	-- The root commit has an all-zero change/commit id and must not be dropped.
	local root = result.revisions[4]
	expect.equality(root.change_id, "zzzzzzzz")
	expect.equality(root.commit_id, "00000000")
	expect.equality(root.author, "root@example.com")
	expect.equality(root.graph, "◆  ")
	expect.equality(root.description, "Initial commit")
end

T["parse_log_output"]["parses bookmarks from commit lines"] = function()
	local output = read_fixture("log-graph-bookmarks.txt")
	local result = log_parser.parse_log_output(output)

	-- Should have 4 revisions
	expect.equality(#result.revisions, 4)

	-- First revision has one bookmark
	local rev1 = result.revisions[1]
	expect.equality(rev1.change_id, "qpvuntsm")
	expect.equality(rev1.commit_id, "230dd059")
	expect.equality(#rev1.bookmarks, 1)
	expect.equality(rev1.bookmarks[1], "main")

	-- Second revision has two bookmarks
	local rev2 = result.revisions[2]
	expect.equality(rev2.change_id, "rlvkpnrz")
	expect.equality(rev2.commit_id, "2443ea76")
	expect.equality(#rev2.bookmarks, 2)
	expect.equality(rev2.bookmarks[1], "feature-branch")
	expect.equality(rev2.bookmarks[2], "dev")

	-- Third revision has no bookmarks
	local rev3 = result.revisions[3]
	expect.equality(rev3.change_id, "tknwxqrs")
	expect.equality(rev3.commit_id, "5621ab34")
	expect.equality(#rev3.bookmarks, 0)

	-- Fourth revision has one bookmark
	local rev4 = result.revisions[4]
	expect.equality(rev4.change_id, "zzzzzzzz")
	expect.equality(rev4.commit_id, "00000000")
	expect.equality(#rev4.bookmarks, 1)
	expect.equality(rev4.bookmarks[1], "release-v1.0")
end

T["parse_log_output"]["preserves tracking decorations on bookmarks"] = function()
	-- The log template uses jj's `bookmarks` keyword, so bookmarks carry jj's
	-- native tracking decorations: `name*` when a local bookmark is ahead of or
	-- differs from its remote, and `name@remote` for a remote-tracking bookmark
	-- shown on the commit it points to. The parser must preserve these intact,
	-- never stripping the `*` or `@remote`.
	local output = read_fixture("log-graph-tracked-bookmarks.txt")
	local result = log_parser.parse_log_output(output)

	expect.equality(#result.revisions, 3)

	-- Working copy: two local bookmarks, both ahead of their remotes.
	local rev1 = result.revisions[1]
	expect.equality(rev1.change_id, "kmtvxqpl")
	expect.equality(#rev1.bookmarks, 2)
	expect.equality(rev1.bookmarks[1], "feature*")
	expect.equality(rev1.bookmarks[2], "main*")

	-- The commit the remote points to shows the remote-tracking bookmark.
	local rev2 = result.revisions[2]
	expect.equality(rev2.change_id, "wzzywqlo")
	expect.equality(#rev2.bookmarks, 1)
	expect.equality(rev2.bookmarks[1], "main@origin")

	-- Decorations survive into the reconstructed display line as well.
	expect.equality(result.raw_lines[1]:find("feature* main*", 1, true) ~= nil, true)
	expect.equality(result.raw_lines[3]:find("main@origin", 1, true) ~= nil, true)

	-- No bookmark on the base commit.
	expect.equality(#result.revisions[3].bookmarks, 0)
end

T["parse_log_output"]["parses merge commits with complex graph"] = function()
	local output = read_fixture("log-graph-merge.txt")
	local result = log_parser.parse_log_output(output)

	-- Should have 5 revisions
	expect.equality(#result.revisions, 5)

	-- Check merge commit
	local merge = result.revisions[1]
	expect.equality(merge.change_id, "qpvuntsm")
	expect.equality(merge.description, "Merge feature and bugfix branches")
	expect.equality(merge.graph, "@    ")

	-- Check feature branch commit
	local feature = result.revisions[2]
	expect.equality(feature.change_id, "rlvkpnrz")
	expect.equality(feature.description, "Add new feature X")

	-- Check bugfix branch commit
	local bugfix = result.revisions[3]
	expect.equality(bugfix.change_id, "tknwxqrs")
	expect.equality(bugfix.description, "Fix critical bug in parser")
end

T["parse_log_output"]["parses conflicted commits (× node)"] = function()
	local output = read_fixture("log-graph-conflict.txt")
	local result = log_parser.parse_log_output(output)

	-- All three commits must be parsed, including the conflicted merge whose
	-- node glyph is `×` (previously silently dropped by the glyph allowlist).
	expect.equality(#result.revisions, 3)

	local conflicted = result.revisions[1]
	expect.equality(conflicted.change_id, "myrmppvl")
	expect.equality(conflicted.commit_id, "1ce52fde")
	expect.equality(conflicted.conflict, true)
	-- The `×` glyph is preserved in the gutter, not swallowed into the id, and
	-- the trailing "(conflict)" suffix does not corrupt commit_id/bookmarks.
	expect.equality(conflicted.graph:match("×"), "×")
	expect.equality(#conflicted.bookmarks, 1)
	expect.equality(conflicted.bookmarks[1], "conflict-state")

	-- Non-conflicted parents are still parsed correctly.
	expect.equality(result.revisions[2].change_id, "qluzpwwq")
	expect.equality(result.revisions[2].conflict, false)
	expect.equality(result.revisions[3].change_id, "nzqnkovr")
	expect.equality(result.revisions[3].conflict, false)
end

T["parse_log_output"]["parses divergent changes sharing a change id"] = function()
	local output = read_fixture("log-graph-divergent.txt")
	local result = log_parser.parse_log_output(output)

	expect.equality(#result.revisions, 3)

	-- Two visible commits share the same change_id but differ by commit_id;
	-- both must survive parsing.
	local a = result.revisions[1]
	local b = result.revisions[2]
	expect.equality(a.change_id, "mmmmmmmm")
	expect.equality(b.change_id, "mmmmmmmm")
	expect.equality(a.commit_id, "aaaa1111")
	expect.equality(b.commit_id, "bbbb2222")
	expect.equality(a.description, "Divergent change A")
	expect.equality(b.description, "Divergent change B")
end

T["parse_log_output"]["parses a lone root commit with empty fields"] = function()
	local output = read_fixture("log-graph-root.txt")
	local result = log_parser.parse_log_output(output)

	expect.equality(#result.revisions, 1)

	local root = result.revisions[1]
	expect.equality(root.change_id, "zzzzzzzz")
	expect.equality(root.commit_id, "00000000")
	expect.equality(root.author, "")
	expect.equality(#root.bookmarks, 0)
	expect.equality(root.conflict, false)
	expect.equality(root.description, "(no description set)")
end

T["parse_log_output"]["preserves raw lines free of control characters"] = function()
	local output = read_fixture("log-graph-simple.txt")
	local result = log_parser.parse_log_output(output)

	-- Should preserve all non-empty lines
	expect.equality(type(result.raw_lines), "table")
	expect.equality(#result.raw_lines > 0, true)

	-- Reconstructed lines must not leak the template's control characters.
	for _, line in ipairs(result.raw_lines) do
		expect.equality(line:find("\30"), nil)
		expect.equality(line:find("\31"), nil)
	end

	-- The first line renders the header fields in a stable, human order.
	expect.equality(result.raw_lines[1], "@  qpvuntsm jane@example.com 2024-03-15 10:30:42 230dd059")
end

T["parse_log_output"]["handles empty input"] = function()
	local result = log_parser.parse_log_output("")

	expect.equality(#result.revisions, 0)
	expect.equality(type(result.graph_data), "table")
	expect.equality(type(result.raw_lines), "table")
end

T["parse_log_output"]["extracts graph characters correctly"] = function()
	local output = read_fixture("log-graph-merge.txt")
	local result = log_parser.parse_log_output(output)

	-- Check that graph characters are preserved
	local merge = result.revisions[1]
	expect.equality(merge.graph:match("@"), "@")

	-- Check that graph data contains expected characters
	for _, graph_info in pairs(result.graph_data) do
		expect.equality(type(graph_info.graph), "string")
	end
end

T["parse_log_output"]["parses the optional unique-prefix fields"] = function()
	-- The template appends jj's unique disambiguating prefixes for the change and
	-- commit ids as two trailing fields (from id.shortest(8).prefix()). The parser
	-- must surface them so the UI can brighten the prefix and dim the rest.
	local output = "@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\031sq\031f\n"
		.. "│  \030Adding jj log support.\n"

	local result = log_parser.parse_log_output(output)

	expect.equality(#result.revisions, 1)
	local rev = result.revisions[1]
	expect.equality(rev.change_id, "sqmvkywl")
	expect.equality(rev.commit_id, "f35b8f36")
	expect.equality(rev.change_id_prefix, "sq")
	expect.equality(rev.commit_id_prefix, "f")
	-- The prefix fields must not leak into the reconstructed display line.
	expect.equality(result.raw_lines[1], "@  sqmvkywl user@example.com 2025-07-14 21:06:06 f35b8f36")
end

T["parse_log_output"]["leaves prefixes nil when the fields are absent or bogus"] = function()
	-- Older fixtures captured before the prefix fields existed must still parse,
	-- with the prefixes left nil (the UI then highlights the whole id).
	local without = "@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\n"
		.. "│  \030Adding jj log support.\n"
	local rev = log_parser.parse_log_output(without).revisions[1]
	expect.equality(rev.change_id_prefix, nil)
	expect.equality(rev.commit_id_prefix, nil)

	-- A prefix that is not a genuine leading substring of the id is rejected, so
	-- the UI never mis-splits the id.
	local bogus = "@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\031xy\031f\n"
		.. "│  \030Adding jj log support.\n"
	local rev2 = log_parser.parse_log_output(bogus).revisions[1]
	expect.equality(rev2.change_id_prefix, nil)
	expect.equality(rev2.commit_id_prefix, "f")
end

T["parse_log_output"]["parses the optional empty field"] = function()
	-- The template appends jj's own emptiness flag as a final field
	-- (if(empty, "empty", "")), after the two unique-prefix fields. The parser
	-- must surface it on the revision (its rendering lives on the description
	-- line, covered by a separate test).
	local empty = "@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\031\031\031empty\n"
		.. "│  \030Adding jj log support.\n"

	local rev = log_parser.parse_log_output(empty).revisions[1]
	expect.equality(rev.change_id, "sqmvkywl")
	expect.equality(rev.commit_id, "f35b8f36")
	expect.equality(rev.empty, true)
	expect.equality(rev.conflict, false)

	-- A non-empty commit (final field blank, or absent) parses as not empty.
	local nonempty = "@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\031\031\031\n"
		.. "│  \030Adding jj log support.\n"
	expect.equality(log_parser.parse_log_output(nonempty).revisions[1].empty, false)

	-- Older fixtures captured before the field existed lack it entirely (only six
	-- header fields); they must still parse as not empty.
	local legacy = "@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\n"
		.. "│  \030Adding jj log support.\n"
	expect.equality(log_parser.parse_log_output(legacy).revisions[1].empty, false)
end

T["parse_log_output"]["keeps (conflict) on the metadata row and (empty) on the description line"] = function()
	-- Matching `jj log`: "(conflict)" stays on the metadata row, while "(empty)"
	-- is rendered at the head of the description line below (never on the metadata
	-- row). The continuation line's graph_data is flagged so the UI can highlight
	-- the marker distinctly.
	local both = "×  \030myrmppvl\031user@example.com\0312025-07-14 21:06:06\031\0311ce52fde\031conflict\031\031\031empty\n"
		.. "│  \030Merge: Add config versions\n"

	local result = log_parser.parse_log_output(both)
	local rev = result.revisions[1]
	expect.equality(rev.empty, true)
	expect.equality(rev.conflict, true)

	-- Metadata row: "(conflict)" present, "(empty)" absent.
	local meta = result.raw_lines[1]
	expect.equality(meta:find("(conflict)", 1, true) ~= nil, true)
	expect.equality(meta:find("(empty)", 1, true), nil)

	-- Description row: "(empty)" prefixes the description text, flagged for the UI.
	local desc = result.raw_lines[2]
	expect.equality(desc:find("(empty) Merge: Add config versions", 1, true) ~= nil, true)
	expect.equality(result.graph_data[2].empty_marker, true)
end

T["parse_log_output"]["preserves ANSI escapes inside fields"] = function()
	-- Field splitting keys purely off the RECORD_SEP (\30) and UNIT_SEP (\31)
	-- control characters, so any ANSI colour escapes that leak into a field are
	-- carried through verbatim rather than corrupting the split. (jj is run with
	-- `--color never`, but the parser must not depend on that.)
	local esc = string.char(27)
	local coloured_id = esc .. "[1msqmvkywl" .. esc .. "[0m"
	local output = "@  \030"
		.. coloured_id
		.. "\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\n"
		.. "│  \030Adding jj log support.\n"

	local result = log_parser.parse_log_output(output)

	expect.equality(#result.revisions, 1)
	local rev = result.revisions[1]
	-- The escape-wrapped change id is preserved intact...
	expect.equality(rev.change_id, coloured_id)
	-- ...and the fields after it still split correctly on UNIT_SEP.
	expect.equality(rev.author, "user@example.com")
	expect.equality(rev.timestamp, "2025-07-14 21:06:06")
	expect.equality(rev.commit_id, "f35b8f36")
	expect.equality(rev.description, "Adding jj log support.")
end

return T
