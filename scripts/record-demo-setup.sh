#!/usr/bin/env bash
#
# Prepare an isolated NeoJJ demo environment for the VHS tape
# (scripts/record-demo.tape).
#
# This is the environment-setup half of the old record-demo.sh, factored out so
# the VHS tape can stay a declarative list of keystrokes. It copies this repo to
# a throwaway dir, clones plenary if needed, writes a cosmetic init.lua and the
# isolated XDG dirs, then prints ONLY the work dir on stdout (progress goes to
# stderr) so the tape can do:  DEMO=$(scripts/record-demo-setup.sh)
#
# Nothing here touches your real working copy.
set -euo pipefail

# Match the user's colorscheme (same knobs as the original record-demo.sh).
COLORSCHEME="molokai"
COLORSCHEME_RTP="$HOME/.local/share/nvim/site/pack/core/opt/molokai"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neojj-demo.XXXXXX")"
DEMO="$WORK/repo"

# Isolated copy of the repo (so only scripted keystrokes touch it).
cp -R "$REPO_ROOT" "$DEMO" >&2
rm -f "$DEMO/demo.gif" "$DEMO/demo-vhs.gif"
# plenary is the only runtime dep; clone it into the copy if the tree lacks it.
if [ ! -d "$DEMO/deps/plenary.nvim" ]; then
  mkdir -p "$DEMO/deps"
  git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim \
    "$DEMO/deps/plenary.nvim" >&2
fi

# Minimal, cosmetic init that loads NeoJJ from the copy with the float diff on.
COLORLINE="vim.cmd('colorscheme $COLORSCHEME')"
if [ -d "$COLORSCHEME_RTP" ]; then
  COLORLINE="vim.opt.runtimepath:prepend('$COLORSCHEME_RTP'); $COLORLINE"
else
  echo "note: $COLORSCHEME_RTP not found; using builtin 'habamax'" >&2
  COLORLINE="vim.cmd('colorscheme habamax')"
fi
cat > "$WORK/init.lua" <<EOF
vim.opt.runtimepath:prepend('$DEMO')
vim.opt.runtimepath:prepend('$DEMO/deps/plenary.nvim')
vim.opt.number = false
vim.opt.signcolumn = 'no'
vim.opt.laststatus = 0
vim.opt.showmode = false
vim.opt.ruler = false
vim.opt.cursorline = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.shortmess:append('I')
vim.opt.fillchars = { eob = ' ' }
vim.o.termguicolors = true
$COLORLINE
require('neojj').setup({ diff = { inline = false, fold = true } })
EOF

# Isolated XDG dirs so no user config/ftplugins load.
mkdir -p "$WORK/xdg-config" "$WORK/xdg-data" "$WORK/xdg-state"

# Force SEMICOLON-form truecolor. VHS's terminal (ttyd/xterm.js) misparses
# Neovim's default *colon*-delimited truecolor SGR (ESC[38:2::r:g:b m), which
# mangles the blue channel -- molokai comes out dim with blue crushed to ~0.
# Neovim has no colon/semicolon switch, but it honours setrgbf/setrgbb from
# terminfo, so we compile an xterm-256color variant that spells them with
# semicolons and point the demo's nvim at it (see record-demo.tape's TERMINFO
# export). Raw printf truecolor already uses semicolons, which is why only
# Neovim was affected.
TIDIR="$WORK/terminfo"
mkdir -p "$TIDIR"
cat > "$WORK/truecolor.src" <<'SRC'
xterm-256color-semi|xterm 256 color with semicolon truecolor,
    use=xterm-256color,
    setrgbf=\E[38;2;%p1%d;%p2%d;%p3%dm,
    setrgbb=\E[48;2;%p1%d;%p2%d;%p3%dm,
SRC
tic -x -o "$TIDIR" "$WORK/truecolor.src" >&2

echo "$WORK"
