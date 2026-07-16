-- Unit tests for the shared parser leaf helpers (neojj.lib.jj.parsers.record).
-- These two functions are exercised indirectly by the log / oplog / opshow
-- parser tests, but their edge cases — especially valid_prefix's guards — are
-- branchy enough to warrant direct coverage now that they live in one module.
-- Both are pure Lua (string.match only), so they run in-process, matching the
-- log/oplog parser tests rather than needing a child Neovim.
local MiniTest = require("mini.test")
local T = MiniTest.new_set()
local expect = MiniTest.expect

local record = require("neojj.lib.jj.parsers.record")

local RS = "\30" -- RECORD SEPARATOR (0x1e): gutter | payload boundary
local US = "\31" -- UNIT SEPARATOR   (0x1f): field boundary within a payload

T["split_gutter"] = MiniTest.new_set()

--- A line with a gutter and payload splits at the record separator.
T["split_gutter"]["splits at the record separator"] = function()
	local gutter, payload = record.split_gutter("@  " .. RS .. "abc" .. US .. "def")
	expect.equality(gutter, "@  ")
	expect.equality(payload, "abc" .. US .. "def")
end

--- An empty gutter (payload starts at column 1) is preserved as "".
T["split_gutter"]["preserves an empty gutter"] = function()
	local gutter, payload = record.split_gutter(RS .. "payload")
	expect.equality(gutter, "")
	expect.equality(payload, "payload")
end

--- A graph-only connector line (no record separator) returns (line, nil).
T["split_gutter"]["returns nil payload for a graph-only line"] = function()
	local gutter, payload = record.split_gutter("├─╮")
	expect.equality(gutter, "├─╮")
	expect.equality(payload, nil)
end

--- A record separator with nothing after it yields an empty-string payload
--- (not nil): the line IS a record, just with an empty payload.
T["split_gutter"]["yields an empty (not nil) payload after a trailing separator"] = function()
	local gutter, payload = record.split_gutter("○ " .. RS)
	expect.equality(gutter, "○ ")
	expect.equality(payload, "")
	expect.no_equality(payload, nil)
end

--- Splitting is non-greedy: it breaks at the FIRST record separator, so a
--- payload that itself contains one keeps the remainder intact.
T["split_gutter"]["splits on the first separator only"] = function()
	local gutter, payload = record.split_gutter("@" .. RS .. "a" .. RS .. "b")
	expect.equality(gutter, "@")
	expect.equality(payload, "a" .. RS .. "b")
end

T["valid_prefix"] = MiniTest.new_set()

--- A genuine leading prefix that is strictly shorter than the id is kept.
T["valid_prefix"]["keeps a leading prefix shorter than the id"] = function()
	expect.equality(record.valid_prefix("abcdef123", "abc"), "abc")
end

--- A nil prefix is rejected.
T["valid_prefix"]["rejects a nil prefix"] = function()
	expect.equality(record.valid_prefix("abcdef", nil), nil)
end

--- An empty-string prefix is rejected.
T["valid_prefix"]["rejects an empty prefix"] = function()
	expect.equality(record.valid_prefix("abcdef", ""), nil)
end

--- A prefix equal to the whole id is rejected: it must be STRICTLY shorter
--- (the #prefix < #id guard) so the UI highlights the whole id instead.
T["valid_prefix"]["rejects a prefix equal to the full id"] = function()
	expect.equality(record.valid_prefix("abcdef", "abcdef"), nil)
end

--- A prefix that is not a leading substring of the id is rejected.
T["valid_prefix"]["rejects a non-leading prefix"] = function()
	expect.equality(record.valid_prefix("abcdef", "xyz"), nil)
end

--- A prefix longer than the id is rejected (guarded by #prefix < #id before the
--- substring compare, so no out-of-range indexing surprises).
T["valid_prefix"]["rejects a prefix longer than the id"] = function()
	expect.equality(record.valid_prefix("abc", "abcdef"), nil)
end

return T
