# Testing Notes for NeoJJ

This file contains testing-specific guidance for Claude Code when working with the NeoJJ test suite.

## Test Framework: MiniTest

NeoJJ uses [mini.test](https://github.com/echasnovski/mini.test) for testing. Key patterns:

### Basic Test Structure
```lua
local T = MiniTest.new_set()
local expect = MiniTest.expect

T.test_name = function()
  -- Test code here
  expect.equality(actual, expected)
end

return T
```

### Child Neovim Tests
For integration tests that need a full Neovim instance:
```lua
local child = MiniTest.new_child_neovim()

T.test_with_child = function()
  child.lua([[ 
    -- Code runs in child neovim
    expect = require('mini.test').expect 
  ]])
end
```

**Important**: When using `expect` inside `child.lua()` blocks, you must make it available with `expect = require('mini.test').expect`

### Screenshot Tests
Create reference screenshots for visual regression testing:
```lua
T.test_screenshot = function()
  child.lua [[ 
    -- Setup UI
    local buffer = Buffer.create({...})
    buffer:open()
    buffer:render(components)
    vim.cmd('redraw')
  ]]
  expect.reference_screenshot(child.get_screenshot())
end
```

Screenshot files are stored in `tests/screenshots/` with naming pattern: `tests-{filename}---{test_name}`

## Key Assertions

- `expect.equality(actual, expected)` - Test equality
- `expect.no_equality(actual, expected)` - Test inequality  
- `expect.error(function() ... end)` - Test that function throws error
- `expect.no_error(function() ... end)` - Test that function doesn't throw error
- `expect.reference_screenshot(screenshot)` - Visual regression testing

## Running Tests

```bash
# All tests
make test

# Specific test file
make test_file FILE=tests/test_ui.lua

# Within nix environment
nix develop --command make test
```

## Test Categories

### Unit Tests (`tests/test_unit.lua`)
- Pure function testing
- Component creation and validation
- No external dependencies

### Integration Tests (`tests/test_integration.lua`)
- Full UI rendering pipeline
- Buffer management
- Component interaction
- Repository state handling

### UI Tests (`tests/test_ui.lua`)
- Visual components
- Buffer rendering
- Screenshot regression tests
- Highlight group validation

### Command Tests (`tests/test_commands.lua`)
- Vim command registration
- Command completion
- Argument validation

## Testing Best Practices

### Component Testing
```lua
-- Test component creation
local component = Ui.text("test", { highlight = "TestHL" })
expect.equality(component:get_tag(), "Text")
expect.equality(component:get_value(), "test")
expect.equality(component:get_highlight(), "TestHL")
```

### Buffer Testing
```lua
-- Test buffer operations
local buffer = Buffer.create({ name = "Test" })
buffer:open()
expect.equality(buffer:is_valid(), true)
buffer:close()
```

### Highlight Testing
Always test that highlights are properly applied:
```lua
-- Setup highlights first
local Highlights = require('neojj.highlights')
Highlights.setup()

-- Test highlight application
local components = StatusUI.create_diff_components(diff_lines, file_path)
-- Should see different highlight groups for +/- lines
```

## Debugging Tests

### Visual Debugging
Use screenshot tests to verify visual output:
```lua
T.test_visual_output = function()
  child.lua([[
    -- Create test scenario
    -- ... setup code ...
    vim.cmd('redraw')
  ]])
  expect.reference_screenshot(child.get_screenshot())
end
```

### Highlight Debugging
Use the highlight inspector for debugging visual issues:
```lua
-- In test or during development
local inspector = require("neojj.debug.highlight_inspector")
inspector.inspect_at_cursor()
```

### Print Debugging in Child
```lua
child.lua([[
  print("Debug info:", vim.inspect(some_value))
  -- Prints appear in test output
]])
```

## Test Data Patterns

### Mock Repository State
```lua
local mock_repo_state = {
  working_copy = {
    change_id = "test123",
    commit_id = "abc456",
    description = "Test commit",
    author = { name = "Test", email = "test@example.com" },
    modified_files = {
      { status = "M", path = "file1.lua" },
      { status = "A", path = "file2.lua" }
    },
    conflicts = {},
    is_empty = false
  }
}
```

### Mock Status Buffer
```lua
local mock_status_buffer = {
  get_file_diff = function(file_path)
    return {
      "diff --git a/" .. file_path .. " b/" .. file_path,
      "@@ -1,3 +1,4 @@",
      " unchanged line",
      "-deleted line",
      "+added line"
    }
  end
}
```

### Mocking Dependencies with package.loaded

NeoJJ uses lazy `require()` calls (requiring modules inside functions rather than at the top level). This pattern enables easy mocking by injecting mocks into `package.loaded` before the module is used.

**Why this works**: When code calls `require('module')`, Lua first checks `package.loaded['module']`. If found, it returns that cached value without loading the file.

**Pattern from test_describe.lua:99-116**:
```lua
-- Mock the JJ CLI to avoid actual command execution
package.loaded['neojj.lib.jj.cli'] = {
  describe = function()
    return {
      arg = function(self, ...) return self end,
      call = function()
        return { success = true, stdout = '', stderr = '' }
      end,
    }
  end,
  log = function()
    return {
      arg = function(self, ...) return self end,
      call = function()
        return { success = true, stdout = 'Test description', stderr = '' }
      end,
    }
  end,
}

-- Now when DescribeBuffer internally calls require('neojj.lib.jj.cli'),
-- it gets our mock instead of the real module
local DescribeBuffer = require('neojj.buffers.describe')
local buffer = DescribeBuffer.new(mock_repo, '@')
```

**Module reload pattern** (test_unit.lua:21):
```lua
-- Force fresh module load for each test
package.loaded["neojj"] = nil
M = require("neojj")
```

**Alternative: Direct function replacement** when module is already loaded:
```lua
M.jj_describe = function(dir, revision, split)
  table.insert(calls, { dir = dir, revision = revision, split = split })
end
```

Use `package.loaded` mocking when:
- The code uses lazy requires (require inside functions)
- You need to mock dependencies without modifying source code
- You want to avoid executing external commands (like `jj`)
- Testing error conditions from dependencies

## Test Environment

Tests run in a minimal Neovim environment (`scripts/minimal_init.lua`) that:
- Loads only necessary dependencies
- Sets up MiniTest
- Configures basic Neovim options
- Does NOT load full plugin configuration

## Regression Testing

### When to Add Screenshot Tests
- New UI components
- Visual changes to existing components  
- Highlight group modifications
- Layout changes

### When Screenshot Tests Fail
1. Check if change is intentional
2. If intentional, regenerate reference with `make test_file FILE=tests/test_ui.lua`
3. Review the new screenshot for correctness
4. Commit the updated reference screenshot

## Common Test Patterns

### Testing Async Operations
```lua
T.test_async = function()
  child.lua([[
    local async_completed = false
    -- Trigger async operation
    vim.defer_fn(function()
      async_completed = true
    end, 100)
    
    -- Wait for completion
    vim.wait(1000, function() return async_completed end)
    expect.equality(async_completed, true)
  ]])
end
```

### Testing Error Conditions
```lua
T.test_error_handling = function()
  expect.error(function()
    -- Code that should throw
    StatusBuffer.new(nil) -- Invalid repo
  end)
end
```

### Testing Interactive Components
```lua
T.test_interactive = function()
  local component = Ui.file_item("M", "test.lua", {
    item = { path = "test.lua" },
    interactive = true
  })
  
  expect.equality(component:is_interactive(), true)
  expect.equality(component:get_item().path, "test.lua")
end
```

## Performance Testing

Keep tests fast by:
- Using minimal test data
- Avoiding unnecessary async operations
- Mocking external dependencies (JJ CLI calls)
- Reusing child neovim instances when possible

## Test Maintenance

### Adding New Tests
1. Choose appropriate test file based on category
2. Follow existing naming conventions
3. Add documentation for complex test scenarios
4. Update this file if introducing new patterns

### Debugging Test Failures
1. Run single test file: `make test_file FILE=tests/test_failing.lua`
2. Add debug prints to understand state
3. Use screenshot tests to verify visual output
4. Check highlight inspector for visual issues