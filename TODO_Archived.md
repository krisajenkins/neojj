# TODO — Archived

Completed items from `TODO.md`, most recent first. Each is stamped with the date
it landed and the jj change id that carried it.

---

*Archived: 2026-07-07 (change qomxttrp)*

# [x] Add second-wave tests: parsers, CLI contract, repository, describe

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

> Note: reconciled a real drift the contract test exposed — the mock had a
> `builder:args()` the real cli.lua lacks; removed it (unused). Added
> tests/test_util.lua; extended the parser/cli/repository/describe/ui/log tests.
> Suite now 170 cases.

---

*Archived: 2026-07-07 (change sqnkwyzm)*

# [x] Fixture housekeeping

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

> Decision: did the three safe sub-tasks (gitignore demo-repo, document the
> canonical/disposable split + jj 0.43.0 in tests/CLAUDE.md). The
> dotfile-test-status.txt recapture was NOT done — regenerating it from the demo
> repo would require adding a capture step AND rewriting the exact-path
> assertions in test_status_parser.lua; instead it is documented as a
> deliberately hand-authored fixture (lower risk, no test churn).

---

*Archived: 2026-07-07 (change yulpztrk)*

# [x] Replace the machine-dependent test and clean up the suite

`tests/test_unit.lua:29-37` runs real `jj` against the developer's live checkout
and `print()`s the result instead of asserting (output includes the local
author). Replace with a hermetic temp-dir test making real assertions.
Also: delete the duplicated component/highlight cases in `test_simple.lua` /
`test_integration.lua` (covered better by `test_components.lua` /
`test_ui.lua`), remove `print("✓ ...")` noise, fix the jammed statements at
`test_describe.lua:79`, and correct `tests/CLAUDE.md`'s description of
`test_unit.lua` (it claims "no external dependencies" — currently the opposite).

> Note: test_unit.lua is now a hermetic temp-repo test (jj git init in a
> tempname dir, pinned JJ_USER/JJ_EMAIL, asserts working-copy change_id +
> modified_files). Deleted test_simple.lua and the 3 duplicated
> test_integration.lua cases; corrected tests/CLAUDE.md.

---

*Archived: 2026-07-07 (change pzmvrnrl)*

# [x] Add error-path tests

With the mock CLI returning `success=false, stderr=...`: drive `:JJ status` /
`StatusBuffer:refresh` and assert `render_error` output appears in the buffer.
Test `:JJ status` in a directory with no `.jj` (friendly message, no crash) and
the missing-jj-executable path. These lock in the error-handling items above.

> Note: two of the three were already covered (test_workflow_status_refresh_
> failure; the missing-jj test in test_cli.lua). Added the no-`.jj`-directory
> test — M.jj_status short-circuits with a vim.notify (no buffer created), so
> the test captures notify and asserts the friendly message + no crash.

---

*Archived: 2026-07-07 (change rtmvonzx)*

# [x] Add cursor-interaction and keybinding tests

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

> Note: added tests/test_cursor.lua (6 cursor cases) and 4 keybinding tests in
> test_integration_workflows.lua. The <Tab> test drives the revision view
> because the mock names diff fixtures from the file path and no fixture exists
> for the working-copy files' paths.

---

*Archived: 2026-07-07 (change poqnpsms)*

# [x] Make the mock CLI fail loudly on unknown fixtures

`tests/helpers/mock_cli.lua:181-188` returns `success = true, stdout = ""` when
no fixture matches a command, silently masking drift — this is likely how the
broken integration tests above got baselined green.

Fix: `error()` (or return `success=false` with a loud stderr) on an unmatched
command, then fix whatever fallout appears.

> Note: chose success=false + a descriptive stderr (naming command/args/missing
> fixture) so drift renders as the visible "Error:" banner. No fallout — after
> the change all integration tests still pass, so no fixture currently masks an
> unrouted path.

---

