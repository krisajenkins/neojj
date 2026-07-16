local child, new_set = require("tests.helpers.child")()
local expect = MiniTest.expect

local T = new_set()

---Test jj log command creation
---@return nil
T.test_jj_log_command_creation = function()
	child.lua([[
		require('neojj').setup()

		-- Check that JJ command exists. nargs is "*" (not "+") so a bare `:JJ`
		-- is valid and routes to jj_back() / the view stack.
		local commands = vim.api.nvim_get_commands({})
		expect.equality(commands.JJ ~= nil, true)
		expect.equality(commands.JJ.nargs, "*")
	]])
end

---Test jj log command arguments
---@return nil
T.test_jj_log_command_arguments = function()
	child.lua([[
		require('neojj').setup()

		-- Test command completion exists
		local commands = vim.api.nvim_get_commands({})
		expect.equality(commands.JJ.complete ~= nil, true)
	]])
end

---Test log buffer creation
---@return nil
T.test_log_buffer_creation = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')
		local jj = require('neojj.lib.jj')

		-- Create a mock repository
		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end
		}

		-- Test log buffer creation
		local log_buffer = LogBuffer.new(mock_repo)
		expect.equality(type(log_buffer), "table")
		expect.equality(type(log_buffer.buffer), "table")
		expect.equality(log_buffer.show_help, false)
	]])
end

---Test that reusing a log buffer merges options rather than replacing them.
---@return nil
T.test_log_buffer_merges_options_on_reuse = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')

		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end
		}

		-- First construction configures a limit and revset.
		local first = LogBuffer.new(mock_repo, { limit = 50, revisions = "@" })
		expect.equality(first.options.limit, 50)
		expect.equality(first.options.revisions, "@")

		-- Reuse with no options must keep the previously configured values.
		local second = LogBuffer.new(mock_repo)
		expect.equality(first, second)
		expect.equality(second.options.limit, 50)
		expect.equality(second.options.revisions, "@")

		-- Reuse with a new value overrides only that key.
		local third = LogBuffer.new(mock_repo, { limit = 200 })
		expect.equality(third.options.limit, 200)
		expect.equality(third.options.revisions, "@")
	]])
end

---Test log UI components
---@return nil
T.test_log_ui_components = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')

		-- Test creating test UI
		local components = LogUI.create_test_ui()
		expect.equality(type(components), "table")
		expect.equality(#components > 0, true)

		-- Test header creation
		local header = LogUI.create_header()
		expect.equality(type(header), "table")

		-- Test help creation
		local help = LogUI.create_help()
		expect.equality(type(help), "table")

		-- Test empty state
		local empty = LogUI.create_empty_state()
		expect.equality(type(empty), "table")
	]])
end

---Rendering an empty log (no revisions) must show the real "no commits" copy.
---@return nil
T.test_log_empty_state_renders_real_text = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')
		local Buffer = require('neojj.lib.buffer')

		-- No raw_lines means LogUI.create falls through to the empty state.
		local components = LogUI.create({ revisions = { items = {} } })

		local buffer = Buffer.create({
			name = 'JJ Log - Empty',
			filetype = 'neojj-log',
			modifiable = false,
			readonly = true,
		})
		buffer:render(components)

		local lines = vim.api.nvim_buf_get_lines(buffer:get_handle(), 0, -1, false)
		local content = table.concat(lines, '\n')

		expect.equality(content:find('No commits found', 1, true) ~= nil, true)
		expect.equality(
			content:find('The repository has no commits or the log query returned no results.', 1, true) ~= nil,
			true
		)

		buffer:close()
	]])
end

