# JJ Split Buffer Specification (v2)

Interactive commit splitting for NeoJJ, allowing hunk-level and line-level selection of changes to split into a new commit.

## Overview

The split buffer displays a diff and allows the user to select which changes go into a **new first commit**. Unselected changes remain in a **second commit** that follows.

### Execution Model

NeoJJ uses `jj split --tool <helper>` to perform the split. The helper tool:

1. Receives two directories: `$left` (before state, read-only) and `$right` (after state, editable)
2. **Reverts unselected changes** in `$right` back to their `$left` state
3. Selected changes remain in `$right`

After the tool exits:

- **First commit** = diff from `$left` → modified `$right` (selected changes)
- **Second commit** = remaining changes (what was reverted)

## Command

```vim
:JJ split [@revision] [horizontal|vertical|tab]
```

- `@revision` - Revision to split (defaults to `@`, the working copy)
- Split type - How to open the buffer (defaults to replacing current view)

## Data Structures

### Diff Parsing

Parse `jj diff -r <rev> --git` output into structured data:

```lua
---@class DiffLine
---@field type "add"|"delete"|"context"
---@field content string        -- Line content (without +/- prefix)
---@field old_line number?      -- Line number in old file (delete/context)
---@field new_line number?      -- Line number in new file (add/context)

---@class DiffHunk
---@field header string         -- "@@ -10,5 +10,8 @@ function_name"
---@field old_start number
---@field old_count number
---@field new_start number
---@field new_count number
---@field context string?       -- Function name after @@
---@field lines DiffLine[]

---@class FileDiff
---@field path string
---@field old_path string?      -- For renames
---@field status "M"|"A"|"D"|"R"
---@field hunks DiffHunk[]
---@field is_binary boolean
```

### Selection State

Selection is tracked per-file, per-hunk, with optional line-level granularity:

```lua
---@alias HunkSelection boolean|table<number, boolean>
-- true = entire hunk selected
-- table = specific lines selected (1-indexed within hunk's add/delete lines)
-- nil/false = nothing selected

---@alias FileSelection table<number, HunkSelection>
-- Key: hunk index (1-indexed)

---@alias SelectionState table<number, FileSelection>
-- Key: file index (1-indexed)
```

Example:

```lua
selected = {
    [1] = {                    -- File 1
        [1] = true,            -- Hunk 1: fully selected
        [2] = {                -- Hunk 2: partial selection
            [3] = true,        -- Line 3 selected
            [5] = true,        -- Line 5 selected
        },
        -- Hunk 3: not selected (nil)
    },
}
```

### Buffer State

```lua
---@class SplitState
---@field files FileDiff[]
---@field current_file number           -- 1-indexed, which file cursor is on
---@field selected SelectionState
---@field expanded_hunks table<string, boolean>  -- Key: "file_idx:hunk_idx"
---@field revision string
---@field commit_message string?
---@field original_diff_text string     -- Raw diff output for validation
---@field show_help boolean             -- Whether help panel is visible
```

### State Initialization

```lua
function SplitState.new(revision)
    local diff_text = jj.diff({ revision = revision, git = true })
    local files = parser.parse_diff(diff_text)

    return {
        files = files,
        current_file = 1,
        selected = {},                    -- Nothing selected initially
        expanded_hunks = {},              -- All collapsed initially
        revision = revision,
        commit_message = nil,
        original_diff_text = diff_text,   -- Keep for validation
        show_help = false,
    }
end
```

## Folding Behavior

Hunks can be **collapsed** (showing only the header) or **expanded** (showing all lines).

### Fold State

```lua
-- In SplitState
expanded_hunks = {
    ["1:2"] = true,   -- File 1, Hunk 2 is expanded
    ["2:1"] = true,   -- File 2, Hunk 1 is expanded
    -- Missing keys = collapsed (default)
}
```

### Initial State

All hunks start **collapsed**. This provides a quick overview and lets users expand only what they need.

### Rendering Logic

```lua
function render_hunk(file_idx, hunk_idx, hunk, selection, expanded_hunks)
    local key = string.format("%d:%d", file_idx, hunk_idx)
    local is_expanded = expanded_hunks[key] == true

    -- Always render the hunk header with selection marker
    local header_component = render_hunk_header(hunk, get_hunk_selection_marker(selection))

    if not is_expanded then
        return { header_component }  -- Collapsed: header only
    end

    -- Expanded: header + all lines
    local components = { header_component }
    for line_idx, line in ipairs(hunk.lines) do
        local line_component = render_diff_line(line, selection, line_idx)
        table.insert(components, line_component)
    end
    return components
end
```

### Folding Commands

| Key       | Action                   | Implementation                                  |
| --------- | ------------------------ | ----------------------------------------------- |
| `<Tab>`   | Toggle hunk at cursor    | `expanded_hunks[key] = not expanded_hunks[key]` |
| `<S-Tab>` | Toggle all hunks in file | Set all hunks in current file to same state     |

## Selection Promotion Algorithm

Selection can be at three levels: line, hunk, or file. The system automatically promotes/demotes between levels.

