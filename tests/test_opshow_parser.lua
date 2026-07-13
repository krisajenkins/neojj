local child, new_set = require("tests.helpers.child")()

local T = new_set({
	pre_case = function()
		child.lua([[ P = require('neojj.lib.jj.parsers.opshow_parser') ]])
		-- A representative templated `jj op show` capture: RS = \x1e leads the
		-- operation record and each commit record; US = \x1f separates fields.
		child.lua([=[
				RS = "\30"
				US = "\31"
				-- Commit record fields, in order: change_id, change_id_prefix,
				-- change_offset, commit_id, commit_id_prefix, empty, hidden, conflict,
				-- description.
				SAMPLE = table.concat({
					RS .. "536c450c5d63" .. US .. "krisjenkins@host" .. US .. "2026-07-09 23:02:58",
					"squash commits into 47558e5a51b2",
					"args: jj squash --into ymlkrvkx",
					"",
					"Changed commits:",
					"+ " .. RS .. "lmuuszuy" .. US .. "lm" .. US .. "" .. US .. "861779e2" .. US .. "8"
						.. US .. "empty" .. US .. "" .. US .. "" .. US .. "(no description set)",
					"- " .. RS .. "ymlkrvkx" .. US .. "ym" .. US .. "/1" .. US .. "47558e5a" .. US .. "475"
						.. US .. "" .. US .. "hidden" .. US .. "" .. US .. "Add op-show view",
				}, "\n")
			]=])
	end,
})

---The operation-header record is parsed into id / user / time.
T.test_parses_operation_header = function()
	child.lua([[
		local els = P.parse(SAMPLE)
		expect.equality(els[1].kind, "operation")
		expect.equality(els[1].operation_id, "536c450c5d63")
		expect.equality(els[1].user, "krisjenkins@host")
		expect.equality(els[1].time, "2026-07-09 23:02:58")
	]])
end

---The operation's description and `args:` metadata become description prose,
---and the blank line becomes a blank element.
T.test_parses_prose_and_blank = function()
	child.lua([[
		local els = P.parse(SAMPLE)
		expect.equality(els[2].kind, "description")
		expect.equality(els[2].text, "squash commits into 47558e5a51b2")
		expect.equality(els[3].kind, "description")
		expect.equality(els[3].text, "args: jj squash --into ymlkrvkx")
		expect.equality(els[4].kind, "blank")
	]])
end

---"Changed …:" lines are recognised as section headers.
T.test_parses_section_header = function()
	child.lua([[
		local els = P.parse(SAMPLE)
		expect.equality(els[5].kind, "section")
		expect.equality(els[5].text, "Changed commits:")
	]])
end

---An added commit record: sign, ids with valid prefixes, empty flag, description.
T.test_parses_added_commit = function()
	child.lua([[
		local els = P.parse(SAMPLE)
		local c = els[6]
		expect.equality(c.kind, "commit_change")
		expect.equality(c.sign, "+")
		expect.equality(c.change_id, "lmuuszuy")
		expect.equality(c.change_id_prefix, "lm")
		expect.equality(c.change_offset, "") -- visible commit: no /N suffix
		expect.equality(c.commit_id, "861779e2")
		expect.equality(c.commit_id_prefix, "8")
		expect.equality(c.empty, true)
		expect.equality(c.hidden, false)
		expect.equality(c.conflict, false)
		expect.equality(c.description, "(no description set)")
	]])
end

---A removed commit record: "-" sign and the hidden flag.
T.test_parses_removed_commit = function()
	child.lua([[
		local els = P.parse(SAMPLE)
		local c = els[7]
		expect.equality(c.kind, "commit_change")
		expect.equality(c.sign, "-")
		expect.equality(c.hidden, true)
		expect.equality(c.change_offset, "/1") -- hidden commit carries the /N suffix
		expect.equality(c.empty, false)
		expect.equality(c.description, "Add op-show view")
	]])
end

---A prefix that isn't a genuine leading substring of the id is dropped so the UI
---highlights the whole id.
T.test_rejects_bogus_prefix = function()
	child.lua([[
		local line = "+ " .. RS .. "abcdefgh" .. US .. "zz" .. US .. "" .. US .. "12345678"
			.. US .. "" .. US .. "" .. US .. "" .. US .. "" .. US .. "desc"
		local els = P.parse(line)
		expect.equality(els[1].change_id, "abcdefgh")
		expect.equality(els[1].change_id_prefix, nil) -- bogus prefix dropped
	]])
end

return T
