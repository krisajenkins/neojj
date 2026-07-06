-- NeoJJ plugin initialization
-- This file is automatically loaded by Neovim when the plugin is installed

-- Only load once
if vim.g.loaded_neojj then
	return
end
vim.g.loaded_neojj = 1

-- Define highlight groups immediately on plugin load
require("neojj.highlights").setup()

-- Register the :JJ command on load so the plugin is usable without a setup()
-- call. setup() re-registers it (idempotently) for backwards compatibility.
require("neojj").create_commands()

-- Re-apply highlights after colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("NeoJJHighlights", { clear = true }),
	callback = function()
		require("neojj.highlights").setup()
	end,
})
