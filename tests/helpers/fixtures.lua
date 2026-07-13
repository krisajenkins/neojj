-- Shared fixture reader for the parser unit tests.
--
-- The parser tests each read committed sample captures from
-- `tests/fixtures/jj-outputs/` and assert against their exact contents. They
-- all carried a byte-identical `read_fixture` helper; this is that helper,
-- lifted into one place.

local M = {}

---Read a committed jj-output fixture from `tests/fixtures/jj-outputs/`.
---@param filename string  Fixture file name, relative to the jj-outputs dir.
---@return string content  The entire file contents.
function M.read_fixture(filename)
	local path = "tests/fixtures/jj-outputs/" .. filename
	local file = io.open(path, "r")
	if not file then
		error("Could not open fixture file: " .. path)
	end
	local content = file:read("*all")
	file:close()
	return content
end

return M
