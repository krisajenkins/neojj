# Bug Report: lua-language-server --check mode doesn't respect .luarc.lua when checking directories

## Problem Description

The lua-language-server's `--check` command does not properly apply `.luarc.lua` configuration when given a directory path, but works correctly when checking individual files.

## Expected Behavior

When running `lua-language-server --check <directory>`, the language server should:
1. Recursively find all `.lua` files in the directory
2. Apply the `.luarc.lua` configuration from the working directory
3. Respect global variable definitions to suppress "undefined global" warnings

## Actual Behavior

When checking a directory, the configuration is ignored and all "undefined global" warnings are shown, even for globals defined in `.luarc.lua`.

## Reproduction Steps

### Setup Test Environment

1. Create a test directory structure:
```
test-project/
├── .luarc.lua
├── src/
│   ├── main.lua
│   └── utils.lua
```

2. Create `.luarc.lua` with the following content:
```lua
return {
  runtime = {
    version = "LuaJIT"
  },
  diagnostics = {
    globals = {"vim", "customGlobal"}
  },
  workspace = {
    checkThirdParty = false
  }
}
```

3. Create `src/main.lua`:
```lua
-- This should not trigger undefined global warnings
print(vim.inspect({test = true}))
local result = vim.fn.getcwd()
customGlobal.doSomething()
```

4. Create `src/utils.lua`:
```lua
-- More vim globals that should be recognized
local list = vim.list_extend({}, {1, 2, 3})
vim.notify("Hello from utils")
```

### Test the Bug

1. **Directory check (BUG - shows warnings):**
```bash
cd test-project
lua-language-server --check src
```
Expected: No "undefined global" warnings for `vim` or `customGlobal`
Actual: Shows multiple "undefined global" warnings

2. **Individual file check (WORKS - no warnings):**
```bash
lua-language-server --check src/main.lua
lua-language-server --check src/utils.lua
```
Expected: No warnings
Actual: No warnings (correct behavior)

3. **Explicit config path (still broken for directories):**
```bash
lua-language-server --configpath=.luarc.lua --check src
```
Expected: No warnings
Actual: Still shows warnings

## Investigation Tasks

1. **Locate the --check command implementation:**
   - Find where the `--check` flag is processed in the codebase
   - Identify how it handles directory vs file arguments
   - Look for differences in configuration loading between modes

2. **Trace configuration loading:**
   - Find where `.luarc.lua` files are discovered and loaded
   - Check if the config loading path differs for directory checking
   - Verify if the working directory context is maintained during directory checks

3. **Debug the directory traversal:**
   - See how directory arguments are expanded to individual files
   - Check if configuration context is lost during file enumeration
   - Verify if each file gets the proper workspace context

4. **Test the fix:**
   - Ensure directory checking applies the same config as individual file checking
   - Verify recursive directory traversal works correctly
   - Test edge cases like nested directories and multiple config files

## Files to Examine

Look for these areas in the lua-language-server codebase:
- Command line argument parsing (likely in `main.lua` or similar)
- Configuration loading logic (`.luarc.lua` discovery and parsing)
- Check mode implementation
- Directory traversal and file enumeration code
- Workspace/project root detection

## Success Criteria

After the fix:
1. `lua-language-server --check src` should produce the same results as checking individual files
2. Configuration should be properly applied for all files in the directory
3. Recursive directory checking should work correctly
4. No regression in individual file checking behavior

## Additional Context

- This bug affects CI/CD pipelines and automated code quality checks
- Workaround currently requires explicitly listing all files instead of using directory paths
- The inconsistency makes the tool less reliable for batch operations

Please investigate and fix this issue, ensuring that directory-based checking respects configuration files the same way individual file checking does.