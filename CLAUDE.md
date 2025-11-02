# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## NeoJJ - Neovim Plugin for Jujutsu VCS

NeoJJ is a Neovim plugin that provides integration with the Jujutsu (jj) version control system.

## Development Setup

The project uses Nix for development environment. Always enter the Nix shell before development:
```bash
nix develop
```

This provides:
- luacheck (static analysis)
- stylua (code formatting)
- lua-language-server (type checking)
- neovim (testing)

## Common Development Commands

```bash
# Run all checks and tests
make

# Run tests only
make test

# Run a specific test file
make test_file FILE=tests/test_components.lua

# Run linting/static analysis
make typecheck

# Format code
make format
```

## Architecture Overview

### Core Components

1. **UI Component System** (`lua/neojj/lib/ui/`)
   - `component.lua`: Defines the component abstraction with support for folding, interactivity, and custom options
   - `renderer.lua`: Renders components to buffer lines with proper highlight tracking
   - Components are immutable data structures with methods for querying properties

2. **Buffer Management** (`lua/neojj/lib/buffer.lua`)
   - Manages Neovim buffers with component rendering support
   - Handles buffer lifecycle, options, and cursor management
   - Integrates with the renderer for displaying UI components

3. **JJ Integration** (`lua/neojj/lib/jj/`)
   - `cli.lua`: Executes jj commands and parses output
   - `repository.lua`: Repository abstraction with caching and state management
   - `status.lua`: Parses jj status output into structured data
   - Uses async execution with plenary for non-blocking operations

4. **Status Buffer** (`lua/neojj/buffers/status/`)
   - `ui.lua`: Creates the component tree for displaying jj status
   - `init.lua`: Manages the status buffer lifecycle and updates
   - Provides interactive UI for viewing repository state

### Key Design Patterns

- **Component-Based UI**: All UI elements are components that can be composed hierarchically
- **Immutable Data**: Components and state are immutable for predictable rendering
- **Async Operations**: JJ commands run asynchronously to avoid blocking the editor
- **Caching**: Repository state is cached to minimize jj command executions
- **Interactive Components**: Components can be marked as `interactive = true` to support cursor-based interaction

### Component Position Tracking System

The renderer tracks the position of interactive components to enable cursor-based interactions:

1. **Renderer** (`lua/neojj/lib/ui/renderer.lua`):
   - Tracks interactive components by line number during rendering
   - Returns `component_positions` table mapping line numbers to components
   - Uses 0-indexed line numbers internally

2. **Buffer** (`lua/neojj/lib/buffer.lua`):
   - Stores component positions from renderer
   - `get_component_at_cursor()` finds the component at cursor position
   - Searches backwards from cursor line to find the nearest interactive component

3. **Interactive Components**:
   - Created with `interactive = true` option
   - Store associated data in `item` field (e.g., file paths, commit data)
   - Accessed via `component:get_item()` method

### Status Buffer Keybindings

- `r` / `<c-r>`: Refresh status buffer
- `<cr>`: Open file at cursor (if on a file entry)
- `q` / `<c-c>` / `<esc>`: Close buffer
- `d`: Describe current commit
- `j` / `k`: Navigate up/down (standard vim navigation also works)

## Testing with MiniTest

### Test Structure
```lua
local T = MiniTest.new_set()
local expect = MiniTest.expect

T.test_name = function()
  -- Test code here
end

return T
```

### Integration Tests with Child Neovim
```lua
local child = MiniTest.new_child_neovim()

T.test_with_child = function()
  child.lua([[ 
    -- Code runs in child neovim
    expect = require('mini.test').expect 
  ]])
end
```

### Key Assertions
- `expect.equality(actual, expected)` - Test equality
- `expect.no_equality(actual, expected)` - Test inequality
- `expect.error(function() ... end)` - Test that function throws error
- `expect.no_error(function() ... end)` - Test that function doesn't throw error

Note: When using `expect` inside `child.lua()` blocks, you must make it available with `expect = require('mini.test').expect`

## Code Style

- Max line length: 120 characters
- Use LuaJIT standard library
- Follow existing patterns for component creation and buffer management
- All new code must pass luacheck static analysis

## Adding New Interactive Features

To add new interactive features to buffers:

1. **Create Interactive Components**:
   ```lua
   local component = Ui.file_item(status, path, {
       item = { path = "file.txt", status = "M" },
       interactive = true,
   })
   ```

2. **Add Keybindings** in buffer `_setup_mappings()`:
   ```lua
   self.buffer:map("n", "<key>", function()
       self:action_method()
   end, { desc = "Action description" })
   ```

3. **Implement Action Methods**:
   ```lua
   function BufferClass:action_method()
       local component = self.buffer:get_component_at_cursor()
       if component and component:is_interactive() then
           local item = component:get_item()
           -- Process the item data
       end
   end
   ```

## Reference Docs

Design Plans: docs/NEOJJ_IMPLEMENTATION_PLAN.md
NeoGit Buffer Creation Architecture: docs/neogit-buffer-analysis.md
NeoJJ Module Architecture: docs/MODULE_ARCHITECTURE.md
