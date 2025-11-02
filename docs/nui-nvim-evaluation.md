# nui.nvim Evaluation for NeoJJ

## Executive Summary

**Recommendation: Keep the custom UI system.**

NeoJJ's custom component system (~450 LOC) is well-suited to the plugin's needs and provides better control, simpler architecture, and fewer dependencies than adopting nui.nvim. While nui.nvim is a mature library, its design philosophy targets different use cases (floating windows, popups, menus) rather than the buffer-based, hierarchical component rendering that NeoJJ requires.

## Overview of nui.nvim

### What is nui.nvim?

nui.nvim is a UI component library for Neovim created by MunifTanjim, designed to provide building blocks for creating interactive UIs. It has ~2,000 GitHub stars and is actively maintained.

**Core Components:**
- **Popup** - Floating windows with borders and positioning
- **Split** - Traditional editor splits (horizontal/vertical)
- **Layout** - Grid-based positioning for multiple components
- **Input** - Text input fields with prompts and callbacks
- **Menu** - Selectable menu interfaces
- **Tree** - Hierarchical tree structures with expand/collapse

**Rendering Blocks:**
- **NuiText** - Highlighted text rendering
- **NuiLine** - Lines with multiple highlighted chunks
- **NuiTable** - Table-like structured content
- **NuiTree** - Tree-like hierarchical content

### Design Philosophy

nui.nvim is designed around Neovim's native floating window system and follows a **wizard-style interaction model** - one question/UI element at a time. Components must be mounted sequentially, and relative sizing/positioning isn't calculated until mount time.

**API Characteristics:**
- Mount/unmount lifecycle (explicit opening/closing)
- Event-driven callbacks (`on_submit`, `on_close`)
- Direct buffer/window access via `bufnr`/`winid` properties
- Extension through object-oriented inheritance patterns

### Requirements & Stability

- **Minimum version**: Neovim 0.5.0
- **Dependencies**: None (standalone library)
- **Maturity**: 547+ commits, actively maintained
- **Distribution**: Available on LuaRocks

## NeoJJ's Current Custom UI System

### Architecture

NeoJJ uses a **component-based rendering system** (~450 LOC) that converts immutable component trees into buffer content:

**Core Files:**
- `component.lua` (108 LOC) - Component abstraction
- `renderer.lua` (171 LOC) - Renders components to buffer lines
- `init.lua` (175 LOC) - Component factory functions

**Design Patterns:**
- Immutable component trees
- Declarative UI composition
- Position tracking for interactive elements
- Custom folding support
- Hierarchical rendering (Col/Row/Text primitives)

### Key Features

1. **Interactive Components** - Components marked `interactive = true` are tracked for cursor-based interactions
2. **Folding Support** - Built-in `foldable` and `folded` states with section persistence
3. **Flexible Rendering** - Direct control over line-by-line buffer rendering
4. **Position Tracking** - Maps buffer lines to component data for keybindings
5. **Highlight Management** - Fine-grained control over syntax highlighting

### Current Usage Patterns

```lua
-- Declarative component composition
local status_ui = Ui.col({
    Ui.text("JJ Status", { highlight = "NeoJJTitle" }),
    Ui.section("Modified Files", file_items, {
        foldable = true,
        section = "modified_files"
    }),
    Ui.file_item("M", "src/main.lua", {
        item = { path = "src/main.lua" },
        interactive = true
    })
})
```

The custom system is already used extensively across:
- Status buffer UI (427 LOC)
- Log buffer UI
- Commit buffer UI
- ~35 occurrences of folding/interactive features

## Comparison: nui.nvim vs Custom System

### Feature Matrix

