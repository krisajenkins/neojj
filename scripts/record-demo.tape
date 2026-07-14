# NeoJJ README demo, as a VHS tape (https://github.com/charmbracelet/vhs).
#
# A declarative port of scripts/record-demo.sh: instead of driving a headless
# tmux + agg + ImageMagick pipeline, VHS runs its own PTY, executes the real
# commands, and renders straight to a GIF. Run it from the repo root:
#
#   nix develop -c vhs scripts/record-demo.tape        # -> demo.gif
#
# The environment prep (throwaway repo copy, plenary, cosmetic init.lua, XDG
# isolation) lives in scripts/record-demo-setup.sh so this file stays a plain
# list of keystrokes. Nothing here touches your real working copy.

Output demo.gif

# --- Terminal geometry & look -------------------------------------------------
# Tuned to land near the original's 150x42 grid at font-size 14. VHS sizes the
# grid from pixels/font metrics, so Width/Height are the knobs, not cols/rows.
Set Shell bash
Set FontSize 14
Set LineHeight 1.2
Set Width 1155
Set Height 665
Set Padding 20
Set TypingSpeed 90ms

# molokai / monokai terminal palette, mirroring the agg theme in
# record-demo.sh. Lives in its own file so it's reusable across tapes.
Source scripts/molokai.tape

# --- Setup (hidden): build the isolated demo repo and launch Neovim -----------
Hide
Type "DEMO=$(scripts/record-demo-setup.sh)"                               Enter
Type "export XDG_CONFIG_HOME=$DEMO/xdg-config XDG_DATA_HOME=$DEMO/xdg-data XDG_STATE_HOME=$DEMO/xdg-state" Enter
# Force semicolon-form truecolor so molokai's blue channel survives VHS's
# terminal (see the terminfo build in record-demo-setup.sh).
Type "export TERMINFO=$DEMO/terminfo TERM=xterm-256color-semi"            Enter
Type "cd $DEMO/repo && clear"                                             Enter
Type "nvim --clean -u $DEMO/init.lua"                                     Enter
Sleep 3.5s
Show

# --- Drive the session (mirrors record-demo.sh's snap/key choreography) -------
Sleep 600ms                       # empty editor

Type ":JJ log"                    # open the log view
Sleep 300ms
Enter
Sleep 2.2s                        # log view

Type "/Type-check"                # find a change touching >1 file
Enter
Sleep 500ms
Enter                             # <cr> drills into its status
Sleep 2.6s

Type "/M Makefile"                # jump to its first file
Enter
Sleep 700ms
Tab                               # file 1 side-by-side float
Sleep 2s
Tab                               # tab out
Sleep 900ms

Type "j"                          # jump to its second file
Sleep 700ms
Tab                               # file 2 side-by-side float
Sleep 2s
Tab                               # tab out
Sleep 900ms

Type "o"                          # operation log
Sleep 2.4s
Type "/new empty commit"          # find an operation to drill into
Enter
Sleep 700ms
Enter                             # <cr> -> op-show detail
Sleep 3.2s
