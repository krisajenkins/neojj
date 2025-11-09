local T = MiniTest.new_set()
local expect = MiniTest.expect

-- Test suite for annotation buffer
T["AnnotateUI"] = MiniTest.new_set()

T["AnnotateUI"]["parse_annotate_line"] = function()
	local AnnotateUI = require("neojj.buffers.annotate.ui")

	-- Test parsing a valid line
	local line = "kznzoynu krisajen 2025-07-11 09:21:52    1: {"
	local parsed = AnnotateUI.parse_annotate_line(line)

	expect.no_equality(parsed, nil)
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

return T
