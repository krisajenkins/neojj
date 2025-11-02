local MiniTest = require("mini.test")
local T = MiniTest.new_set()
local expect = MiniTest.expect

local status_parser = require("neojj.lib.jj.parsers.status_parser")

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

T["parse_working_copy_info"] = MiniTest.new_set()

T["parse_working_copy_info"]["parses clean status"] = function()
	local output = read_fixture("status-clean.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "qpvuntsm")
	expect.equality(#result.parent_ids, 1)
	expect.equality(result.parent_ids[1], "rlvkpnrz")
	expect.equality(#result.modified_files, 0)
	expect.equality(#result.conflicts, 0)
	expect.equality(result.is_empty, true)
end

T["parse_working_copy_info"]["parses modified files"] = function()
	local output = read_fixture("status-modified.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "qpvuntsm")
	expect.equality(result.author.name, "Jane Doe")
	expect.equality(result.author.email, "jane@example.com")
	expect.equality(#result.modified_files, 3)
	expect.equality(result.is_empty, false)

	-- Check modified file
	expect.equality(result.modified_files[1].status, "M")
	expect.equality(result.modified_files[1].path, "README.md")

	-- Check added file
	expect.equality(result.modified_files[2].status, "A")
	expect.equality(result.modified_files[2].path, "examples/demo.lua")

	-- Check deleted file
	expect.equality(result.modified_files[3].status, "D")
	expect.equality(result.modified_files[3].path, "old_config.lua")
end

T["parse_working_copy_info"]["parses conflicts"] = function()
	local output = read_fixture("status-conflicts.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "qpvuntsm")
	expect.equality(#result.parent_ids, 2)
	expect.equality(result.parent_ids[1], "rlvkpnrz")
	expect.equality(result.parent_ids[2], "tknwxqrs")
	expect.equality(#result.modified_files, 2)
	expect.equality(#result.conflicts, 1)

	-- Check conflict
	expect.equality(result.conflicts[1].path, "config/settings.lua")
end

T["parse_working_copy_info"]["parses merge with multiple parents"] = function()
	local output = read_fixture("status-merge.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "qpvuntsm")
	expect.equality(#result.parent_ids, 3)
	expect.equality(result.parent_ids[1], "rlvkpnrz")
	expect.equality(result.parent_ids[2], "tknwxqrs")
	expect.equality(result.parent_ids[3], "xmplqrst")
	expect.equality(result.author.name, "John Smith")
	expect.equality(result.author.email, "john@example.com")
	expect.equality(#result.modified_files, 3)
	expect.equality(result.is_empty, false)
end

T["parse_working_copy_info"]["handles empty input"] = function()
	local result = status_parser.parse_working_copy_info({})

	expect.equality(result.change_id, nil)
	expect.equality(#result.parent_ids, 0)
	expect.equality(#result.modified_files, 0)
	expect.equality(#result.conflicts, 0)
	expect.equality(result.is_empty, true)
end

return T
