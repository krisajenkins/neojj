# TODO — Archived

Completed items from `TODO.md`, most recent first. Each is stamped with the date
it landed and the jj change id that carried it.

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
