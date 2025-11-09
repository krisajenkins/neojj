We're going to add an annotate feature. This is very similar to git blame. Run `jj file annotate flake.nix` to see an example of the output.

Your task is to add an annotation buffer and support for `:JJ annotate <filename>`. The filename is optional and defaults to the current file.

Running the command opens the file (if not already active) and opens a
30-column window to the left, showing annotation information (change id,
author, date).

The cursor for the annotation buffer is scroll-bound to the cursor for the
actual file. scrollbinding is a vim feature you will need to research.

When the buffer we're annotating is closed or disappears for any reason, the
annotation buffer gets killed.

Repeated change IDs should be collapsed with ASCIIart, so that:

```
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
kymnyksp krisajen     2025-07-11
tsyzzrzl krisajen     2025-07-14
sqmvkywl krisajen     2025-07-15
yrzvztnn krisajen     2025-11-09
kymnyksp krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
uqzommup krisajen     2025-07-08
uqzommup krisajen     2025-07-08
```

...becomes:

```
rxpvrtqt krisajen     2025-07-11
o
kymnyksp krisajen     2025-07-11
tsyzzrzl krisajen     2025-07-14
sqmvkywl krisajen     2025-07-15
yrzvztnn krisajen     2025-11-09
kymnyksp krisajen     2025-07-11
rxpvrtqt krisajen     2025-07-11
|
|
|
|
|
|
|
|
|
|
|
|
|
|
|
|
|
|
|
|
o
uqzommup krisajen     2025-07-08
o
```

...or similar.

## Keybindings

The annotation buffer supports the following keybindings:

- `<cr>` - Open status buffer for the change at cursor
  - If a status buffer is already open, reuse it and update with the new change
  - Opens in a horizontal split with the file buffer (not the narrow annotation buffer)
  - Focus returns to the annotation buffer after opening
  - Works on continuation lines (`│` or `o`) by finding the change ID from above
- `y` - Copy change ID at cursor to system clipboard
  - Also works on continuation lines
- `q`, `<c-c>`, `<esc>` - Close annotation buffer

## Implementation Notes

- Format: `8-char change_id + 7-char author + date` (total ~27 chars to fit in 30-column window)
- Continuation lines must correctly resolve to their parent change ID when interacted with
- ANSI color codes from `jj file annotate` output must be stripped before parsing
- Scrollbind is bidirectional between annotation and file buffers
- Annotation buffer is positioned on the far left via `wincmd H`