### Line Index Mapping

Within a hunk, only **add** and **delete** lines are selectable. Context lines are not. Line indices in `HunkSelection` tables refer to the position among selectable lines only:

```lua
-- Example hunk lines:
-- 1: context "  unchanged"     <- not selectable
-- 2: delete  "- old line"      <- selectable, index 1
-- 3: add     "+ new line 1"    <- selectable, index 2
-- 4: add     "+ new line 2"    <- selectable, index 3
-- 5: context "  unchanged"     <- not selectable

-- Partial selection of this hunk:
selection[file_idx][hunk_idx] = {
    [1] = true,   -- "- old line" selected
    [3] = true,   -- "+ new line 2" selected
    -- index 2 ("+ new line 1") not selected
}
```

### Promotion Rules

```lua
function normalize_hunk_selection(hunk, selection)
    if type(selection) ~= "table" then
        return selection  -- Already boolean or nil
    end

    local selectable_count = count_selectable_lines(hunk)
    local selected_count = table_size(selection)

    if selected_count == 0 then
        return nil  -- Demote to unselected
    elseif selected_count == selectable_count then
        return true  -- Promote to fully selected
    else
        return selection  -- Keep partial
    end
end
```

### Selection Marker Computation

```lua
function get_selection_marker(selection)
    if selection == true then
        return "[x]"  -- Fully selected
    elseif selection == nil or selection == false then
        return "[ ]"  -- Not selected
    elseif type(selection) == "table" then
        return "[~]"  -- Partially selected
    end
end

function get_file_selection_marker(file_idx, state)
    local file_selection = state.selected[file_idx]
    if not file_selection then
        return "[ ]"
    end

    local total_hunks = #state.files[file_idx].hunks
    local full_count, partial_count = 0, 0

    for hunk_idx = 1, total_hunks do
        local sel = file_selection[hunk_idx]
        if sel == true then
            full_count = full_count + 1
        elseif type(sel) == "table" then
            partial_count = partial_count + 1
        end
    end

    if full_count == total_hunks then
        return "[x]"  -- All hunks fully selected
    elseif full_count > 0 or partial_count > 0 then
        return "[~]"  -- Some selection
    else
        return "[ ]"  -- Nothing selected
    end
end
```

## UI Layout

Single buffer with three logical sections rendered vertically:

```
┌─────────────────────────────────────────────────────┐
│ JJ Split (@)                                        │
│ Tab: expand  Space: select  S: split  q: cancel     │
├─────────────────────────────────────────────────────┤
│ Files (3)                                           │
│ [x] M src/main.lua (5 selected)                     │
│ [~] A new_file.lua (2 selected)                     │
│ [ ] D old_file.lua                                  │
├─────────────────────────────────────────────────────┤
│ Diff: src/main.lua                                  │
│ diff --git a/src/main.lua b/src/main.lua            │
│ [x] @@ +3/-2 @@ function setup()                     │  <- Collapsed hunk
│ [ ] @@ +1/-0 @@ function run()                       │  <- Collapsed hunk
│ [~] @@ +2/-1 @@ function cleanup()                   │  <- Expanded hunk (below)
│   [ ] +added line 1                                 │
│   [x] +added line 2                                 │
│       context line                                  │
│   [ ] -deleted line                                 │
├─────────────────────────────────────────────────────┤
│ Selected Changes                                    │
│ src/main.lua: 2 hunks, 5 lines                      │
│ new_file.lua: 1 hunk, 2 lines                       │
│                                                     │
│ Total: 3 hunks, 7 lines going to new commit         │
└─────────────────────────────────────────────────────┘
```

### Selection Markers

- `[x]` - Fully selected (hunk or line)
- `[ ]` - Not selected
- `[~]` - Partially selected (some lines in hunk, or some hunks in file)

### Visual Indicators

- Current file in files panel: bold/highlighted
- Add lines: green (`+` prefix)
- Delete lines: red (`-` prefix)
- Context lines: normal (space prefix, not selectable)

## Keybindings

### Navigation

| Key       | Action                         |
| --------- | ------------------------------ |
| `j` / `k` | Move cursor up/down            |
| `J` / `K` | Navigate to next/previous file |
| `]` / `[` | Navigate to next/previous hunk |

### Folding

| Key       | Action                                        |
| --------- | --------------------------------------------- |
| `<Tab>`   | Toggle expansion of hunk at cursor            |
| `<S-Tab>` | Toggle expansion of all hunks in current file |

Hunks are **collapsed by default**, showing only the header line. When expanded, individual lines are shown and selectable.

### Selection

| Key       | Action                                    |
| --------- | ----------------------------------------- |
| `<Space>` | Toggle selection at cursor (hunk or line) |
| `<CR>`    | Same as `<Space>`                         |
| `a`       | Select all hunks in current file          |
| `A`       | Select all hunks in all files             |
| `u`       | Clear selection in current file           |
| `U`       | Clear all selections                      |

### Selection Behavior

**On collapsed hunk header:**

- `<Space>` toggles the entire hunk

