# TODO — Archived

Completed items from `TODO.md`, most recent first. Each is stamped with the date
it landed and the jj change id that carried it.

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
