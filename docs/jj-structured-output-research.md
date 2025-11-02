# Jujutsu (jj) Structured Output Research

**Date**: 2025-11-02
**Research Focus**: Current state of structured/JSON output support in Jujutsu VCS

## Executive Summary

Jujutsu **does support structured JSON output**, but through its templating system rather than via universal `--json` flags. The template system includes a `json()` function (added in v0.31.0, released July 2025) that can serialize values to JSON format. However, not all commands support templates, and `jj status` notably lacks template support.

**Key Finding**: NeoJJ should continue using regex parsing for `jj status` but can leverage template-based JSON output for other commands like `jj log`, `jj show`, `jj file list`, etc.

## Current State of Structured Output Support

### Template System with JSON Support

As of **v0.31.0** (2025-07-02), Jujutsu includes a `json()` function in its template language:

```bash
# Example: Get commit metadata as JSON
jj log -r @ -T 'json(self) ++ "\n"' --no-graph

# Example: Get specific fields as JSON
jj log -T 'json(commit_id) ++ " " ++ json(description) ++ "\n"' --no-graph
```

The `json()` function can serialize any `Serialize` type to JSON format. Field names and value types are "usually stable across jj versions, but backward compatibility isn't guaranteed."

### Commands Supporting Templates

The following commands accept the `-T`/`--template` flag (as of the latest documentation):

1. **`jj log`** - List revisions (Commit type)
2. **`jj evolog`** - Show evolution history (CommitEvolutionEntry type)
3. **`jj show`** - Show commit details (Commit type)
4. **`jj bookmark list`** - List bookmarks
5. **`jj file list`** - List files (TreeEntry type)
6. **`jj file show`** - Show file content with metadata
7. **`jj file annotate`** - Show file annotations (AnnotationLine type)
8. **`jj diff`** - Show differences (TreeDiffEntry type)
9. **`jj config list`** - List configuration (supports `json(self)` as of v0.33.0)
10. **`jj op show`** - Show operation details (added in v0.33.0)

### Commands WITHOUT Template Support

**`jj status`** does NOT support templates. This is the primary command NeoJJ uses and must be parsed with regex.

### Additional Template Features

- **`.escape_json()` method** (v0.24.0+): Escape strings for JSON embedding
  ```bash
  jj log -T '{"description": ' ++ description.escape_json() ++ '}\n'
  ```

- **String pattern matching** (v0.33.0): `string.match(pattern)`
- **List predicates** (v0.33.0): `any()` and `all()` methods
- **Arithmetic operators** (v0.30.0): `+`, `-`, `*`, `/`, `%` on integers

## Serializable Types

The following types can be serialized with `json()`:

- **Primitive types**: Boolean, Integer, String
- **Commit**: Author, committer, change_id, commit_id, description, etc.
- **Operation**: ID, description, timestamp, user
- **CommitRef, ChangeId, CommitId**: Reference types
- **Lists**: Serialize as JSON arrays
- **ConfigValue**: Configuration values

## Ongoing Development & Feature Requests

### Open Issue: Universal --json Flag

**Issue #5662**: "FR: All commands to have optional structured output, eg. --json"
**Status**: Open (no active development as of research date)
**URL**: https://github.com/jj-vcs/jj/issues/5662

This feature request proposes adding `--json` to popular commands for easier scripting:
```bash
CHANGE_ID=$(jj new main --json | jq .change_id)
```

**Community Discussion**:
- Alternative suggestion: `--output-format=json` or `--output=json` (similar to AWS CLI)
- No implementation work or pull requests currently linked
- Issue remains in backlog awaiting prioritization

### Completed: JSON Function Support