*Archived: 2026-07-07 (change mwlpklql)*

# [x] Fix the two integration tests that pass without testing anything

`tests/test_integration_workflows.lua:160` uses `vim.cmd("normal! \<CR>")` —
that sends literal `\<CR>` characters, and `normal!` bypasses buffer-local
mappings anyway; the reference screenshot for
`test_workflow_log_to_commit_navigation` still shows the **log** view (only the
cursor moved). Same bug at `:221` for the `?` help test — its screenshot shows
no help panel.

Fix: use `child.type_keys("<CR>")` / `child.type_keys("?")`, assert the buffer
content actually changed (e.g. contains `"Change ID:"` / help text), and
re-baseline the screenshots. Also replace the seven `vim.wait(500)` sleeps in
this file with condition-based waits where practical.

> Note: both tests now route keys through mappings and assert the view switched
> ("Change ID:" / "NeoJJ Status Help"); the two affected screenshots were
> re-baselined; all 11 fixed sleeps became condition-based vim.wait polls. No
> new fixture was needed (initial-show-at.txt already populates the commit view).

---

*Archived: 2026-07-07 (change lpspsrqk)*

# [x] Extract shared buffer helpers to stop copy-paste drift

The describe-submit callback logic exists three times
(`log/init.lua:319-352`, `status/init.lua:526-560`, `neojj.lua:229-273`) with
100 ms `vim.defer_fn` focus hacks, and has already drifted (the `neojj.lua` copy
claims to refresh status buffers but only focuses them). `move_cursor_up/down`,
`show/show_split/show_tab`, `render_error`, `is_valid`, `get_handle` are
copy-pasted across all four buffer classes.

Fix: extract a shared `buffers/common.lua` (or push the methods onto `Buffer`);
replace the defer_fn timing hacks by focusing from the describe buffer's close
path. Pure refactor — behaviour covered by the suite before and after.

> Note: reordered describe submit() to close before firing on_submit, removing
> the defer_fn hacks and fixing the drifted M.jj_describe copy (now refreshes +
> focuses via a new StatusBuffer.list_instances()). render_error pushed onto
> Buffer. move_cursor_* were already deleted with the j/k remaps; is_valid/
> get_handle/show* delegates left as-is (show* also refresh, so not pure
> forwards).

---

*Archived: 2026-07-07 (change yonrlssl)*

# [x] Remove dead code and the unimplemented D binding

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

> Notes / deviations:
> - `Cli:call_async` was KEPT — a prior change made it the genuine async path,
>   so it is no longer dead. Only the unused builders were removed (plus their
>   parallel copies in mock_cli.lua).
> - The section-folding path was NOT removed — the premise was wrong: `folded =
>   true` IS set in production (status Bookmarks / Recent Commits sections), so
>   the renderer branch is reachable and tested.
> - `create_test_ui` move: deleted the dead `DescribeUI.create_test_ui`; LEFT
>   `StatusUI`/`LogUI.create_test_ui` in place (9 call sites across 6 test files,
>   several inside child.lua blocks — moving them into a tests/ helper would
>   risk breakage for little gain). Deferred.
> - Buffer.create trim was conservative: removed the floating TODO branch and 3
>   never-read fields (header/scroll_header/status_column); kept 4 passed-but-
>   unread fields (context_highlight/active_item_highlight/foldmarkers/cwd).

---

*Archived: 2026-07-07 (change oytumqzq)*

# [x] Raise the log limit and preserve log options

The log view is silently capped at 10 revisions (`options.limit or 10`,
`lua/neojj/buffers/log/init.lua:193-196`) with no way to see more, and
`LogBuffer.new` resets `instance.options = options` on every reuse
(`log/init.lua:20-27`), discarding previously configured options.

Fix: raise the default to ~100 (make it a `setup()` option), merge rather than
replace options on instance reuse, and accept a count argument to `:JJ log`.
(Revset filtering UI is a daily-driver feature, not this item.)

