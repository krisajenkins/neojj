# JJ Split Buffer Specification

Interactive commit splitting for NeoJJ, allowing hunk-level and line-level selection of changes to split into a new commit.

## Overview

The split buffer displays a diff and allows the user to select which changes go into a new commit. Unselected changes remain in the original commit.

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
-- table = specific lines selected (1-indexed within hunk)
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
---@field current_file number           -- 1-indexed, which file is shown in diff panel
---@field selected SelectionState
---@field expanded_hunks table<string, boolean>  -- Key: "file_idx:hunk_idx"
---@field revision string
---@field commit_message string?
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

## Content Reconstruction (Patcher)

Given original file content, the parsed diff, and selection state, produce the content for the new commit.

### Algorithm

For each hunk in the file:

1. **If hunk not selected:** Keep original content (ignore the hunk's changes)
2. **If hunk fully selected:** Apply all changes (adds and deletes)
3. **If hunk partially selected:**
   - For each line in the hunk:
     - Context lines: always include
     - Add lines: include only if selected
     - Delete lines: remove only if selected (keep if not selected)

### Edge Cases

- **New files (status "A"):** Build content only from selected add lines
- **Deleted files (status "D"):** If any deletes selected, file is deleted in new commit
- **Renames:** Handle `old_path` → `path` mapping
- **Binary files:** Cannot split (show as non-selectable)

## JJ Integration

### Fetching Diff

```bash
jj diff -r <revision> --git --color=never
```

### Executing Split

The actual `jj split` command uses a tool-based workflow. Options:

**Option A: Custom diff tool**

```bash
jj split -r <revision> --tool <neojj-helper>
```

The helper receives `$left` (original) and `$right` (target) paths and modifies `$right` based on selection state.

**Option B: Direct manipulation**

1. Create new commit
2. Apply selected changes via patch
3. Use `jj squash` or similar to finalize

**Option C: Generate and apply patch**

1. Generate a patch file from selected hunks
2. Use `jj` commands to create the split manually

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

## File Structure

```
lua/neojj/buffers/split/
├── init.lua      -- SplitBuffer class, state management, keybindings
├── ui.lua        -- Component builders for the three panels
├── parser.lua    -- Parse jj diff --git output
└── patcher.lua   -- Reconstruct content from selections
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

### Patcher Tests

- Full hunk selection
- No selection (returns original)
- Partial line selection within hunk
- New file content building
- Selection counting utilities

### Integration Tests

- Buffer creation and lifecycle
- Selection state management
- Keybinding functionality
- Expansion/collapse behavior

## Open Questions

1. **Default expansion state:** Should hunks start collapsed (current) or expanded?
2. **File panel interactivity:** Should clicking a file in the files panel switch to it?
3. **Syntax highlighting:** Should diff lines have syntax highlighting for their language?
4. **Large diffs:** How to handle very large diffs efficiently?
5. **Conflict handling:** What happens if the revision has conflicts?