---Test log parsing
---@return nil
T.test_log_parsing = function()
	child.lua([[
		local log_parser = require('neojj.lib.jj.parsers.log_parser')

		-- Test parsing sample log output in the NeoJJ template format.
		-- "\30" is the record separator (graph|payload); "\31" separates fields.
		local sample_output =
			"@  \030sqmvkywl\031user@example.com\0312025-07-14 21:06:06\031\031f35b8f36\031\n" ..
			"│  \030Adding jj log support.\n" ..
			"○  \030knsrwpnn\031user@example.com\0312025-07-14 20:58:50\031\0311e062938\031\n" ..
			"│  \030Implementing status functions.\n"

		local parsed = log_parser.parse_log_output(sample_output)
		expect.equality(type(parsed), "table")
		expect.equality(type(parsed.revisions), "table")
		expect.equality(type(parsed.graph_data), "table")
		expect.equality(type(parsed.raw_lines), "table")

		-- Should have parsed at least 2 revisions
		expect.equality(#parsed.revisions >= 2, true)

		-- Basic structure validation
		expect.equality(#parsed.revisions > 0, true)
		if #parsed.revisions > 0 then
			local first_rev = parsed.revisions[1]
			expect.equality(type(first_rev.change_id), "string")
			expect.equality(type(first_rev.author), "string")
			expect.equality(type(first_rev.commit_id), "string")
		end
	]])
end

---Test log buffer screenshot
---@return nil
T.test_log_screenshot = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')
		local LogUI = require('neojj.buffers.log.ui')
		local Highlights = require('neojj.highlights')
		local Buffer = require('neojj.lib.buffer')

		-- Setup highlights
		Highlights.setup()

		-- Create a test buffer
		local buffer = Buffer.create({
			name = "Test Log",
			filetype = "neojj-test",
			kind = "split",
			modifiable = false,
			readonly = true,
		})

		-- Create test log UI
		local components = LogUI.create_test_ui()

		buffer:open()
		buffer:render(components)

		-- Ensure buffer is visible
		vim.cmd('redraw')
	]])

	-- Take screenshot
	expect.reference_screenshot(child.get_screenshot())
end

---Test that each commit metadata field is coloured with its own highlight group.
T.test_log_metadata_field_highlights = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')

		local revision = {
			change_id = "sqmvkywl",
			change_id_prefix = "sq",
			author = "krisajenkins@gmail.com",
			timestamp = "2025-07-14 21:06:06",
			commit_id = "f35b8f36",
			commit_id_prefix = "f",
			bookmarks = { "main" },
			conflict = false,
		}
		local commit_text = revision.change_id
			.. " " .. revision.author
			.. " " .. revision.timestamp
			.. " " .. revision.bookmarks[1]
			.. " " .. revision.commit_id

		-- Non-current-head row: each field gets its own semantic highlight, and
		-- the ids are split into a bright unique prefix + a dimmed remainder.
		local comps = LogUI.create_commit_text_components(commit_text, revision, false)
		local seen = {}
		for _, c in ipairs(comps) do
			seen[c:get_highlight()] = c:get_value()
		end
		expect.equality(seen["NeoJJLogChangeId"], "sq")
		expect.equality(seen["NeoJJLogChangeIdRest"], "mvkywl")
		expect.equality(seen["NeoJJLogAuthor"], "krisajenkins@gmail.com")
		expect.equality(seen["NeoJJLogTimestamp"], "2025-07-14 21:06:06")
		expect.equality(seen["NeoJJLogBookmark"], "main")
		expect.equality(seen["NeoJJLogCommitId"], "f")
		expect.equality(seen["NeoJJLogCommitIdRest"], "35b8f36")

		-- Working-copy (@) row keeps its bold emphasis on the change-id prefix,
		-- while the non-unique remainder still dims.
		local head_comps = LogUI.create_commit_text_components(commit_text, revision, true)
		local head_seen = {}
		for _, c in ipairs(head_comps) do
			head_seen[c:get_highlight()] = c:get_value()
		end
		expect.equality(head_seen["NeoJJLogCurrentHead"], "sq")
		expect.equality(head_seen["NeoJJLogChangeIdRest"], "mvkywl")
		expect.equality(head_seen["NeoJJLogChangeId"], nil)
		expect.equality(head_seen["NeoJJLogCommitId"], "f")

		-- Without prefix data the whole id is highlighted as one span (fallback).
		local no_prefix = {
			change_id = "sqmvkywl",
			author = "krisajenkins@gmail.com",
			timestamp = "2025-07-14 21:06:06",
			commit_id = "f35b8f36",
			bookmarks = {},
			conflict = false,
		}
		local plain = LogUI.create_commit_text_components(
			"sqmvkywl krisajenkins@gmail.com 2025-07-14 21:06:06 f35b8f36",
			no_prefix,
			false
		)
		local plain_seen = {}
		for _, c in ipairs(plain) do
			plain_seen[c:get_highlight()] = c:get_value()
		end
		expect.equality(plain_seen["NeoJJLogChangeId"], "sqmvkywl")
		expect.equality(plain_seen["NeoJJLogChangeIdRest"], nil)
		expect.equality(plain_seen["NeoJJLogCommitId"], "f35b8f36")
	]])
