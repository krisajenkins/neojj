# TODO — Polished v0.1

Scope: harden what exists (status, log, describe, annotate), fix review
findings, fill test gaps, docs, `:checkhealth`, CI. New features live in
`TODO_DAILY_DRIVER.md` — cherry-pick items from there into this file when
they're wanted.

Items are ordered: correctness blockers → majors → hardening → tests → docs →
CI. Note the ordering dependency: the log-template rewrite must land **before**
the empty-environment fix, because fixing the env will let user-configured jj
log templates load and break the current parser.

# [ ] Replace the machine-dependent test and clean up the suite

`tests/test_unit.lua:29-37` runs real `jj` against the developer's live checkout
and `print()`s the result instead of asserting (output includes the local
author). Replace with a hermetic temp-dir test making real assertions.
Also: delete the duplicated component/highlight cases in `test_simple.lua` /
`test_integration.lua` (covered better by `test_components.lua` /
`test_ui.lua`), remove `print("✓ ...")` noise, fix the jammed statements at
`test_describe.lua:79`, and correct `tests/CLAUDE.md`'s description of
`test_unit.lua` (it claims "no external dependencies" — currently the opposite).

# [ ] Fixture housekeeping

`fixtures/demo-repo/` is untracked and nondeterministic:
`fixtures/create-demo-repo.sh` pins `JJ_USER`/`JJ_EMAIL`/`JJ_TIMESTAMP` but jj
change IDs are random, so regenerating produces IDs that no longer match the
frozen `tests/fixtures/jj-outputs/*` or the 11 reference screenshots.

Fix: treat the committed `tests/fixtures/jj-outputs/` as canonical; add
`/fixtures/demo-repo/` to `.gitignore`; document in `tests/CLAUDE.md` that
regenerating the demo repo re-baselines everything, and record which jj version
the fixtures were captured with. Recapture the oddball
`dotfile-test-status.txt` (mode 0600, captured from the real neojj repo, not
the demo repo) from the demo repo for consistent provenance.

# [ ] Add second-wave tests: parsers, CLI contract, repository, describe

Lower-urgency but wanted before calling the suite trustworthy:

- Malformed-input parser tests: truncated status output, unknown status
  letters, ANSI-coloured input to the log/status parsers; a table-driven loop
  over awkward paths (spaces, unicode, dotfiles) in `status_parser`.
- Contract-test `lua/neojj/lib/jj/cli.lua`'s builder
  (`arg`/`args`/`option`/`flag`/`short_flag`/`cwd` → expected argv/spawn opts)
  so the mock CLI can't silently drift from the real interface.
- `repository.lua`: `instance()` caching per dir, `refresh()` populating state
  via the mock CLI, `detect_repository()` on a non-repo.
- `util.lua` pure functions: `find_jj_dir` walking up from a nested subdir,
  `path_join` edge cases.
- Describe flow: `submit()` invokes `jj describe` with multiline buffer
  content; `abort()` fires `on_abort` without calling the CLI.
- Empty/fresh-repo rendering: log with zero revisions, status with no
  description — assert the actual empty-state text, replacing the tautological
  `type(content) == "string"` checks (`test_ui.lua:295-297`,
  `test_log.lua:74-83`).

# [ ] README accuracy pass

Verified inaccuracies: the log-buffer table says `d` = "Show commit diff" (it's
describe); the status-buffer table is missing `n` (new change); `D` is
advertised but was a stub (remove once the dead-code item lands); the Commands
section is missing `:JJ annotate`; `:JJ new` and `:JJ split` should be
documented. Refresh the feature list against the code (keep the honest
work-in-progress framing), and re-verify every keybinding table against
`_setup_mappings()` in each buffer.

# [ ] Vimdoc completeness

Bring `doc/neojj.txt` in line with post-cleanup reality: every command
(`:JJ status/log/describe/new/annotate/split`), every buffer's keybindings,
setup options. Regenerate tags (`nvim --headless -c "helptags doc/" -c quit`)
and commit `doc/tags` per the project convention.

# [ ] Add :checkhealth support

Create `lua/neojj/health.lua` with a `check()` that reports: jj binary on PATH
and its version (warn if older than the minimum the parsers were built
against — note it after the template rewrite), plenary.nvim available, Neovim
version. Register so `:checkhealth neojj` works; mention it in README and
vimdoc.

# [ ] GitHub Actions CI

Add `.github/workflows/ci.yml`: checkout, install Nix
(`DeterminateSystems/nix-installer-action` + `magic-nix-cache-action`), run
`nix develop -c make` (typecheck + tests — the dev shell already provides jj,
luacheck, stylua, and neovim, so no extra setup steps). Add a `check-format`
Make target (`stylua --check lua scripts tests`) and run it in CI too. Trigger
on push and pull_request; add a status badge to the README.
