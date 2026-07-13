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

# [ ] Extract the duplicated jj-action boilerplate shared by the buffers (M)

`StatusBuffer` and `LogBuffer` carry byte-for-byte identical copies of five
jj-action methods: `fix()`, `tug()`, `_run_push(opts)`, `push()`'s `_run_push`
tail, and `fetch()`. Each repeats the same skeleton — `async.run` →
`cli.X():cwd(self.repo.dir):call_async()` → `vim.schedule(notify success/failure
+ self:refresh())` — differing only in the builder, an optional "pending"
notice, the success message, and the failure prefix. This is one layer *above*
`cli.lua` (the command builders there are already DRY); the duplication is in
the two buffer classes.

Extract a small free-function helper — a new `lua/neojj/lib/jj/action.lua`
exposing `M.run(view, opts)` — rather than a base class. The classes use
hand-rolled metatables, and each action needs only `view.repo.dir` and
`view:refresh()` from `self`, so a duck-typed helper avoids entangling the
view-stack lifecycle code that a shared superclass would drag in.

```lua
---@param view table  -- StatusBuffer | LogBuffer (needs .repo.dir + :refresh())
---@param opts { builder, pending?: string, success: string|fun(result):string, failure: string }
function M.run(view, opts)
    local async = require("plenary.async")
    if opts.pending then vim.notify(opts.pending, vim.log.levels.INFO) end
    async.run(function()
        local result = opts.builder:cwd(view.repo.dir):call_async()
        vim.schedule(function()
            if result.success then
                local msg = type(opts.success) == "function" and opts.success(result) or opts.success
                vim.notify(msg, vim.log.levels.INFO)
                view:refresh()
            else
                vim.notify(opts.failure .. ": " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
            end
        end)
    end)
end
```

Each call site collapses to a declaration (builder + messages):

```lua
function StatusBuffer:fix()
    action.run(self, {
        builder = require("neojj.lib.jj.cli").fix(),
        success = function(result)
            local msg = vim.trim(result.stderr or "")
            return msg ~= "" and msg or "Ran jj fix"
        end,
        failure = "Failed to run jj fix",
    })
end

function StatusBuffer:fetch()
    action.run(self, {
        builder = require("neojj.lib.jj.cli").git_fetch(),
        pending = "Fetching from remote...",
        success = "Fetched from remote",
        failure = "Failed to fetch",
    })
end
```

`push()`'s `vim.ui.select` prompt stays as UI; only its `_run_push` async tail
delegates to `action.run`, passing a pre-built `cli.git_push()` builder with the
`bookmark`/`change` option already applied. The `success`-as-function hatch is
what lets `fix()` return its trimmed-stderr message through the same helper.

Possible follow-on (separate item, riskier): the view-stack/lifecycle plumbing
(`show`/`show_split`/`show_tab`/`close`/`toggle_help`/`go_back`/`_push_frame`/
`is_valid`/`get_handle`) is *also* duplicated across the two classes, but that
touches `view_stack.lua` and is a bigger extraction — don't fold it in here.
