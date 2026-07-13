-- Side-by-side diff floats for the status view.
--
-- When `config.diff.inline` is false, `<tab>` on a file opens the file's two
-- sides (parent vs. shown revision) in two adjacent floating windows running
-- Neovim's native diff mode. The diff engine does all the alignment, filler
-- lines, long-line handling and syntax highlighting for us, so this module only
-- fetches the two sides and manages the float pair's lifecycle.
--
-- Only one pair is ever open at a time; opening a new one closes any existing
-- pair. The pair is transient and is NOT pushed onto the view stack (consistent
-- with the inline toggle).

local logger = require("neojj.logger")

local M = {}

-- The currently-open float pair (or nils when nothing is open). `origin_win` is
-- the window we return focus to on close (the status window). `closing` guards
-- the WinClosed autocmd against re-entering M.close while it tears the pair
-- down.
local state = {
	left_win = nil,
	right_win = nil,
	origin_win = nil,
	closing = false,
}

local augroup = vim.api.nvim_create_augroup("NeoJJDiffFloat", { clear = true })

-- Close the current float pair (if any) and return focus to the origin window.
function M.close()
	if state.closing then
		return
	end
	state.closing = true

	local origin = state.origin_win
	for _, win in ipairs({ state.left_win, state.right_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	state.left_win, state.right_win, state.origin_win = nil, nil, nil

	if origin and vim.api.nvim_win_is_valid(origin) then
		pcall(vim.api.nvim_set_current_win, origin)
	end

	state.closing = false
end

-- Turn raw `jj file show` stdout into buffer lines, reporting whether the
-- content looks binary (contains a NUL byte). A trailing newline yields a
-- trailing empty line from vim.split, which we drop so the diff doesn't show a
-- spurious blank last line.
local function to_lines(stdout)
	if not stdout or stdout == "" then
		return {}, false
	end
	local binary = stdout:find("\0", 1, true) ~= nil
	local lines = vim.split(stdout, "\n")
	if #lines > 0 and lines[#lines] == "" then
		table.remove(lines)
	end
	return lines, binary
end

-- Fetch a file's content at a revision. Returns (lines, is_binary). A failed
-- fetch (e.g. the path doesn't exist at that revision) yields empty content
-- rather than an error, which is the right neutral side for the diff.
local function fetch_side(repo, rev, path)
	local cli = require("neojj.lib.jj.cli")
	local result = cli.file():arg("show"):arg("-r"):arg(rev):arg(path):cwd(repo.dir):call_async()
	if not result.success then
		logger.warn("Failed to fetch " .. path .. " at " .. rev .. ": " .. tostring(result.stderr))
		return {}, false
	end
	return to_lines(result.stdout)
end

-- Create a read-only scratch buffer holding the given lines, with a filetype
-- derived from the path so native syntax highlighting works inside diff mode.
local function make_scratch(lines, filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	if filetype and filetype ~= "" then
		vim.bo[buf].filetype = filetype
	end
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
	return buf
end

-- Map the close keys (<tab>, q, <esc>) in a float buffer so any of them tears
-- down the whole pair and returns to the status view.
local function map_close_keys(buf)
	for _, key in ipairs({ "<tab>", "q", "<esc>" }) do
		vim.keymap.set("n", key, function()
			M.close()
		end, { buffer = buf, nowait = true, silent = true, desc = "Close side-by-side diff" })
	end
end

-- Configure a window for native diff mode, mirroring what `:diffthis` sets.
local function set_diff_win(win)
	vim.wo[win].diff = true
	vim.wo[win].scrollbind = true
	vim.wo[win].cursorbind = true
	vim.wo[win].wrap = false
	vim.wo[win].foldmethod = "diff"
	vim.wo[win].foldcolumn = "2"
end

-- Open the two adjacent floats and put them into diff mode.
local function open_pair(path, left_rev, right_rev, left_lines, right_lines)
	M.close()
	state.origin_win = vim.api.nvim_get_current_win()

	local filetype = vim.filetype.match({ filename = path })

	local total_width = vim.o.columns
	local total_height = vim.o.lines

	local gap = 2
	local pane_width = math.floor((total_width - gap - 4) / 2)
	local height = math.max(5, math.floor(total_height * 0.8))
	local row = math.max(0, math.floor((total_height - height) / 2) - 1)
	local left_col = math.max(0, math.floor((total_width - (pane_width * 2 + gap)) / 2))
	local right_col = left_col + pane_width + gap

	local left_buf = make_scratch(left_lines, filetype)
	local right_buf = make_scratch(right_lines, filetype)
	map_close_keys(left_buf)
	map_close_keys(right_buf)

	state.left_win = vim.api.nvim_open_win(left_buf, false, {
		relative = "editor",
		width = pane_width,
		height = height,
		row = row,
		col = left_col,
		border = "rounded",
		title = " " .. path .. " @ " .. left_rev .. " ",
		title_pos = "center",
	})

	state.right_win = vim.api.nvim_open_win(right_buf, true, {
		relative = "editor",
		width = pane_width,
		height = height,
		row = row,
		col = right_col,
		border = "rounded",
		title = " " .. path .. " @ " .. right_rev .. " ",
		title_pos = "center",
	})

	set_diff_win(state.left_win)
	set_diff_win(state.right_win)

	-- When either float closes (by any means), close its sibling too so we never
	-- leave a lone half-diff floating. `once` keeps a fresh open from stacking up
	-- handlers on the shared group; the first WinClosed tears the whole pair down
	-- (the `closing` guard in M.close stops it recursing on the sibling's close).
	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		once = true,
		callback = function(args)
			local win = tonumber(args.match)
			if win == state.left_win or win == state.right_win then
				M.close()
			end
		end,
	})

	vim.cmd("diffupdate")
end

-- Open a side-by-side diff for a file. `revision` is the status view's pinned
-- revision (nil for the working copy `@`); `status` is the file's status letter
-- (M/A/D/R). Added files get an empty left side, deleted files an empty right
-- side, and binary files fall back to a notification instead of diffing.
---@param repo table Repository instance
---@param revision? string Revision being shown, or nil for the working copy
---@param path string File path relative to the repo root
---@param status? string File status letter (M/A/D/R)
function M.open(repo, revision, path, status)
	local async = require("plenary.async")

	local right_rev = revision or "@"
	local left_rev = right_rev .. "-"

	async.run(function()
		local left_lines, left_binary = {}, false
		local right_lines, right_binary = {}, false

		-- Added files have no parent-side content; deleted files have no
		-- revision-side content. Skip those fetches and leave the side empty.
		if status ~= "A" then
			left_lines, left_binary = fetch_side(repo, left_rev, path)
		end
		if status ~= "D" then
			right_lines, right_binary = fetch_side(repo, right_rev, path)
		end

		vim.schedule(function()
			if left_binary or right_binary then
				vim.notify("NeoJJ: binary file — cannot show side-by-side diff", vim.log.levels.WARN)
				return
			end
			open_pair(path, left_rev, right_rev, left_lines, right_lines)
		end)
	end)
end

return M
