--- View stack for NeoJJ drill-down navigation.
---
--- NeoJJ's log, status and file views form a drill-down stack: opening a change
--- from the log, then opening a file from that change, stacks three live views.
--- Rather than snapshot each view's (cursor, revision, folds) and re-render it
--- on the way back, we keep every view's buffer alive and simply switch the
--- shared window between them. Vim then preserves each buffer's cursor, folds
--- and scroll position for free (see the "View Stacks" design notes).
---
--- `q`/`<esc>` on a NeoJJ view pops one frame and reveals the one beneath; the
--- no-arg `:JJ` command returns to the stack from anywhere (for example a file
--- opened from a status view).
---
--- Only log, status and file views are stack frames. describe, annotate and the
--- split terminal are transient and never pushed.
local M = {}

-- Ordered list of frames; the last entry is the top (most recently shown).
-- Each frame is `{ bufnr = number, teardown = function? }`:
--   bufnr    : the buffer displayed for this frame.
--   teardown : optional full close (window + buffer) for the NeoJJ scratch views
--              we own; absent for file buffers, which we merely navigate into
--              and leave listed when they drop off the stack.
local frames = {}

-- The window the stack lives in. Drill-down navigation replaces the buffer
-- shown here, so all frames share one window.
local stack_win = nil

---@param win? number
---@return boolean
local function win_valid(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---@param bufnr? number
---@return boolean
local function buf_valid(bufnr)
	return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

-- Drop frames whose buffer has been wiped from under us (for example closed by
-- some path other than the stack), and forget an invalidated stack window.
local function prune()
	local kept = {}
	for _, frame in ipairs(frames) do
		if buf_valid(frame.bufnr) then
			table.insert(kept, frame)
		end
	end
	frames = kept
	if not win_valid(stack_win) then
		stack_win = nil
	end
end

--- Reset the stack, forgetting all frames without tearing their buffers down.
--- Primarily a test seam; production flows unwind through `pop`.
function M.clear()
	frames = {}
	stack_win = nil
end

--- Number of frames currently on the stack.
---@return number
function M.depth()
	prune()
	return #frames
end

--- The top (most recent) frame, or nil when the stack is empty.
---@return table|nil
function M.top()
	prune()
	return frames[#frames]
end

--- Push `bufnr` as the new top frame, recording the current window as the stack
--- window. If the buffer is already on the stack it is moved to the top rather
--- than duplicated, so revisiting a view (e.g. `:JJ log` while a log view is
--- already stacked, which reuses the singleton buffer) keeps one frame per
--- buffer.
---@param bufnr number Buffer to show as the new top frame
---@param opts? { teardown?: function }
function M.push(bufnr, opts)
	opts = opts or {}
	prune()

	-- Move-to-top: drop any existing frame for this buffer before re-adding.
	for i = #frames, 1, -1 do
		if frames[i].bufnr == bufnr then
			table.remove(frames, i)
		end
	end

	table.insert(frames, { bufnr = bufnr, teardown = opts.teardown })
	stack_win = vim.api.nvim_get_current_win()
end

--- Pop the top frame. If a frame remains beneath, reveal it in the stack window
--- (returning to the view the user drilled down from) and discard the popped
--- view. If the stack empties, tear the last view down entirely.
---@return boolean popped True if a frame was popped
function M.pop()
	prune()

	local popped = table.remove(frames)
	if not popped then
		return false
	end

	local beneath = frames[#frames]
	local win = win_valid(stack_win) and stack_win or vim.api.nvim_get_current_win()

	if beneath then
		-- Unwind one level: reveal the frame beneath in the stack window, then
		-- discard the popped view. Vim restores the revealed buffer's cursor.
		if buf_valid(beneath.bufnr) and win_valid(win) then
			vim.api.nvim_win_set_buf(win, beneath.bufnr)
			vim.api.nvim_set_current_win(win)
		end
	else
		-- Last frame: nothing to reveal, so let the teardown close the view (an
		-- owned split/tab and its buffer), exactly as the old `q`=close behaved.
		stack_win = nil
	end

	if popped.teardown then
		pcall(popped.teardown)
	end

	return true
end

--- Return to the stack from anywhere. When the current buffer is already the
--- top frame — for example a file opened from a status view — step back one
--- level into the stack; otherwise focus the stack window and show the top
--- frame. Bound to the no-arg `:JJ` command.
function M.raise()
	prune()

	local top = frames[#frames]
	if not top then
		vim.notify("NeoJJ: no view stack to return to", vim.log.levels.INFO)
		return
	end

	if vim.api.nvim_get_current_buf() == top.bufnr then
		-- Already viewing the top frame; step back one level into the stack.
		M.pop()
		return
	end

	if win_valid(stack_win) then
		vim.api.nvim_set_current_win(stack_win)
		if vim.api.nvim_win_get_buf(stack_win) ~= top.bufnr then
			vim.api.nvim_win_set_buf(stack_win, top.bufnr)
		end
	else
		vim.api.nvim_set_current_buf(top.bufnr)
		stack_win = vim.api.nvim_get_current_win()
	end
end

return M
