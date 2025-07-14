-- Highlight inspector for debugging highlight groups at cursor position
local M = {}

-- Get highlight groups at cursor position
function M.inspect_at_cursor()
	local buf = vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1 -- Convert to 0-indexed
	
	-- Get all namespaces
	local namespaces = vim.api.nvim_get_namespaces()
	
	print("=== Highlight Groups at cursor position ===")
	print(string.format("Position: line %d, col %d", row + 1, col + 1))
	print("")
	
	-- Check each namespace for highlights
	local found_any = false
	for name, ns_id in pairs(namespaces) do
		-- Get extmarks in the current line
		local extmarks = vim.api.nvim_buf_get_extmarks(
			buf, 
			ns_id, 
			{row, 0}, 
			{row, -1}, 
			{details = true}
		)
		
		for _, mark in ipairs(extmarks) do
			local mark_row = mark[2]
			local mark_col = mark[3]
			local details = mark[4]
			
			-- Check if cursor is within this extmark's range
			if mark_row == row then
				local end_col = details.end_col or mark_col
				if col >= mark_col and col < end_col then
					found_any = true
					print(string.format("Namespace: %s (id: %d)", name, ns_id))
					if details.hl_group then
						print(string.format("  Highlight: %s", details.hl_group))
						
						-- Show the actual highlight definition
						local hl = vim.api.nvim_get_hl(0, { name = details.hl_group, link = true })
						if hl.link then
							print(string.format("  Links to: %s", hl.link))
							-- Get the final highlight
							local linked_hl = vim.api.nvim_get_hl(0, { name = hl.link })
							print(string.format("  Final colors: %s", vim.inspect(linked_hl)))
						else
							print(string.format("  Colors: %s", vim.inspect(hl)))
						end
					end
					print("")
				end
			end
		end
	end
	
	-- Also check for syntax highlighting (traditional method)
	local synID = vim.fn.synID(row + 1, col + 1, 1)
	local synName = vim.fn.synIDattr(synID, "name")
	if synName and synName ~= "" then
		found_any = true
		print("Syntax highlighting:")
		print(string.format("  Group: %s", synName))
		local transID = vim.fn.synIDtrans(synID)
		local transName = vim.fn.synIDattr(transID, "name")
		if transName ~= synName then
			print(string.format("  Translates to: %s", transName))
		end
	end
	
	if not found_any then
		print("No highlight groups found at cursor position")
	end
end

-- Create a command for easy access
function M.setup()
	vim.api.nvim_create_user_command('InspectHighlight', function()
		M.inspect_at_cursor()
	end, { desc = "Inspect highlight groups at cursor position" })
	
	-- Also create a keymap for quick access
	vim.keymap.set('n', '<leader>hi', M.inspect_at_cursor, { 
		desc = "Inspect highlights at cursor",
		silent = true 
	})
end

-- Alternative: Get all highlights in current line
function M.inspect_line()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	
	print("=== All highlights on current line ===")
	print(string.format("Line %d", row + 1))
	print("")
	
	-- Get line content
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	print("Content: " .. line)
	print("")
	
	-- Check all namespaces
	local namespaces = vim.api.nvim_get_namespaces()
	for name, ns_id in pairs(namespaces) do
		local extmarks = vim.api.nvim_buf_get_extmarks(
			buf, 
			ns_id, 
			{row, 0}, 
			{row, -1}, 
			{details = true}
		)
		
		if #extmarks > 0 then
			print(string.format("Namespace: %s", name))
			for _, mark in ipairs(extmarks) do
				local col = mark[3]
				local details = mark[4]
				local end_col = details.end_col or col
				
				if details.hl_group then
					print(string.format("  [%d-%d]: %s", col, end_col, details.hl_group))
				end
			end
			print("")
		end
	end
end

-- Simpler inspection using built-in treesitter capture
function M.simple_inspect()
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	local buf = vim.api.nvim_get_current_buf()
	
	-- Method 1: Using vim.inspect_pos (Neovim 0.9+)
	if vim.inspect_pos then
		local inspect_result = vim.inspect_pos(buf, line - 1, col)
		print(vim.inspect(inspect_result))
		return
	end
	
	-- Method 2: Manual inspection for older versions
	print("Cursor position: line " .. line .. ", col " .. col)
	
	-- Get syntax groups
	local syn_id = vim.fn.synID(line, col + 1, true)
	local syn_name = vim.fn.synIDattr(syn_id, "name")
	local syn_trans_id = vim.fn.synIDtrans(syn_id)
	local syn_trans_name = vim.fn.synIDattr(syn_trans_id, "name")
	
	print("Syntax group: " .. (syn_name or "none"))
	if syn_trans_name ~= syn_name then
		print("Translated to: " .. syn_trans_name)
	end
	
	-- Get the actual colors
	local hl = vim.api.nvim_get_hl(0, { name = syn_trans_name or syn_name })
	if next(hl) then
		print("Highlight definition: " .. vim.inspect(hl))
	end
end

return M