end

---An expanded log entry must carry the graph gutter (the vertical connectors) on
---every description/stats line, not plain-space indentation. The gutter is a
---pass-through derived from the commit's own node-header gutter — NOT copied from
---the line jj draws immediately below, which under a side branch is a
---branch-closing connector like "├─╯" that must not repeat down the block. So a
---node under "│ ○  " expands with a "│ │  " gutter even though jj's own next line
---is "├─╯  ".
---@return nil
T.test_expanded_details_carry_pass_through_gutter = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')

		-- A side-branch node whose header sits under a "│ ○  " gutter. jj draws the
		-- branch-closing connector "├─╯  " on the line immediately below it (this
		-- is the regression: that connector must NOT be reused for the expanded
		-- block; the pass-through "│ │  " must be).
		local revision = {
			change_id = "sqmvkywl",
			author = "user@example.com",
			timestamp = "2025-07-14 21:06:06",
			commit_id = "f35b8f36",
			bookmarks = {}, conflict = false,
			graph = "│ ○  ",
			line_number = 1,
		}
		local log_state = {
			raw_lines = {
				"│ ○  sqmvkywl user@example.com 2025-07-14 21:06:06 f35b8f36",
				"├─╯  A side-branch change.",
			},
			graph_data = {
				[1] = { graph = "│ ○  ", revision = revision },
				[2] = { graph = "├─╯  ", revision = nil },
			},
		}

		-- A log buffer whose only expanded revision is the one above, with a
		-- multi-line description and a stats summary line.
		local log_buffer = {
			expanded_revisions = {
				[revision.change_id] = {
					description = { "A side-branch change.", "More detail." },
					stats = { "1 file changed, 2 insertions(+)" },
				},
			},
		}

		local components = LogUI.create_log_components(log_state, log_buffer)

		-- Walk the tree collecting every detail Row: a Row whose first child is a
		-- NeoJJLogGraph gutter span and second child is the detail text. Also
		-- collect the gutter-only separator Row (a single NeoJJLogGraph span) that
		-- runs between the description and stats blocks.
		local detail_rows = {}
		local separator_gutters = {}
		local function walk(node)
			if type(node) ~= "table" then return end
			if node.get_tag and node:get_tag() == "Row" then
				local kids = node:get_children()
				-- A detail row is exactly [gutter span, text span]; the commit header
				-- row has many more children, so #kids == 2 excludes it.
				if #kids == 2
					and kids[1] and kids[1].get_highlight and kids[1]:get_highlight() == "NeoJJLogGraph"
					and kids[2] and kids[2].get_tag and kids[2]:get_tag() == "Text"
					and kids[2]:get_highlight() ~= "NeoJJLogGraph" then
					table.insert(detail_rows, { gutter = kids[1]:get_value(), text = kids[2]:get_value(),
						text_hl = kids[2]:get_highlight() })
				elseif #kids == 1
					and kids[1] and kids[1].get_highlight and kids[1]:get_highlight() == "NeoJJLogGraph" then
					table.insert(separator_gutters, kids[1]:get_value())
				end
			end
			for _, child in ipairs(node.get_children and node:get_children() or {}) do
				walk(child)
			end
		end
		-- components[1] is the commit's own tree (header + expanded block);
		-- components[2] is the separately-rendered jj continuation line ("├─╯  "),
		-- which is intentionally kept and excluded here.
		walk(components[1])

		-- Two description lines + one stats summary line = three detail rows, each
		-- prefixed with the pass-through "│ │  " gutter (NOT the "├─╯  " below).
		expect.equality(#detail_rows, 3)
		expect.equality(detail_rows[1].gutter, "│ │  ")
		expect.equality(detail_rows[1].text, "A side-branch change.")
		expect.equality(detail_rows[1].text_hl, "NeoJJLogDescription")
		expect.equality(detail_rows[2].gutter, "│ │  ")
		expect.equality(detail_rows[2].text, "More detail.")
		expect.equality(detail_rows[3].gutter, "│ │  ")
		expect.equality(detail_rows[3].text, "1 file changed, 2 insertions(+)")
		expect.equality(detail_rows[3].text_hl, "NeoJJLogStatsSummary")

		-- The blank separator between description and stats also carries the
		-- gutter, so the vertical connector runs unbroken through it.
		expect.equality(#separator_gutters, 1)
		expect.equality(separator_gutters[1], "│ │  ")
	]])
