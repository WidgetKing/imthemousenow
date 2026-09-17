# imthemousenow

Drive the mouse pointer from the keyboard on [Omarchy](https://omarchy.org).

Today the pointing is done by [wl-kbptr](https://github.com/moverest/wl-kbptr),
which `imthemousenow` drives rather than reimplements, so upstream options pass
straight through `-o`. That backend is an implementation detail: the four
concepts below, the CLI and the keybindings are the stable surface, and are
free to grow capabilities wl-kbptr does not have.

## The four choices

Every invocation is the same four independent choices. There are no modes with
names to memorise and no special cases — any combination is valid.

| | Options | |
| --- | --- | --- |
| **MODE** | `hints` · `grid` | how targets are presented |
| **SCOPE** | `window` · `monitor` | where the overlay is drawn |
| **ACTION** | `left-click` · `right-click` · `move` · `drag` | what happens when you land (`;` switches it live) |
| **LIFETIME** | `single` · `continuous` | one selection, or until Escape |

**MODE** — `hints` labels what looks clickable: detected targets when the build
has OpenCV, open window rectangles when it does not. Typing a hint's label
clicks it, because the hint already identifies the target. `grid` labels a grid
of cells covering the area, then halves the chosen cell with the home row until
the pointer is exactly where you want it — slower, but it never misses a target,
because it does not try to guess where the targets are.

**SCOPE** — `window` confines the overlay to the focused window, so the labels
stay short and you aren't offered the rest of the desktop. `monitor` covers the
whole focused screen.

**ACTION** — what the pointer does on arrival. `move` places the pointer and
leaves it there, clicking nothing. `drag` is not implemented yet. This is the
one axis you do not have to decide up front: `;` switches it while the overlay
is on screen, which is the only moment you can actually see what you are
aiming at.

**LIFETIME** — `single` clicks once and gets out of the way. `continuous`
reopens after every click, so a burst of clicking is one invocation; Escape
ends it. Targets are recomputed every pass, so it follows windows that move,
open or close between clicks.

## Keys

`SUPER + ;` is the common case: hints, in the window you are already looking at,
one left click. Each modifier flips exactly one axis, and they compose — so you
memorise one binding plus what three modifiers mean, not eight bindings. ACTION
is not among them, because it is chosen inside the overlay instead.

| Modifier | Flips |
| --- | --- |
| `SHIFT` | SCOPE → `monitor` |
| `ALT` | MODE → `grid` |
| `CTRL` | LIFETIME → `continuous` |

| Chord | MODE | SCOPE | LIFETIME |
| --- | --- | --- | --- |
| `SUPER + ;` | hints | window | single |
| `SUPER + SHIFT + ;` | hints | monitor | single |
| `SUPER + ALT + ;` | grid | window | single |
| `SUPER + SHIFT + ALT + ;` | grid | monitor | single |
| `SUPER + CTRL + ;` | hints | window | continuous |
| `SUPER + CTRL + SHIFT + ;` | hints | monitor | continuous |
| `SUPER + CTRL + ALT + ;` | grid | window | continuous |
| `SUPER + CTRL + SHIFT + ALT + ;` | grid | monitor | continuous |

### Inside the overlay

In `hints`, type a label and it clicks. In `grid`, type a label to pick a cell,
then the home row (`a s d f` / `j k l m`) halves it until the pointer is where
you want it; `g`, `h` and `b` commit with a left, right or middle click.

**`;` switches ACTION**, in either mode, at any point before you commit:

```
;   left click  <->  right click        the overlay turns red for right click
;   again                               back to left click
```

It is a one-off: after the click lands, the overlay returns to whatever ACTION
the chord asked for, even in a continuous lifetime. So a right click costs one
extra keypress and never changes what the next click does.

The overlay is torn down and relaunched to do this, because wl-kbptr takes its
configuration at startup and cannot be reconfigured while it holds the
keyboard. You will see a flicker, and anything you had already typed is
discarded — the trade for being able to decide *after* seeing the overlay
rather than before.

`;` reaches us rather than wl-kbptr because it is a compositor binding inside a
Hyprland submap that exists only while the overlay is up. Everywhere else, and
at every other moment, `;` is an ordinary semicolon. The submap is reset
however the overlay exits, including a crash, and `CTRL + ALT + DELETE` resets
it too.

## Install

```bash
./install.sh          # build wl-kbptr + wire everything up
./install.sh --dev    # same, but symlinked to this checkout for development
./install.sh --lite   # build without OpenCV (hints label windows instead)
./install.sh --no-build --dev   # integration only, no compile
```

`./uninstall.sh` reverses it (add `--purge` to drop user overrides too).

## Command line

The flags are the four choices; anything you leave out comes from your config.

```bash
imthemousenow                                   # the defaults
imthemousenow --mode grid --scope monitor       # grid over the whole screen
imthemousenow --action move                     # place the pointer, click nothing
imthemousenow --lifetime continuous             # keep reopening until Escape
imthemousenow --list                            # available modes
imthemousenow -n --mode grid                    # print the wl-kbptr command
imthemousenow --stop                            # close a stuck overlay
```

## Getting unstuck

Only one overlay runs at a time. wl-kbptr grabs the keyboard, so a second
instance would stack an unreachable overlay beneath the new one and lock the
session out; pressing any pointer chord while one is up is a no-op instead.
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
| `[mode.<name>]` | how a MODE builds a wl-kbptr mode chain |
| everything else | passed through to wl-kbptr verbatim |

Passing sections through rather than enumerating them means an option upstream
adds tomorrow works today, without a code change here.

Your config lives at `~/.config/omarchy/imthemousenow/config.toml` and is merged
over the shipped defaults, key by key:

```toml
[imthemousenow]
single_instance = true    # never let two overlays stack
theme_colors = true       # start from the Omarchy theme
theme_font = true

# What you get when a flag is not given -- i.e. what SUPER + ; does.
[imthemousenow.defaults]
mode = "hints"
scope = "window"
action = "left-click"
lifetime = "single"

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
```

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

The fix is a **build** fix. One reporter on #99 says floating mode still dims
the screen without drawing labels under OpenCV 5 — so `hints` degrades cleanly:
on a build without OpenCV support it labels window rectangles from `hyprctl`
instead, which needs no OpenCV and is exact where detection is heuristic.
`--lite` makes that configuration explicit.

## Layout

```
bin/imthemousenow           the four choices -> wl-kbptr flags; the whole CLI
bin/imthemousenow-config    config superset -> compiled wl-kbptr config
bin/imthemousenow-regions   window rects for hints without OpenCV
bin/imthemousenow-panic     Ctrl+Alt+Delete escape hatch
config.default.toml         shipped defaults and MODEs
templates/wl-kbptr.conf.tpl Omarchy theme template -> theme colours
hypr/imthemousenow.lua      keybindings + layer rules
hooks/{theme-set,font-set,post-update}
pkg/{PKGBUILD,source.toml}  from-source build
install.sh / uninstall.sh
```

See [docs/design-notes.md](docs/design-notes.md) for what was verified against
this machine and where the implementation departs from the original plan, and
[docs/lessons-learned.md](docs/lessons-learned.md) for what it cost to find out
— wl-kbptr internals, Hyprland's Lua config surface, and which decisions here
are load-bearing.
