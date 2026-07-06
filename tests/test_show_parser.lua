local MiniTest = require("mini.test")
local T = MiniTest.new_set()
local expect = MiniTest.expect

-- parse_show_output is a StatusBuffer method, but its body never touches `self`,
-- so we invoke it as a plain function with a nil `self`.
local StatusBuffer = require("neojj.buffers.status")

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

local function parse(filename)
	-- parse_show_output never touches `self`, so we invoke it statically with nil.
	---@diagnostic disable-next-line: param-type-mismatch
	return StatusBuffer.parse_show_output(nil, read_fixture(filename))
end

---Build a { path -> status } map for the modified files of a parsed result.
local function files_by_path(result)
	local map = {}
	for _, file in ipairs(result.modified_files) do
		map[file.path] = file.status
	end
	return map
end

T["parse_show_output"] = MiniTest.new_set()

T["parse_show_output"]["parses a single added file"] = function()
	local result = parse("initial-show-at.txt")

	expect.equality(result.change_id, "ttokvzsnktvrtyppqxunwtmovknuwvmu")
	expect.equality(result.commit_id, "cdad2788bf9615e2307a969704f38cc33b745483")
	expect.equality(result.author, "Test User <test@example.com> (2024-01-01 12:00:00)")
	expect.equality(result.committer, "Test User <test@example.com> (2024-01-01 12:00:00)")

	expect.equality(#result.modified_files, 1)
	expect.equality(result.modified_files[1].path, ".gitignore")
	expect.equality(result.modified_files[1].status, "A")
	expect.equality(result.is_empty, false)
end

T["parse_show_output"]["parses multiple added files"] = function()
	local result = parse("feature-start-show-at.txt")

	expect.equality(result.change_id, "kmkxlsonrlvvrpwpvwwzmxsxomtvtmqz")
	expect.equality(result.commit_id, "d2b46e5296d8a1052b16b4a2a033af627612ae18")

	expect.equality(#result.modified_files, 3)
	local files = files_by_path(result)
	expect.equality(files["src/main.lua"], "A")
	expect.equality(files["src/utils.lua"], "A")
	expect.equality(files["tests/test_main.lua"], "A")
	expect.equality(result.is_empty, false)
end

T["parse_show_output"]["parses a mix of modified, deleted and added files"] = function()
	local result = parse("multiple-changes-show-at.txt")

	expect.equality(result.change_id, "rszmmswmqkrpywtkuuvmrvsvyvnlntmp")
	expect.equality(result.commit_id, "f812d13fcf7bd1e7c734028dbac03c4149da7ef6")
	expect.equality(result.author, "Test User <test@example.com> (2024-01-01 12:00:00)")

	expect.equality(#result.modified_files, 4)
	local files = files_by_path(result)
	-- Modified: has an index header but no new/deleted-file-mode line.
	expect.equality(files["src/main.lua"], "M")
	-- Deleted: "deleted file mode" header.
	expect.equality(files["src/utils.lua"], "D")
	-- Added: "new file mode" header.
	expect.equality(files["temp.txt"], "A")
	expect.equality(files["tests/test_new.lua"], "A")
	expect.equality(result.is_empty, false)
end

T["parse_show_output"]["treats a diffless merge commit as empty"] = function()
	local result = parse("merge-state-show-at.txt")

	expect.equality(result.change_id, "xsmlzlpqlwvpnpqqokywmymornuplmtx")
	expect.equality(result.commit_id, "8b050db224f6851c4a91c8b42512a38e75505b4a")
	expect.equality(result.committer, "Test User <test@example.com> (2024-01-01 12:00:00)")

	expect.equality(#result.modified_files, 0)
	expect.equality(result.is_empty, true)
end

T["parse_show_output"]["treats a diffless conflict commit as empty"] = function()
	local result = parse("conflict-state-show-at.txt")

	expect.equality(result.change_id, "myrmppvlrnxrvlkrptqqzkosuxxtswyu")
	expect.equality(result.commit_id, "1ce52fdeb457ed3feaa859c2a8abc39bb47f71a2")

	expect.equality(#result.modified_files, 0)
	expect.equality(result.is_empty, true)
end

T["parse_show_output"]["returns empty result for empty output"] = function()
	---@diagnostic disable-next-line: param-type-mismatch
	local result = StatusBuffer.parse_show_output(nil, "")

	expect.equality(result.change_id, nil)
	expect.equality(result.commit_id, nil)
	expect.equality(#result.modified_files, 0)
	expect.equality(result.is_empty, true)
end

return T
