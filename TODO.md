# TODO

# [ ] Bookmark management (M)

Wraps `jj bookmark create/move/delete/rename/track/untrack/list`. In the log
buffer, `b` on a revision opens a small `vim.ui.select` menu: create bookmark
here, move existing bookmark here, delete, rename, track remote. The log UI
already parses and highlights bookmarks, so the display side exists — this adds
the write operations. Without this you cannot prepare a push.

# [ ] Auto-refresh on repo change (S/M)

Watch `.jj/repo/op_heads` with `vim.uv.fs_event` and refresh open NeoJJ buffers
when the repo changes externally — the equivalent of neogit watching `.git`.
This needs a little research - how good is the `vim.uv.fs_event support`? Will
it work reliably? Across which platforms?

# [ ]  Empty

`jj log` and `jj status` will show you when a commit is empty. We should do the same, with special syntax highlighting.