**On expanded hunk header:**

- `<Space>` toggles the entire hunk

**On individual line (when hunk expanded):**

- `<Space>` toggles just that line
- Context lines are not selectable

**Partial selection promotion:**

- When all lines in a hunk are selected, promote to `true` (full hunk)
- When no lines in a hunk are selected, set to `nil`

### Actions

| Key                     | Action                                     |
| ----------------------- | ------------------------------------------ |
| `S`                     | Execute split with current selection       |
| `p`                     | Preview what would be split (show summary) |
| `d`                     | Set commit message for new commit          |
| `r`                     | Refresh (re-fetch diff)                    |
| `?`                     | Toggle help panel                          |
| `q` / `<Esc>` / `<C-c>` | Cancel and close                           |

## JJ Integration

### Fetching the Diff

```bash
jj diff -r <revision> --git --color=never
```

### Validation Before Split

Before executing the split, NeoJJ must validate that the diff hasn't changed:

```lua
function SplitBuffer:validate_before_split()
    -- Re-fetch the current diff
    local current_diff = jj.diff({ revision = self.state.revision, git = true })

    -- Compare with the diff we displayed
    if current_diff ~= self.state.original_diff_text then
        return false, "Commit has changed since buffer was opened. Press 'r' to refresh."
    end

    -- Check for empty selection
    if self:count_selected_items() == 0 then
        return false, "No changes selected. Select at least one hunk or line."
    end

    return true, nil
end
```

### Executing the Split

NeoJJ uses `jj split --tool` with a generated wrapper script. This is necessary because:

1. jj passes `$left` and `$right` directories as arguments to the tool
2. We also need to pass our selection state file path
3. A wrapper script bridges these two requirements

#### Communication Flow

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌─────────────┐
│   NeoJJ     │     │   jj split       │     │  Wrapper        │     │  Helper     │
│   (Lua)     │     │                  │     │  Script         │     │  Tool       │
└──────┬──────┘     └────────┬─────────┘     └────────┬────────┘     └──────┬──────┘
       │                     │                        │                     │
       │ 1. Write selection  │                        │                     │
       │    state JSON       │                        │                     │
       │                     │                        │                     │
       │ 2. Generate wrapper │                        │                     │
       │    script (embeds   │                        │                     │
       │    state file path) │                        │                     │
       │                     │                        │                     │
       │ 3. jj split --tool  │                        │                     │
       │    <wrapper-script> │                        │                     │
       ├────────────────────>│                        │                     │
       │                     │                        │                     │
       │                     │ 4. jj invokes wrapper  │                     │
       │                     │    with $left, $right  │                     │
       │                     ├───────────────────────>│                     │
       │                     │                        │                     │
       │                     │                        │ 5. Wrapper invokes  │
       │                     │                        │    helper with      │
       │                     │                        │    state + dirs     │
       │                     │                        ├────────────────────>│
       │                     │                        │                     │
       │                     │                        │    6. Helper        │
       │                     │                        │       modifies      │
       │                     │                        │       $right        │
       │                     │                        │                     │
       │                     │                        │ 7. Helper exits 0   │
       │                     │                        │<────────────────────┤
       │                     │                        │                     │
       │                     │ 8. Wrapper exits 0     │                     │
       │                     │<───────────────────────┤                     │
       │                     │                        │                     │
       │ 9. jj creates       │                        │                     │
       │    two commits      │                        │                     │
       │<────────────────────┤                        │                     │
       │                     │                        │                     │
       │ 10. NeoJJ cleans up │                        │                     │
       │     temp files      │                        │                     │
       │                     │                        │                     │
```

#### Generated Wrapper Script

NeoJJ generates a temporary wrapper script that embeds the state file path:

```bash
#!/bin/bash
# Generated by NeoJJ for jj split operation
# This script is deleted after use

STATE_FILE="/tmp/neojj-split-state-abc123.json"
HELPER="/path/to/neojj-split-helper"

# jj passes $left as $1 and $right as $2
exec "$HELPER" "$STATE_FILE" "$1" "$2"
```

This approach:

- Requires no jj configuration changes
- Works with any jj version that supports `--tool`
- Keeps the state file path out of process arguments (cleaner)

#### State File Format

NeoJJ writes the selection state to a temporary JSON file:

```json
{
  "revision": "@",
  "files": [
    {
      "path": "src/main.lua",
      "old_path": null,
      "status": "M",
      "hunks": [
        {
          "old_start": 10,
          "old_count": 5,
          "new_start": 10,
          "new_count": 8,
          "selected": true
        },
        {
          "old_start": 30,
          "old_count": 3,
          "new_start": 33,
          "new_count": 4,
          "selected": {
            "lines": [1, 3]
          }
        }
      ]
    },
    {
      "path": "new_file.lua",
      "old_path": null,
      "status": "A",
      "hunks": [
        {
          "old_start": 0,
          "old_count": 0,
          "new_start": 1,
          "new_count": 20,
          "selected": false
        }
      ]
    }
  ]
}
```

### The Helper Tool Algorithm

The helper tool (`neojj-split-helper`) modifies `$right` to contain only the selected changes:

```
For each file in state:
    left_file = $left / file.path
    right_file = $right / file.path

    If file.status == "A" (added):
        If no hunks selected:
            Delete right_file entirely
        Else if partial selection:
            Rebuild right_file with only selected add lines

    Else if file.status == "D" (deleted):
        If no hunks selected:
            Copy left_file to right_file (restore it)
        Else:
            Leave right_file deleted (or handle partial)

    Else if file.status == "M" (modified):
        For each hunk:
            If hunk not selected:
                Revert that region in right_file to match left_file
            Else if hunk partially selected:
                For unselected add lines: remove them from right_file
                For unselected delete lines: restore them in right_file

    Else if file.status == "R" (renamed):
        Handle old_path -> path mapping
        Apply same logic as modified
