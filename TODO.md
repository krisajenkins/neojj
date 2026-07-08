# TODO

# [ ] `:JJ debug` command for bug reports (S/M)

Errors currently live only in ephemeral `vim.notify` toasts — `logger.lua` is a
thin wrapper over `vim.notify` with no persistence, so once a toast fades the
detail (including jj's stderr) is gone. Neovim's `:messages` catches the default
notifier incidentally, but notify plugins (nvim-notify, fidget, snacks) usually
bypass it, so "run this and paste the output" isn't reliably possible today.

Add a `:JJ debug` subcommand (the `:JJ` dispatcher in `neojj.lua` already has a
clean subcommand table) that dumps a report to paste into a GitHub issue:
Neovim version, OS/platform, `jj --version`, current log level, and recent
NeoJJ activity. To have activity to report, give `logger.lua` a small capped
in-memory ring buffer that every `debug/info/warn/error` appends to (with
timestamp + level) regardless of whether it's notified — so even suppressed
DEBUG lines are retained.

Decision needed: scope. Minimum is logs-only (the ring buffer above). The
higher-value version also adds a recent-command ring to `cli.lua` — the last N
jj invocations with argv + exit code + stderr — which is what actually pins
down failures like the `jj bookmark move --revision` bug. Complements the
existing static `:checkhealth neojj` (`health.lua`) with the runtime half.
