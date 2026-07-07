# TODO

# [ ] View Stacks

This needs some design thought, but imagine this common scenario: I call up `:JJ log`, go down to a particular change, hit enter to get the status, go down to a particular file and expand the diff, then hit enter to open the file. I'd like to be able to get back to the status view with my cursor where it was, or the log with my cursor where it was. At the moment I have to renavigate every time.

I think we're looking for some kind of stacking of views, where quitting takes you back a step up the stack, and you can always return to the top of the stack from a non-JJ view.

Probably, "go back to the stack," would be bound to plain `:JJ` (no-arg).

> ⚠ Blocked (2026-07-07): Needs design decisions before coding — the current
> architecture lacks the primitives. Today `:JJ` is `nargs = "+"`
> (`lua/neojj.lua:127`), so no-arg `:JJ` errors; views are singletons
> (`StatusBuffer.new`/`LogBuffer.new` reuse one instance) so two status views of
> different changes can't coexist as stack frames; there's no cursor-position
> storage, `open_file_at_cursor` just `:edit`s over the window, and `q` calls
> `Buffer:close()` which tears the buffer down. Decisions needed: (1) Should a
> stack frame store (buffer-type, revision/file, cursor) and re-render on pop, or
> keep live buffers/windows alive? (2) Repurpose `q`/`<esc>` to pop one frame
> (closing only when the stack empties), or keep `q` as close and add a separate
> "go back" key? (3) Which view types are stack frames — just log/status/file, or
> also describe/annotate/split-terminal?

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
