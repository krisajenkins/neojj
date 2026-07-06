# TODO — Polished v0.1

Scope: harden what exists (status, log, describe, annotate), fix review
findings, fill test gaps, docs, `:checkhealth`, CI. New features live in
`TODO_DAILY_DRIVER.md` — cherry-pick items from there into this file when
they're wanted.

Items are ordered: correctness blockers → majors → hardening → tests → docs →
CI. Note the ordering dependency: the log-template rewrite must land **before**
the empty-environment fix, because fixing the env will let user-configured jj
log templates load and break the current parser.

# [ ] Use the repo root, not the cwd, for all path handling

`repo.dir` is just Neovim's cwd at first use, not the repo root
(`repository.lua:38`), and three features confuse the two:

- `jj_annotate` (`lua/neojj.lua:348-394`) prefix-checks and joins file paths
  against `repo.dir` → false "Current file is not in the repository" errors when
  cwd is a subdirectory; the unanchored `sub(1, #dir)` check also matches
  sibling dirs (`/a/bc` vs `/a/b`) and fails across macOS symlinks
  (`/tmp` vs `/private/tmp`).
- `StatusBuffer:open_file_at_cursor` (`status/init.lua:503-517`) runs `:edit
  <relative path>` against whatever the current cwd is — opens a nonexistent new
  file if the user has `:cd`-ed.
- `M.jj_split` (`neojj.lua:399-415`) permanently changes the window's `lcd` as a
  side effect **and** interpolates the revision unescaped into a `:terminal`
  command — revsets routinely contain spaces and parens.

Fix: use `repo:get_root()` normalised via `vim.loop.fs_realpath` with a
trailing-`/`-anchored prefix comparison in `jj_annotate`; open files by absolute
path in `open_file_at_cursor`; in `jj_split`, drop the `lcd` and launch via
`vim.fn.jobstart({...}, {cwd = root, term = true})` (or `shellescape` the
revision and restore the previous `lcd`).

# [ ] Match NeoJJ buffers by exact name

`Buffer.from_name` (`lua/neojj/lib/buffer.lua:27-34`) uses `vim.fn.bufnr(name)`,
which does file-pattern *partial* matching (verified: with `"NeoJJ Status:
abc12345"` open, `bufnr("NeoJJ Status")` returns it). Opening plain `:JJ status`
hijacks and renames the revision buffer, leaving two StatusBuffer instances
sharing one handle with mixed keymaps; a user file whose path matches the
pattern could even be converted to a wipeable `nofile` scratch buffer. Names
with pattern chars (`JJ Annotate: <path>` containing `[`/`*`) are also affected.

Fix: iterate `vim.api.nvim_list_bufs()` comparing `nvim_buf_get_name()` for
exact equality (mind the cwd prefix on unnamed-path buffers) instead of
`bufnr(name)`. Add a regression test.

# [ ] Namespace buffers per repo

Buffer names are fixed strings (`"NeoJJ Status"` at `status/init.lua:40`,
`"NeoJJ Log"` at `log/init.lua:24-43`) while instances are keyed per repo
(`status/init.lua:14-29`), so status views for two different repos share one
underlying nvim buffer — the second repo's `_setup_mappings` closures overwrite
the first's, and a still-"valid" first instance renders repo A's content while
`r`/`d`/`n` act on repo B.

Fix: include a repo identifier (root basename, disambiguated) in the buffer
name. Do this after the exact-name matching fix above.

# [ ] Re-detect repositories initialised after first use

`JjRepo.instance` memoises per cwd and `detect_repository` only runs in the
constructor (`lua/neojj/lib/jj/repository.lua:49-57,127-137`). A repo created
with `jj git init` *after* the first `:JJ` call is never recognised — every
command reports "Not a jj repository" until Neovim restarts.

Fix: in `JjRepo.instance` (or at the top of the `M.jj_*` entry points), re-run
`detect_repository()` when the cached state has `jj_dir == ""`.

# [ ] Close windows when closing NeoJJ views

Closing the annotate view (`lua/neojj/buffers/annotate/init.lua:333-342`)
deletes the buffer but leaves its 30-column vsplit orphaned showing an arbitrary
buffer — after *every single use*. Similarly, `q` in status/log is a bare
`<cmd>bdelete<cr>` (`status/init.lua:57-59`, `log/init.lua:58-60`) that leaves
splits/tabs open when the view was opened via `:JJ status vertical` etc.

