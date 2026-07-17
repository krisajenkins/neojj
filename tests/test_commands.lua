local child, new_set = require("tests.helpers.child")()

---@type table
local T = new_set({
	pre_case = function()
		child.lua([[ M = require('neojj') ]])
	end,
})

---Test that the :JJ command exists after plugin load, without any setup() call.
---The child Neovim sources plugin/neojj.lua (no --noplugin), which registers
---the command, so users who install without calling setup() still get :JJ.
---@return nil
T.test_jj_command_available_without_setup = function()
	child.lua([[
		-- Plugin was sourced on startup; command must exist with no setup() call.
		local exists = vim.fn.exists(':JJ') == 2
		expect.equality(exists, true)
	]])
end

---Test that setup() re-registers the :JJ command (idempotent).
---@return nil
T.test_jj_command_creation = function()
	child.lua([[
		-- Run setup
		M.setup()

		-- Command should exist after setup
		local exists_after = vim.fn.exists(':JJ') == 2
		expect.equality(exists_after, true)
	]])
end

---Test that setup() validates options and rejects a non-numeric log_level.
---@return nil
T.test_setup_validates_options = function()
	child.lua([[
		-- A string log_level silently breaks the logger's numeric comparisons,
		-- so setup() must reject it with a clear error.
		local ok, err = pcall(M.setup, { log_level = "debug" })
		expect.equality(ok, false)
		expect.equality(err:find("log_level") ~= nil, true)

		-- A numeric log_level is accepted.
		expect.no_error(function()
			M.setup({ log_level = vim.log.levels.DEBUG })
		end)
	]])
end

---Test that setup() seeds and overrides the configurable log_limit.
---@return nil
T.test_setup_configures_log_limit = function()
	child.lua([[
		-- The default is a high cap, not the old hardcoded 10.
		expect.equality(M.config.log_limit, 100)

		-- A non-numeric log_limit is rejected up front.
		local ok, err = pcall(M.setup, { log_limit = "lots" })
		expect.equality(ok, false)
		expect.equality(err:find("log_limit") ~= nil, true)

		-- A numeric log_limit is stored on the runtime config.
		M.setup({ log_limit = 250 })
		expect.equality(M.config.log_limit, 250)
	]])
end

---Test that :JJ log parses an optional split and revision count in either order.
---@return nil
T.test_jj_log_command_arguments = function()
	child.lua([[
		M.setup()

		local calls = {}
		M.jj_log = function(dir, split, limit)
			table.insert(calls, { dir = dir, split = split, limit = limit })
		end

		vim.cmd('JJ log')
		expect.equality(calls[1].split, nil)
		expect.equality(calls[1].limit, nil)

		vim.cmd('JJ log vertical')
		expect.equality(calls[2].split, 'vertical')
		expect.equality(calls[2].limit, nil)

		vim.cmd('JJ log 50')
		expect.equality(calls[3].split, nil)
		expect.equality(calls[3].limit, 50)

		vim.cmd('JJ log vertical 25')
		expect.equality(calls[4].split, 'vertical')
		expect.equality(calls[4].limit, 25)
	]])
end

---Test that jj_log wires the configured log_limit through to LogBuffer options.
---@return nil
T.test_jj_log_passes_configured_limit = function()
	child.lua([[
		-- Reload neojj with a stubbed LogBuffer so we can observe the options it
		-- is constructed with, without shelling out to jj.
		package.loaded['neojj'] = nil
		local captured
		package.loaded['neojj.buffers.log'] = {
			new = function(_repo, options)
				captured = options
				return {
					show = function() end,
					show_split = function() end,
					show_tab = function() end,
				}
			end,
		}

		local M2 = require('neojj')
		M2.get_repo = function() return { is_jj_repo = function() return true end } end

		-- With no explicit limit, the configured default (100) flows through.
		M2.jj_log(nil, nil, nil)
		expect.equality(captured.limit, 100)

		-- An explicit limit takes precedence over the default.
		M2.jj_log(nil, nil, 7)
		expect.equality(captured.limit, 7)

		package.loaded['neojj.buffers.log'] = nil
		package.loaded['neojj'] = nil
	]])
