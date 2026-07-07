# TODO — Daily-Driver v1.0 (pick-and-choose)

Candidate features for making NeoJJ a full daily driver — enough to manage a jj
repo without dropping to the terminal. Derived from a neogit→jj feature-gap
analysis (see the mapping notes at the bottom). Items use the same `# [ ]`
format as `TODO.md`: move an item across when you want it worked.

Ordering within each tier is by how essential the feature is to daily jj use.
Sizes are rough: S = an evening, M = a day or two, L = a project.

**Dependencies to keep in mind:** bookmark management gates push (you can't
prepare a push without moving bookmarks); the real-async CLI work in `TODO.md`
gates good UX for push/fetch (long-running network commands must not freeze the
editor); the picker item upgrades the prompt-based flows in squash, rebase, and
bookmarks and can land before or after them.

## Tier 1 — can't daily-drive without these

# [ ] Squash (S basic, M with targeting)

Wraps `jj squash` / `jj squash --from X --into Y`. In the status buffer, `S`
squashes the working copy into its parent — the single most common jj operation
and the staging-area replacement. In the log buffer, `S` on a revision squashes
it into its parent; a variant prompts for an `--into` target change ID.
Confirm before executing, refresh after. Reuses
`get_item_at_cursor().change_id` and the CLI builder — both already in place.

# [ ] Abandon (S)

Wraps `jj abandon <rev>`. In the log buffer, `x` (or `a`) abandons the revision
at cursor; in the status buffer, `x` with no file under the cursor abandons the
working-copy change. Needs a `vim.fn.confirm` y/n since it's destructive-ish
(though undoable — see the undo item, which makes all these keys trustworthy).

# [ ] Undo and operation-log view (M; undo alone is S)

Wraps `jj undo`, `jj op log`, `jj op restore` — jj's universal safety net, and
the thing that makes squash/abandon/rebase keys safe to press. `u` in
status/log runs `jj undo` with a notification of what was undone. New
:JJ oplog` buffer cloning the log-buffer pattern (parser + ui + init) listing
operations; `<cr>` or `r` on an operation runs `jj op restore` with
confirmation.

## Tier 2 — needed weekly, expected of a magit-alike

# [ ] Rebase (L; M for a prompt-based version)

Wraps `jj rebase -r/-s/-b <src> -d <dest>` (later `--before/--after`). In the
log buffer, two-step interaction consistent with the plugin's direct-key style:
`R` marks the revision at cursor as source and enters "select destination" mode
(statusline/virtual-text hint); a second `R`/`<cr>` on another revision
executes. Choose `-r` vs `-s` vs `-b` via prompt (default `-s`). Post-rebase
conflicts are fine — jj commits them and the status buffer shows them (once the
status-parser conflict fix from TODO.md is in).

# [ ] Restore / discard file changes (S)

Wraps `jj restore <path>` (and bare `jj restore` for everything). In the status
buffer, `x` on a file item discards that file's working-copy changes with
confirmation; on a section header, restores all. The neogit-discard equivalent,
and the last piece of the stage/unstage replacement story (squash = keep,
restore = discard, split = divide).

# [ ] Real diff view (M)

Wraps `jj diff -r <rev> [path]`, later `--from/--to`. Implement what the
removed `D` stub promised: a proper diff buffer (filetype `diff`, `q` closes)
for the file at cursor in the status buffer; `D` in the log buffer shows the
whole revision's diff. The diff-fetching code already exists in
`get_file_diff()` — this is mostly a presentation buffer.

# [ ] Log revsets and limit control (S/M)

Wraps `jj log -r <revset> --limit N`. In the log buffer, `L` (or `/`) prompts
for a revset (`vim.fn.input` with history) and re-renders; `+` or a count
raises the limit. (TODO.md already raises the hard-coded default of 10; this
item adds the interactive control.)

# [ ] Conflict resolution actions (M)

Wraps `jj resolve` / `jj resolve --list`. Conflicts are parsed and displayed in
the status buffer (after TODO.md's status-parser fix); add: `<cr>` on a
conflict opens the file jumped to the first conflict marker; `o` (or `X`) runs
`jj resolve <path>` in a terminal, delegating to the configured merge tool —
same pattern as `:JJ split`; show a count in the section header.

## Tier 3 — rounds out v1.0

# [ ] Absorb (S)

Wraps `jj absorb`. In the status buffer, `A` runs it on the working copy,
notifies which revisions received hunks, refreshes. Huge quality-of-life for
stacked-change workflows, and trivially undoable.

# [ ] Duplicate and backout (S each)

jj's cherry-pick and revert. In the log buffer: `C` runs
`jj duplicate <rev> [-d <dest>]` (optionally prompt for destination); `V` runs
`jj backout -r <rev>` (newer jj spells it `jj revert`). Both act on the
revision at cursor.

# [ ] New with multiple parents — merge (S/M)

Extends the existing `n`. In the log buffer, visual-mode selection or a
mark-then-`n` flow runs `jj new <rev1> <rev2>`, creating a merge change (jj's
merge is just a new change with 2+ parents).

# [ ] Native split UI (L)

Replace the `:terminal jj split` delegation with a native hunk-selection UI.
`jj-split-tool-interface.md` in the repo already documents the external
diff-editor protocol: NeoJJ registers itself as the tool, receives left/right
dirs, presents a hunk-selection buffer, writes the result. The biggest single
feature; the terminal fallback works meanwhile.

# [ ] Picker integration (M)

Telescope / `vim.ui.select` pickers for revisions and bookmarks, used by squash
`--into`, rebase destination, `jj new <rev>`, and bookmark ops. An enabler
that upgrades the prompt-based flows above from type-a-change-id to
pick-from-a-list.

## Explicitly out of scope for v1.0

Irrelevant or low-value under jj's model: staging/index UI (no index), stash
(the working copy is a commit; `jj new` stashes implicitly), amend (every
change is always editable), a reset popup (subsumed by undo / abandon /
restore / bookmark-move), the interactive-rebase editor (jj decomposes it into
per-revision squash/describe/abandon/rebase), tags (read-only in jj), bisect
(no jj support), workspaces, and remote management (`jj git remote` — rare
enough that the terminal is fine).

## Neogit → jj mapping notes

For future reference, the analysis behind this list: neogit's
stage/unstage/discard maps to squash/split/restore; commit → describe (exists)
plus the commit gesture; branch popup → bookmarks; push/pull → `jj git
push/fetch` (jj has no "pull"); cherry-pick → duplicate; revert → backout;
stash and amend are non-features under jj; and jj adds concepts git lacks that
neogit therefore has no popup for — edit, undo/op log, absorb, and first-class
conflict state — which is why they appear here despite no neogit equivalent.
