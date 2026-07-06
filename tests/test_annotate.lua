local T = MiniTest.new_set()
local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

-- Test suite for annotation buffer
T["AnnotateUI"] = MiniTest.new_set()

T["AnnotateUI"]["parse_annotate_line"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	-- Test parsing a valid line
	local line = "kznzoynu krisajen 2025-07-11 09:21:52    1: {"
	local parsed = AnnotateUI.parse_annotate_line(line)

	expect.no_equality(parsed, nil)
	assert(parsed)
	expect.equality(parsed.change_id, "kznzoynu")
	expect.equality(parsed.author, "krisajen")
	expect.equality(parsed.date, "2025-07-11")
	expect.equality(parsed.full_timestamp, "2025-07-11 09:21:52")
end

T["AnnotateUI"]["parse_annotate_line handles ANSI codes"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	-- Line with ANSI color codes (like actual jj output)
	local line =
		"\27[1m\27[38;5;5mkz\27[0m\27[38;5;8mnzoynu\27[39m \27[38;5;3mkrisajen\27[39m \27[38;5;6m2025-07-11 09:21:52\27[39m    1: {"
	local parsed = AnnotateUI.parse_annotate_line(line)

	expect.no_equality(parsed, nil)
	assert(parsed)
	expect.equality(parsed.change_id, "kznzoynu")
	expect.equality(parsed.author, "krisajen")
	expect.equality(parsed.date, "2025-07-11")
end

T["AnnotateUI"]["collapse_annotations single line"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local annotations = {
		{ change_id = "abc123", author = "user", date = "2025-01-01" },
	}

	local collapsed = AnnotateUI.collapse_annotations(annotations)

	expect.equality(#collapsed, 1)
	expect.equality(collapsed[1].type, "full")
	expect.equality(collapsed[1].change_id, "abc123")
end

T["AnnotateUI"]["collapse_annotations consecutive identical"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local annotations = {
		{ change_id = "abc123", author = "user", date = "2025-01-01" },
		{ change_id = "abc123", author = "user", date = "2025-01-01" },
		{ change_id = "abc123", author = "user", date = "2025-01-01" },
		{ change_id = "abc123", author = "user", date = "2025-01-01" },
	}

	local collapsed = AnnotateUI.collapse_annotations(annotations)

	-- Should be: full, continuation, continuation, end_marker
	expect.equality(#collapsed, 4)
	expect.equality(collapsed[1].type, "full")
	expect.equality(collapsed[2].type, "continuation")
	expect.equality(collapsed[3].type, "continuation")
	expect.equality(collapsed[4].type, "end_marker")
end

T["AnnotateUI"]["collapse_annotations multiple blocks"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local annotations = {
		{ change_id = "aaa", author = "user1", date = "2025-01-01" },
		{ change_id = "aaa", author = "user1", date = "2025-01-01" },
		{ change_id = "bbb", author = "user2", date = "2025-01-02" },
		{ change_id = "bbb", author = "user2", date = "2025-01-02" },
		{ change_id = "aaa", author = "user1", date = "2025-01-01" },
	}

	local collapsed = AnnotateUI.collapse_annotations(annotations)

	-- Block 1 (aaa): full, end_marker
	-- Block 2 (bbb): full, end_marker
	-- Block 3 (aaa): full (single)
	expect.equality(#collapsed, 5)
	expect.equality(collapsed[1].type, "full")
	expect.equality(collapsed[1].change_id, "aaa")
	expect.equality(collapsed[2].type, "end_marker")
	expect.equality(collapsed[3].type, "full")
	expect.equality(collapsed[3].change_id, "bbb")
	expect.equality(collapsed[4].type, "end_marker")
	expect.equality(collapsed[5].type, "full")
	expect.equality(collapsed[5].change_id, "aaa")
end

T["AnnotateUI"]["format_annotation full"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local annotation = {
		type = "full",
		change_id = "kznzoynu",
		author = "krisajen",
		date = "2025-07-11",
	}

	local formatted = AnnotateUI.format_annotation(annotation)

	-- Should fit in 30 columns and include all info
	-- Check that it's a non-empty string
	expect.no_equality(formatted, "")
	-- Check that the string contains the key parts
	local has_change_id = formatted:match("kznzoynu") ~= nil
	-- Author is truncated to 7 chars for 30-column width
	local has_author = formatted:match("krisaje") ~= nil
	local has_date = formatted:match("2025%-07%-11") ~= nil
	expect.equality(has_change_id, true)
	expect.equality(has_author, true)
	expect.equality(has_date, true)
end

T["AnnotateUI"]["format_annotation continuation"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local annotation = {
		type = "continuation",
	}

	local formatted = AnnotateUI.format_annotation(annotation)
	expect.equality(formatted, "│")
end

T["AnnotateUI"]["format_annotation end_marker"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local annotation = {
		type = "end_marker",
	}

	local formatted = AnnotateUI.format_annotation(annotation)
	expect.equality(formatted, "o")
end

T["AnnotateUI"]["create generates components"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	local output = [[
kznzoynu krisajen 2025-07-11 09:21:52    1: line 1
kznzoynu krisajen 2025-07-11 09:21:52    2: line 2
abcdefgh testuser 2025-07-12 10:00:00    3: line 3
]]

	local components = AnnotateUI.create(output)

	-- Should have at least some components
	expect.no_equality(#components, 0)

	-- First component should be for kznzoynu
	-- Second should be end marker (since there are 2 kznzoynu lines)
	-- Third should be for abcdefgh
	expect.equality(#components, 3)
end

-- Cursor parsing tests need a real buffer/window so component position tracking
-- and cursor movement are exercised, so they run in a child Neovim.
T["cursor"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.bo.readonly = false
			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ expect = require('mini.test').expect ]])
			-- Helper: render annotate output into a real buffer wrapped in a
			-- minimal AnnotateBuffer, then return its change id at a given line.
			child.lua([[
				local AnnotateUI = require('neojj.buffers.annotate.ui')
				local AnnotateBuffer = require('neojj.buffers.annotate')
				local Buffer = require('neojj.lib.buffer')

				_G.change_id_at = function(output, line)
					local buffer = Buffer.create({
						name = "Test Annotate",
						filetype = "neojj-annotate-test",
						kind = "split",
						modifiable = false,
						readonly = true,
					})
					buffer:open()
					buffer:render(AnnotateUI.create(output))

					local ab = setmetatable({ buffer = buffer }, AnnotateBuffer)
					buffer:set_cursor(line, 0)
					local id = ab:get_change_id_at_cursor()
					buffer:close()
					return id
				end
			]])
		end,
		post_once = child.stop,
	},
})

T["cursor"]["no annotations line yields no change id"] = function()
	local id = child.lua_get([[change_id_at("", 1)]])
	expect.equality(id, vim.NIL)
end

T["cursor"]["full line yields untruncated change id"] = function()
	-- change_id is 12 chars; the display form is truncated to 8 but the item
	-- must carry the full id.
	local output = "kznzoynuvwxy krisajen 2025-07-11 09:21:52    1: line 1\n"
	local id = child.lua_get(string.format("change_id_at(%q, 1)", output))
	expect.equality(id, "kznzoynuvwxy")
end

T["cursor"]["continuation and end-marker lines resolve to parent change id"] = function()
	-- Three consecutive identical change ids collapse to full/continuation/
	-- end_marker rows. The cursor on any of those rows should resolve to the
	-- same parent change id.
	local output = table.concat({
		"abcdefghijkl user 2025-01-01 00:00:00    1: a",
		"abcdefghijkl user 2025-01-01 00:00:00    2: b",
		"abcdefghijkl user 2025-01-01 00:00:00    3: c",
		"",
	}, "\n")

	expect.equality(child.lua_get(string.format("change_id_at(%q, 1)", output)), "abcdefghijkl")
	expect.equality(child.lua_get(string.format("change_id_at(%q, 2)", output)), "abcdefghijkl")
	expect.equality(child.lua_get(string.format("change_id_at(%q, 3)", output)), "abcdefghijkl")
end

return T
