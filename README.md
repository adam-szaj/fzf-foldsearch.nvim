# fzf-foldsearch.nvim

Fast log file search and filtering for Neovim, built on [fzf-lua](https://github.com/ibhagwan/fzf-lua).

Two complementary tools:

- **FoldSearch** — fold away non-matching lines in the current buffer (single pattern, very fast)
- **FuzzLogg** — dual-panel live viewer with multiple colored patterns, set algebra, and persistent compositions

Designed for large log files — tested up to 1 GB.

## Requirements

- Neovim 0.10+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)

## Installation

```lua
-- lazy.nvim
{
  'adam-szaj/fzf-foldsearch.nvim',
  -- dir = '~/Projects/fzf-foldsearch.nvim',
  dependencies = { 'fzf-lua' },
  config = function()
    require('fzf-foldsearch').setup()
  end,
}
```

---

## FoldSearch

FoldSearch hides all lines that don't match a pattern by folding them. You see only the lines you care about, in place, in the original file — no new buffer, no copy. When you're done, your original fold state is restored.

### Basic usage

You have a big log file open. You want to see only lines containing `ERROR`.

1. Press `,fs` (or `:FzfFoldSearch`).  
   An fzf picker opens showing the file contents — you can type to filter.

2. Type `ERROR` in the picker.  
   As you type, fzf highlights matching lines. You're not selecting a line —
   you're writing the pattern you want to keep visible.

3. Press `<Enter>`.  
   The picker closes. All lines that don't match `ERROR` are folded away.
   You're left with only the error lines, visible in the original buffer.

4. Want to also see a few lines around each match for context?  
   Press `,fi` a few times (or `:FzfFoldContextAdd 3`).  
   Each press adds one more line of context above and below each match.

5. Done? Press `,fe` (or `:FzfFoldEnd`).  
   All folds are removed and your original fold state is restored.

### Extracting results

Sometimes you want a copy of the matching lines in a separate buffer —
for example to save them or process further.

Inside the fzf picker (before pressing `<Enter>`):

- Press `<Ctrl-x>` — opens a new buffer with **only the lines that match**
- Press `<Ctrl-o>` — opens a new buffer with **matched lines plus context**

Or, when a fold search is already active:

```
,fm   — extract matched lines to a new buffer
,fv   — extract visible lines (matched + context) to a new buffer
```

Result buffers are scratch buffers — they won't ask you to save on quit.

### Using regex

The pattern is a Vim regex. Some examples:

```
ERROR               — literal string
ERROR\|WARN         — ERROR or WARN  (Vim regex alternation)
\d\+\.\d\+\.\d\+   — IP address pattern
^\[2024             — lines starting with [2024
```

If you had a recent `/` search, the picker is pre-filled with it — just press `<Enter>` to reuse it.

### Keymaps (suggested)

| Key | Action |
|-----|--------|
| `<leader>fs` | Open picker, `<Enter>` to fold |
| `<leader>fe` | End fold search, restore folds |
| `<leader>fi` | Context +1 |
| `<leader>fd` | Context -1 |
| `<leader>fI` | Context +5 |
| `<leader>fD` | Context -5 |
| `<leader>fm` | Extract matched lines |
| `<leader>fv` | Extract visible lines |

Inside the picker:

| Key | Action |
|-----|--------|
| `<Enter>` | Apply folds |
| `<Ctrl-x>` | Extract matched lines |
| `<Ctrl-o>` | Extract visible lines |

### Commands

| Command | Description |
|---------|-------------|
| `:FzfFoldSearch` | Open pattern picker |
| `:FzfFoldEnd` | Restore original folds |
| `:FzfFoldContextAdd {n}` | Adjust context by n lines (can be negative) |
| `:FzfFoldExtractMatched` | Extract matched lines to new buffer |
| `:FzfFoldExtractVisible` | Extract visible lines to new buffer |

### Configuration

```lua
require('fzf-foldsearch').setup({
  context        = 0,      -- lines of context shown around each match
  large_file_mb  = 50,     -- disable treesitter/LSP for files larger than this
  result_open    = 'new',  -- how to open result buffers:
                           --   'new'    horizontal split
                           --   'vnew'   vertical split
                           --   'edit'   same window
                           --   'tabnew' new tab
  max_result_bufs = 5,     -- max result buffers in memory (0 = unlimited)
})
```

---

## FuzzLogg

FuzzLogg opens a second panel next to your file showing only the lines that match your patterns. You can have multiple patterns at once, each in a different color. The results update live. You can jump between the results panel and the original file. Patterns and named filter sets (compositions) are saved between sessions.

