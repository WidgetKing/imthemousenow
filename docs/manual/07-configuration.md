# Configuration

`imthemousenow` has its own config file, and it is a **superset of wl-kbptr's**:
every section wl-kbptr understands passes straight through, so an existing
wl-kbptr config is already a valid one here. Two section names are reserved and
never reach wl-kbptr:

| Section | Owner |
| --- | --- |
| `[imthemousenow]`, `[imthemousenow.*]` | this tool's own behaviour |
| `[mode.<name>]` | how a MODE builds a wl-kbptr mode chain |
| everything else | passed through to wl-kbptr verbatim |

Passing sections through rather than enumerating them means an option upstream
adds tomorrow works today, without a code change here.

Your config lives at `~/.config/omarchy/imthemousenow/config.toml` and is merged
over the shipped defaults, key by key:

```toml
[imthemousenow]
theme_colors = true       # start from the Omarchy theme
theme_font = true

# What you get when a flag is not given -- i.e. what SUPER + ; does, and
# what each modifier flips away from.
[imthemousenow.defaults]
mode = "hints"
scope = "window"
action = "left-click"
lifetime = "single"

# How much of the screen each MODE hides, as a multiplier on the alpha the
# theme gave it. Backgrounds only -- labels and borders keep their alpha, so an
# overlay turned down is see-through, not unreadable. `default` covers any MODE
# without a line of its own.
[imthemousenow.opacity]
default = 1.0
hints = 0.6               # lighter dimming when labelling clickable things
grid = 1.0

[imthemousenow.continuous]
guard_ms = 200            # a "success" faster than this is a misfire
max_quick_exits = 5       # this many in a row stops a runaway burst
max_passes = 0            # 0 = unlimited clicks per burst

# MODEs are config too. `refine` is how a selection narrows to a point:
# bisect (home row) or split (arrow keys).
[mode.grid]
refine = "split"

# Anything below here is wl-kbptr's own config, passed through:
[mode_tile]
label_symbols = "arstgmneio"
```

The layers, later winning:

1. `config.default.toml` — shipped defaults and modes
2. the Omarchy theme template — colours, re-rendered on every theme change
3. your `config.toml`

`imthemousenow-config` drives all of it:

```bash
imthemousenow-config check      # validate every layer
imthemousenow-config path       # where each layer lives
imthemousenow-config compile    # write the wl-kbptr config, print its path
imthemousenow-config modes      # every MODE, from every layer
imthemousenow-config env        # every setting, as shell assignments
```

`env` is how the shell reads its settings: one call at startup, evalled, and
every lookup after that is a variable. It used to be a process per lookup, each
one re-parsing all three layers.

Compilation is cached in `$XDG_RUNTIME_DIR` and redone only when a layer
changes, so it costs nothing per keypress. The compiled file is a build
artifact — edit a layer, never the output.

`[imthemousenow.action.right-click]` is rendered by the theme template, so the
right-click tint follows your palette. It uses `red`: Omarchy themes collapse
semantic colour names freely — in Matte Black, `blue` equals `accent` and
`yellow` is a red — but `accent` and `red` were distinct in every theme checked,
and they read as "normal" versus "careful".

One trap worth knowing: `general.home_row_keys` is left unset, so wl-kbptr
derives it from your keymap. If you do set it, it must be **exactly 11
characters** or wl-kbptr rejects the entire config, and every chord silently
does nothing. `imthemousenow-config check` catches that before you find out the
hard way.

---

[← The command line](06-command-line.md) · [Manual contents](README.md) · [The bar widget →](08-bar-widget.md)
