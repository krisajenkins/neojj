local Renderer = require("neojj.lib.ui.renderer")

---@class Buffer
---@field handle number Buffer handle
---@field name string Buffer name
---@field filetype string Buffer filetype
---@field mappings table Key mappings
---@field autocmds table[] Auto commands
---@field components table[] UI components
---@field config table Buffer configuration
local Buffer = {}
Buffer.__index = Buffer

---@class BufferConfig
---@field name string Buffer name
---@field filetype string Buffer filetype
---@field mappings? table Key mappings
---@field autocmds? table[] Auto commands
---@field modifiable? boolean Whether buffer is modifiable
---@field readonly? boolean Whether buffer is readonly
---@field unlisted? boolean Whether buffer is unlisted
---@field scratch? boolean Whether buffer is scratch

---Create a new buffer
---@param config BufferConfig Buffer configuration
---@return Buffer buffer Buffer instance
function Buffer.new(config)
	local buffer = vim.api.nvim_create_buf(false, true)

	local instance = setmetatable({
		handle = buffer,
		name = config.name,
		filetype = config.filetype,
		mappings = config.mappings or {},
		autocmds = config.autocmds or {},
		components = {},
		config = config,
	}, Buffer)

	instance:_setup_buffer()

	return instance
end

---Setup buffer properties and options
function Buffer:_setup_buffer()
	-- Set buffer name
	if self.name then
		vim.api.nvim_buf_set_name(self.handle, self.name)
	end

	-- Set buffer options
	local opts = {
		filetype = self.filetype,
		modifiable = self.config.modifiable ~= false,
		readonly = self.config.readonly == true,
		bufhidden = "wipe",
		buftype = "nofile",
		swapfile = false,
		wrap = false,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		colorcolumn = "",
		spell = false,
		list = false,
		conceallevel = 0,
		concealcursor = "",
		cursorline = true,
		cursorcolumn = false,
		scrolloff = 5,
		sidescrolloff = 5,
	}

	for option, value in pairs(opts) do
		vim.api.nvim_buf_set_option(self.handle, option, value)
	end

	-- Set up key mappings
	self:_setup_mappings()

	-- Set up autocmds
	self:_setup_autocmds()
end

---Setup key mappings for the buffer
function Buffer:_setup_mappings()
	for mode, mode_mappings in pairs(self.mappings) do
		for key, mapping in pairs(mode_mappings) do
			local opts = {
				buffer = self.handle,
				nowait = true,
				silent = true,
			}

			if type(mapping) == "table" then
				opts = vim.tbl_extend("force", opts, mapping.opts or {})
				vim.keymap.set(mode, key, mapping.callback or mapping[1], opts)
			else
				vim.keymap.set(mode, key, mapping, opts)
			end
		end
	end
end

---Setup autocmds for the buffer
function Buffer:_setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("neojj_buffer_" .. self.handle, { clear = true })

	for _, autocmd in ipairs(self.autocmds) do
		vim.api.nvim_create_autocmd(autocmd.event, {
			group = augroup,
			buffer = self.handle,
			callback = autocmd.callback,
			pattern = autocmd.pattern,
			once = autocmd.once,
		})
	end
end

---Render components to the buffer
---@param components table[] Components to render
function Buffer:render(components)
	self.components = components

	-- Make buffer modifiable temporarily
	vim.api.nvim_buf_set_option(self.handle, "modifiable", true)

	-- Render components
	Renderer.render_to_buffer(self.handle, components)

	-- Restore modifiable state
	vim.api.nvim_buf_set_option(self.handle, "modifiable", self.config.modifiable ~= false)
end

---Show the buffer in the current window
function Buffer:show()
	vim.api.nvim_set_current_buf(self.handle)
end

---Show the buffer in a new split
---@param split_type? string Split type ("horizontal" or "vertical")
function Buffer:show_split(split_type)
	if split_type == "vertical" then
		vim.cmd("vsplit")
	else
		vim.cmd("split")
	end
	vim.api.nvim_set_current_buf(self.handle)
end

---Show the buffer in a new tab
function Buffer:show_tab()
	vim.cmd("tabnew")
	vim.api.nvim_set_current_buf(self.handle)
end

---Close the buffer
function Buffer:close()
	if vim.api.nvim_buf_is_valid(self.handle) then
		vim.api.nvim_buf_delete(self.handle, { force = true })
	end
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function Buffer:is_valid()
	return vim.api.nvim_buf_is_valid(self.handle)
end

---Get buffer handle
---@return number handle Buffer handle
function Buffer:get_handle()
	return self.handle
end

---Get buffer name
---@return string name Buffer name
function Buffer:get_name()
	return self.name
end

---Get current cursor position
---@return number[] position Line and column (1-indexed)
function Buffer:get_cursor()
	local windows = vim.fn.win_findbuf(self.handle)
	if #windows > 0 then
		return vim.api.nvim_win_get_cursor(windows[1])
	end
	return { 1, 0 }
end

---Set cursor position
---@param line number Line number (1-indexed)
---@param col number Column number (0-indexed)
function Buffer:set_cursor(line, col)
	local windows = vim.fn.win_findbuf(self.handle)
	if #windows > 0 then
		vim.api.nvim_win_set_cursor(windows[1], { line, col })
	end
end

---Get the component at the current cursor position
---@return table|nil component Component at cursor or nil
function Buffer:get_component_at_cursor()
	-- This is a simplified implementation
	-- In a full implementation, you'd track component positions during rendering
	local _, _ = unpack(self:get_cursor())

	-- For now, return nil - this would need proper implementation
	-- based on component position tracking during rendering
	return nil
end

---Refresh the buffer content
function Buffer:refresh()
	if #self.components > 0 then
		self:render(self.components)
	end
end

---Add a key mapping to the buffer
---@param mode string|table Mapping mode(s)
---@param key string Key sequence
---@param callback function|string Callback function or command
---@param opts? table Mapping options
function Buffer:map(mode, key, callback, opts)
	opts = opts or {}
	opts.buffer = self.handle
	opts.nowait = opts.nowait ~= false
	opts.silent = opts.silent ~= false

	vim.keymap.set(mode, key, callback, opts)
end

---Create a status buffer with common JJ status mappings
---@param name string Buffer name
---@return Buffer buffer Status buffer instance
function Buffer.create_status(name)
	return Buffer.new({
		name = name,
		filetype = "neojj-status",
		mappings = {
			n = {
				["q"] = "<cmd>close<cr>",
				["<c-c>"] = "<cmd>close<cr>",
				["<esc>"] = "<cmd>close<cr>",
				["r"] = function()
					-- Refresh status - will be implemented later
					print("Refreshing status...")
				end,
				["g?"] = function()
					-- Show help - will be implemented later
					print("Help not yet implemented")
				end,
				["<tab>"] = function()
					-- Toggle fold - will be implemented later
					print("Folding not yet implemented")
				end,
				["<s-tab>"] = function()
					-- Toggle fold (reverse) - will be implemented later
					print("Folding not yet implemented")
				end,
			},
		},
		autocmds = {
			{
				event = "BufWinEnter",
				callback = function()
					vim.cmd("setlocal cursorline")
				end,
			},
			{
				event = "BufWinLeave",
				callback = function()
					-- Save cursor position or state if needed
				end,
			},
		},
		modifiable = false,
		readonly = true,
	})
end

return Buffer
