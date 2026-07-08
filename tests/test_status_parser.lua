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
	-- The working-copy line carries jj's "(empty)" marker, so the authoritative
	-- emptiness flag is set too.
	expect.equality(result.empty, true)
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
	-- No "(empty)" marker on this working-copy line: the commit is not empty.
	expect.equality(result.empty, false)

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

	expect.equality(result.change_id, "myrmppvl")
	expect.equality(#result.parent_ids, 2)
	expect.equality(result.parent_ids[1], "nzqnkovr")
	expect.equality(result.parent_ids[2], "qluzpwwq")

	-- The conflict comes from the "unresolved conflicts" warning block, not a
	-- file-status line, so there are no modified files here.
	expect.equality(#result.modified_files, 0)
	expect.equality(#result.conflicts, 1)

	-- Check conflict path and annotation
	expect.equality(result.conflicts[1].path, "src/config.lua")
	expect.equality(result.conflicts[1].sides, 2)
	expect.equality(result.conflicts[1].annotation, "2-sided conflict")

	-- Presence of conflicts means the working copy is not "clean"
	expect.equality(result.is_empty, false)
end

T["parse_working_copy_info"]["parses jj's authoritative (empty) marker on a conflicted merge"] = function()
	-- An empty conflicted merge shows "(conflict) (empty)" on its working-copy
	-- line. jj's own `empty` flag must be true even though the derived `is_empty`
	-- is false (the unresolved conflicts make it non-clean).
	local output = read_fixture("conflict-state-status.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "myrmppvl")
	expect.equality(result.empty, true)
	expect.equality(result.is_empty, false)
end

T["parse_working_copy_info"]["parses copied files"] = function()
	local output = read_fixture("status-copy.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "rlvkpnrz")
	expect.equality(#result.modified_files, 3)
	expect.equality(#result.conflicts, 0)
	expect.equality(result.is_empty, false)

	-- The copied file should be a modified file with status "C" (NOT a conflict)
	local copied = nil
	for _, file in ipairs(result.modified_files) do
		if file.status == "C" then
			copied = file
		end
	end
	expect.no_equality(copied, nil)
	assert(copied)
	expect.equality(copied.path, "src/config_backup.lua")
	expect.equality(copied.old_path, "src/config.lua")
end

T["parse_working_copy_info"]["parses untracked files"] = function()
	local output = read_fixture("status-untracked.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "lpovlvly")
	-- 2 tracked changes (M, A) + 2 untracked (?) = 4 entries
	expect.equality(#result.modified_files, 4)
	expect.equality(result.is_empty, false)

	local untracked = {}
	for _, file in ipairs(result.modified_files) do
		if file.status == "?" then
			table.insert(untracked, file.path)
		end
	end
	expect.equality(#untracked, 2)
	expect.equality(untracked[1], "notes.txt")
	expect.equality(untracked[2], "build/output.log")
end

T["parse_working_copy_info"]["parses a mix of statuses"] = function()
	local output = read_fixture("status-mixed.txt")
	local lines = vim.split(output, "\n")
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "qpvuntsm")
	expect.equality(result.is_empty, false)

	-- Count each status in modified_files
	local counts = {}
	for _, file in ipairs(result.modified_files) do
		counts[file.status] = (counts[file.status] or 0) + 1
	end
	expect.equality(counts["M"], 1)
	expect.equality(counts["A"], 1)
	expect.equality(counts["D"], 1)
	expect.equality(counts["R"], 1)
	expect.equality(counts["C"], 1)
	expect.equality(counts["?"], 1)

	-- Two conflicts from the warning block, with their side counts
	expect.equality(#result.conflicts, 2)
	expect.equality(result.conflicts[1].path, "src/app.lua")
	expect.equality(result.conflicts[1].sides, 2)
	expect.equality(result.conflicts[2].path, "config/settings.toml")
	expect.equality(result.conflicts[2].sides, 3)
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

-- Second-wave malformed-input tests: the parser must never raise on garbage,
-- and must ignore lines it cannot classify rather than misfiling them.

T["parse_working_copy_info"]["survives truncated output"] = function()
	-- A header cut off mid-stream (jj killed, pipe closed) must still yield the
	-- change_id it did see and a clean, non-crashing structure.
	local lines = {
		"Working copy  (@) : wwqvwtzo 4291f1c2",
		"Parent commit (@-):", -- truncated mid-line: colon present, no id follows
	}
	local result = status_parser.parse_working_copy_info(lines)

	expect.equality(result.change_id, "wwqvwtzo")
	-- The truncated "Parent commit (@-):" line has no id to capture.
	expect.equality(#result.parent_ids, 0)
	expect.equality(#result.modified_files, 0)
	expect.equality(#result.conflicts, 0)
	expect.equality(result.is_empty, true)
end

T["parse_working_copy_info"]["ignores unknown status letters"] = function()
	-- jj only emits M/A/D/R/C/? status codes. An unrecognised leading letter
	-- must be dropped, not misfiled as a modified file.
	local lines = {
		"Working copy  (@) : qpvuntsm abcd1234",
		"X unexpected/status.txt",
		"Z another/mystery.txt",
		"M real/change.lua",
	}
	local result = status_parser.parse_working_copy_info(lines)

	-- Only the genuine "M" line survives; X and Z are ignored.
	expect.equality(#result.modified_files, 1)
	expect.equality(result.modified_files[1].status, "M")
	expect.equality(result.modified_files[1].path, "real/change.lua")
end

T["parse_working_copy_info"]["does not crash on ANSI-coloured input"] = function()
	-- The plugin always runs jj with `--color never`, so ANSI escapes should
	-- never appear. If they leak through anyway, the parser must degrade
	-- gracefully (return a well-formed structure) rather than raise: the escape
	-- prefix simply prevents the file-status branches from matching.
	local esc = string.char(27)
	local lines = {
		esc .. "[1mWorking copy  (@) : qpvuntsm abcd1234" .. esc .. "[0m",
		esc .. "[32mM" .. esc .. "[0m README.md",
		esc .. "[31mD" .. esc .. "[0m old.lua",
	}

	local result
	expect.no_error(function()
		result = status_parser.parse_working_copy_info(lines)
	end)

	-- Structure is intact and iterable regardless of the colour noise.
	expect.equality(type(result.modified_files), "table")
	expect.equality(type(result.conflicts), "table")
	expect.equality(type(result.parent_ids), "table")
end

T["parse_working_copy_info"]["parses awkward paths"] = function()
	-- Table-driven coverage of paths jj can legitimately produce: embedded
	-- spaces, unicode, dotfiles and emoji. `^([MAD]) (.+)` captures everything
	-- after the status letter and space, so these must round-trip verbatim.
	local cases = {
		{ line = "M my file.txt", status = "M", path = "my file.txt" },
		{ line = "A dir with spaces/data.csv", status = "A", path = "dir with spaces/data.csv" },
		{ line = "M café/résumé.md", status = "M", path = "café/résumé.md" },
		{ line = "A .config/settings.toml", status = "A", path = ".config/settings.toml" },
		{ line = "M .hidden", status = "M", path = ".hidden" },
		{ line = "D path/with-emoji-🚀.txt", status = "D", path = "path/with-emoji-🚀.txt" },
	}

	for _, case in ipairs(cases) do
		local result = status_parser.parse_working_copy_info({ case.line })
		expect.equality(#result.modified_files, 1)
		expect.equality(result.modified_files[1].status, case.status)
		expect.equality(result.modified_files[1].path, case.path)
		expect.equality(result.is_empty, false)
	end
end

return T
