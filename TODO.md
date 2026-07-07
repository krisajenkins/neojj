# TODO

# [ ] Edit (S)

Wraps `jj edit <rev>`. In the log buffer, `e` on a revision makes it the
working copy (jj's "checkout" for daily work), notify + refresh. Pairs
naturally with the existing `n` (new).

# [ ] Git push / fetch (M)

Wraps `jj git push` (`--bookmark X`, `--change @`, all tracked) and
`jj git fetch`. In status + log buffers: `P` push with a prompt among
all-tracked / specific bookmark / `--change` at cursor; `f` fetch. Must be
genuinely async (see TODO.md's async item) with progress notification, refresh
on completion, and stderr surfaced on failure (auth errors, bookmark
conflicts). Gated by bookmark management below.

# [ ] Bookmark management (M)

Wraps `jj bookmark create/move/delete/rename/track/untrack/list`. In the log
buffer, `b` on a revision opens a small `vim.ui.select` menu: create bookmark
here, move existing bookmark here, delete, rename, track remote. The log UI
already parses and highlights bookmarks, so the display side exists — this adds
the write operations. Without this you cannot prepare a push.

# [ ] Commit gesture: describe + new (S)

Wraps `jj commit` semantics. In the status buffer, `c` opens the existing
describe buffer; on submit, runs `jj commit -m <msg>` (describe + `jj new`) so
the user lands on a fresh empty working copy — the canonical "finish this
change" gesture. Reuses DescribeBuffer with a different submit action.

# [ ] `jj tug` support

This is currently an alias in `~/.config/jj/config.toml`, but I find it so very useful I'd like to make it a first-class feature.

# [ ] Undo and operation-log view (M; undo alone is S)

Wraps `jj undo`, `jj op log`, `jj op restore` — jj's universal safety net, and
the thing that makes squash/abandon/rebase keys safe to press. `u` in
status/log runs `jj undo` with a notification of what was undone. New
:JJ oplog` buffer cloning the log-buffer pattern (parser + ui + init) listing
operations; `<cr>` or `r` on an operation runs `jj op restore` with
confirmation.

# [ ] Auto-refresh on repo change (S/M)

Watch `.jj/repo/op_heads` with `vim.uv.fs_event` and refresh open NeoJJ buffers
when the repo changes externally — the equivalent of neogit watching `.git`.
This needs a little research - how good is the `vim.uv.fs_event support`? Will
it work reliably? Across which platforms?