Fix: in each close path, find the view's window (`vim.fn.bufwinid`) and
`nvim_win_close` it (unless it's the last window) before deleting the buffer;
track the window created by `Buffer:open` so split-opened views clean up. Route
the string mappings through `Buffer:map` so they carry `desc`s.

# [ ] Make the plugin work without setup() and validate options

The `:JJ` command is only created inside `M.setup()`, which `plugin/neojj.lua`
never calls — a user who installs the plugin without a `setup()` call gets
highlights but no command. `setup()` also performs no option validation
(`log_level = "debug"` as a string would silently break the logger's numeric
comparisons) (`lua/neojj.lua:34-39`).

Fix: create the `:JJ` user command idempotently from `plugin/neojj.lua`;
validate `opts` (e.g. `vim.validate`) in `M.setup`.

# [ ] Describe buffer: don't wipe user input on async load

The describe buffer opens empty, schedules `startinsert`, and the async
`load_current_description` render lands later
(`lua/neojj/buffers/describe/init.lua:129-144, 263-299`) — erasing anything the
user has already typed and force-resetting `'modified'`.

Fix: render the current description synchronously before showing the buffer, or
skip the render if the buffer is already modified.

# [ ] Annotate robustness: cursor parsing, scroll alignment, help

Three fixes in `lua/neojj/buffers/annotate/`:

- `get_change_id_at_cursor` (`init.lua:204-236`) returns the first word of any
  line, so `<CR>` on the "No annotations available" line opens a status view for
  revision `"No"`. Validate with the same pattern as
  `AnnotateUI.parse_annotate_line`, or store change IDs as component items and
  use `get_item_at_cursor`.
- Scrollbind is enabled without `:syncbind` and before the async render lands,
  and `AnnotateUI.create` drops unparseable output lines, so annotation rows can
  be offset from source lines with no re-sync (`init.lua:125-148`). Call
  `vim.cmd("syncbind")` after `render_components()` and emit a placeholder line
  for unparseable annotate output to preserve 1:1 alignment.
- Add a `?` help mapping for parity with status/log (annotate currently has
  bindings but no help).

# [ ] Cursor handling and render robustness fixes

A cluster of small verified correctness fixes:

- `toggle_file_diff` cursor restore (`status/init.lua:409-427`) can match an
  interactive *diff line* (same `path`, see `status/ui.lua:374-379`) and call
  `set_cursor` past the end of the shortened buffer after collapse → "Cursor
  position outside buffer" error at the user. Match only header components
  (`get_item().line == nil`) and clamp to `nvim_buf_line_count`.
- `expanded_files` is keyed by bare path shared between the Modified and
  Conflicts sections (`status/init.lua:431-457`, `status/ui.lua:152-171`) —
  toggling a file present in both toggles both. Namespace the key by section.
- `Buffer:get_cursor`/`set_cursor` (`lua/neojj/lib/buffer.lua:230-246`) use
  `win_findbuf(...)[1]` — an arbitrary window; with the buffer in two splits,
  cursor actions act on the wrong item. Prefer `nvim_get_current_win()` when it
  shows the buffer, falling back to `win_findbuf`.
- Guard `Buffer:render`/`refresh` (`buffer.lua:166-179,277-281`) with
  `self:is_valid()` — the 100 ms `vim.defer_fn` callbacks in `lua/neojj.lua`
  can fire after a `bufhidden=wipe` buffer is gone, throwing "Invalid buffer
  id".
- Fix `Renderer.add_line`'s latent highlight off-by-one
  (`lua/neojj/lib/ui/renderer.lua:34-47`): record the highlight at
  `#context.lines - 1` after insertion so `add_line` and `add_text` share one
  source of truth.
- Prune stale entries from the `instances` maps (`status/init.lua:14-29` and
  equivalents) when buffers are wiped, via `BufUnload`/`on_detach`.

# [ ] Keybinding and help consistency pass

- Remove the `j`/`k` remaps (`status/init.lua:147-153`,
  `log/init.lua:136-142`) — they replicate default motion but drop count
  support (`5j` moves one line).
- Decide `<esc>` behaviour once: closing the whole view on a reflexive Esc is
  surprising; either drop the binding or apply it consistently (describe has
  none).
- Fix help-text drift: log help (`log/ui.lua:282-307`) omits `y` and `<C-r>`;
  status help (`status/ui.lua:455-474`) omits `<C-c>`.
- Give the `q`/`<c-c>`/`<esc>` string mappings `desc`s by routing them through
  `Buffer:map`.

# [ ] Raise the log limit and preserve log options

The log view is silently capped at 10 revisions (`options.limit or 10`,
`lua/neojj/buffers/log/init.lua:193-196`) with no way to see more, and
`LogBuffer.new` resets `instance.options = options` on every reuse
(`log/init.lua:20-27`), discarding previously configured options.

Fix: raise the default to ~100 (make it a `setup()` option), merge rather than
replace options on instance reuse, and accept a count argument to `:JJ log`.
(Revset filtering UI is a daily-driver feature, not this item.)

# [ ] Remove dead code and the unimplemented D binding

Release hygiene — all verified unused or broken:

- The `D` mapping prints "Diff display not yet implemented"
  (`status/init.lua:520-523`, mapping at `:132-134`) yet is advertised in the
  `?` help (`status/ui.lua:468`) and README. Remove mapping, stub, and help
  line — the real diff view is on the daily-driver list.
- Legacy `M.status()` (`lua/neojj.lua:152-190`): `print()`-based dump relying on
  the accidental synchrony of `refresh()`. Delete.
- `Cli:call_async` and unused builders `bookmark/operation/workspace/util/
  debug/config/git` (`cli.lua:117-172`). Delete (they'll come back with the
  features that need them).
- `Highlights.group_exists` (`highlights.lua:108-119`) always throws
  (`nvim_exec2` rejects `on_output`); unused. Delete. Also fix `NeoJJDiffFile`
  linking to nonexistent group `DiffFile` (`highlights.lua:59`) — link to
  `diffFile` or a real builtin.
- `describe/ui.lua:78-171` (`parse_line`, `parse_keybinding_line`,
  `parse_command_line`), `log/ui.lua:253-267` (`create_enhanced_graph`) and
  `log/ui.lua:175-179` (no-op `highlight_graph`). Delete.
- `ftdetect/neojj.vim`: augroup-less autocmd on every `BufRead,BufNewFile *`
  whose condition can never be true at BufRead time. Delete (the filetype is
  set programmatically).
- Move `create_test_ui` fixtures (`status/ui.lua:478`, `log/ui.lua:311`) into
  `tests/`.
- Trim `Buffer.create`'s never-honoured config fields and the TODO
  floating-window branch (`buffer.lua:418`); either wire up or remove the
  unreachable section-folding path (`Ui.section` sets `foldable` but nothing
  toggles `folded`; `renderer.lua:92-101`).

Run `make` after each deletion batch.

# [ ] Extract shared buffer helpers to stop copy-paste drift

The describe-submit callback logic exists three times
(`log/init.lua:319-352`, `status/init.lua:526-560`, `neojj.lua:229-273`) with
100 ms `vim.defer_fn` focus hacks, and has already drifted (the `neojj.lua` copy
claims to refresh status buffers but only focuses them). `move_cursor_up/down`,
`show/show_split/show_tab`, `render_error`, `is_valid`, `get_handle` are
copy-pasted across all four buffer classes.

Fix: extract a shared `buffers/common.lua` (or push the methods onto `Buffer`);
replace the defer_fn timing hacks by focusing from the describe buffer's close
path. Pure refactor — behaviour covered by the suite before and after.

# [ ] Fix the two integration tests that pass without testing anything

`tests/test_integration_workflows.lua:160` uses `vim.cmd("normal! \\<CR>")` —
that sends literal `\<CR>` characters, and `normal!` bypasses buffer-local
mappings anyway; the reference screenshot for
`test_workflow_log_to_commit_navigation` still shows the **log** view (only the
cursor moved). Same bug at `:221` for the `?` help test — its screenshot shows
no help panel.

Fix: use `child.type_keys("<CR>")` / `child.type_keys("?")`, assert the buffer
content actually changed (e.g. contains `"Change ID:"` / help text), and
re-baseline the screenshots. Also replace the seven `vim.wait(500)` sleeps in
this file with condition-based waits where practical.

# [ ] Make the mock CLI fail loudly on unknown fixtures

`tests/helpers/mock_cli.lua:181-188` returns `success = true, stdout = ""` when
no fixture matches a command, silently masking drift — this is likely how the
broken integration tests above got baselined green.

Fix: `error()` (or return `success=false` with a loud stderr) on an unmatched
command, then fix whatever fallout appears.

# [ ] Add cursor-interaction and keybinding tests

The cursor-interaction system CLAUDE.md calls central has zero tests:

- `Buffer:get_component_at_cursor` / `get_item_at_cursor`
  (`lua/neojj/lib/buffer.lua:250-276`): child-nvim tests rendering
  `StatusUI.create_test_ui()`, with the cursor on a file row, above the first
  interactive row, on the last line, and in an empty buffer — assert the
  returned item's `path`.
- Keybinding-driven tests via `child.type_keys`: `<tab>` on a file toggles diff
  lines into the status buffer; `y` in the log buffer yanks the change ID
  (assert `getreg`); `q` closes the view; `r` refreshes after
  `MockCli.set_state` switches fixtures and the new content appears.

# [ ] Add error-path tests

With the mock CLI returning `success=false, stderr=...`: drive `:JJ status` /
`StatusBuffer:refresh` and assert `render_error` output appears in the buffer.
Test `:JJ status` in a directory with no `.jj` (friendly message, no crash) and
the missing-jj-executable path. These lock in the error-handling items above.

# [ ] Replace the machine-dependent test and clean up the suite

`tests/test_unit.lua:29-37` runs real `jj` against the developer's live checkout
and `print()`s the result instead of asserting (output includes the local
author). Replace with a hermetic temp-dir test making real assertions.
Also: delete the duplicated component/highlight cases in `test_simple.lua` /
`test_integration.lua` (covered better by `test_components.lua` /
`test_ui.lua`), remove `print("✓ ...")` noise, fix the jammed statements at
`test_describe.lua:79`, and correct `tests/CLAUDE.md`'s description of
`test_unit.lua` (it claims "no external dependencies" — currently the opposite).

# [ ] Fixture housekeeping

`fixtures/demo-repo/` is untracked and nondeterministic:
`fixtures/create-demo-repo.sh` pins `JJ_USER`/`JJ_EMAIL`/`JJ_TIMESTAMP` but jj
change IDs are random, so regenerating produces IDs that no longer match the
frozen `tests/fixtures/jj-outputs/*` or the 11 reference screenshots.

Fix: treat the committed `tests/fixtures/jj-outputs/` as canonical; add
`/fixtures/demo-repo/` to `.gitignore`; document in `tests/CLAUDE.md` that
regenerating the demo repo re-baselines everything, and record which jj version
the fixtures were captured with. Recapture the oddball
`dotfile-test-status.txt` (mode 0600, captured from the real neojj repo, not
the demo repo) from the demo repo for consistent provenance.

# [ ] Add second-wave tests: parsers, CLI contract, repository, describe

Lower-urgency but wanted before calling the suite trustworthy:

- Malformed-input parser tests: truncated status output, unknown status
  letters, ANSI-coloured input to the log/status parsers; a table-driven loop
  over awkward paths (spaces, unicode, dotfiles) in `status_parser`.
- Contract-test `lua/neojj/lib/jj/cli.lua`'s builder
  (`arg`/`args`/`option`/`flag`/`short_flag`/`cwd` → expected argv/spawn opts)
  so the mock CLI can't silently drift from the real interface.
- `repository.lua`: `instance()` caching per dir, `refresh()` populating state
  via the mock CLI, `detect_repository()` on a non-repo.
- `util.lua` pure functions: `find_jj_dir` walking up from a nested subdir,
  `path_join` edge cases.
- Describe flow: `submit()` invokes `jj describe` with multiline buffer
  content; `abort()` fires `on_abort` without calling the CLI.
- Empty/fresh-repo rendering: log with zero revisions, status with no
  description — assert the actual empty-state text, replacing the tautological
  `type(content) == "string"` checks (`test_ui.lua:295-297`,
  `test_log.lua:74-83`).

# [ ] README accuracy pass

Verified inaccuracies: the log-buffer table says `d` = "Show commit diff" (it's
describe); the status-buffer table is missing `n` (new change); `D` is
advertised but was a stub (remove once the dead-code item lands); the Commands
section is missing `:JJ annotate`; `:JJ new` and `:JJ split` should be
documented. Refresh the feature list against the code (keep the honest
work-in-progress framing), and re-verify every keybinding table against
`_setup_mappings()` in each buffer.

# [ ] Vimdoc completeness

Bring `doc/neojj.txt` in line with post-cleanup reality: every command
(`:JJ status/log/describe/new/annotate/split`), every buffer's keybindings,
setup options. Regenerate tags (`nvim --headless -c "helptags doc/" -c quit`)
and commit `doc/tags` per the project convention.

# [ ] Add :checkhealth support

Create `lua/neojj/health.lua` with a `check()` that reports: jj binary on PATH
and its version (warn if older than the minimum the parsers were built
against — note it after the template rewrite), plenary.nvim available, Neovim
version. Register so `:checkhealth neojj` works; mention it in README and
vimdoc.

# [ ] GitHub Actions CI

Add `.github/workflows/ci.yml`: checkout, install Nix
(`DeterminateSystems/nix-installer-action` + `magic-nix-cache-action`), run
`nix develop -c make` (typecheck + tests — the dev shell already provides jj,
luacheck, stylua, and neovim, so no extra setup steps). Add a `check-format`
Make target (`stylua --check lua scripts tests`) and run it in CI too. Trigger
on push and pull_request; add a status badge to the README.
