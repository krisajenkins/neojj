# NeoJJ

A Neovim plugin for [Jujutsu (jj)](https://github.com/martinvonz/jj) version control, inspired by [Neogit](https://github.com/NeogitOrg/neogit).

<div align="center">

**Manage your Jujutsu repositories without leaving Neovim**

[Features](#features) - [Installation](#installation) - [Usage](#usage) - [Configuration](#configuration) - [Development](#development)

</div>

---

## Status: Work In Progress

Feel free to use it. What it does, it does well. But it probably doesn't do all
the things you want.

## Features

- **Beautiful UI** - Syntax-highlighted buffers with intuitive navigation
- **Status View** - See working copy changes, conflicts, and file diffs
- **Log View** - Browse commit history with graph visualization
- **Describe Commits** - Edit commit descriptions with a dedicated buffer
- **Commit Details** - View detailed commit information and diffs
- **Vim-style Keybindings** - Navigate and interact using familiar Vim motions
- **Split Support** - Open buffers in horizontal/vertical splits or tabs
- **Auto-refresh** - Automatically updates when colorscheme changes

## Screenshots

### Status Buffer
View your working copy changes, expand file diffs inline, and navigate with ease:
```
JJ Status
Press ? for help, q to quit

Working Copy @ qpvuntsm 8e5f9e7d
  Change ID: qpvuntsm...
  Commit ID: 8e5f9e7d...
  Description: Add syntax highlighting support
  Author: Your Name <you@example.com>

Modified Files:
  M lua/neojj/highlights.lua
  A plugin/neojj.lua
```

### Log Buffer
Browse commit history with graph visualization:
```
JJ Log
Press ? for help, q to quit

@  qpvuntsm you@example.com 2024-01-15 10:30:00
|  Add syntax highlighting support
o  rlvkpnrz you@example.com 2024-01-15 09:15:00
|  Implement describe buffer
o  yostqsxw you@example.com 2024-01-14 16:45:00
   Initial commit
```

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "krisajenkins/neojj",
  dependencies = {
    "nvim-lua/plenary.nvim",  -- Required for async operations
  },
  config = function()
    local neojj = require("neojj")
    neojj.setup()

    -- Optional: Add keybindings
    vim.keymap.set("n", "<leader>js", neojj.jj_status, { desc = "JJ Status" })
    vim.keymap.set("n", "<leader>jl", neojj.jj_log, { desc = "JJ Log" })
    vim.keymap.set("n", "<leader>jd", neojj.jj_describe, { desc = "JJ Describe" })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "krisajenkins/neojj",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("neojj").setup()
  end
}
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/krisajenkins/neojj.git ~/.local/share/nvim/site/pack/plugins/start/neojj
   ```

2. Install dependencies:
   ```bash
   git clone https://github.com/nvim-lua/plenary.nvim.git ~/.local/share/nvim/site/pack/plugins/start/plenary.nvim
   ```

3. Add to your `init.lua`:
   ```lua
   require("neojj").setup()
   ```

## Usage

For detailed documentation, see `:help neojj` in Neovim.

### Commands

NeoJJ provides a unified `:JJ` command with subcommands:

```vim
:JJ status [change_id] [split]  " Open status buffer (working copy or specific change)
:JJ log [split]                 " Open log buffer
:JJ describe [revision] [split] " Edit commit description (defaults to @)
:JJ new [revision]              " Create new empty change
```

**Split types**: `horizontal`, `vertical`, `tab`

#### Examples

```vim
:JJ status                    " Open status for working copy in current window
:JJ status horizontal         " Open status in horizontal split
:JJ status abc123             " Show status for a specific change
:JJ status abc123 vertical    " Show specific change in vertical split
:JJ log vertical              " Open log in vertical split
:JJ describe                  " Describe current commit (@)
:JJ describe @-               " Describe parent commit
:JJ new                       " Create new change from working copy
```

### Status Buffer Keybindings

| Key | Action |
|-----|--------|
| `j`/`k` | Move cursor up/down |
| `<Tab>` | Toggle file diff |
| `<S-Tab>` | Toggle all file diffs |
| `r` | Refresh status |
| `d` | Describe current commit |
| `D` | Show diff for file at cursor |
| `l` | Open log view |
| `q` / `<Esc>` | Quit |
| `?` | Show/hide help |

### Log Buffer Keybindings

| Key | Action |
|-----|--------|
| `j`/`k` | Move cursor up/down |
| `<Enter>` | Show commit details |
| `d` | Show commit diff |
| `r` | Refresh log |
| `s` | Open status view |
| `q` / `<Esc>` | Quit |
| `?` | Show/hide help |

### Describe Buffer Keybindings

| Key | Action |
|-----|--------|
| `<C-s>` | Submit description |
| `<C-c><C-c>` | Submit description |
| `<C-c><C-q>` | Abort (discard changes) |
| `ZZ` | Submit description |
| `ZQ` | Abort (discard changes) |
| `:w` / `:wq` | Submit description |

## Configuration

### Basic Setup

```lua
require("neojj").setup({
  log_level = vim.log.levels.INFO,  -- Set log level (DEBUG, INFO, WARN, ERROR)
})
```

### Custom Keybindings

```lua
-- Smart keybinding: JJ status in jj repos, Neogit in git repos
vim.keymap.set("n", "<Leader>jj", function()
  local util = require("neojj.lib.jj.util")
  if util.is_jj_repo() then
    require("neojj").jj_status()
  else
    -- Fallback to git tool
    vim.cmd("Git")
  end
end, { desc = "Open VCS status" })

-- Direct keybindings
vim.keymap.set("n", "<Leader>js", function()
  require("neojj").jj_status()
end, { desc = "JJ Status" })

vim.keymap.set("n", "<Leader>jl", function()
  require("neojj").jj_log()
end, { desc = "JJ Log" })

vim.keymap.set("n", "<Leader>jd", function()
  require("neojj").jj_describe()
end, { desc = "JJ Describe" })
```

### Custom Highlight Groups

NeoJJ uses highlight groups that link to standard Neovim groups. You can customize them:

```lua
-- After setup, override highlight groups
require("neojj").setup()

-- Customize colors
vim.api.nvim_set_hl(0, "NeoJJTitle", { fg = "#ff0000", bold = true })
vim.api.nvim_set_hl(0, "NeoJJDiffAdd", { fg = "#00ff00" })

-- Or link to different groups
vim.api.nvim_set_hl(0, "NeoJJTitle", { link = "Keyword" })
vim.api.nvim_set_hl(0, "NeoJJSectionHeader", { link = "Type" })
```

#### Available Highlight Groups

| Group | Default Link | Purpose |
|-------|--------------|---------|
| `NeoJJTitle` | `Title` | Buffer titles |
| `NeoJJSectionHeader` | `Function` | Section headers |
| `NeoJJFileAdded` | `DiffAdd` | Added files |
| `NeoJJFileModified` | `DiffChange` | Modified files |
| `NeoJJFileDeleted` | `DiffDelete` | Deleted files |
| `NeoJJDiffAdd` | `DiffAdd` | Added lines in diffs |
| `NeoJJDiffDelete` | `DiffDelete` | Deleted lines in diffs |
| `NeoJJLogGraph` | `Special` | Log graph characters |
| `NeoJJConflict` | `Error` | Conflict markers |

See `lua/neojj/highlights.lua` for the complete list.

## Requirements

- **Neovim** >= 0.9.0
- **Jujutsu** >= 0.9.0 (the `jj` command-line tool)
- **plenary.nvim** - Required dependency for async operations

## Architecture

NeoJJ is built with a modular architecture inspired by Neogit:

```
lua/neojj/
??? buffers/          # Buffer implementations (status, log, commit, describe)
??? lib/
?   ??? jj/          # Jujutsu CLI integration
?   ??? ui/          # UI component system
??? highlights.lua   # Syntax highlighting definitions
??? logger.lua       # Logging utilities
??? neojj.lua        # Main plugin entry point
```

### Key Concepts

- **Component-based UI**: Virtual DOM-like rendering system for building interactive buffers
- **Async Operations**: Non-blocking Jujutsu command execution using plenary.nvim
- **State Management**: Centralized repository state with automatic refresh
- **Extensible**: Easy to add new buffers and commands

## Development

### Running Tests

```bash
make test
```

### Project Structure

- `lua/neojj/` - Main plugin code
- `tests/` - Test suite using mini.test
- `docs/` - Additional documentation
- `fixtures/` - Test fixtures and demo repositories

### Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Testing Your Changes

Create a test repository:

```bash
cd fixtures
./create-demo-repo.sh
cd demo-repo
```

Then open Neovim and test your changes:

```vim
:JJ status
```

## Troubleshooting

### Syntax Highlighting Not Working

If you don't see colors in NeoJJ buffers:

1. **Verify highlights are loaded**:
   ```vim
   :lua print(vim.inspect(vim.api.nvim_get_hl(0, {name='NeoJJTitle'})))
   ```
   Should show: `{ link = "Title" }`

2. **Manually reapply highlights**:
   ```vim
   :lua require('neojj.highlights').setup()
   ```

3. **Check your colorscheme**: Some colorschemes might not define base groups. Try:
   ```vim
   :colorscheme default
   ```

See [HIGHLIGHTS_FIX.md](HIGHLIGHTS_FIX.md) for more details.

### Commands Not Found

If `:JJ` command doesn't exist:

1. Verify the plugin is loaded:
   ```vim
   :lua print(vim.g.loaded_neojj)
   ```
   Should print `1`

2. Manually initialize:
   ```vim
   :lua require('neojj').setup()
   ```

### Jujutsu Not Found

Ensure `jj` is installed and in your PATH:

```bash
which jj
jj --version
```

Install Jujutsu: https://github.com/martinvonz/jj#installation

## Roadmap

- [x] Status buffer with file diffs
- [x] Log buffer with graph visualization
- [x] Describe buffer for editing commit descriptions
- [x] Commit detail buffer
- [x] Syntax highlighting
- [ ] Commit picker for advanced operations
- [ ] Rebase/squash operations
- [ ] Bookmark management
- [ ] Conflict resolution UI
- [ ] Integration with telescope.nvim
- [ ] Custom templates for commit descriptions

## Related Projects

- [Jujutsu](https://github.com/martinvonz/jj) - The version control system
- [Neogit](https://github.com/NeogitOrg/neogit) - Magit for Neovim (Git)
- [vim-jujutsu](https://github.com/avm99963/vim-jujutsu) - Vim plugin for Jujutsu

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Inspired by [Neogit](https://github.com/NeogitOrg/neogit) and [Magit](https://magit.vc/)
- Built for the amazing [Jujutsu](https://github.com/martinvonz/jj) VCS
- Thanks to the Neovim community for the excellent plugin ecosystem

---

<div align="center">

**[^ back to top](#neojj)**

Made with ❤️ for Neovim and Jujutsu users

</div>