end

---The pass-through gutter turns a node-header gutter's single node glyph into a
---vertical bar, per UTF-8 character, so multi-byte glyphs neither leak through
---nor over-indent. A linear "○  " node expands under a clean "│  " gutter.
---@return nil
T.test_pass_through_gutter_replaces_node_glyph = function()
	child.lua([[
		local LogUI = require('neojj.buffers.log.ui')

		-- Every node glyph collapses to a vertical bar; lanes and spacing are kept.
		expect.equality(LogUI.pass_through_gutter("○  "), "│  ")
		expect.equality(LogUI.pass_through_gutter("@  "), "│  ")
		expect.equality(LogUI.pass_through_gutter("◆  "), "│  ")
		expect.equality(LogUI.pass_through_gutter("│ ○  "), "│ │  ")
		expect.equality(LogUI.pass_through_gutter(""), "")

		-- The derived gutter keeps the node gutter's display width (a multi-byte
		-- glyph must not over-indent: "○  " is 3 display columns, not 5 bytes).
		local details = { description = { "Only line." }, stats = {} }
		local comps = LogUI.create_expanded_details(details, "○  ")
		expect.equality(#comps, 1)
		local kids = comps[1]:get_children()
		expect.equality(kids[1]:get_highlight(), "NeoJJLogGraph")
		expect.equality(kids[1]:get_value(), "│  ")
		expect.equality(vim.fn.strdisplaywidth("│  "), 3)
	]])
end

---The log view should open with the cursor on the working-copy (@) change, not
---on the header line above it.
---@return nil
T.test_log_cursor_starts_on_working_copy = function()
	child.lua([[
		local LogBuffer = require('neojj.buffers.log')
		local Highlights = require('neojj.highlights')
		Highlights.setup()

		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end,
		}

		local log_buffer = LogBuffer.new(mock_repo)
		log_buffer.buffer:open()

		-- @ is the SECOND revision here, so a correct implementation must move the
		-- cursor past the header AND the first (non-@) commit to land on it.
		log_buffer.state = {
			revisions = {},
			raw_lines = {
				"○  \030knsrwpnn user@example.com 2025-07-14 20:58:50 1e062938",
				"│  A regular commit above the working copy.",
				"@  \030sqmvkywl user@example.com 2025-07-14 21:06:06 f35b8f36",
				"│  The working-copy change.",
			},
			graph_data = {
				[1] = { graph = "○  ", revision = {
					change_id = "knsrwpnn", author = "user@example.com",
					timestamp = "2025-07-14 20:58:50", commit_id = "1e062938",
					bookmarks = {}, conflict = false, graph = "○  ",
				} },
				[2] = { graph = "│  ", revision = nil },
				[3] = { graph = "@  ", revision = {
					change_id = "sqmvkywl", author = "user@example.com",
					timestamp = "2025-07-14 21:06:06", commit_id = "f35b8f36",
					bookmarks = {}, conflict = false, graph = "@  ",
				} },
				[4] = { graph = "│  ", revision = nil },
			},
		}

		log_buffer:render()

		-- The cursor should have landed on the @ commit row: the item under the
		-- cursor must be the working-copy revision.
		local item = log_buffer.buffer:get_item_at_cursor()
		expect.equality(item ~= nil, true)
		expect.equality(item.change_id, "sqmvkywl")
		expect.equality(log_buffer._cursor_initialized, true)
	]])
end

return T