```

#### Key Principle

The mental model is **"revert unselected changes"**:

| Change Type | Selected                 | Not Selected                            |
| ----------- | ------------------------ | --------------------------------------- |
| Add line    | Keep in `$right`         | Remove from `$right`                    |
| Delete line | Keep deleted in `$right` | Restore in `$right` (copy from `$left`) |
| Context     | Always keep              | Always keep                             |

### Edge Cases

- **Empty selection**: Prevented by validation before split. User must select at least one hunk.
- **Full selection**: If everything is selected, `$right` stays unchanged (first commit gets all changes, second commit is empty). jj may warn about empty second commit.
- **Binary files**: Cannot be split at line level; either fully selected or not. Display as single selectable item.
- **Renames**: Must handle the path change; file exists at `old_path` in `$left` and `path` in `$right`
- **JJ-INSTRUCTIONS file**: jj may write a `JJ-INSTRUCTIONS` file to `$right`. The helper must ignore this file (don't process it, don't delete it - jj handles it automatically).
- **Commit changed during selection**: Validated before split. If diff doesn't match, user must refresh.
- **Symlinks**: Preserve symlinks; don't follow them when copying/modifying.

## Highlights

```lua
-- Split-specific highlights
NeoJJSplitMarker      -- [x], [ ], [~] markers
NeoJJSplitCurrentFile -- Currently selected file in files panel
NeoJJSplitTotal       -- Total line in selected summary
NeoJJSplitSelected    -- Selected items
NeoJJSplitUnselected  -- Unselected items

-- Reuse existing diff highlights
NeoJJDiffAdd, NeoJJDiffDelete, NeoJJDiffContext, NeoJJDiffHunk, etc.
```

## Module Architecture

### File Structure

```
lua/neojj/
├── buffers/split/
│   ├── init.lua      -- SplitBuffer class, orchestration
│   ├── ui.lua        -- Component builders for rendering
│   ├── parser.lua    -- Parse jj diff --git output
│   └── selection.lua -- Selection state management
└── split_helper.lua  -- Standalone script for jj split --tool

bin/
└── neojj-split-helper    -- Bash wrapper invoking split_helper.lua
```

### Module Responsibilities & APIs

#### `neojj.buffers.split` (init.lua)

**Responsibility:** Buffer lifecycle, keybindings, orchestrating other modules.

**Public API:**

```lua
local Split = require("neojj.buffers.split")

-- Open a split buffer for a revision
Split.open(revision, split_type)  -- revision: string, split_type: "horizontal"|"vertical"|"tab"|nil
```

**Internal Structure:**

```lua
---@class SplitBuffer
---@field buffer Buffer           -- from neojj.lib.buffer
---@field state SplitState
local SplitBuffer = {}

function SplitBuffer:new(revision, split_type) end
function SplitBuffer:refresh() end
function SplitBuffer:close() end
function SplitBuffer:execute_split() end

-- Keybinding handlers
function SplitBuffer:toggle_selection() end
function SplitBuffer:toggle_fold() end
function SplitBuffer:select_all_file() end
function SplitBuffer:select_all() end
function SplitBuffer:clear_file() end
function SplitBuffer:clear_all() end
function SplitBuffer:next_file() end
function SplitBuffer:prev_file() end
function SplitBuffer:next_hunk() end
function SplitBuffer:prev_hunk() end
```

**Dependencies:**

- `neojj.buffers.split.ui`
- `neojj.buffers.split.parser`
- `neojj.buffers.split.selection`
- `neojj.lib.buffer`
- `neojj.lib.jj.cli`

---

#### `neojj.buffers.split.parser`

**Responsibility:** Parse `jj diff --git` output into structured data.

**Public API:**

```lua
local parser = require("neojj.buffers.split.parser")

---@param diff_text string  -- Raw output from `jj diff --git`
---@return FileDiff[]
parser.parse(diff_text)

---@param header string  -- e.g., "@@ -10,5 +10,8 @@ function_name"
---@return { old_start: number, old_count: number, new_start: number, new_count: number, context: string? }
parser.parse_hunk_header(header)
```

**Dependencies:** None (pure parsing logic).

---

#### `neojj.buffers.split.selection`

**Responsibility:** Selection state management, normalization, serialization.

**Public API:**

```lua
local selection = require("neojj.buffers.split.selection")

