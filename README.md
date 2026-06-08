# nvim-keymap-panel

A persistent right-hand sidebar that lists your keymaps so you never have to
remember them. It combines a **static** cheatsheet (parsed from a Markdown
file) with **dynamically detected** keymaps defined in your own config, and
keeps them in view while you work.

> The plugin started as a personal answer to "I keep forgetting both the
> built-in shortcuts and the keymaps I defined myself." Keeping the list
> always visible turned out to be the simplest fix.

## Features

- **Hybrid listing**
  - *Static*: parses a `cheatsheet.md` (sections + Markdown tables) so you can
    show built-in keys (`i`, `v`, `u`, …) that can't be enumerated as keymaps.
  - *Dynamic*: auto-detects keymaps defined in your config and appends them in a
    dedicated section. New keymaps show up automatically.
- **Accurate dynamic detection** (two strategies, deduped against the cheatsheet):
  - *A*: regex-scans your config files for `vim.keymap.set(...)` / `map(...)`
    and cross-checks against `nvim_get_keymap`, so only **actually active**
    maps are shown (string-rhs maps included).
  - *B*: walks Lua callbacks from `nvim_get_keymap` via `debug.getinfo` and
    keeps the ones defined under your config dir (symlinks resolved) — catches
    maps defined inside plugin `config` blocks that the regex can't.
- **Multi-tab aware** (tab-as-workspace): the buffer is shared across tabs, the
  window is per-tab. `open`/`close`/`toggle` act only on the current tab.
- **Stays out of your way**: follows manual resizes, restores itself if a file
  is accidentally opened in the panel window, and won't block `:q` when it is
  the last non-sidebar window.

## Requirements

- Neovim >= 0.9

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "kei-gnu/nvim-keymap-panel",
  lazy = false,
  config = function()
    require("keymap-panel").setup({
      -- see Configuration below
    })
    vim.keymap.set("n", "<Leader>k", "<cmd>KeymapPanel toggle<CR>", { desc = "Toggle keymap panel" })
  end,
}
```

## Configuration

Defaults:

```lua
require("keymap-panel").setup({
  width = 34,
  key_width = 12,
  auto_open = true, -- open automatically on startup
  -- Static cheatsheet source (Markdown). Missing file => static section is empty.
  cheatsheet = vim.fn.stdpath("config") .. "/cheatsheet.md",
  -- Config paths to scan for your own keymaps (relative to stdpath("config")).
  scan = { "init.lua", "lua/config", "lua/plugins", "lua/polish.lua" },
  -- Modes considered by dynamic detection.
  modes = { "n", "v", "i", "t" },
  custom_section = "自作キーマップ (動的)", -- header for the dynamic section
})
```

### `cheatsheet.md` format

Each `## Heading` becomes a section; each `| key | description |` table row
becomes an entry. Header rows (`| キー | ... |`) and separator rows
(`|---|---|`) are skipped. Backticks around cells are stripped.

```markdown
## Window

| key      | description        |
| -------- | ------------------ |
| `<C-w>s` | split horizontally |
| `<C-w>v` | split vertically   |
```

## Usage

- `:KeymapPanel [open|close|toggle|refresh|focus_next|focus_prev|close_all]`
  (no argument = `toggle`)
- Inside the panel: `q` to close, `R` to reload.
- `focus_next` / `focus_prev` cycle left↔right across normal windows (wrapping
  at the edges); handy if you don't use `<C-h>/<C-l>`.

## Integration notes

These are optional. They matter only if you use session restore or a file
explorer, and mirror how the author wires it up.

<details>
<summary>Session managers (auto-session etc.)</summary>

The panel is a non-serializable window. Close it before `mksession` runs,
otherwise the saved session records an `enew` and a phantom "Untitled" buffer
comes back on restore (same issue neo-tree has). Use `close_all()` (all tabs):

```lua
-- auto-session
pre_save_cmds = {
  function() pcall(function() require("keymap-panel").close_all() end) end,
},
```
</details>

<details>
<summary>neo-tree / async file explorers</summary>

Opening the panel while an async explorer is still building can let a file
window get hijacked by the panel. For auto-open paths (e.g. `TabNewEntered`),
use `open_when_tree_ready()`, which polls until the tree finishes (or gives up
after ~2s and opens the panel anyway):

```lua
vim.api.nvim_create_autocmd("TabNewEntered", {
  callback = function()
    local ok, kp = pcall(require, "keymap-panel")
    if ok then kp.open_when_tree_ready() end
  end,
})
```
</details>

## Limitations

- Strategy A's regex only matches the common "mode and lhs on one line" form;
  it is not a full Lua parser.
- The astrocore `mappings` table form (`["<Leader>x"] = {...}`) isn't picked up
  by strategy A (it is by strategy B if a callback is present).

## License

MIT
