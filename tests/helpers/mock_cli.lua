--- Mock CLI for integration testing
--- Returns fixture file contents instead of running real jj commands
---@class MockCli
local MockCli = {}

-- Current state (bookmark name)
MockCli._state = "initial"

-- Fixtures directory path
MockCli._fixtures_dir = nil

--- Read a fixture file
---@param filename string
---@return string|nil
local function read_fixture(filename)
	local path = MockCli._fixtures_dir .. "/" .. filename
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	return content
end

--- Set the fixtures directory
---@param dir string
function MockCli.set_fixtures_dir(dir)
	MockCli._fixtures_dir = dir
end

--- Set the current repository state (bookmark)
---@param state string
function MockCli.set_state(state)
	MockCli._state = state
end

--- Get the current state
---@return string
function MockCli.get_state()
	return MockCli._state
end

--- Create a mock builder that returns fixture content
---@param command string
---@return table
local function create_mock_builder(command)
	local builder = {
		_command = command,
		_args = {},
		_cwd = nil,
	}

	function builder:arg(value)
		table.insert(self._args, value)
		return self
	end

	function builder:args(values)
		vim.list_extend(self._args, values)
		return self
	end

	function builder:option(key, value)
		if value then
			table.insert(self._args, "--" .. key)
			table.insert(self._args, value)
		else
			table.insert(self._args, "--" .. key)
		end
		return self
	end

	function builder:flag(key)
		table.insert(self._args, "--" .. key)
		return self
	end

	function builder:short_flag(key)
		table.insert(self._args, "-" .. key)
		return self
	end

	function builder:env(key, value)
		return self
	end

	function builder:cwd(dir)
		self._cwd = dir
		return self
	end

	function builder:call()
		local state = MockCli._state
		local cmd = self._command
		local args = self._args

		-- Determine which fixture to load based on command pattern
		local fixture_name = nil

		-- Check for specific command patterns
		local args_str = table.concat(args, " ")

		if cmd == "status" then
			fixture_name = state .. "-status.txt"
		elseif cmd == "log" then
			-- Check if it's a JSON template request
			if args_str:match("json%(self%)") then
				fixture_name = state .. "-log-json.json"
			else
				fixture_name = state .. "-log.txt"
			end
		elseif cmd == "show" then
			fixture_name = state .. "-show-at.txt"
		elseif cmd == "diff" then
			-- Look for file path in args
			for _, arg in ipairs(args) do
				if arg:match("%.lua$") then
					local file_name = arg:gsub("/", "-"):gsub("%.lua$", "-lua")
					fixture_name = state .. "-diff-" .. file_name .. ".txt"
					break
				end
			end
			-- Default diff fixture
			if not fixture_name then
				fixture_name = state .. "-diff.txt"
			end
		elseif cmd == "edit" then
			-- For edit commands, update the state and return success
			local bookmark = args[1]
			if bookmark then
				MockCli.set_state(bookmark)
			end
			return {
				success = true,
				exit_code = 0,
				stdout = "",
				stderr = "Working copy now at: " .. (bookmark or "unknown"),
			}
		elseif cmd == "bookmark" then
			if args[1] == "list" or args_str:match("list") then
				fixture_name = "bookmark-list.txt"
			end
		elseif cmd == "new" then
			-- Mock new command - just return success
			return {
				success = true,
				exit_code = 0,
				stdout = "",
				stderr = "Working copy now at: mocked123",
			}
		elseif cmd == "describe" then
			-- Mock describe command - just return success
			return {
				success = true,
				exit_code = 0,
				stdout = "",
				stderr = "",
			}
		elseif cmd == "file" then
			-- Mock file annotate
			if args[1] == "annotate" then
				fixture_name = state .. "-annotate.txt"
			end
		end

		-- Try to load the fixture
		local content = nil
		if fixture_name then
			content = read_fixture(fixture_name)
		end

		if content then
			return {
				success = true,
				exit_code = 0,
				stdout = content,
				stderr = "",
			}
		else
			-- Return empty success if no fixture found
			return {
				success = true,
				exit_code = 0,
				stdout = "",
				stderr = "",
			}
		end
	end

	function builder:call_async()
		return builder:call()
	end

	return builder
end

--- Create the mock CLI module that matches the real CLI interface
---@return table
function MockCli.create_mock_module()
	local M = {}

	function M.status()
		return create_mock_builder("status")
	end

	function M.log()
		return create_mock_builder("log")
	end

	function M.bookmark()
		return create_mock_builder("bookmark")
	end

	function M.show()
		return create_mock_builder("show")
	end

	function M.describe()
		return create_mock_builder("describe")
	end

	function M.operation()
		return create_mock_builder("operation")
	end

	function M.workspace()
		return create_mock_builder("workspace")
	end

	function M.file()
		return create_mock_builder("file")
	end

	function M.util()
		return create_mock_builder("util")
	end

	function M.debug()
		return create_mock_builder("debug")
	end

	function M.config()
		return create_mock_builder("config")
	end

	function M.git()
		return create_mock_builder("git")
	end

	function M.new()
		return create_mock_builder("new")
	end

	function M.raw()
		local builder = create_mock_builder("raw")
		-- Override arg to capture the actual command
		local original_arg = builder.arg
		builder.arg = function(self, value)
			if self._command == "raw" then
				self._command = value
				return self
			end
			return original_arg(self, value)
		end
		return builder
	end

	return M
end

return MockCli
