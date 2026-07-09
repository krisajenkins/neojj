local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.bo.readonly = false
			child.cmd([[ set rtp+=deps/plenary.nvim ]])
			child.lua([[ expect = require('mini.test').expect ]])
			child.lua([[ UI = require('neojj.buffers.opshow.ui') ]])
		end,
		post_once = child.stop,
	},
})

---Op-show buffer creation yields a valid buffer keyed on the operation id.
T.test_opshow_buffer_creation = function()
	child.lua([[
		local OpShowBuffer = require('neojj.buffers.opshow')

		local mock_repo = {
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end,
		}

		local a = OpShowBuffer.new(mock_repo, "aff62571bf72")
		local b = OpShowBuffer.new(mock_repo, "aff62571bf72")
		expect.equality(a, b) -- same (repo, op) reuses the instance

		local c = OpShowBuffer.new(mock_repo, "0123456789ab")
		expect.no_equality(a, c) -- a different operation is its own instance
	]])
end

---The op-show view maps `l` to open the commit log view.
T.test_opshow_maps_l_to_log = function()
	child.lua([[
		local OpShowBuffer = require('neojj.buffers.opshow')
		local buf = OpShowBuffer.new({
			dir = vim.fn.getcwd(),
			is_jj_repo = function() return true end,
		}, "aff62571bf72")

		local mapped = false
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf:get_handle(), "n")) do
			if m.lhs == "l" then mapped = true end
		end
		expect.equality(mapped, true)
		expect.equality(type(buf.open_log), "function")
	]])
end

---The operation-header element becomes a row splitting id / user / time into the
---oplog highlight groups.
T.test_operation_row_spans = function()
	child.lua([[
		local row = UI.operation_row({
			kind = "operation",
			operation_id = "536c450c5d63",
			user = "krisjenkins@host",
			time = "2026-07-09 23:02:58",
		})
		expect.equality(row:get_tag(), "Row")
		local spans = row:get_children()
		expect.equality(spans[1]:get_value(), "536c450c5d63")
		expect.equality(spans[1]:get_highlight(), "NeoJJOplogId")

		local values, highlights = {}, {}
		for _, s in ipairs(spans) do
			table.insert(values, s:get_value())
			highlights[s:get_highlight() or ""] = true
		end
		expect.equality(vim.tbl_contains(values, "krisjenkins@host"), true)
		expect.equality(highlights["NeoJJOplogUser"], true)
		expect.equality(highlights["NeoJJOplogTime"], true)
	]])
end

---An added commit row: the "+" sign is add-highlighted and the change id is split
---into a bright unique prefix + dimmed remainder.
T.test_commit_row_added_id_split = function()
	child.lua([[
		local row = UI.commit_row({
			kind = "commit_change",
			sign = "+",
			change_id = "lmuuszuy",
			change_id_prefix = "lm",
			commit_id = "861779e2",
			commit_id_prefix = "8",
			empty = true,
			hidden = false,
			conflict = false,
			description = "(no description set)",
		})
		local spans = row:get_children()

		-- First span is the "+" sign in the add colour.
		expect.equality(spans[1]:get_value(), "+")
		expect.equality(spans[1]:get_highlight(), "NeoJJDiffAdd")

		-- The change id is rendered as prefix ("lm", bright) + rest ("uuszuy", dim).
		local seen = {}
		for _, s in ipairs(spans) do
			seen[s:get_value()] = s:get_highlight()
		end
		expect.equality(seen["lm"], "NeoJJLogChangeId")
		expect.equality(seen["uuszuy"], "NeoJJLogChangeIdRest")
		-- The (empty) marker is present with the shared empty highlight.
		expect.equality(seen["(empty)"], "NeoJJEmpty")
	]])
end

---A removed commit row uses the delete colour for its sign and shows (hidden).
T.test_commit_row_removed_hidden = function()
	child.lua([[
		local row = UI.commit_row({
			kind = "commit_change",
			sign = "-",
			change_id = "ymlkrvkx",
			change_id_prefix = "ym",
			change_offset = "/1",
			commit_id = "47558e5a",
			commit_id_prefix = "475",
			empty = false,
			hidden = true,
			conflict = false,
			description = "Add op-show view",
		})
		local spans = row:get_children()
		expect.equality(spans[1]:get_value(), "-")
		expect.equality(spans[1]:get_highlight(), "NeoJJDiffDelete")

		local seen = {}
		for _, s in ipairs(spans) do
			seen[s:get_value()] = s:get_highlight()
		end
		expect.equality(seen["(hidden)"], "NeoJJLogChangeIdRest")
		-- The "/1" change offset is rendered (dimmed) right after the change id.
		expect.equality(seen["/1"], "NeoJJLogChangeIdRest")
	]])
end

---create() maps each parsed element kind to the right component shape/highlight.
T.test_create_shapes_elements = function()
	child.lua([[
		local components = UI.create({
			{ kind = "operation", operation_id = "abc", user = "u", time = "t" },
			{ kind = "description", text = "args: jj foo" },
			{ kind = "blank" },
			{ kind = "section", text = "Changed commits:" },
			{ kind = "commit_change", sign = "+", change_id = "a", commit_id = "b",
			  empty = false, hidden = false, conflict = false, description = "d" },
		})
		expect.equality(#components, 5)
		expect.equality(components[1]:get_tag(), "Row") -- operation header
		expect.equality(components[2]:get_highlight(), "NeoJJOplogDescription")
		expect.equality(components[3]:get_value(), "") -- blank line
		expect.equality(components[4]:get_highlight(), "NeoJJSectionHeader")
		expect.equality(components[5]:get_tag(), "Row") -- commit change
	]])
end

return T
