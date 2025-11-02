local MiniTest = require("mini.test")
local T = MiniTest.new_set()
local expect = MiniTest.expect

local json_parser = require("neojj.lib.jj.parsers.json_parser")

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

T["parse_log_json"] = MiniTest.new_set()

T["parse_log_json"]["parses valid JSON"] = function()
	local json_str = read_fixture("log-json-working-copy.json")
	local result, err = json_parser.parse_log_json(json_str)

	expect.equality(err, nil)
	expect.equality(type(result), "table")
	expect.equality(result.change_id, "qpvuntsmnoplqrstvwxyzabcdefghijklmnopqrst")
	expect.equality(result.commit_id, "230dd0593f8a2b1c4d5e6f7890abcdef12345678")
	expect.equality(result.working_copy, true)
	expect.equality(result.conflict, false)
end

T["parse_log_json"]["parses author information"] = function()
	local json_str = read_fixture("log-json-working-copy.json")
	local result, err = json_parser.parse_log_json(json_str)

	expect.equality(err, nil)
	expect.equality(type(result.author), "table")
	expect.equality(result.author.name, "Jane Doe")
	expect.equality(result.author.email, "jane@example.com")
	expect.equality(type(result.author.timestamp), "table")
end

T["parse_log_json"]["parses arrays"] = function()
	local json_str = read_fixture("log-json-working-copy.json")
	local result, err = json_parser.parse_log_json(json_str)

	expect.equality(err, nil)
	expect.equality(type(result.parents), "table")
	expect.equality(#result.parents, 1)
	expect.equality(result.parents[1], "2443ea76f1b2c3d4e5f67890abcdef1234567890")
	expect.equality(type(result.bookmarks), "table")
	expect.equality(#result.bookmarks, 0)
end

T["parse_log_json"]["handles invalid JSON"] = function()
	local result, err = json_parser.parse_log_json("not valid json {{{")

	expect.equality(result, nil)
	expect.equality(type(err), "string")
	expect.equality(err:match("Failed to parse JSON"), "Failed to parse JSON")
end

T["parse_log_json"]["handles non-object JSON"] = function()
	local result, err = json_parser.parse_log_json('"just a string"')

	expect.equality(result, nil)
	expect.equality(type(err), "string")
	expect.equality(err:match("Expected JSON object"), "Expected JSON object")
end

T["json_to_working_copy"] = MiniTest.new_set()

T["json_to_working_copy"]["converts JSON to WorkingCopy"] = function()
	local json_str = read_fixture("log-json-working-copy.json")
	local log_json, err = json_parser.parse_log_json(json_str)
	expect.equality(err, nil)

	local working_copy = json_parser.json_to_working_copy(log_json)

	expect.equality(working_copy.change_id, "qpvuntsmnoplqrstvwxyzabcdefghijklmnopqrst")
	expect.equality(working_copy.commit_id, "230dd0593f8a2b1c4d5e6f7890abcdef12345678")
	expect.equality(type(working_copy.description), "string")
	expect.equality(working_copy.description:match("Update README"), "Update README")
end

T["json_to_working_copy"]["extracts author information"] = function()
	local json_str = read_fixture("log-json-working-copy.json")
	local log_json, err = json_parser.parse_log_json(json_str)
	expect.equality(err, nil)

	local working_copy = json_parser.json_to_working_copy(log_json)

	expect.equality(working_copy.author.name, "Jane Doe")
	expect.equality(working_copy.author.email, "jane@example.com")
end

T["json_to_working_copy"]["extracts parent IDs"] = function()
	local json_str = read_fixture("log-json-working-copy.json")
	local log_json, err = json_parser.parse_log_json(json_str)
	expect.equality(err, nil)

	local working_copy = json_parser.json_to_working_copy(log_json)

	expect.equality(#working_copy.parent_ids, 1)
	expect.equality(working_copy.parent_ids[1], "2443ea76f1b2c3d4e5f67890abcdef1234567890")
end

T["json_to_working_copy"]["handles missing fields gracefully"] = function()
	local minimal_json = {
		change_id = "abc123",
		commit_id = "def456",
	}

	local working_copy = json_parser.json_to_working_copy(minimal_json)

	expect.equality(working_copy.change_id, "abc123")
	expect.equality(working_copy.commit_id, "def456")
	expect.equality(working_copy.description, "")
	expect.equality(working_copy.author.name, "")
	expect.equality(working_copy.author.email, "")
	expect.equality(#working_copy.parent_ids, 0)
end

T["parse_json_lines"] = MiniTest.new_set()

T["parse_json_lines"]["parses multiple JSON objects"] = function()
	-- Create multi-line JSON (one object per line)
	local line1 = '{"change_id":"abc123","commit_id":"def456","description":"First"}'
	local line2 = '{"change_id":"ghi789","commit_id":"jkl012","description":"Second"}'
	local output = line1 .. "\n" .. line2

	local results, errors = json_parser.parse_json_lines(output)

	expect.equality(#errors, 0)
	expect.equality(#results, 2)
	expect.equality(results[1].change_id, "abc123")
	expect.equality(results[2].change_id, "ghi789")
end

T["parse_json_lines"]["handles mixed valid and invalid lines"] = function()
	local output = '{"change_id":"abc123"}\ninvalid json\n{"change_id":"def456"}'

	local results, errors = json_parser.parse_json_lines(output)

	expect.equality(#results, 2)
	expect.equality(#errors, 1)
	expect.equality(errors[1]:match("Line 2"), "Line 2")
end

T["parse_json_lines"]["skips empty lines"] = function()
	local output = '{"change_id":"abc123"}\n\n{"change_id":"def456"}\n'

	local results, errors = json_parser.parse_json_lines(output)

	expect.equality(#errors, 0)
	expect.equality(#results, 2)
end

return T
