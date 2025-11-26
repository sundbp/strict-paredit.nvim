# strict-paredit.nvim

A strict paredit-like plugin for Neovim that uses treesitter to prevent unbalanced delimiters in Lisp-like languages. Inspired by Emacs' `smartparens-strict-mode`.

## Features

- **Strict insertion**: Opening delimiters auto-pair; closing delimiters only move over existing ones (never create unmatched)
- **Paired deletion**: Deleting any delimiter automatically deletes its match
- **Treesitter-powered**: Uses treesitter for accurate delimiter matching
- **String/comment aware**: Strict mode is bypassed inside strings and comments
- **Multiple modes**: Works in both insert and normal mode

## Installation

### Using lazy.nvim / LazyVim

Add to your plugins (e.g., `~/.config/nvim/lua/plugins/strict-paredit.lua`):

```lua
return {
  "sundbp/strict-paredit.nvim",  -- or local path, see below
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  ft = { "clojure", "fennel", "scheme", "lisp", "racket", "janet", "hy", "query" },
  opts = {
    -- your options here (see Configuration below)
  },
}
```

### Local development / before publishing to GitHub

```lua
return {
  dir = "~/projects/strict-paredit.nvim",  -- path to your local clone
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  ft = { "clojure", "fennel", "scheme", "lisp", "racket" },
  opts = {},
}
```

### Using packer.nvim

```lua
use {
  "yourusername/strict-paredit.nvim",
  requires = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    require("strict-paredit").setup()
  end
}
```

## Configuration

```lua
require("strict-paredit").setup({
  -- Filetypes to enable strict paredit (defaults shown)
  filetypes = {
    "clojure",
    "fennel",
    "scheme", 
    "lisp",
    "racket",
    "janet",
    "hy",
    "lfe",
    "query",
  },
  
  -- Show notification warnings when operations are blocked (default: true)
  notify = true,
})
```

## Behavior

### Insert Mode

| Key | Behavior |
|-----|----------|
| `(`, `[`, `{` | Inserts both opening and closing delimiter, cursor between |
| `)`, `]`, `}` | If at matching closer, moves over it; otherwise blocked |
| `<BS>` | If before delimiter, deletes both it and its match |
| `<Del>` | If on delimiter, deletes both it and its match |

It also handles strings like "string" by inserting matching "-characters and
always deleting them as a pair. If you type a " in this position "foo |bar",
then an escaped " will be inserted.

### Normal Mode

| Key | Behavior |
|-----|----------|
| `x` | If on delimiter, deletes both it and its match |
| `X` | If before delimiter, deletes both it and its match |
| `s` | Blocked on delimiters (would unbalance) |

### Examples

```clojure
;; Typing '(' produces:
(|)  ;; cursor at |

;; With cursor here: (foo bar|)
;; Typing ')' moves cursor: (foo bar)|

;; With cursor here: (|foo bar)
;; Pressing backspace deletes both parens: |foo bar

;; With cursor on opening paren: |(foo bar)
;; Pressing 'x' in normal mode: |foo bar
```

## Escape Hatches

When you genuinely need to bypass strict mode:

```vim
:StrictPareditForceDelete   " Force delete char under cursor
:StrictPareditForceBackspace " Force delete char before cursor
```

## API

```lua
local sp = require("strict-paredit")

-- Enable for current buffer (useful for unlisted filetypes)
sp.enable()

-- Check if deletion would be allowed at cursor
sp.can_delete_at_cursor()  -- returns boolean
```

## Requirements

- Neovim 0.9+ (for treesitter APIs)
- Treesitter parser installed for your language (`:TSInstall clojure`, etc.)

## Limitations

1. **Treesitter dependent**: If treesitter can't parse the buffer (e.g., during heavy editing with syntax errors), matching may fail. The plugin will block operations it can't verify as safe.

2. **No slurp/barf**: This plugin focuses on strict delimiter handling. For structural editing operations like slurp, barf, raise, etc., use [nvim-paredit](https://github.com/julienvincent/nvim-paredit) alongside this plugin.

3. **Reader macros**: Some Lisp reader macros (`#(`, `@`, etc.) may not be handled perfectly depending on the treesitter grammar.

## Complementary Plugins

This plugin pairs well with:

- [nvim-paredit](https://github.com/julienvincent/nvim-paredit) - Structural editing (slurp, barf, etc.)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - Required for treesitter support
- [conjure](https://github.com/Olical/conjure) - Interactive evaluation for Lisps

## License

MIT
