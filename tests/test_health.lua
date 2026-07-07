-- Tests for the :checkhealth neojj support in neojj.health.
--
-- The health module captures vim.health at require time, so we install a
-- capturing stub *before* forcing a fresh load, then assert on the recorded
-- reports. The test environment has both `jj` and plenary.nvim present.
local T = MiniTest.new_set()
local expect = MiniTest.expect

-- Install a stub vim.health that records every report, load a fresh copy of
-- neojj.health against it, and return both the module and the recording.
local function with_stubbed_health()
	local records = { start = {}, ok = {}, warn = {}, error = {}, info = {} }
	local original = vim.health

	vim.health = {
		start = function(name)
			table.insert(records.start, name)
		end,
		ok = function(msg)
			table.insert(records.ok, msg)
		end,
		warn = function(msg)
			table.insert(records.warn, msg)
		end,
		error = function(msg)
			table.insert(records.error, msg)
		end,
		info = function(msg)
			table.insert(records.info, msg)
		end,
	}

	package.loaded["neojj.health"] = nil
	local health = require("neojj.health")

	local function restore()
		vim.health = original
		package.loaded["neojj.health"] = nil
	end

	return health, records, restore
end

-- True if any recorded message contains `needle`.
local function any_contains(list, needle)
	for _, msg in ipairs(list) do
		if type(msg) == "string" and msg:find(needle, 1, true) then
			return true
		end
	end
	return false
end

T["check is a function"] = function()
	local health = require("neojj.health")
	expect.equality(type(health.check), "function")
end

T["check runs without error and reports a neojj section"] = function()
	local health, records, restore = with_stubbed_health()

	expect.no_error(function()
		health.check()
	end)
	expect.equality(records.start[1], "neojj")

	restore()
end

T["reports ok for jj and plenary in the test environment"] = function()
	local health, records, restore = with_stubbed_health()

	health.check()

	-- Both jj and plenary are available in the test environment, so each should
	-- produce an ok report and neither an error.
	expect.equality(any_contains(records.ok, "jj"), true)
	expect.equality(any_contains(records.ok, "plenary"), true)
	expect.equality(#records.error, 0)

	restore()
end

return T