-- State management
---@param files FileDiff[]
---@return SelectionState
selection.new()

---@param state SelectionState
---@param file_idx number
---@param hunk_idx number
---@param line_idx number?  -- nil for hunk-level toggle
selection.toggle(state, file_idx, hunk_idx, line_idx)

---@param state SelectionState
---@param file_idx number
selection.select_all_in_file(state, files, file_idx)

---@param state SelectionState
selection.select_all(state, files)

---@param state SelectionState
---@param file_idx number
selection.clear_file(state, file_idx)

---@param state SelectionState
selection.clear_all(state)

-- Queries
---@return "full"|"partial"|"none"
selection.get_hunk_status(state, file_idx, hunk_idx)

---@return "full"|"partial"|"none"
selection.get_file_status(state, files, file_idx)

---@return number  -- count of selected hunks/lines
selection.count_selected(state, files)

-- Serialization (for helper tool)
---@param state SelectionState
---@param files FileDiff[]
---@return table  -- JSON-serializable structure
selection.serialize(state, files)
```

**Dependencies:** None (pure state logic).

---

#### `neojj.buffers.split.ui`

**Responsibility:** Build UI components for rendering.

**Public API:**

```lua
local ui = require("neojj.buffers.split.ui")

---@param state SplitState
---@return Component  -- Root component for entire buffer
ui.render(state)

-- Individual section builders (used internally, exposed for testing)
---@return Component
ui.header(revision, show_help)

---@return Component
ui.files_panel(files, selection)

---@return Component
ui.diff_panel(file, file_idx, selection, expanded_hunks)

---@return Component
ui.summary_panel(files, selection)

---@return Component
ui.help_panel()
```

**Dependencies:**

- `neojj.lib.ui.component`
- `neojj.buffers.split.selection` (for status queries)

---

#### `neojj.split_helper`

**Responsibility:** Standalone script that modifies `$right` directory based on selection state. Invoked by `jj split --tool`.

**Public API:**

```lua
local helper = require("neojj.split_helper")

-- Main entry point (called when run as script)
helper.main()

-- Exported for testing
---@param left_dir string
---@param right_dir string
---@param file_state table  -- Single file from state JSON
helper.apply_file_selection(left_dir, right_dir, file_state)

---@param right_lines string[]  -- Modified in place
---@param left_lines string[]
---@param hunk table
---@param selected boolean|table|nil
helper.revert_hunk(right_lines, left_lines, hunk, selected)
```

**Dependencies:**

- `vim.json` (for parsing state file)
- `vim.split` (for line splitting)
- Standard Lua `io` and `os`

**Note:** This module runs standalone via `nvim --headless`, not as part of the plugin. It must not require any other NeoJJ modules.

---

### Integration with Existing NeoJJ Modules

```
┌─────────────────────────────────────────────────────────────┐
│                     User Command                            │
│                     :JJ split @                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              neojj/commands.lua                             │
│              (registers :JJ split command)                  │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              neojj/buffers/split/init.lua                   │
│              SplitBuffer:new()                              │
└───┬─────────────┬─────────────┬─────────────┬───────────────┘
    │             │             │             │
    ▼             ▼             ▼             ▼
┌────────┐  ┌──────────┐  ┌───────────┐  ┌─────────────┐
│ parser │  │ selection│  │    ui     │  │ lib/buffer  │
│        │  │          │  │           │  │ (existing)  │
└────────┘  └──────────┘  └─────┬─────┘  └─────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │ lib/ui/component      │
                    │ lib/ui/renderer       │
                    │ (existing)            │
                    └───────────────────────┘

On execute_split():
┌─────────────────────────────────────────────────────────────┐
│              SplitBuffer:execute_split()                    │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              neojj/lib/jj/cli.lua                           │
│              jj.split({ revision, tool })                   │
│              (existing module, may need split() added)      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              jj split --tool <wrapper>                      │
│              (external process)                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              bin/neojj-split-helper                         │
│              → nvim --headless -l split_helper.lua          │
└─────────────────────────────────────────────────────────────┘
```

### Required Changes to Existing Modules

1. **`neojj/lib/jj/cli.lua`** - Add `split()` function:

   ```lua
   ---@param opts { revision: string?, tool: string? }
   ---@return { success: boolean, stdout: string, stderr: string }
   function M.split(opts)
       local args = { "split" }
       if opts.revision then
           table.insert(args, "-r")
           table.insert(args, opts.revision)
       end
       if opts.tool then
           table.insert(args, "--tool")
           table.insert(args, opts.tool)
       end
       return M.run(args)
   end
   ```

2. **`neojj/commands.lua`** - Register the `:JJ split` command:
   ```lua
   vim.api.nvim_create_user_command("JJ", function(opts)
       local args = vim.split(opts.args, " ")
       local cmd = args[1]
       if cmd == "split" then
           local Split = require("neojj.buffers.split")
           local revision = args[2] or "@"
           local split_type = args[3]
           Split.open(revision, split_type)
       end
       -- ... other commands
   end, { nargs = "*" })
   ```

## Testing

### Parser Tests

- Simple modification (add/delete/context lines)
- New file, deleted file, renamed file
- Multiple files in one diff
- Multiple hunks in one file
- Binary files
- Empty input
- Hunk header parsing (with/without context)

### State Serialization Tests

- Round-trip: Lua state → JSON → parsed back
- Full hunk selection serialization
- Partial line selection serialization
- All file statuses (M, A, D, R)

### Helper Tool Tests

The helper (`lua/neojj/split_helper.lua`) exports its functions as a module, making it directly testable:

```lua
local helper = require("neojj.split_helper")