> Note: added `M.config.log_limit` (default 100, settable via setup, validated);
> reuse merges options via tbl_extend; `:JJ log [split] [count]` parses a
> positional count. Documented in doc/neojj.txt.

---

*Archived: 2026-07-07 (change qlvzzqok)*

# [x] Keybinding and help consistency pass

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

> Decision: dropped the reflexive `<Esc>`→close binding (kept `q`/`<c-c>`), for
> consistency with describe. Removed the unused move_cursor_up/down methods and
> corrected help drift in both `?` panels and doc/neojj.txt (log `d` was
> mislabeled "Show diff"; it describes).

---

*Archived: 2026-07-07 (change pqrnypts)*

# [x] Cursor handling and render robustness fixes

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

---

*Archived: 2026-07-07 (change zptstnst)*

# [x] Annotate robustness: cursor parsing, scroll alignment, help

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

> Note: cursor parsing now uses interactive component items (untruncated change
> id) + get_item_at_cursor; unparseable lines become placeholder rows and a
> syncbind runs after render; `?` help mirrors the log/status pattern.

---

*Archived: 2026-07-07 (change yrmnzrqm)*

# [x] Describe buffer: don't wipe user input on async load

The describe buffer opens empty, schedules `startinsert`, and the async
`load_current_description` render lands later
(`lua/neojj/buffers/describe/init.lua:129-144, 263-299`) — erasing anything the
user has already typed and force-resetting `'modified'`.

Fix: render the current description synchronously before showing the buffer, or
skip the render if the buffer is already modified.

> Note: implemented the skip-if-modified guard in render_components (the async
> load is deliberately not made synchronous). Also nil-guarded the load's CLI
> result.

---

*Archived: 2026-07-07 (change kpvyurpz)*

# [x] Make the plugin work without setup() and validate options

The `:JJ` command is only created inside `M.setup()`, which `plugin/neojj.lua`
never calls — a user who installs the plugin without a `setup()` call gets
highlights but no command. `setup()` also performs no option validation
(`log_level = "debug"` as a string would silently break the logger's numeric
comparisons) (`lua/neojj.lua:34-39`).

Fix: create the `:JJ` user command idempotently from `plugin/neojj.lua`;
validate `opts` (e.g. `vim.validate`) in `M.setup`.

> Note: extracted the command block into `M.create_commands()` (called from the
> plugin load-once guard and by setup); setup validates opts/log_level via the
> 0.11+ `vim.validate` signature.

---

*Archived: 2026-07-07 (change rrozzwvu)*

# [x] Close windows when closing NeoJJ views

Closing the annotate view (`lua/neojj/buffers/annotate/init.lua:333-342`)
deletes the buffer but leaves its 30-column vsplit orphaned showing an arbitrary
buffer — after *every single use*. Similarly, `q` in status/log is a bare
`<cmd>bdelete<cr>` (`status/init.lua:57-59`, `log/init.lua:58-60`) that leaves
splits/tabs open when the view was opened via `:JJ status vertical` etc.

