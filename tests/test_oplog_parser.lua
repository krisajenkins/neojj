local MiniTest = require("mini.test")
local T = MiniTest.new_set()
local expect = MiniTest.expect

local oplog_parser = require("neojj.lib.jj.parsers.oplog_parser")

local read_fixture = require("tests.helpers.fixtures").read_fixture

T["parse_oplog_output"] = MiniTest.new_set()

T["parse_oplog_output"]["parses a simple linear operation history"] = function()
	local output = read_fixture("oplog-graph-simple.txt")
	local result = oplog_parser.parse_oplog_output(output)

	-- Should have 3 operations
	expect.equality(#result.operations, 3)

	-- Check first (current) operation
	local op1 = result.operations[1]
	expect.equality(op1.operation_id, "a1b2c3d4e5f6")
	expect.equality(op1.user, "jane@example.com")
	expect.equality(op1.time_start, "2024-03-15 10:30:42")
	expect.equality(op1.time_end, "2024-03-15 10:30:43")
	expect.equality(op1.description, "commit working copy")
	expect.equality(op1.is_current, true)
	expect.equality(op1.graph, "@  ")

	-- Second operation is not current
	local op2 = result.operations[2]
	expect.equality(op2.operation_id, "9f8e7d6c5b4a")
	expect.equality(op2.user, "john@example.com")
	expect.equality(op2.description, "describe commit abc123")
	expect.equality(op2.is_current, false)

	-- Third operation
	local op3 = result.operations[3]
	expect.equality(op3.operation_id, "1122334455aa")
	expect.equality(op3.description, "initialize repo")
	expect.equality(op3.is_current, false)
end

T["parse_oplog_output"]["tracks graph data per line"] = function()
	local output = read_fixture("oplog-graph-simple.txt")
	local result = oplog_parser.parse_oplog_output(output)

	expect.equality(type(result.graph_data), "table")
	-- The first line's graph data references the first operation.
	expect.equality(result.graph_data[1].operation, result.operations[1])
	-- The second line is a description continuation (no operation).
	expect.equality(result.graph_data[2].operation, nil)
end

T["parse_oplog_output"]["preserves raw lines free of control characters"] = function()
	local output = read_fixture("oplog-graph-simple.txt")
	local result = oplog_parser.parse_oplog_output(output)

	expect.equality(type(result.raw_lines), "table")
	expect.equality(#result.raw_lines > 0, true)

	for _, line in ipairs(result.raw_lines) do
		expect.equality(line:find("\30"), nil)
		expect.equality(line:find("\31"), nil)
	end

	-- The first line renders the header fields in a stable, human order.
	expect.equality(result.raw_lines[1], "@  a1b2c3d4e5f6 jane@example.com 2024-03-15 10:30:42")
end

T["parse_oplog_output"]["handles empty input"] = function()
	local result = oplog_parser.parse_oplog_output("")

	expect.equality(#result.operations, 0)
	expect.equality(type(result.graph_data), "table")
	expect.equality(type(result.raw_lines), "table")
end

T["parse_oplog_output"]["parses inline sample output"] = function()
	-- "\30" is the record separator (graph|payload); "\31" separates fields.
	local sample = "@  \030abc123def456\031user@example.com\0312025-01-01 12:00:00\0312025-01-01 12:00:01\n"
		.. "│  \030push bookmark main\n"
		.. "○  \030fed654cba321\031user@example.com\0312025-01-01 11:00:00\0312025-01-01 11:00:00\n"
		.. "│  \030new empty change\n"

	local result = oplog_parser.parse_oplog_output(sample)

	expect.equality(#result.operations, 2)
	expect.equality(result.operations[1].operation_id, "abc123def456")
	expect.equality(result.operations[1].is_current, true)
	expect.equality(result.operations[1].description, "push bookmark main")
	expect.equality(result.operations[2].operation_id, "fed654cba321")
	expect.equality(result.operations[2].is_current, false)
	expect.equality(result.operations[2].description, "new empty change")
end

T["parse_oplog_output"]["preserves ANSI escapes inside fields"] = function()
	-- Field splitting keys purely off RECORD_SEP (\30) and UNIT_SEP (\31), so any
	-- ANSI colour escapes that leak into a field are carried through verbatim.
	local esc = string.char(27)
	local coloured_id = esc .. "[1mabc123def456" .. esc .. "[0m"
	local output = "@  \030"
		.. coloured_id
		.. "\031user@example.com\0312025-01-01 12:00:00\0312025-01-01 12:00:01\n"
		.. "│  \030push bookmark main\n"

	local result = oplog_parser.parse_oplog_output(output)

	expect.equality(#result.operations, 1)
	local op = result.operations[1]
	expect.equality(op.operation_id, coloured_id)
	expect.equality(op.user, "user@example.com")
	expect.equality(op.time_start, "2025-01-01 12:00:00")
	expect.equality(op.description, "push bookmark main")
end

return T
