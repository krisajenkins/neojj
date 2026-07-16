-- Tests for the squash combine-descriptions template (neojj.lib.jj.squash).
local T = MiniTest.new_set()
local expect = MiniTest.expect

local squash = require("neojj.lib.jj.squash")

-- Flatten build_combine_components into the plain text lines it renders to.
local function rendered_lines(components)
	local lines = {}
	for _, component in ipairs(components) do
		table.insert(lines, component:get_value())
	end
	return lines
end

-- Reproduce DescribeBuffer:get_description_from_buffer's stripping: drop the
-- `JJ:` guidance lines and trailing blanks. The result is the message jj would
-- write for the combined commit.
local function stripped_message(lines)
	local kept = {}
	for _, line in ipairs(lines) do
		if not line:match("^JJ:") then
			table.insert(kept, line)
		end
	end
	while #kept > 0 and kept[#kept] == "" do
		table.remove(kept)
	end
	return table.concat(kept, "\n")
end

T["build_combine_components combines destination then source, blank-separated"] = function()
	local dest = "Add squash\n\nDetails here"
	local source = "Fixup"

	local components = squash.build_combine_components({
		dest_description = dest,
		source_description = source,
		dest_change_id = "wmtnlpyk",
		files = { "M a.lua", "A b.lua" },
	})

	-- After stripping guidance, the editable payload is exactly the destination
	-- description, a blank line, then the source description.
	expect.equality(stripped_message(rendered_lines(components)), dest .. "\n\n" .. source)
end

T["build_combine_components emits jj-style guidance and change list"] = function()
	local components = squash.build_combine_components({
		dest_description = "Dest",
		source_description = "Src",
		dest_change_id = "wmtnlpyk",
		files = { "M a.lua" },
	})
	local lines = rendered_lines(components)

	expect.equality(lines[1], "JJ: Enter a description for the combined commit.")
	expect.equality(lines[2], "JJ: Description from the destination commit:")

	-- The change list and the trailing "will be removed" hint are present.
	local joined = table.concat(lines, "\n")
	expect.equality(joined:find("JJ: Description from source commit:", 1, true) ~= nil, true)
	expect.equality(joined:find("JJ: Change ID: wmtnlpyk", 1, true) ~= nil, true)
	expect.equality(joined:find("JJ:     M a.lua", 1, true) ~= nil, true)
	expect.equality(joined:find('JJ: Lines starting with "JJ:" (like this one) will be removed.', 1, true) ~= nil, true)
end

T["build_combine_components tolerates an empty change list"] = function()
	local components = squash.build_combine_components({
		dest_description = "Dest",
		source_description = "Src",
		dest_change_id = "abc",
		files = {},
	})
	-- Still round-trips the two descriptions.
	expect.equality(stripped_message(rendered_lines(components)), "Dest\n\nSrc")
end

return T
