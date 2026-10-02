# FuzzLogg workflow and implementation review

FuzzLogg filters the current Neovim buffer with Vim regular expressions. It
shows matching lines in a results buffer, preserves source line numbers for
jumping, and can save filters as compositions. The implementation is in
[`lua/fzf-foldsearch/fuzzlogg.lua`](lua/fzf-foldsearch/fuzzlogg.lua).

## Workflow

### Open and build a filter

Open a log or text buffer and run:

```vim
:FuzzLoggOpen
:FuzzLoggAdd
:FuzzLoggAdd exclude
```

`:FuzzLoggOpen` is optional. Commands that need a session open one automatically
for the current buffer. Panel actions use the source window associated with the
panel.

The default layout is a vertical split. `fuzzlogg.layout` also accepts `split`
and `same_window`. In the picker, press `<Alt-Enter>` to add the typed Vim regex
even if history matches, or `<Enter>` to select an item from shared FoldSearch
pattern history. Includes combine with OR; excludes veto matching lines. With
only excludes, no lines are selected. When a line matches
multiple includes, the first matching include determines its highlight color.
Use `:FuzzLoggAdd ERROR` or `:FuzzLoggAdd exclude heartbeat` to add a pattern
directly without the picker.
To create a separate colored pattern for every distinct capture value in the
source buffer, run `:FuzzLoggAddGroup 1 \v^\[(\S+)\s*\]`. This keeps the regex
conditions around group 1 and matches each captured value exactly. The existing
pattern limit applies to the whole batch. Only the source regex is added to
pattern history; group patterns come only from the current buffer, are
session-only, and are omitted from saved compositions.

Results update after source edits (100 ms debounce by default). Context can be
adjusted with `:FuzzLoggContextAdd {n}`. It expands around selected lines after
filtering, so context lines may themselves match excluded patterns. Context is
not part of a saved composition.

### Navigate and edit

- Press `<Enter>` in results to jump to the source line.
- Run `:FuzzLoggJumpToResult` from the source buffer to jump to a visible result.
- Use `:FuzzLoggList` to see the active filter.
- Use `:FuzzLoggRemove` to select multiple active items with `<Tab>` and remove
  them with `<Enter>`, `:FuzzLoggRemove {n}` for one index, or `:FuzzLoggClear`
  to clear all active items.

When a loaded composition is active, `:FuzzLoggList` shows it as one
`expression` item at index 1. Removing index 1 drops the loaded expression;
interactive patterns added afterward follow it in the list. The default limit
of eight patterns applies to both interactive additions and loaded expressions.

### Save and load

Save a named composition with `:FuzzLoggSave` (prompt) or
`:FuzzLoggSave incident review` (multiword names are accepted). Load it with
`:FuzzLoggLoad incident review` or select it in `:FuzzLoggPanel`.

The RPN syntax is postfix. `/regex/` is a Vim regex atom, and spaces inside an
atom are allowed. Escape a delimiter slash as `\/`. `|`, `&`, and `-` mean
union, intersection, and difference; postfix `~` means complement. Parentheses
are accepted for readability and ignored during parsing. Saved composition
references can be nested up to five levels; expression-tree depth is capped at
128.

```vim
:FuzzLoggLoad /ERROR/ /WARN/ |
:FuzzLoggLoad /ERROR/ /WARN/ | /heartbeat/ -
:FuzzLoggLoad errors /debug/ ~ &
```

`:FuzzLoggLoad` accepts the whole command line, including spaces and `|`.
Exact composition names are checked first; otherwise the argument is parsed as
an expression. Names with spaces are usable as direct command arguments, but
RPN references use the `name` or `namespace::label` token forms and therefore
do not include spaces.

FuzzLogg stores pattern history and compositions in
`{stdpath('data')}/fuzzlogg/store.json`. It creates an anonymous snapshot after
filter additions, removals, clears, and loads. The oldest unpinned anonymous
snapshots are pruned when their count exceeds 20, leaving the newest 20. Empty
filters use the `@empty` RPN atom; older plugin versions do not recognize
this atom. Context is not saved.

### Panel actions

Run `:FuzzLoggPanel` to open the saved-data panel. On a pattern-history row,
`<Enter>` loads the pattern, `a` adds it as an include, and `x` adds it as an
exclude. On a composition row, `<Enter>` loads, `p` toggles pinning, `d`
deletes, and `r` renames. `s` saves the active session and `q` closes the
panel. These actions track the underlying store item, including anonymous and
namespaced compositions.

### Import `.fl` files

Each nonblank, non-comment line has the form `label: expression`. A comment
starts with `#` after optional leading whitespace. The filename stem is the
namespace. For example, `alerts.fl`:

```text
base: /ERROR/ /WARN/ |
without_heartbeat: alerts::base /heartbeat/ -
```

Import with `:FuzzLoggImport /path/to/alerts.fl`. Referenced namespaces are
loaded from beside the importing file first, then from `fuzzlogg.import_path`
if configured. Import validates entries and dependencies before replacing
those namespaces in the store.

## Commands

| Command | Purpose |
| --- | --- |
| `:FuzzLoggOpen` | Open a session for the current buffer |
| `:FuzzLoggAdd [include\|exclude] [pattern]` | Pick or directly add a pattern |
| `:FuzzLoggAddGroup {n} {regex}` | Add one pattern per distinct capture value |
| `:FuzzLoggRemove [n]` | Pick active items or remove one by index |
| `:FuzzLoggClear` | Clear the active filter |
| `:FuzzLoggClose` | End the session |
| `:FuzzLoggContextAdd {n}` | Change the context line count |
| `:FuzzLoggList` | List the active filter |
| `:FuzzLoggSave [name]` | Save a named composition |
| `:FuzzLoggLoad {name\|expr}` | Load a composition or RPN expression |
| `:FuzzLoggPanel` | Open saved patterns and compositions |
| `:FuzzLoggJumpToResult` | Jump from source to a result |
| `:FuzzLoggJumpToSource` | Jump from results to source |
| `:FuzzLoggImport {file}` | Import a `.fl` file |

The `<leader>v…` mappings shown in README and Vim help are suggestions; the
plugin does not register them. Define mappings in your Neovim configuration
if you want them.

## Fixes implemented after review

The review found issues in expression evaluation, persistence, panel row
dispatch, import behavior, session cleanup, and command argument handling.
The implementation now preserves a loaded expression as the active filter,
serializes include/exclude filters with set difference, enforces the pattern
limit on loads, and maps panel actions to store indices rather than display
positions. Anonymous compositions can be loaded, pinned, renamed, and deleted
from the panel. `same_window` restores its source buffer on close.

RPN tokenization now treats `/.../` as one atom (including spaces and escaped
slashes) and permits parentheses next to tokens. Import parses references from
the expression tree, validates all staged namespaces, and only writes after
validation succeeds. Only whole-line `#` comments are ignored, so `#` inside a
regex is retained. Empty filters are represented by `@empty` to make clears
persist as snapshots.

The overlap color rule is intentional: the first matching include colors a
line. Context rows inherit the color of a nearby selected line when available.
