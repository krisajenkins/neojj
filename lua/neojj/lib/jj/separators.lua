-- The two ASCII control bytes NeoJJ uses to delimit jj's machine-oriented
-- `--template` output. Rather than parse jj's fragile human-facing format, the
-- log / oplog / opshow views ask jj to emit an unambiguous layout keyed on these
-- bytes, and the matching parsers split the output back apart on them. This is
-- the one source of truth, shared by the template builders (`neojj.buffers.*`)
-- and the parsers (`neojj.lib.jj.parsers.*`).
--
--   RECORD SEPARATOR (0x1e) marks the boundary between jj's graph gutter and our
--     templated payload. jj never emits this byte as part of the graph, so
--     splitting on it is unambiguous for any node glyph (@, ○, ◆, ×, ├, ─, …).
--   UNIT SEPARATOR   (0x1f) separates the fields within a record's payload.
--
-- Each delimiter is exposed in two forms because the two sides consume it
-- differently: the parsers split jj's *output* on the raw byte, while the
-- `--template` builders splice a jj-template string literal (`"\x1e"`) into the
-- template DSL to make jj *emit* that byte. The template form is derived from
-- the byte so the two can never drift.
local M = {}

M.RECORD = "\30" -- raw 0x1e, for splitting jj's output
M.UNIT = "\31" -- raw 0x1f, for splitting a record's fields

-- jj-template literals that emit the bytes above, e.g. `"\x1e"`, for splicing
-- into a `--template` argument.
M.RECORD_TEMPLATE = string.format('"\\x%02x"', M.RECORD:byte())
M.UNIT_TEMPLATE = string.format('"\\x%02x"', M.UNIT:byte())

return M
