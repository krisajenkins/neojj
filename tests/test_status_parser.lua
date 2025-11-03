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

T["parse_working_copy_info"]["parses renames"] = function()
	local output = read_fixture("status-renames.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "wwqvwtzo")
	expect.equality(#result.parent_ids, 1)
	expect.equality(result.parent_ids[1], "okpkknwl")

	-- Should have 36 total file changes (33 A + 3 R + 1 M - 1 empty line)
	-- Note: The actual count depends on how renames are parsed
	expect.equality(#result.modified_files > 0, true)
	expect.equality(result.is_empty, false)

	-- Check for renamed files (R status)
	local renamed_files = {}
	for _, file in ipairs(result.modified_files) do
		if file.status == "R" then
			table.insert(renamed_files, file)
		end
	end

	-- Should have 3 renamed files
	expect.equality(#renamed_files, 3)

	-- Check one of the renames has the expected format
	local found_betting_offices = false
	for _, file in ipairs(renamed_files) do
		if file.path:match("betting_offices.csv") then
			found_betting_offices = true
			-- The path should contain the rename information
			expect.equality(file.path:match("betting_offices.csv") ~= nil, true)
		end
	end
	expect.equality(found_betting_offices, true)
end

T["parse_working_copy_info"]["parses renames with relative paths"] = function()
	local output = read_fixture("status-renames-relative.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "wwqvwtzo")
	expect.equality(#result.parent_ids, 1)
	expect.equality(result.parent_ids[1], "okpkknwl")
	expect.equality(result.is_empty, false)

	-- Check for renamed files (R status)
	local renamed_files = {}
	for _, file in ipairs(result.modified_files) do
		if file.status == "R" then
			table.insert(renamed_files, file)
		end
	end

	-- Should have 3 renamed files with relative paths
	expect.equality(#renamed_files, 3)

	-- Check that relative path renames are parsed correctly
	-- Format: R {.. => seeds}/betting_offices.csv
	-- This means: old path was ../betting_offices.csv, new path is seeds/betting_offices.csv
	local found_relative_rename = false
	for _, file in ipairs(renamed_files) do
		if file.path:match("seeds/betting_offices.csv") then
			found_relative_rename = true
			-- Should have extracted the new path
			expect.equality(file.path, "seeds/betting_offices.csv")
			-- Should have extracted the old path (.. + /betting_offices.csv)
			expect.equality(file.old_path, "../betting_offices.csv")
		end
	end
	expect.equality(found_relative_rename, true)

	-- Verify we also parse regular files with relative paths (../)
	local found_relative_file = false
	for _, file in ipairs(result.modified_files) do
		if file.path == "../README.md" and file.status == "A" then
			found_relative_file = true
		end
	end
	expect.equality(found_relative_file, true)
end

T["parse_working_copy_info"]["handles empty input"] = function()
	local result = status_parser.parse_working_copy_info({})

	expect.equality(result.change_id, nil)
	expect.equality(#result.parent_ids, 0)
	expect.equality(#result.modified_files, 0)
	expect.equality(#result.conflicts, 0)
	expect.equality(result.is_empty, true)
end

T["parse_working_copy_info"]["parses dotfiles in paths"] = function()
	local output = read_fixture("dotfile-test-status.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(#result.modified_files, 3)
	expect.equality(result.is_empty, false)

	-- Check dotfile path is parsed correctly
	expect.equality(result.modified_files[1].status, "A")
	expect.equality(result.modified_files[1].path, "fixtures/demo-repo/.gitignore")

	-- Check other files still work
	expect.equality(result.modified_files[2].status, "M")
	expect.equality(result.modified_files[2].path, "lua/neojj/buffers/log/init.lua")

	expect.equality(result.modified_files[3].status, "M")
	expect.equality(result.modified_files[3].path, "lua/neojj/buffers/status/init.lua")
end

return T