**Issue #5648**: "FR: Add a `json` function in template language"
**Status**: CLOSED - Implemented
**Resolution**: Added `.escape_json()` method (PR #5671) and later `json()` function (v0.31.0)

## Recent Changes (2024-2025)

### v0.34.0 (2025-10-01)
- String `.replace()` method with pattern-based replacement
- `hyperlink(url, text)` builtin for OSC8 terminal links

### v0.33.0 (2025-09-03)
- `jj config list` supports `json(self)` serialization
- `jj file show` accepts `-T`/`--template` option
- `any()` and `all()` methods for list predicates
- String pattern matching via `string.match(pattern)`
- `jj op show` accepts `-T`/`--template` option

### v0.31.0 (2025-07-02)
- **Templates gained `json(x)` function** for JSON serialization

### v0.28.0 (2025-04-02)
- `jj config list` supports showing variable origin via `builtin_config_list_detailed` template

### v0.26.0 (2025-02-05)
- Cryptographic signature display templates

## Recommendations for NeoJJ

### Short-Term Strategy (Current)

**Continue using regex parsing for `jj status`**:
- `jj status` does not support templates
- Regex parsing is the only reliable option
- Current implementation in `lua/neojj/lib/jj/status.lua` is appropriate

**Leverage templates for other commands**:
- Already using templates in `status.lua` line 76:
  ```lua
  cli.log()
    :arg("-r")
    :arg("@")
    :option("template", 'change_id ++ "\\n" ++ commit_id ++ "\\n" ++ description')
    :flag("no-graph")
  ```
- This approach is good but could use JSON for more robust parsing

### Medium-Term Improvements

1. **Use `json()` for `jj log` output**:
   ```lua
   -- Current approach (string concatenation):
   :option("template", 'change_id ++ "\\n" ++ commit_id ++ "\\n" ++ description')

   -- Better approach (JSON):
   :option("template", 'json(self) ++ "\\n"')
   ```
   This provides structured data that's easier to parse and less fragile.

2. **Use templates for file operations**:
   - `jj file list -T 'json(self) ++ "\n"'`
   - `jj file show -T 'json(self) ++ "\n"'`

3. **Use templates for bookmark/branch information**:
   - `jj bookmark list -T 'json(self) ++ "\n"'`

4. **Consider templates for diff operations**:
   - `jj diff -T 'json(self) ++ "\n"'` (added in recent versions)

### Long-Term Strategy

**Monitor Issue #5662** for universal `--json` flag:
- If implemented, refactor to use `--json` flag across all commands
- This would eliminate need for custom template strings
- Would provide more consistent output format

**Watch for `jj status` template support**:
- File a feature request if needed
- Structured output for status would significantly improve parsing reliability
- Could eliminate complex regex patterns

### Migration Path

1. **Phase 1** (Now): Continue regex for `jj status`, use simple templates for `jj log`
2. **Phase 2** (Next): Migrate to JSON templates for all template-supporting commands
3. **Phase 3** (Future): When `--json` flag is available, refactor to use universal flag

## Example Implementations

### Current NeoJJ Usage (status.lua)
```lua
-- Line 73-79: Using template for jj log
local show_result = cli.log()
    :arg("-r")
    :arg("@")
    :option("template", 'change_id ++ "\\n" ++ commit_id ++ "\\n" ++ description')
    :flag("no-graph")
    :cwd(repo.dir)
    :call()
```

### Recommended Improvement
```lua
-- Using JSON template for more robust parsing
local show_result = cli.log()
    :arg("-r")
    :arg("@")
    :option("template", 'json(self) ++ "\\n"')
    :flag("no-graph")
    :cwd(repo.dir)
    :call()

-- Then parse JSON:
if show_result.success and show_result.stdout then
    local ok, data = pcall(vim.json.decode, show_result.stdout)
    if ok then
        repo.state.working_copy.change_id = data.change_id
        repo.state.working_copy.commit_id = data.commit_id
        repo.state.working_copy.description = data.description
    end
end
```

### Building Complex Templates

For selective field output:
```lua
-- Get specific fields as JSON object
local template = [[
{
  "change_id": ]] .. json(change_id) .. [[,
  "commit_id": ]] .. json(commit_id) .. [[,
  "description": ]] .. json(description) .. [[,
  "author": ]] .. json(author) .. [[
}
]]

:option("template", template)
```

Or use the entire object:
```lua
-- Get all available fields
:option("template", 'json(self) ++ "\\n"')
```

## Stability & Compatibility Notes

From the official documentation:

> "Field names and value types in the serialized output are usually stable across jj versions, but backward compatibility isn't guaranteed."

**Implications for NeoJJ**:
- JSON output is relatively stable but not guaranteed
- Include jj version detection and graceful fallbacks
- Log warnings when JSON parsing fails
- Consider adding version-specific templates if needed

## Testing Considerations

When implementing JSON-based parsing:

1. **Test with multiple jj versions**:
   - v0.31.0+ (when `json()` was added)
   - Current stable release
   - Development versions

2. **Test edge cases**:
   - Empty descriptions
   - Multi-line descriptions
   - Special characters in commit messages
   - Unicode characters

3. **Fallback handling**:
   - Detect when JSON parsing fails
   - Fall back to string parsing if needed
   - Log appropriate warnings

4. **Performance**:
   - JSON parsing may be slower than simple string splitting
   - Benchmark critical paths (status refresh)

## Useful Links

- **Templating Documentation**: https://jj-vcs.github.io/jj/latest/templates/
- **CLI Reference**: https://jj-vcs.github.io/jj/latest/cli-reference/
- **Changelog**: https://jj-vcs.github.io/jj/latest/changelog/
- **Issue #5662** (--json flag): https://github.com/jj-vcs/jj/issues/5662
- **Issue #5648** (json function): https://github.com/jj-vcs/jj/issues/5648
- **GitHub Repository**: https://github.com/jj-vcs/jj
- **Template Tutorial**: https://steveklabnik.github.io/jujutsu-tutorial/customization/templates.html

## Conclusion

Jujutsu provides solid structured output support through its templating system, with the `json()` function being a mature and usable feature as of v0.31.0. However, the lack of template support in `jj status` means NeoJJ must maintain regex parsing for that command.

**Recommendation**: Adopt a hybrid approach:
1. Continue regex parsing for `jj status` (no alternative available)
2. Migrate to JSON templates for all other operations (`jj log`, `jj file list`, etc.)
3. Monitor upstream development for universal `--json` flag support
4. File feature requests for `jj status` template support if needed

This approach balances immediate reliability with future maintainability while taking advantage of Jujutsu's existing structured output capabilities.
