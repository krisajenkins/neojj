# TODO

# [ ] I'd like side-by-side diff support in `jj status`.

This will have to be configurable, and defaulting to the current behaviour.

And that will be our first configuration flag, so it needs docs, README
installation instructions etc. My guess is we'll want to group diff options, so
something like this?

```lua
require("neojj").setup({
    diff = {
        inline = true
    }
})
```

# [ ] New with multiple parents — merge (S/M)

Extends the existing `n`. In the log buffer, a mark-then-`n` flow runs `jj new
<rev1> <rev2>`, creating a merge change (jj's merge is just a new change with
2+ parents). 

I'm thinking `N` can toggle the marks, `n` executes them. 

If we write the logic so that `n` includes the change under the cursor in the
marks, then immediately creates a new change with the marked parents, if should
work out neatly.


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

# [ ] Extract shared parser helpers `split_gutter` / `valid_prefix` (S)

Two small helpers are still duplicated across the jj output parsers in
`lua/neojj/lib/jj/parsers/`:

- `split_gutter(line)` is byte-identical in `log_parser.lua` (~:52) and
  `oplog_parser.lua` (~:34).
- `valid_prefix(id, prefix)` exists as a named helper in `opshow_parser.lua`
  (~:26) but is inlined twice in `log_parser.lua` (~:107-126, once for
  change_id and once for commit_id).

Lift both into a shared home — `separators.lua` already collects the parser's
byte-level constants, so it's the natural place, or a new `parsers/record.lua`
if you'd rather keep `separators.lua` data-only. Zero behaviour change; each
parser sources the helper instead of its own copy.

Explicitly out of scope: a higher-order "parse two-line records" loop driver.
The `parse_*_output` loops look similar but `log_parser` carries extra optional
trailing fields, `(empty)`-marker handling and a different display-line
assembly, so unifying the loop bodies buys little for a lot of callback
plumbing. Just extract the two leaf helpers.

