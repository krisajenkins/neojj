## Issues and Analysis

### 1. Deprecated API Usage
- [ ] **nvim_buf_set_option() is deprecated. Use nvim_set_option_value() instead.**

**Current Usage Found:**
- `lua/neojj/lib/buffer.lua:77` - Used in loop to set buffer options
- `lua/neojj/lib/buffer.lua:128` - Setting "modifiable" to true  
- `lua/neojj/lib/buffer.lua:134` - Restoring "modifiable" state
- `lua/neojj/buffers/describe/init.lua:296` - Setting "modified" to false

**Also Found:**
- `lua/neojj/buffers/describe/init.lua:131` - Uses deprecated `nvim_buf_get_option()`
- `lua/neojj/buffers/describe/init.lua:233` - Uses deprecated `nvim_buf_get_option()`

**Migration Pattern:**
```lua
-- Before:
vim.api.nvim_buf_set_option(bufnr, "option_name", value)
vim.api.nvim_buf_get_option(bufnr, "option_name")

-- After:
vim.api.nvim_set_option_value("option_name", value, { buf = bufnr })
vim.api.nvim_get_option_value("option_name", { buf = bufnr })
```

### 2. Filetype Inconsistencies
- [ ] **We have created two new filetypes: `jjdescribe` and `neojj-status`. This creates some problems:**

**Current Filetypes:**
- `jjdescribe` - Used for commit description editing buffers
- `neojj-status` - Used for status view buffers

**Analysis:** The naming is inconsistent (`jjdescribe` vs `neojj-status`). The `neojj-${command}` pattern is more consistent and scalable.

  - [ ] **We should use consistent naming for new filetypes. I think `neojj-${command}` makes more sense.**
  
  **Recommended Changes:**
  - `jjdescribe` → `neojj-describe` ✅ **COMPLETED**
  - `neojj-status` (already correct)
  - Future commands should follow `neojj-${command}` pattern

  **Files Updated:**
  - ✅ `lua/neojj/buffers/describe/init.lua` - Changed filetype from "jjdescribe" to "neojj-describe"
  - ✅ `syntax/jjdescribe.vim` → `syntax/neojj-describe.vim` - Renamed and updated syntax file
  - ✅ `ftdetect/neojj.vim` - Updated filetype detection patterns

  - [ ] **We need to be consistent about creating buffers. We seem to have code in `lua/neojj/buffers/${command}/init.lua`, but also `lua/neojj/lib/buffer.lua` has `Buffer.create_status`. What's redundant? How does NeoGit handle this? Follow their structure.**

  **Current Architecture Issues:**
  - Mixed buffer creation patterns: factory methods vs direct instantiation
  - Status buffer uses `Buffer.create_status()` factory method
  - Describe buffer uses `Buffer.new()` directly with custom configuration
  - Inconsistent approaches between buffer types

  **NeoGit's Approach:**
  - Single `Buffer.create(config)` factory method for all buffers
  - All buffer-specific logic is configuration-driven
  - Unified, consistent approach across all buffer types

  **Recommended Solution:**
  - Remove `Buffer.create_status()` specialized factory method
  - Update all buffers to use a unified `Buffer.create(config)` factory
  - Move buffer-specific logic to configuration objects
  - Follow NeoGit's pattern for consistency

  - [ ] **Describe and Status both have syntax highlighting, but only describe is using a `syntax/jjdescribe.vim` file. So how is Status being syntax highlighted? And why isn't it the same for both? And what does NeoGit do?**

  **Current Syntax Highlighting Analysis:**

  **Describe Buffer:**
  - Uses traditional Vim syntax file: `syntax/jjdescribe.vim`
  - Filetype detection via `ftdetect/neojj.vim`
  - Pattern-based highlighting with regex matching

  **Status Buffer:**
  - Uses **programmatic highlighting** through component-based UI system
  - No traditional syntax file - highlights applied via `lua/neojj/lib/ui/renderer.lua`
  - Highlight groups defined in `lua/neojj/highlights.lua`
  - Uses `vim.api.nvim_buf_add_highlight()` for precise character-level highlighting

  **Technical Implementation:**
  - Components store highlight group names via `get_highlight()` method
  - Renderer applies highlights during buffer rendering using Neovim's API
  - Uses namespace `neojj_ui` for highlight management
  - More precise control than pattern-based syntax files

  **NeoGit's Approach:**
  - Uses entirely programmatic highlighting (no traditional syntax files)
  - All highlighting handled through centralized highlight system
  - Consistent approach across all buffer types

  **Why Different Approaches:**
  - Status buffer uses modern component-based rendering system
  - Describe buffer uses older traditional syntax file approach
  - Inconsistent implementation between buffer types

  **Recommended Solution:**
  - Choose one approach for consistency (recommend programmatic highlighting)
  - If keeping syntax files, create `syntax/neojj-status.vim`
  - If going programmatic, remove `syntax/jjdescribe.vim` and implement through renderer

## Implementation Plan

### Phase 1: Fix Deprecated APIs (High Priority)
1. **Update nvim_buf_set_option() calls** in `lua/neojj/lib/buffer.lua` (3 instances)
2. **Update nvim_buf_get_option() calls** in `lua/neojj/buffers/describe/init.lua` (2 instances)
3. **Update nvim_buf_set_option() calls** in `lua/neojj/buffers/describe/init.lua` (1 instance)
4. **Test all buffer operations** to ensure functionality remains intact

### Phase 2: Standardize Filetype Naming (Medium Priority)
1. **Rename filetype** from "jjdescribe" to "neojj-describe" in describe buffer
2. **Rename syntax file** from `syntax/jjdescribe.vim` to `syntax/neojj-describe.vim`
3. **Update filetype detection** in `ftdetect/neojj.vim`
4. **Update any references** to old filetype name in documentation/comments

### Phase 3: Unify Buffer Creation Architecture (Medium Priority)
1. **Remove specialized factory method** `Buffer.create_status()` from `lua/neojj/lib/buffer.lua`
2. **Create unified factory method** `Buffer.create(config)` following NeoGit pattern
3. **Update status buffer** to use unified factory method
4. **Update describe buffer** to use unified factory method  
5. **Refactor buffer-specific logic** into configuration objects

### Phase 4: Standardize Syntax Highlighting (Low Priority)
**Full Programmatic Highlighting**
1. **Remove** `syntax/jjdescribe.vim` file
2. **Implement describe buffer highlighting** through renderer system
3. **Extend highlight groups** in `lua/neojj/highlights.lua` for describe buffer
4. **Update describe buffer UI** to use component-based highlighting
5. Remove old syntax-file approach for JJ Describe.

### Testing Strategy
- **Unit tests** for buffer creation and option setting
- **Integration tests** for syntax highlighting in both buffer types
- **Manual testing** of all buffer operations and visual appearance
- **Regression testing** to ensure no functionality is broken

### Priority Order
1. **Phase 1** (Deprecated APIs) - Immediate (prevents warnings)
2. **Phase 2** (Filetype naming) - Next (improves consistency)
3. **Phase 3** (Buffer architecture) - Medium term (architectural improvement)
4. **Phase 4** (Syntax highlighting) - Future (consistency improvement)