-- Test revert_hunk directly
local right_lines = { "line1", "added", "line3" }
local left_lines = { "line1", "line3" }
helper.revert_hunk(right_lines, left_lines, hunk, nil)
expect.equality(right_lines, { "line1", "line3" })
```

Test cases:

- Full hunk revert (unselected hunk)
- Partial line revert within hunk
- New file: full selection vs no selection
- Deleted file: restore vs keep deleted
- Renamed file handling
- Binary file passthrough
- Edge case: empty hunk, single-line hunk

### Integration Tests

- Buffer creation and lifecycle
- Selection state management
- Keybinding functionality
- Expansion/collapse behavior
- End-to-end split with jj (requires test repository)

## Implementation Notes

### Helper Tool Implementation

The helper is implemented in pure Lua, invoked via `nvim --headless`. This requires no additional dependencies - users already have Neovim.

#### Wrapper Script (bin/neojj-split-helper)

```bash
#!/bin/bash
# neojj-split-helper: Wrapper that invokes the Lua implementation via Neovim
# Usage: neojj-split-helper <state-file> <left-dir> <right-dir>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_SCRIPT="$SCRIPT_DIR/../lua/neojj/split_helper.lua"

exec nvim --headless -l "$LUA_SCRIPT" -- "$@"
```

#### Lua Implementation (lua/neojj/split_helper.lua)

```lua
--- neojj-split-helper: Modify $right based on selection state.
--- Invoked by jj split --tool via the wrapper script.
---
--- Usage: nvim --headless -l split_helper.lua -- <state-file> <left-dir> <right-dir>

local M = {}

--- Read entire file contents
---@param path string
---@return string?
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

--- Write content to file, creating parent directories if needed
---@param path string
---@param content string
local function write_file(path, content)
    -- Ensure parent directory exists
    local dir = path:match("(.*/)")
    if dir then
        os.execute(string.format("mkdir -p %q", dir))
    end
    local f = io.open(path, "w")
    if not f then
        error("Failed to open file for writing: " .. path)
    end
    f:write(content)
    f:close()
end

--- Copy a file from src to dst
---@param src string
---@param dst string
local function copy_file(src, dst)
    local content = read_file(src)
    if content then
        write_file(dst, content)
    end
end

--- Delete a file if it exists
---@param path string
local function delete_file(path)
    os.remove(path)
end

--- Check if any hunks have selection
---@param hunks table[]
---@return boolean
local function any_selected(hunks)
    for _, hunk in ipairs(hunks) do
        if hunk.selected then
            return true
        end
    end
    return false
end

--- Check if all hunks are fully selected
---@param hunks table[]
---@return boolean
local function all_selected(hunks)
    for _, hunk in ipairs(hunks) do
        if hunk.selected ~= true then
            return false
        end
    end
    return true
end

--- Build set from array
---@param arr number[]
---@return table<number, boolean>
local function array_to_set(arr)
    local set = {}
    for _, v in ipairs(arr) do
        set[v] = true
    end
    return set
end

--- Rebuild an added file with only selected lines
---@param right_path string
---@param hunks table[]
local function rebuild_added_file(right_path, hunks)
    local lines = {}

    for _, hunk in ipairs(hunks) do
        local selected = hunk.selected
        if selected == true then
            -- Full hunk: include all add lines
            for _, line in ipairs(hunk.lines or {}) do
                if line.type == "add" then
                    table.insert(lines, line.content)
                end
            end
        elseif type(selected) == "table" and selected.lines then
            -- Partial: include only selected add lines
            local selected_indices = array_to_set(selected.lines)
            local add_idx = 0
            for _, line in ipairs(hunk.lines or {}) do
                if line.type == "add" then
                    add_idx = add_idx + 1
                    if selected_indices[add_idx] then
                        table.insert(lines, line.content)
                    end
                end
            end
        end
    end

    local content = table.concat(lines, "\n")
    if #lines > 0 then
        content = content .. "\n"
    end
    write_file(right_path, content)
end

