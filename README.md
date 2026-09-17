# imthemousenow

Drive the mouse pointer from the keyboard on [Omarchy](https://omarchy.org).

Today the pointing is done by [wl-kbptr](https://github.com/moverest/wl-kbptr),
which `imthemousenow` drives rather than reimplements, so upstream options pass
straight through `-o`. That backend is an implementation detail: the CLI, the
presets and the keybindings are the stable surface, and are free to grow
capabilities wl-kbptr does not have.

What the tool adds today:

- **Presets** — named mode chains (`quick`, `precise`, `detect`, `windows`, ...)
  instead of memorising `-o modes=tile,bisect,click`.
- **Theming** — colours are rendered from the active Omarchy theme through
  Omarchy's own template system; the label font follows `omarchy font set`.
- **Scoping** — `--scope active-window` restricts the overlay via `-r`, and the
  focused monitor is always passed via `-O`.
- **Window targeting** — the `windows` preset feeds wl-kbptr's floating mode
  real window rectangles from `hyprctl clients`, which needs no OpenCV.
- **Keybindings** — `SUPER + ;` and friends, with descriptions so they appear
  in Omarchy's keybinding overlay.
- **A build that works on this machine** — see OpenCV 5 below.

## Install

```bash
./install.sh          # build wl-kbptr + wire everything up
./install.sh --dev    # same, but symlinked to this checkout for development
./install.sh --lite   # build without OpenCV (everything but `detect`)
./install.sh --no-build --dev   # integration only, no compile
```

`./uninstall.sh` reverses it (add `--purge` to drop user overrides too).

## Use

| Binding | Preset | What it does |
| --- | --- | --- |
| `SUPER + ;` | `quick` | Grid → bisect → click |
| `SUPER + CTRL + ;` | `precise` | Grid → arrow-key split → click |
| `SUPER + SHIFT + ;` | `detect` | OpenCV-detected targets → click |
| `SUPER + ALT + ;` | `windows` | Label open windows → click |
| `SUPER + CTRL + SHIFT + ;` | `quick --repeat` | Reopens after every click until Escape |
| `SUPER + SHIFT + ALT + ;` | `detect --scope active-window` | Detect targets inside the focused window |

```bash
imthemousenow --list                      # every preset
imthemousenow quick --scope active-window # restrict to the focused window
imthemousenow move                        # move the pointer, don't click
imthemousenow quick --repeat              # keep reopening until Escape
imthemousenow detect --scope active-window
imthemousenow --stop                      # close a stuck overlay
```

Only one overlay runs at a time. wl-kbptr grabs the keyboard, so a second
instance would stack an unreachable overlay beneath the new one and lock the
session out; pressing any pointer binding while one is up is a no-op instead.
`imthemousenow --stop` closes whatever is running, including an overlay left
behind by a crash.

`CTRL + ALT + DELETE` is also a way out: the plugin rebinds it to
`imthemousenow-panic`, which dismisses any overlay and then runs Omarchy's own
action for that key (`omarchy-hyprland-window-close-all`), so the stock
behaviour is preserved rather than replaced. Hyprland keybindings still fire
while wl-kbptr holds the keyboard, which is what makes this reachable at all.

## Configuration

`imthemousenow` has its own config file, and it is a **superset of wl-kbptr's**:
every section wl-kbptr understands passes straight through, so an existing
wl-kbptr config is already a valid one here. Two section names are reserved and
never reach wl-kbptr:

| Section | Owner |
| --- | --- |
| `[imthemousenow]`, `[imthemousenow.*]` | this tool's own behaviour |
| `[preset.<name>]` | named mode chains |
| everything else | passed through to wl-kbptr verbatim |

Passing sections through rather than enumerating them means an option upstream
adds tomorrow works today, without a code change here.

Your config lives at `~/.config/omarchy/imthemousenow/config.toml` and is merged
over the shipped defaults, key by key:

```toml
[imthemousenow]
default_preset = "precise"
single_instance = true    # never let two overlays stack
theme_colors = true       # start from the Omarchy theme
theme_font = true

[imthemousenow.scope]
default = "screen"        # screen | active-window | workspace

[imthemousenow.repeat]
guard_ms = 200            # a "success" faster than this is a misfire
max_quick_exits = 5       # this many in a row stops a runaway burst
max_passes = 0            # 0 = unlimited clicks per burst

# Anything below here is wl-kbptr's own config, passed through:
[mode_tile]
label_symbols = "arstgmneio"

# Presets are config too, so you can add your own:
[preset.myown]
description = "Grid, then click"
modes = "tile,click"
```

The layers, later winning:

1. `config.default.toml` — shipped defaults and presets
2. the Omarchy theme template — colours, re-rendered on every theme change
3. your `config.toml`

`imthemousenow-config` drives all of it:

```bash
imthemousenow-config check      # validate every layer
imthemousenow-config path       # where each layer lives
imthemousenow-config compile    # write the wl-kbptr config, print its path
imthemousenow-config presets    # every preset, from every layer
```

Compilation is cached in `$XDG_RUNTIME_DIR` and redone only when a layer
changes, so it costs nothing per keypress. The compiled file is a build
artifact — edit a layer, never the output.

## OpenCV 5

Arch ships opencv 5. wl-kbptr 0.4.1 — the tagged release, and what the AUR
still packages — does not build against it (upstream issue #99). Upstream
commit `0854a51` makes meson accept opencv 4 **or** 5, but it is not in any
release yet.

So `pkg/source.toml` pins that commit and `install.sh` builds it with
`makepkg`, which means pacman owns the binary (`wl-kbptr-omarchy`, which
`provides`/`conflicts` with `wl-kbptr`, so it swaps cleanly with the AUR
package later). When upstream tags a release, set `mode = "release"`, or
`mode = "aur"` once the AUR catches up, and re-run `install.sh`.

The fix is a **build** fix. One reporter on #99 says floating/detect mode still
dims the screen without drawing labels under OpenCV 5 — the plugin is built so
this degrades cleanly: only `detect` depends on OpenCV, and it refuses to run
(with a notification) rather than dimming your screen, on a build that lacks
OpenCV support. `--lite` makes that configuration explicit.

## Layout

```
bin/imthemousenow           preset -> wl-kbptr flags; the whole CLI
bin/imthemousenow-regions   window rects for floating/stdin mode
presets.toml                shipped presets
templates/wl-kbptr.conf.tpl Omarchy theme template -> theme colours
hypr/imthemousenow.lua              keybindings + layer rules
hooks/{theme-set,font-set,post-update}
pkg/{PKGBUILD,source.toml}  from-source build
install.sh / uninstall.sh
```

See [docs/design-notes.md](docs/design-notes.md) for what was verified against
this machine and where the implementation departs from the original plan.
