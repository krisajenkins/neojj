# TODO

# [ ] Auto-refresh on repo change (S/M)

Watch `.jj/repo/op_heads` with `vim.uv.fs_event` and refresh open NeoJJ buffers
when the repo changes externally — the equivalent of neogit watching `.git`.
This needs a little research - how good is the `vim.uv.fs_event support`? Will
it work reliably? Across which platforms?

# [ ]  Empty

`jj log` and `jj status` will show you when a commit is empty. We should do the same, with special syntax highlighting.