--- Apply partial hunk selection to a modified file
--- This reverts unselected changes while keeping selected ones
---@param left_path string
---@param right_path string
---@param hunks table[]
local function apply_partial_selection(left_path, right_path, hunks)
    local left_content = read_file(left_path) or ""
    local right_content = read_file(right_path) or ""

    local left_lines = vim.split(left_content, "\n", { plain = true })
    local right_lines = vim.split(right_content, "\n", { plain = true })

    -- Process hunks in reverse order to maintain line number validity
    for i = #hunks, 1, -1 do
        local hunk = hunks[i]
        local selected = hunk.selected

        if selected == true then
            -- Fully selected, keep as-is in right
            goto continue
        end

        -- Revert this hunk (partially or fully)
        M.revert_hunk(right_lines, left_lines, hunk, selected)

        ::continue::
    end

    write_file(right_path, table.concat(right_lines, "\n"))
end

--- Revert a single hunk's unselected changes
---@param right_lines string[]
---@param left_lines string[]
---@param hunk table
---@param selected boolean|table|nil
function M.revert_hunk(right_lines, left_lines, hunk, selected)
    -- For a fully unselected hunk: replace the region in right with left's version
    -- For partial selection: selectively revert individual lines

    local new_start = hunk.new_start
    local new_count = hunk.new_count
    local old_start = hunk.old_start
    local old_count = hunk.old_count

    if not selected then
        -- Fully unselected: replace entire region with left's version
        -- Remove new_count lines starting at new_start, insert old_count lines from left
        for _ = 1, new_count do
            table.remove(right_lines, new_start)
        end
        for j = old_count, 1, -1 do
            table.insert(right_lines, new_start, left_lines[old_start + j - 1])
        end
    elseif type(selected) == "table" and selected.lines then
        -- Partial selection: need to selectively revert individual lines
        local selected_indices = array_to_set(selected.lines)

        -- Build the new content for this region by going through hunk lines
        local new_region = {}
        local selectable_idx = 0

        for _, line in ipairs(hunk.lines or {}) do
            if line.type == "context" then
                -- Context lines always kept
                table.insert(new_region, line.content)
            elseif line.type == "add" then
                selectable_idx = selectable_idx + 1
                if selected_indices[selectable_idx] then
                    -- Selected add: keep it
                    table.insert(new_region, line.content)
                end
                -- Unselected add: omit it (don't add to new_region)
            elseif line.type == "delete" then
                selectable_idx = selectable_idx + 1
                if not selected_indices[selectable_idx] then
                    -- Unselected delete: restore it (the line should be in the output)
                    table.insert(new_region, line.content)
                end
                -- Selected delete: keep it deleted (don't add to new_region)
            end
        end

        -- Replace the region in right_lines
        for _ = 1, new_count do
            table.remove(right_lines, new_start)
        end
        for j = #new_region, 1, -1 do
            table.insert(right_lines, new_start, new_region[j])
        end
    end
end

--- Apply selection state to a single file
---@param left_dir string
---@param right_dir string
---@param file_state table
function M.apply_file_selection(left_dir, right_dir, file_state)
    local path = file_state.path
    local old_path = file_state.old_path
    local status = file_state.status
    local hunks = file_state.hunks

    -- Skip JJ-INSTRUCTIONS file
    if path == "JJ-INSTRUCTIONS" then
        return
    end

    local left_path = left_dir .. "/" .. (old_path or path)
    local right_path = right_dir .. "/" .. path

    local has_any = any_selected(hunks)
    local has_all = all_selected(hunks)

    if status == "A" then
        -- Added file
        if not has_any then
            -- No selection: delete the file entirely (revert the add)
            delete_file(right_path)
        elseif not has_all then
            -- Partial: rebuild with only selected lines
            rebuild_added_file(right_path, hunks)
        end
        -- If all selected, keep right as-is

    elseif status == "D" then
        -- Deleted file
        if not has_any then
            -- No selection: restore the file (revert the delete)
            copy_file(left_path, right_path)
        end
        -- If selected, file stays deleted

    elseif status == "M" or status == "R" then
        -- Modified or Renamed
        if not has_any then
            -- No selection: restore entire file to left state
            copy_file(left_path, right_path)
        elseif not has_all then
            -- Partial: apply hunk-by-hunk
            apply_partial_selection(left_path, right_path, hunks)
        end
        -- If all selected, keep right as-is
    end
end

--- Main entry point
function M.main()
    -- Parse arguments (after --)
    local args = vim.v.argv
    local state_file, left_dir, right_dir

    -- Find arguments after "--"
    local found_separator = false
    local positional = {}
    for _, arg in ipairs(args) do
        if found_separator then
            table.insert(positional, arg)
        elseif arg == "--" then
            found_separator = true
        end
    end

    if #positional ~= 3 then
        io.stderr:write("Usage: neojj-split-helper <state-file> <left-dir> <right-dir>\n")
        os.exit(1)
    end

    state_file = positional[1]
    left_dir = positional[2]
    right_dir = positional[3]

    -- Read and parse state file
    local state_content = read_file(state_file)
    if not state_content then
        io.stderr:write("Failed to read state file: " .. state_file .. "\n")
        os.exit(1)
    end

    local ok, state = pcall(vim.json.decode, state_content)
    if not ok then
        io.stderr:write("Failed to parse state file as JSON\n")
        os.exit(1)
    end

    -- Process each file
    for _, file_state in ipairs(state.files or {}) do
        M.apply_file_selection(left_dir, right_dir, file_state)
    end

    os.exit(0)
end

-- Run main if executed directly
if not pcall(debug.getlocal, 4, 1) then
    M.main()
end

return M
```

### Neovim-side Flow

```lua
function SplitBuffer:execute_split()
    -- 1. Validate
    local ok, err = self:validate_before_split()
    if not ok then
        vim.notify(err, vim.log.levels.ERROR)
        return
    end

    -- 2. Serialize selection state to temp file
    local state_file = self:write_state_file()

    -- 3. Generate wrapper script
    local wrapper_script = self:generate_wrapper_script(state_file)

    -- 4. Execute jj split
    local result = jj.split({
        revision = self.state.revision,
        tool = wrapper_script,
    })

    -- 5. Clean up temp files
    os.remove(state_file)
    os.remove(wrapper_script)

    -- 6. Handle result
    if result.success then
        self:close()
        -- Emit event for status buffer refresh
        vim.api.nvim_exec_autocmds("User", { pattern = "NeoJJSplitComplete" })
    else
        self:show_error(result.stderr)
    end
end

function SplitBuffer:write_state_file()
    local state = self:serialize_state()
    local path = os.tmpname()
    local f = io.open(path, "w")
    f:write(vim.json.encode(state))
    f:close()
    return path
end

function SplitBuffer:generate_wrapper_script(state_file)
    local helper_path = self:get_helper_path()
    local wrapper_path = os.tmpname()

    local script = string.format([[#!/bin/bash
# Generated by NeoJJ for jj split operation
STATE_FILE="%s"
HELPER="%s"
exec "$HELPER" "$STATE_FILE" "$1" "$2"
]], state_file, helper_path)

    local f = io.open(wrapper_path, "w")
    f:write(script)
    f:close()

    -- Make executable
    os.execute("chmod +x " .. wrapper_path)

    return wrapper_path
end

function SplitBuffer:get_helper_path()
    -- Find the helper script relative to the plugin installation
    -- This file is at lua/neojj/buffers/split/init.lua
    -- Helper is at bin/neojj-split-helper
    local source = debug.getinfo(1, "S").source:sub(2)  -- Remove leading @
    local plugin_root = vim.fn.fnamemodify(source, ":h:h:h:h")
    return plugin_root .. "/bin/neojj-split-helper"
end

function SplitBuffer:serialize_state()
    -- Convert internal state to JSON-serializable format
    local files = {}
    for file_idx, file in ipairs(self.state.files) do
        local hunks = {}
        for hunk_idx, hunk in ipairs(file.hunks) do
            local selection = self.state.selected[file_idx]
                and self.state.selected[file_idx][hunk_idx]
            table.insert(hunks, {
                old_start = hunk.old_start,
                old_count = hunk.old_count,
                new_start = hunk.new_start,
                new_count = hunk.new_count,
                lines = hunk.lines,  -- Include for partial selection
                selected = self:serialize_selection(selection),
            })
        end
        table.insert(files, {
            path = file.path,
            old_path = file.old_path,
            status = file.status,
            hunks = hunks,
        })
    end
    return {
        revision = self.state.revision,
        files = files,
    }
end

function SplitBuffer:serialize_selection(selection)
    if selection == true then
        return true
    elseif type(selection) == "table" then
        -- Convert line indices table to array
        local lines = {}
        for idx, _ in pairs(selection) do
            table.insert(lines, idx)
        end
        table.sort(lines)
        return { lines = lines }
    else
        return false
    end
end
```

## Resolved Decisions

1. **Helper tool location**: Bundled with the plugin in `bin/neojj-split-helper`. The wrapper script approach means no jj configuration is needed.

2. **Implementation language**: Pure Lua, invoked via `nvim --headless -l`. No external dependencies - if users have Neovim, they have everything needed.

3. **Tool invocation**: Use a generated wrapper script that embeds the state file path and receives `$left`/`$right` from jj. Clean and requires no user configuration.

4. **Validation**: Re-fetch diff before split and compare. Reject if changed.

5. **Empty selection**: Prevented by validation. User must select at least one change.

## Open Questions

1. **Conflict handling**: What happens if the revision has conflicts? Options:
   - Prevent splitting (show error, suggest resolving conflicts first)
   - Allow splitting but show conflict markers as non-selectable regions
   - Allow selecting which side of conflicts to include

2. **Large diffs**: For very large diffs, should we:
   - Paginate the display?
   - Virtualize rendering (only render visible lines)?
   - Truncate with "... N more files" and expand on demand?

3. **Undo after split**: Can we provide an undo mechanism?
   - jj has `jj undo` which could revert the split
   - Could show a "Split complete. Press 'u' to undo" message

4. **Syntax highlighting**: Should diff lines have language-aware syntax highlighting?
   - Would require detecting file type and applying treesitter
   - May be complex for partial lines

5. **Visual mode selection**: Should we support visual mode for selecting ranges of lines?
   - Would be more familiar to vim users
   - Adds implementation complexity
