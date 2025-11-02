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
	expect.equality(rev1.commit_id, "230dd059")
	expect.equality(rev1.description, "Update README with examples")
	expect.equality(rev1.graph, "@  ")

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

T["parse_log_output"]["preserves raw lines"] = function()
	local output = read_fixture("log-graph-simple.txt")
	local result = log_parser.parse_log_output(output)

	-- Should preserve all non-empty lines
	expect.equality(type(result.raw_lines), "table")
	expect.equality(#result.raw_lines > 0, true)
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
	for line_num, graph_info in pairs(result.graph_data) do
		expect.equality(type(graph_info.graph), "string")
	end
end

return T