Fix: in each close path, find the view's window (`vim.fn.bufwinid`) and
`nvim_win_close` it (unless it's the last window) before deleting the buffer;
track the window created by `Buffer:open` so split-opened views clean up. Route
the string mappings through `Buffer:map` so they carry `desc`s.

> Note: implemented via an `owned_window` field set by show_split/show_tab/open
> (not the replace/reuse paths) and closed in Buffer:close when valid and not the
> last window; annotate needed no change since it routes through Buffer:open.

---

*Archived: 2026-07-07 (change pvkrmlmy)*

# [x] Re-detect repositories initialised after first use

`JjRepo.instance` memoises per cwd and `detect_repository` only runs in the
constructor (`lua/neojj/lib/jj/repository.lua:49-57,127-137`). A repo created
with `jj git init` *after* the first `:JJ` call is never recognised — every
command reports "Not a jj repository" until Neovim restarts.

Fix: in `JjRepo.instance` (or at the top of the `M.jj_*` entry points), re-run
`detect_repository()` when the cached state has `jj_dir == ""`.

> Note: re-running detect alone was insufficient — `setup_modules()` must also
> run after a successful re-detect (it registers the status module only when
> `is_jj_repo()`), and `register_module` already guards double registration.

---

*Archived: 2026-07-07 (change tpvrmzxl)*

# [x] Namespace buffers per repo

Buffer names are fixed strings (`"NeoJJ Status"` at `status/init.lua:40`,
`"NeoJJ Log"` at `log/init.lua:24-43`) while instances are keyed per repo
(`status/init.lua:14-29`), so status views for two different repos share one
underlying nvim buffer — the second repo's `_setup_mappings` closures overwrite
the first's, and a still-"valid" first instance renders repo A's content while
`r`/`d`/`n` act on repo B.

Fix: include a repo identifier (root basename, disambiguated) in the buffer
name. Do this after the exact-name matching fix above.

> Note: added `util.repo_namespace(repo)` (basename + 6-char sha256 slice of the
> root path); converted the log buffer's module-global singleton to a per-repo
> `instances` map so two repos' log views coexist. The path-hash suffix is
> visible in the statusline, so the integration test repo was pinned to a
> deterministic path and the 8 reference screenshots re-baselined.

---

*Archived: 2026-07-06 (change uonomuxv)*

# [x] Match NeoJJ buffers by exact name

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

> Note: `nvim_buf_get_name` absolutizes synthetic names, so the comparison also
> matches against `fnamemodify(name, ":p")` to reuse an existing buffer while
> still rejecting prefixes.

---

*Archived: 2026-07-06 (change vyysrrrt)*

# [x] Use the repo root, not the cwd, for all path handling

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

---

*Archived: 2026-07-06 (change zktrzkmn)*

# [x] Pass --git to jj show so revision views work on stock config

`get_revision_data` (`lua/neojj/buffers/status/init.lua:163`) runs `jj show
<rev>` without `--git`, but `parse_show_output` (line 179+) only recognises
`diff --git` headers. jj's default diff format is color-words, so on a stock jj
config the revision view (reached via `<CR>` in log/annotate) shows **no
modified files** and dumps the diff into the description text.

Fix: add `:flag("git")` to the `cli.show()` builder call. Then unit-test
`parse_show_output` directly against the existing
`tests/fixtures/jj-outputs/*-show-at.txt` fixtures (metadata fields, per-file
diff splitting, `is_empty`) — it is a 110-line parser with zero direct tests.

---

*Archived: 2026-07-06 (change outpyzmz)*

# [x] Make the CLI layer genuinely async and stop running jj during render

Despite CLAUDE.md's description, the async architecture is not real: every jj
call blocks the UI thread via `Job:sync()` (`cli.lua:80`); `Cli:call_async`
(`cli.lua:117-122`) just delegates to the blocking call. `repo:refresh()`
(`lua/neojj/lib/jj/repository.lua:65-88`) wraps its body in an un-awaited
`async.void(...)()` with no completion signal — it only works "synchronously by
accident". Worst, jj processes run synchronously *during render*:
`status/init.lua:462-500` runs one `jj diff` per expanded file (`<S-Tab>`
expand-all = N sequential blocking processes), and `log/init.lua:469-500` via
`log/ui.lua:110` re-fetches revision details on every re-render.

Fix: convert `Cli:call` to `Job:start` with an `on_exit` callback wrapped via
plenary async so callers can genuinely await; make `refresh()` awaitable and
awaited; cache diff/detail results in `expanded_files` / `expanded_revisions`
state at toggle time instead of fetching inside UI builders. Keep the public
`Cli` interface stable so `tests/helpers/mock_cli.lua` keeps working; run the
full suite after. This is the largest item in the list — it can be split into
(1) real async call, (2) awaited refresh, (3) cache-at-toggle if needed.

> Note: sub-part (2), awaited refresh, was already landed by an earlier commit
> (478012d); this change delivered (1) genuine `Job:start`-based async and (3)
> cache-at-toggle for status diffs and log revision details.

---

# [x] jj log bug

The log view for the current repo shows:

```
@  uollykru krisajenkins@gmail.com 2026-07-06 17:41:57 de65b8a6
│  (no description set)
○  slpsoxow krisajenkins@gmail.com 2026-07-06 17:31:15 e153c5b3
│  Handle missing jj binary and slow commands gracefully.
○  lqvrnlpn krisajenkins@gmail.com 2026-07-06 15:43:51 main 8d520ed9
│  Stop passing an empty environment to jj subprocesses.
◆  uytlyqwo krisajenkins@gmail.com 2026-07-06 15:29:01 main 3c0aebc0
│  Fix status parser: conflicts, copied files, untracked paths.
◆  qptmtmks krisajenkins@gmail.com 2026-07-06 15:10:45 304a1f7c
```

In `jj log`, the first `main` would display as `main*`, to show it's ahead of its tracked remote, and the second would show as `main@origin` to show it's a tracking branch. They get this special presentation whenever there's a difference between the bookmark and remote it's tracking. We should follow suit.

---

*Archived: 2026-07-06 (change smooynwz)*

# [x] Surface jj failures in the status buffer instead of rendering empty

If `jj status` fails mid-refresh (jj missing, repo locked, version mismatch),
`repo:refresh()` only logs and `get_working_copy()` returns nil/stale — the
status buffer silently renders just the "JJ Status" header with no files and no
error (`lua/neojj/buffers/status/init.lua:312-331`).

Fix: have `JjRepo:refresh()` return success/error and make
`StatusBuffer:refresh()` call `self:render_error(...)` on failure, mirroring the
revision path at `status/init.lua:306-311`. Assert the error rendering with the
mock CLI returning `success=false`.

---

*Archived: 2026-07-06 (change slpsoxow)*

# [x] Handle missing jj binary and slow commands gracefully

In `Cli:call` (`lua/neojj/lib/jj/cli.lua:72-91`), `Job:new` sits *outside* the
pcall; plenary raises `error(debug.traceback(...))` when the executable is
missing, so a user without jj on Neovim's PATH gets a raw Lua stack trace from
`:JJ new`. Also `job:sync()` (line 80) uses plenary's default 5000 ms timeout
and hard-errors past it — `jj log` on a large repo or a first-run working-copy
snapshot surfaces as a cryptic "unable to complete in 5000ms" failure.

Fix: pre-check `vim.fn.exepath("jj") == ""` (or move `Job:new` inside the
pcall) and return `{success=false, stderr="jj executable not found..."}` with a
`vim.notify`-worthy message; pass an explicit generous timeout (e.g.
`job:sync(60000)`); surface timeouts via `vim.notify`. Error-path tests come in
a later item.

---

*Archived: 2026-07-06 (change lqvrnlpn)*

# [x] Stop passing an empty environment to jj subprocesses

`lua/neojj/lib/jj/cli.lua:13` sets `builder.env = {}` and passes it to plenary's
`Job:new`, which treats any non-nil table as the *entire* child environment
(verified empirically) — every jj command NeoJJ runs is stripped of `PATH`,
`SSH_AUTH_SOCK`, `JJ_CONFIG`, `EDITOR`, watchman helpers, and any
env-conditional jj config.

Fix: in `cli.lua:72-77`, only pass `env` when non-empty: `env = next(self.env)
and self.env or nil`. Do this **after** the log-template rewrite above — with
the env restored, user-configured log templates start loading, which the current
parser can't survive.

---

*Archived: 2026-07-06 (change uytlyqwo)*

# [x] Fix status parser: conflicts, copied files, untracked paths

`lua/neojj/lib/jj/parsers/status_parser.lua:96-105` detects conflicts by
parsing `C <path>` lines — a format jj never emits (verified on jj 0.43: real
output is a `Warning: There are unresolved conflicts at these paths:` block with
`<path>    2-sided conflict` lines). So `working_copy.conflicts` is always empty
and the status buffer's Conflicts section never populates. Worse, `C` in
"Working copy changes" means *copied*, so copied files would be shown as
conflicts. Untracked files (`? <path>` under "Untracked paths:") are ignored
entirely.

Fix: parse the conflicts warning block statefully (path + N-sided annotation);
treat `^C ` as a copied file in `modified_files`; add a `^? ` branch producing
`status = "?"` entries (`highlights.lua:98` already maps `?`). Update the
fixture-driven tests in `tests/test_status_parser.lua` with real jj output.

---

*Archived: 2026-07-06 (change qptmtmks)*

# [x] Rewrite the log parser to use an explicit jj template

`lua/neojj/lib/jj/parsers/log_parser.lua` parses jj's default *human* output,
which is fragile and demonstrably wrong today (verified empirically on jj 0.43
against `fixtures/demo-repo`: 9 commits, 7 parsed):

- The graph character classes (lines 28 and 73) omit the `×` conflict node and
  curved corners `╭╮╯╰`, so **conflicted commits are silently dropped** from the
  log view — in a repo with conflicts (jj's headline feature) you cannot select
  or act on them.
- The commit regex requires an `author@email` token, so the root commit is
  dropped too.
- A trailing `(conflict)` suffix makes `words[#words]` capture `"(conflict)"` as
  the commit_id and shifts the real commit_id into bookmarks.
- Any user with a configured `templates.log` gets a garbled/empty view.

Fix: in `lua/neojj/buffers/log/init.lua`, fetch with an explicit
machine-oriented `--template` (a field list with an unambiguous separator, or
`json(self)`), keeping `--graph` for the gutter; rewrite `log_parser.lua` to
split the graph prefix from the templated payload and delete the human-format
regexes. Update `tests/test_log_parser.lua` and fixtures; add cases for
conflicted, empty, divergent, and root commits.

---

*Archived: 2026-07-06 (change srtroook)*

# [x] Stop stripping legitimate '#' lines from commit descriptions

`get_description_from_buffer()` (`lua/neojj/buffers/describe/init.lua:322-339`)
drops **every** line starting with `#`, so a Markdown heading (`# Overview`) or
an issue ref (`#123 ...`) in a commit message is silently deleted — data loss in
a commit-message editor.

Fix: change the help-comment convention to a distinctive prefix (e.g. `JJ:`,
matching jj's own convention) in `describe/ui.lua`'s `create_help_section()`,
and filter only that prefix in `get_description_from_buffer()`. Add a test whose
description contains a `#`-prefixed line and assert it survives round-trip.

---

*Archived: 2026-07-06 (change wqruytor)*

# [x] Fix describe buffer quit semantics and double-submit race

The `QuitPre` autocmd (`lua/neojj/buffers/describe/init.lua:156-168`) submits
the description whenever the buffer is modified, for *every* kind of quit
including `:q!` — there is no way to discard an edit via quit commands; a user
who types `:q!` to bail out overwrites the commit description anyway. Separately,
the `BufWriteCmd` handler (`describe/init.lua:147-153`) calls `submit()` without
clearing `'modified'`, so `:wq` fires both the write and quit submit paths,
launching two concurrent `jj describe --stdin` jobs racing each other.

Fix: never auto-submit on quit — abort (or prompt like
`close_with_confirmation()`); in the `BufWriteCmd` callback set `modified =
false` around `submit()`; add a `self.submitting` re-entry guard in `submit()`.
Add child-nvim tests covering `:q`, `:q!`, `:wq`, `ZZ`, `ZQ`.
