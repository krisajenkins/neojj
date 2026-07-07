# TODO — Polished v0.1

Scope: harden what exists (status, log, describe, annotate), fix review
findings, fill test gaps, docs, `:checkhealth`, CI. New features live in
`TODO_DAILY_DRIVER.md` — cherry-pick items from there into this file when
they're wanted.

Items are ordered: correctness blockers → majors → hardening → tests → docs →
CI. Note the ordering dependency: the log-template rewrite must land **before**
the empty-environment fix, because fixing the env will let user-configured jj
log templates load and break the current parser.

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
