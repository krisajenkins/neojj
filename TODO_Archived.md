# TODO — Archived

Completed items from `TODO.md`, most recent first. Each is stamped with the date
it landed and the jj change id that carried it.

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
