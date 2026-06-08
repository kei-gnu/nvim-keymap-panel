# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

A Neovim plugin that renders a persistent right-hand sidebar listing keymaps.
It answers the problem of forgetting both built-in shortcuts and self-defined
keymaps by keeping the list always visible.

## Structure

```
lua/keymap-panel/
  init.lua        -- entry point, setup(), UI (right sidebar), rendering
  cheatsheet.lua  -- cheatsheet.md parser (static section)
  detector.lua    -- dynamic detection of user-defined keymaps
```

## Display model (hybrid)

1. **Static**: parses a `cheatsheet.md` (sections + Markdown tables). Needed
   because built-in keys (`i`, `v`, `u`, …) can't be enumerated as keymaps.
2. **Dynamic**: auto-detects user keymaps and appends them in a trailing
   section. Two strategies, deduped against the cheatsheet (normalized compare
   absorbs `<Space>`/`<Sp>`/`<Ctrl>` spelling variants):
   - **A**: regex-scan config files (`scan` paths) for `vim.keymap.set` / `map(`
     `(mode, lhs)` and cross-check against `nvim_get_keymap`, so only **actually
     active** maps are shown (string-rhs maps included).
   - **B**: walk Lua callbacks from `nvim_get_keymap` via `debug.getinfo` and
     keep those whose source is under the config dir (symlinks resolved) —
     catches maps defined inside plugin `config` blocks.

## Commands / operations

- `:KeymapPanel [open|close|toggle|refresh|focus_next|focus_prev|close_all]`
  (no argument = `toggle`).
- In the panel: `q` close, `R` reload. A hint line is pinned at the top; manual
  resizes are followed via `WinResized`.
- If a file gets opened in the panel window (e.g. Telescope/`:e` while focused
  on the panel), `BufWinEnter` restores the panel and re-opens the file in the
  center editor window.

## Integration & gotchas (the tricky parts)

- **Multi-tab** (tab-as-workspace): buffer is shared across tabs, window is
  per-tab. `open`/`close`/`toggle` act only on the current tab. The panel window
  is identified by the window-local marker `vim.w[win].keymap_panel` (not
  filetype, so it survives buffer swaps).
- **Session managers**: the panel is a non-serializable window. Call
  `close_all()` (all tabs) from a pre-save hook, or `mksession` records an
  `enew` and a phantom "Untitled" buffer reappears on restore.
- **neo-tree / async explorers race**: opening the panel while the explorer is
  still building can hijack a file window. Auto-open paths must use
  `open_when_tree_ready()`, which polls until the tree is ready (≤2s fallback).
- **Startup auto-open**: done on `VimEnter` + `vim.schedule`, after all VimEnter
  handlers, to avoid being closed by a session-restore `silent only`.
- **`QuitPre`**: if only sidebar windows remain, the panel closes so it doesn't
  block `:q`.

## Constraints

- Strategy A's regex only matches the common "mode and lhs on one line" form;
  it is not a full Lua parser.
- The astrocore `mappings` table form (`["<Leader>x"] = {...}`) isn't picked up
  by strategy A (it is by B if a callback is present).

## Development

- Manual check: `:KeymapPanel toggle`; after edits `:Lazy reload keymap-panel`.
- Keep code comments and the existing style; UI strings may be non-English.
- Commits: English messages, and keep the `Co-Authored-By: Claude Code` trailer
  (this is a self-made plugin).