| Feature | nui.nvim | NeoJJ Custom |
|---------|----------|--------------|
| **Floating Windows** | ✓ Excellent | ✗ Not needed |
| **Buffer Rendering** | ✗ Not primary focus | ✓ Optimized for this |
| **Hierarchical Components** | ~ Tree component only | ✓ Full Col/Row/Text |
| **Interactive Tracking** | Manual keybinding setup | ✓ Built-in position tracking |
| **Folding Support** | ~ Via Tree expand/collapse | ✓ Native with persistence |
| **Declarative API** | ✗ Imperative mount/unmount | ✓ Pure functions |
| **Line-level Control** | ✗ Limited | ✓ Complete control |
| **Dependencies** | Library dependency | ✗ None |
| **Code Size** | ~2,000+ LOC (entire library) | ✓ ~450 LOC (exactly what's needed) |

### Architectural Alignment

**NeoJJ's Needs:**
- Render complex hierarchical UIs to buffers
- Track component positions for interactive keybindings
- Support section folding with state persistence
- Fine-grained control over highlighting and rendering
- Declarative component composition

**nui.nvim's Strengths:**
- Creating floating windows and popups
- Menu selection interfaces
- Input prompts with validation
- Modal dialog-style UIs
- Sequential wizard workflows

**Mismatch:** nui.nvim excels at *window management* and *modal interactions*, while NeoJJ needs *buffer-based component rendering* with *position tracking*.

## How Other Plugins Approach UI

### Neogit (Similar VCS Plugin)

**UI System:** Custom component-based rendering (similar to NeoJJ)
- Does **not** use nui.nvim
- Implements custom buffer rendering with component trees
- Uses native Neovim buffers with custom keymap systems
- ~500-800 LOC for UI infrastructure

**Why:** Buffer-based status views require fine-grained rendering control that nui.nvim doesn't provide.

### Diffview.nvim (Diff Viewer)

**UI System:** Custom buffer management
- Does **not** use nui.nvim
- Direct manipulation of Neovim windows and buffers
- Custom panel system with dedicated keymaps
- No external UI dependencies

**Why:** Complex multi-panel layouts need precise control over buffer content and window positioning.

### Plugins That Use nui.nvim

**noice.nvim** - Complete UI replacement for messages/cmdline/popupmenu
- Uses Popup components for floating notifications
- Menu components for selection interfaces
- Perfect fit: needs floating windows and modal interactions

**dressing.nvim** - Improves vim.ui interfaces
- Uses Menu for `vim.ui.select`
- Input for `vim.ui.input`
- Perfect fit: enhancing modal input/selection prompts

**Pattern:** Plugins use nui.nvim when they need **floating windows** and **modal dialogs**, not for **buffer-based content rendering**.

## Pros and Cons Analysis

### Pros of Adopting nui.nvim

1. **Community Support** - Well-tested library with active maintenance
2. **Documentation** - Comprehensive wiki and examples
3. **Tree Component** - Built-in tree rendering with expand/collapse
4. **Object System** - Inheritance patterns for extending components
5. **Standardization** - Familiar API for users of other nui.nvim plugins

### Cons of Adopting nui.nvim

1. **Architectural Mismatch** - Designed for floating windows, not buffer rendering
2. **Sequential Limitations** - Components must be mounted sequentially; relative sizing unavailable until mount
3. **Complex Layouts** - Manual position calculation required for multi-component layouts
4. **Overhead** - ~2,000+ LOC library for features NeoJJ doesn't need
5. **Additional Dependency** - Users must install another plugin
6. **Loss of Control** - Less fine-grained control over rendering
7. **Breaking Changes** - Current UI code (~35 interactive/foldable components) would need rewrite
8. **Imperative API** - Mount/unmount lifecycle doesn't fit NeoJJ's declarative pattern

### Pros of Keeping Custom System

1. **Perfect Fit** - Built exactly for NeoJJ's buffer-based rendering needs
2. **Zero Dependencies** - No external libraries required
3. **Small Footprint** - ~450 LOC vs nui.nvim's 2,000+ LOC
4. **Complete Control** - Fine-grained rendering and highlight management
5. **Position Tracking** - Built-in component-to-line mapping for interactions
6. **Declarative API** - Pure functions, immutable components
7. **Already Working** - Currently powers all NeoJJ buffers successfully
8. **Folding Built-in** - Section folding with persistence is native
9. **No Migration** - Avoid rewriting working code

### Cons of Keeping Custom System

1. **Maintenance Burden** - Must maintain and debug own code
2. **Limited Features** - No floating window support (but not needed)
3. **Learning Curve** - Contributors must learn custom system
4. **No Community** - Limited external examples/support

## Known Limitations of nui.nvim

Based on GitHub issues and discussions:

1. **Multi-Component Rendering** - "Not meant to render several UI elements simultaneously" (GitHub Discussion #121)
2. **Relative Sizing** - Relative values (50%, etc.) only calculated at mount time, preventing pre-calculation
3. **Complex Layouts** - "Completely manual process where users need to calculate positions themselves"
4. **Sequential Dependencies** - Cannot bind keymaps or define layouts until after mounting
5. **Philosophy** - Fits "one question at a time" wizard workflows, not complex multi-pane UIs

These limitations directly conflict with NeoJJ's needs for:
- Simultaneous rendering of multiple sections (Working Copy, Files, Conflicts, etc.)
- Pre-calculated component positions for interaction tracking
- Complex hierarchical layouts rendered declaratively

## Migration Effort Estimate

If migrating to nui.nvim:

**Phase 1: Core Refactoring** (3-5 days)
- Replace component system with NuiTree
- Refactor renderer to use nui.nvim APIs
- Convert declarative components to imperative mount/unmount

**Phase 2: Feature Parity** (5-7 days)
- Reimplement interactive position tracking
- Rebuild folding with NuiTree expand/collapse
- Migrate all buffer UIs (status, log, commit)
- Update 35+ foldable/interactive component usages

**Phase 3: Testing & Debugging** (3-5 days)
- Test all interactive features
- Debug layout/rendering issues
- Performance tuning
- Edge case handling

**Total Estimate:** 11-17 days of development work

**Risk Factors:**
- Fundamental architectural differences may require workarounds
- NuiTree might not support all current folding features
- Position tracking may need custom implementation anyway
- Could discover blockers requiring custom code on top of nui.nvim

## Recommendation

**Keep the custom UI system.**

### Rationale

1. **Architectural Fit** - NeoJJ's custom system is purpose-built for buffer-based component rendering, while nui.nvim targets floating windows and modal interactions.

2. **Working Solution** - The current system successfully powers all NeoJJ buffers with ~450 LOC of clean, focused code.

3. **No Clear Benefits** - nui.nvim doesn't provide features NeoJJ needs (buffer rendering, position tracking, hierarchical layouts) and adds features NeoJJ doesn't need (floating windows, popups, modals).

4. **Cost > Benefit** - 11-17 days of migration work plus ongoing dependency management outweighs potential benefits.

5. **Industry Pattern** - Similar plugins (Neogit, Diffview) use custom buffer rendering systems, validating this approach.

6. **Maintenance is Manageable** - At 450 LOC with a clean architecture, the custom system is maintainable. NeoJJ will need buffer management code regardless; might as well own the rendering layer too.

### Alternative Consideration

If NeoJJ later needs floating windows, popups, or input prompts (e.g., for a commit message editor, confirmation dialogs), consider using nui.nvim **alongside** the custom rendering system for those specific features. This hybrid approach is common and practical.

## References

### nui.nvim Documentation
- GitHub Repository: https://github.com/MunifTanjim/nui.nvim
- Wiki (nui.tree): https://github.com/MunifTanjim/nui.nvim/wiki/nui.tree
- Tutorial: https://muniftanjim.dev/blog/neovim-build-ui-using-nui-nvim/

### Similar Plugin Analysis
- Neogit (custom UI): https://github.com/NeogitOrg/neogit
- Diffview.nvim (custom UI): https://github.com/sindrets/diffview.nvim
- noice.nvim (uses nui.nvim): https://github.com/folke/noice.nvim
- dressing.nvim (uses nui.nvim): https://github.com/stevearc/dressing.nvim

### nui.nvim Known Issues
- Complex layouts discussion: https://github.com/MunifTanjim/nui.nvim/discussions/121
- Limitations with multi-component rendering
- Sequential mounting requirements

### NeoJJ Documentation
- Implementation Plan: docs/NEOJJ_IMPLEMENTATION_PLAN.md
- Neogit Buffer Analysis: docs/neogit-buffer-analysis.md
- Module Architecture: docs/MODULE_ARCHITECTURE.md

---

**Document Version:** 1.0
**Date:** 2025-11-02
**Author:** Claude Code Agent (Evaluation Research)
