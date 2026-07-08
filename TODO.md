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

# [ ] Undo and operation-log view (M)

Wraps `jj undo`, `jj op log`, `jj op restore` — jj's universal safety net, and
the thing that makes squash/abandon/rebase keys safe to press. New :JJ oplog`
buffer cloning the log-buffer pattern (parser + ui + init) listing operations;
`<cr>` or `r` on an operation runs `jj op restore` with confirmation.