end

---Test JJ command completion
---@return nil
T.test_jj_command_completion = function()
	child.lua([[
		M.setup()

		-- Get subcommand completion options
		local subcommands = vim.fn.getcompletion('JJ ', 'cmdline')
		expect.equality(type(subcommands), 'table')
		expect.equality(#subcommands, 8)  -- status, describe, log, oplog, new, annotate, split, arrange

		-- Get split completion options for status subcommand
		local splits = vim.fn.getcompletion('JJ status ', 'cmdline')
		expect.equality(type(splits), 'table')
		expect.equality(#splits, 3)
	]])
end

---Test JJ status command with different arguments
---@return nil
T.test_jj_status_command_arguments = function()
	child.lua([[
		M.setup()

		-- The dispatcher resolves the target repo from the current buffer. In this
		-- scratch (unnamed) buffer that falls back to the working directory, so the
		-- dir handed to jj_status is current_buffer_dir(), not nil.
		local expected_dir = M.current_buffer_dir()

		-- Mock the jj_status function to track calls
		local calls = {}
		M.jj_status = function(dir, revision, split)
			table.insert(calls, { dir = dir, revision = revision, split = split })
		end

		-- Test without arguments
		vim.cmd('JJ status')
		expect.equality(#calls, 1)
		expect.equality(calls[1].dir, expected_dir)
		expect.equality(calls[1].revision, nil)
		expect.equality(calls[1].split, nil)

		-- Test with horizontal split
		vim.cmd('JJ status horizontal')
		expect.equality(#calls, 2)
		expect.equality(calls[2].dir, expected_dir)
		expect.equality(calls[2].revision, nil)
		expect.equality(calls[2].split, 'horizontal')

		-- Test with vertical split
		vim.cmd('JJ status vertical')
		expect.equality(#calls, 3)
		expect.equality(calls[3].dir, expected_dir)
		expect.equality(calls[3].revision, nil)
		expect.equality(calls[3].split, 'vertical')

		-- Test with tab
		vim.cmd('JJ status tab')
		expect.equality(#calls, 4)
		expect.equality(calls[4].dir, expected_dir)
		expect.equality(calls[4].revision, nil)
		expect.equality(calls[4].split, 'tab')

		-- Test with change_id and split
		vim.cmd('JJ status abc123 horizontal')
		expect.equality(#calls, 5)
		expect.equality(calls[5].dir, expected_dir)
		expect.equality(calls[5].revision, 'abc123')
		expect.equality(calls[5].split, 'horizontal')

		-- Test with change_id only
		vim.cmd('JJ status xyz789')
		expect.equality(#calls, 6)
		expect.equality(calls[6].dir, expected_dir)
		expect.equality(calls[6].revision, 'xyz789')
		expect.equality(calls[6].split, nil)
	]])
end

---Test that :JJ arrange forwards its positional revsets.
---@return nil
T.test_jj_arrange_command_arguments = function()
	child.lua([[
		M.setup()

		-- Buffer-derived target dir (working directory here — scratch buffer).
		local expected_dir = M.current_buffer_dir()

		-- Mock jj_arrange to capture the revsets it is handed.
		local calls = {}
		M.jj_arrange = function(dir, revisions)
			table.insert(calls, { dir = dir, revisions = revisions })
		end

		-- No revsets: an empty list is forwarded.
		vim.cmd('JJ arrange')
		expect.equality(#calls, 1)
		expect.equality(calls[1].dir, expected_dir)
		expect.equality(calls[1].revisions, {})

		-- A single revset.
		vim.cmd("JJ arrange mutable()")
		expect.equality(#calls, 2)
		expect.equality(calls[2].revisions, { 'mutable()' })

		-- Multiple positional revsets are all forwarded.
		vim.cmd('JJ arrange abc123 def456')
		expect.equality(#calls, 3)
		expect.equality(calls[3].revisions, { 'abc123', 'def456' })
	]])
end

---A normal file buffer resolves to the directory containing its file, so `:JJ`
---acts on the repo owning the file you are editing — the core of multi-repo
---support. The file need not be inside a jj repo for this helper; it only
---returns the directory (JjRepo.instance then walks up to the root).
---@return nil
T.test_current_buffer_dir_uses_file_directory = function()
	child.lua([[
		-- A real directory + file on disk so the isdirectory() guard passes.
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, 'p')
		local file = dir .. '/README.md'
		vim.fn.writefile({ 'hello' }, file)

		vim.cmd('edit ' .. vim.fn.fnameescape(file))
		-- Compare against the directory of the buffer's *own* resolved name: on
		-- macOS `:edit` canonicalises /tmp -> /private/tmp, so deriving the
		-- expectation from the loaded buffer name avoids a spurious symlink
		-- mismatch while still asserting the contract (file buffer -> its dir).
		local expected = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p:h')
		expect.equality(M.current_buffer_dir(), expected)
		expect.no_equality(expected, vim.fn.getcwd())

		vim.cmd('bwipeout!')
		vim.fn.delete(dir, 'rf')
	]])
end

---Special buffers (here an unnamed scratch buffer) have no usable file path, so
---the helper falls back to Neovim's working directory rather than guessing.
---@return nil
T.test_current_buffer_dir_falls_back_to_cwd = function()
	child.lua([[
		vim.cmd('enew')
		expect.equality(vim.api.nvim_buf_get_name(0), '')
		expect.equality(M.current_buffer_dir(), vim.fn.getcwd())

		vim.cmd('bwipeout!')
	]])
end

---A NeoJJ view tags itself with its repo root (`b:neojj_repo_dir`); a `:JJ`
---command run while sitting in that view — a `nofile` buffer — must target the
---tagged repo, NOT the working directory. This is the in-view case: open a
---status view for one project, then `:JJ log` must stay on that project.
---@return nil
T.test_current_buffer_dir_prefers_view_tag = function()
	child.lua([[
		vim.cmd('enew')
		vim.bo.buftype = 'nofile'
		vim.b.neojj_repo_dir = '/somewhere/project-two'

		-- The tag wins over the working-directory fallback that a bare nofile
		-- buffer would otherwise get.
		expect.equality(M.current_buffer_dir(), '/somewhere/project-two')
		expect.no_equality(M.current_buffer_dir(), vim.fn.getcwd())

		vim.cmd('bwipeout!')
	]])
end

---A leader mapping wired straight to `neojj.jj_log` (etc.) calls it with no
---arguments, so `dir` is nil. get_repo(nil) must still resolve the CURRENT
---BUFFER's repo, not Neovim's working directory — otherwise the mapping acts on
---the wrong project while the equivalent `:JJ log` command works.
---@return nil
T.test_get_repo_nil_resolves_from_current_buffer = function()
	child.lua([[
		local original_cwd = vim.fn.getcwd()

		-- A directory with a file inside it (no `.jj`, so this stays a plain-dir
		-- resolution check and never spins up the jj status module).
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, 'p')
		local file = dir .. '/README.md'
		vim.fn.writefile({ 'x' }, file)

		-- Work from a DIFFERENT directory so getcwd() is not the file's dir.
		local elsewhere = vim.fn.tempname()
		vim.fn.mkdir(elsewhere, 'p')
		vim.cmd('cd ' .. elsewhere)

		vim.cmd('edit ' .. vim.fn.fnameescape(file))

		-- get_repo(nil): the path a leader mapping -> neojj.jj_log() takes. The
		-- resolved repo's dir must be the CURRENT BUFFER's directory, not the
		-- working directory.
		local repo = M.get_repo(nil)
		local file_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p:h')
		expect.equality(repo.dir, file_dir)
		expect.no_equality(repo.dir, vim.fn.getcwd())

		vim.cmd('bwipeout!')
		vim.cmd('cd ' .. original_cwd)
		vim.fn.delete(dir, 'rf')
		vim.fn.delete(elsewhere, 'rf')
	]])
end

return T