Inspired by [klogg](https://klogg.filimonov.dev/).

### Basic usage

You have a log file open and want to investigate errors, but ignore noise from a specific module.

**Step 1 — Open FuzzLogg**

Press `,vo` (or `:FuzzLoggOpen`).

A new panel opens to the right (vsplit by default). It's empty — no patterns yet.

**Step 2 — Add your first pattern**

Press `,va` (or `:FuzzLoggAdd include`).

A picker opens showing your pattern history (empty on first use). Type `ERROR` and press `<Enter>`.

The results panel now shows all lines containing `ERROR`, highlighted in color 1 (blue).

**Step 3 — Add a second pattern**

Press `,va` again. Type `WARN` and press `<Enter>`.

Lines matching `WARN` appear in the results panel highlighted in color 2 (cyan). Both patterns are active simultaneously.

**Step 4 — Exclude noisy lines**

There's a module called `heartbeat` that logs every second and drowns out real errors.

Press `,vx` (or `:FuzzLoggAdd exclude`). Type `heartbeat` and press `<Enter>`.

Lines containing `heartbeat` disappear from the results — even if they also matched a previous pattern.

**Step 5 — Add context**

The error lines alone don't give enough information. Press `,vi` a few times to show lines around each match.

Each press of `,vi` adds one more line of context above and below each match. `,vd` reduces it. `,vI` / `,vD` change by 5 at a time.

**Step 6 — Jump between panels**

In the results panel, move the cursor to any line and press `<Enter>`. The cursor jumps to that exact line in the source file — useful for seeing the full surrounding context.

From the source file, press `,vj` to jump back to the corresponding line in the results panel.

**Step 7 — Save and close**

Press `,vs` (or `:FuzzLoggSave`). You'll be prompted for a name — type `errors-no-heartbeat` and press `<Enter>`.

Next time you open a similar log, you can reload this filter set from the panel (`,vp`).

Press `,ve` (or `:FuzzLoggClose`) to close the results panel and remove highlights.

### The pattern picker

When you press `,va` or `,vx`, an fzf picker opens:

```
FuzzLogg include>
  WARN
  ERROR
  heartbeat
  connection refused
```

The list shows your pattern history — patterns you've used before, most recent first. You can:

- **Select a historical pattern** — move the cursor to it and press `<Enter>`
- **Type a new pattern** — just start typing; press `<Enter>` to use what you typed
- **Filter the history** — type to narrow down the list, then `<Enter>` to select the highlighted item

If you type something that partially matches a historical entry, fzf will highlight it — but pressing `<Enter>` uses whatever you typed, not the highlighted item (unless you navigate to it explicitly with the arrow keys).

The picker is pre-filled with your last `/` search register.

### Managing active patterns

```
,vl   — list active patterns with index and color
,vc   — clear all patterns
```

To remove a specific pattern by index:

```
:FuzzLoggRemove 2     — remove pattern #2
```

### Compositions — saving and loading filter sets

A **composition** is a saved set of patterns (or a set expression) that you can reload later.

**Saving:**

```
,vs                          — prompts for a name, saves current patterns
:FuzzLoggSave errors-clean   — saves with that name directly
```

**Loading by name:**

```
:FuzzLoggLoad errors-clean
```

**Anonymous auto-save:**

Every time you add or remove a pattern, FuzzLogg automatically saves an anonymous snapshot. These show up in the panel with a timestamp label. The 20 oldest are kept; older ones are deleted automatically.

### The panel

Press `,vp` (or `:FuzzLoggPanel`) to open the panel:

```
# FuzzLogg Panel

## Patterns (history)
  ERROR
  WARN
  heartbeat
  connection refused

## Compositions
  [pinned] errors-clean         /ERROR/ /WARN/ | /heartbeat/ ~
  [anon]   2026-04-21 09:15     /ERROR/
  [anon]   2026-04-21 09:14     /WARN/
```

**Panel keymaps:**

| Key | Action |
|-----|--------|
| `<Enter>` | Load composition or pattern into active session |
| `a` | Add pattern under cursor (inclusive) |
| `x` | Add pattern under cursor (exclusive) |
| `p` | Toggle pin — pinned compositions are never auto-deleted |
| `d` | Delete composition |
| `r` | Rename composition |
| `s` | Save current session as new composition |
| `q` | Close panel |

### Advanced: set expressions (RPN)

FuzzLogg can load filter expressions using set algebra — not just simple pattern lists. This lets you express things like "lines that match A or B, but not C, unless they also match D".

Expressions use **Reverse Polish Notation (RPN)**: you write the operands first, then the operator.

**Operators:**

| Token | Meaning | Example |
|-------|---------|---------|
| `\|` | union — lines in A or B | `/ERROR/ /WARN/ \|` |
| `&` | intersection — lines in both A and B | `/ERROR/ /critical/ &` |
| `-` | difference — lines in A but not B | `/ERROR/ /debug/ -` |
| `~` | complement — all lines NOT in A (unary) | `/heartbeat/ ~` |

**Atoms:**

- `/regex/` — a Vim regex pattern, wrapped in slashes
- `name` — the name of a saved composition (resolved recursively)

Parentheses `( )` are allowed for readability but ignored by the parser.

**Reading RPN:**

Think of a stack. Each atom pushes a set of lines. Each operator pops operands and pushes the result.

```
/ERROR/ /WARN/ |
```
→ push {ERROR lines}, push {WARN lines}, `|` pops both → {ERROR ∪ WARN lines}

```
/ERROR/ /WARN/ | /heartbeat/ -
```
→ {ERROR ∪ WARN}, push {heartbeat lines}, `-` → {(ERROR ∪ WARN) without heartbeat}

```
/ERROR/ /debug/ ~ &
```
→ push {ERROR lines}, push complement of {debug lines} (= all lines without debug), `&` → intersection

**Loading an expression directly:**

```
:FuzzLoggLoad /ERROR/ /WARN/ |
:FuzzLoggLoad /ERROR/ /WARN/ | /heartbeat/ -
:FuzzLoggLoad errors-clean /noise/ ~ &
```

The last example uses a saved composition `errors-clean` as an operand and intersects it with the complement of `/noise/`.

**Compositions referencing other compositions:**

```
:FuzzLoggSave base-errors      ← save current patterns as "base-errors"

then later:
:FuzzLoggLoad base-errors /verbose/ -
```

This loads `base-errors` (resolved from the store) and subtracts lines matching `/verbose/`. You can then save this as a new composition too. Nesting is allowed up to depth 5.

### Keymaps (suggested)

| Key | Action |
|-----|--------|
| `<leader>vo` | Open FuzzLogg |
| `<leader>va` | Add inclusive pattern |
| `<leader>vx` | Add exclusive pattern |
| `<leader>ve` | Close FuzzLogg |
| `<leader>vi` | Context +1 |
| `<leader>vd` | Context -1 |
| `<leader>vI` | Context +5 |
| `<leader>vD` | Context -5 |
| `<leader>vj` | Jump to result (from source buffer) |
| `<leader>vl` | List active patterns |
| `<leader>vc` | Clear all patterns |
| `<leader>vs` | Save session as composition |
| `<leader>vp` | Open panel |
| `<Enter>` *(results panel)* | Jump to source line |

### Commands

| Command | Description |
|---------|-------------|
| `:FuzzLoggOpen` | Open FuzzLogg for current buffer |
| `:FuzzLoggAdd [include\|exclude]` | Add pattern via picker |
| `:FuzzLoggRemove {n}` | Remove pattern at index n |
| `:FuzzLoggClear` | Remove all patterns |
| `:FuzzLoggClose` | Close FuzzLogg |
| `:FuzzLoggContextAdd {n}` | Adjust context lines (can be negative) |
| `:FuzzLoggList` | List active patterns |
| `:FuzzLoggSave [name]` | Save current session as composition |
| `:FuzzLoggLoad {name\|expr}` | Load composition or RPN expression |
| `:FuzzLoggPanel` | Open panel |
| `:FuzzLoggJumpToResult` | Jump from source to result line |
| `:FuzzLoggJumpToSource` | Jump from result to source line |

### Persistence

Saved to `{stdpath('data')}/fuzzlogg/store.json`:

- **Pattern history** — all patterns ever used, deduplicated, shown in picker
- **Named compositions** — saved with `:FuzzLoggSave name`, kept permanently
- **Anonymous compositions** — auto-saved on every change, oldest deleted when count exceeds 20

### Configuration

```lua
require('fzf-foldsearch').setup({
  fuzzlogg = {
    layout      = 'vsplit',   -- results panel layout:
                              --   'vsplit'      vertical split (default)
                              --   'split'       horizontal split
                              --   'same_window' replace current window
    context     = 0,          -- default context lines around matches
    debounce_ms = 100,        -- live-update debounce in milliseconds
    max_patterns = 8,         -- max simultaneous patterns
    colors = {                -- fg highlight colors for patterns 1–8
      '#3d59a1', '#2ac3de', '#7aa2f7', '#bb9af7',
      '#394b70', '#0db9d7', '#9d7cd8', '#2d4f67',
    },
  },
})
```
