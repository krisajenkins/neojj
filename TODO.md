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

# [ ] Share the "empty working copy" default struct (S)

`status_parser.lua` (~:13-23) and `repository.lua` (~:14-24) both hand-build an
identical default working-copy record: `{ change_id = nil, commit_id = nil,
description = "", author = { name = "", email = "" }, parent_ids = {},
modified_files = {}, conflicts = {}, is_empty = true, empty = false }`. Two
copies of the same shape drift apart the moment a field is added to one.

Extract a single `empty_working_copy()` constructor (a fresh table each call, so
callers can mutate their copy) — natural home is `status.lua` or `status_parser`
since it owns that shape — and have both sites call it. Surfaced by `jscpd`;
the earlier audit missed it.

# [ ] Share the UI help-panel and span-emitter rendering (M)

Two families of copy-pasted UI construction in `lua/neojj/buffers/*/ui.lua`:

1. Help panels: `create_help` is a hand-built list of
   `Ui.text("  <key>  - <desc>", { highlight = "NeoJJHelpText" })` rows under
   `NeoJJSectionHeader` sections in `log/ui.lua` (~:305), `oplog/ui.lua`
   (~:174), `status/ui.lua` (~:490) and `annotate/ui.lua` (~:192). The content
   differs per view (correctly), but the row/section formatting is repeated.
   Add `Ui.help_panel(title, sections)` taking a data table
   (`{ {"Navigation", {{"d","Describe commit"}, ...}}, ... }`); each buffer
   supplies data, the formatting lives once. `create_header` is similarly
   near-identical across log/oplog/status — collapse to `Ui.header(title, opts)`
   at the same time.
2. Span emitter: `LogUI.create_commit_text_components` (`log/ui.lua` ~:212) and
   `OplogUI.create_operation_text_components` (`oplog/ui.lua` ~:98) share the
   same closure-based positional emitter (`pos` cursor, `emit_field(value, hl)`
   that `:find`s the value, emits the gap + field, plus identical trailing /
   fallback tails). Extract a `lib/ui/span_emitter.lua`; log's `emit_id_field`
   and opshow's `append_id` (`opshow/ui.lua` ~:18) are two more variants of the
   same prefix-bright/rest-dim id renderer that collapse into one `id_field`.

Caveat: `describe/ui.lua`'s help uses a different `"JJ: "`-comment style (it
renders inside an editable buffer) — leave it out of the shared panel. The
opshow `append_id` variant builds spans from values rather than positionally,
so unifying all three id renderers needs a little care; log+oplog alone is
clean.
