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
| **MODE** | `hints` · `grid` · `windows` | how targets are presented |
| **SCOPE** | `window` · `monitor` | where the overlay is drawn |
| **ACTION** | `left-click` · `right-click` · `move` · `drag` | what happens when you land (`;` switches it live) |
| **LIFETIME** | `single` · `continuous` | one selection, or until Escape |

**MODE** — `hints` labels what looks clickable: detected targets when the build
has OpenCV, open window rectangles when it does not. Typing a hint's label
clicks it, because the hint already identifies the target. `grid` labels a grid
of cells covering the area, then halves the chosen cell with the home row until
the pointer is exactly where you want it — slower, but it never misses a target,
because it does not try to guess where the targets are. `windows` labels whole
windows, one label each — what `Tab` opens to pick a window to swap with, and
useful on its own when a whole window is the thing you are aiming at.

**SCOPE** — `window` confines the overlay to the focused window, so the labels
stay short and you aren't offered the rest of the desktop. `monitor` covers the
whole focused screen. Either way the digits and the arrow keys steer without
closing the overlay: they move the screen under a `monitor` overlay, and the
window under a `window` one.

**ACTION** — what the pointer does on arrival. `move` places the pointer and
leaves it there, clicking nothing. `drag` is not implemented yet. This is the
one axis you do not have to decide up front: `;` and `:` switch it while the
overlay is on screen, which is the only moment you can actually see what you
are aiming at.

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

**`;` and `:` switch ACTION**, in either mode, at any point before you commit:

```
;   right click        the overlay turns red
:   move, no click     the overlay turns magenta
```

Both are toggles — press the same key again to go back — and both are one-offs:
after the pointer lands, the overlay returns to whatever ACTION the chord asked
for, even in a continuous lifetime. So a right click or a bare move costs one
extra keypress and neither changes what the next click does.

**SHIFT and ALT retune the overlay**, tapped on their own with nothing else
held. They flip the same axis they flip in the chords, so there is nothing new
to remember:

```
SHIFT   SCOPE   window  <->  monitor
ALT     MODE    hints   <->  grid
```

That is the whole point of the modifiers being one-axis-each: the overlay in
front of you can become the one you meant without closing it and re-chording.
Tapping either again flips back. A tap within 400ms of any other overlay key is
ignored, because releasing SHIFT is also how a chord like `:` ends
(`switch.tap_debounce_ms`).

They are the same physical key, which is the point: `;` to click differently,
`:` to not click at all. The tint is what tells you which one you are in, so
the colours follow the Omarchy theme rather than being fixed — `red` and
`magenta`, chosen because across all 22 shipped themes those are the hues least
likely to collapse into the accent the untinted overlay already uses.

The overlay is torn down and relaunched to do this, because wl-kbptr takes its
configuration at startup and cannot be reconfigured while it holds the
keyboard. You will see a flicker, and anything you had already typed is
discarded — the trade for being able to decide *after* seeing the overlay
rather than before.

### Refreshing an overlay: `F5`

An overlay is measured once, when it opens — the window's geometry, and in
`hints` mode the regions found in one frame of the framebuffer. The screen does
not hold still for that: a page scrolls, a window resizes, a dialog opens, and
the labels go on naming where things used to be. `F5` rebuilds the overlay
against the screen as it is now, keeping MODE, SCOPE and ACTION. It costs the
same flicker as `;`, and anything you had already typed is discarded.

### Swapping two windows: `Tab`

In `window` SCOPE, `Tab` swaps the window the overlay is on with another one —
and the other one is chosen the way everything else here is chosen, by naming
it. `Tab` opens a picker with one label per window on screen; pick one and the
two windows exchange places, with the overlay coming back on the window you
started from, now where the other one was.

The picker is an ordinary overlay — `--mode windows`, which you can also ask
for directly when the detector keeps missing something and a whole window is
the target you want. It is tinted, like `;` and `:` are, because it is not the
overlay you opened. Escape leaves it without swapping anything, and so does
picking the window you started from.

Escape in the picker returns you to the overlay you pressed `Tab` in, rather
than ending the run — it abandons the detour, not the session. Escape there
closes the overlay as it always has.

The picker labels what is on screen on this monitor: its active workspace, plus
the scratchpad when the scratchpad is up. Windows sitting on other workspaces
of the same monitor keep their geometry but are not on screen, so labelling
them would be labelling nothing — and drawing them over the windows you can see
is what makes a picker unreadable.

Nothing happens in `monitor` SCOPE, where the overlay is not drawn over any one
window, or when there is only one window to pick.

### Moving what is under the overlay

The digits and the arrow keys move the world underneath the overlay, which is
then rebuilt around where things ended up — so you never have to close it to go
there. What they move depends on SCOPE.

When SCOPE is `monitor`, the overlay is a whole screen, so they move the screen:

| Key | Does |
| --- | --- |
| `1` … `9` | switch to that workspace |
| `←` / `→` | previous / next workspace on this monitor |
| `↑` / `↓` | previous / next monitor, left to right, wrapping |

When SCOPE is `window`, the overlay is one window, and moving the view would be
moving away from the thing you are aiming at — so the same keys move that
window instead, exactly as they do outside the overlay:

| Key | Does | Same as |
| --- | --- | --- |
| `1` … `9` | send the window to that workspace, and follow it there | `SUPER + SHIFT + n` |
| `←` `→` `↑` `↓` | move the window within the workspace | `SUPER + arrow` |

Tiled windows move through the layout, floating ones across the screen. With no
window to move — an empty workspace — the keys do nothing.

### Keeping a popup open: `popups.keep_open` (experimental)

Opening the overlay closes a context menu or a browser extension popup, which
is often the very thing you wanted to click. That is the compositor, not the
app: a layer surface that asks for keyboard focus makes Hyprland drop the grab
the popup holds, and the client is told its popup is done.

Turn `popups.keep_open` on and the overlay asks for no keyboard focus at all.
Its keys come from compositor bindings instead — the same mechanism that
already gets `;`, `F5` and the arrows to it — relayed through a file wl-kbptr
reads, so the menu underneath keeps its focus and stays open to be aimed at.

```toml
[imthemousenow.popups]
keep_open = true
```

Experimental, and off by default. What to know before turning it on:

- It needs the wl-kbptr this plugin builds (`./install.sh` applies
  `pkg/0002-read-keys-from-a-channel-*.patch`). With a stock wl-kbptr the
  setting is ignored and nothing changes.
- Every key the overlay uses is a binding, in its own submap. Plain keys it
  does not use are swallowed rather than reaching the window underneath;
  chords are not, so `CTRL + T` still opens a tab in the browser you are
  aiming at.
- Everything else is the same overlay: same modes, same labels, same `;`, same
  Escape.

### Resizing the window: `-` `=` `_` `+`

In `window` SCOPE, the four keys Omarchy already resizes with resize the window
the overlay is drawn over, in the same directions and by the same 100px step:

| Key | Does | Same as |
| --- | --- | --- |
| `-` | expand the window left | `SUPER + -` |
| `=` | shrink the window left | `SUPER + =` |
| `_` | shrink the window up | `SUPER + _` |
| `+` | expand the window down | `SUPER + +` |

The step is `resize.step` in the config. Nothing happens in `monitor` SCOPE,
where the overlay is not drawn over any one window, or with no window to
resize. Like everything else that changes the world under the overlay, each
press costs the flicker of a rebuild and discards anything you had typed.

All of them cost the same flicker as `;`, for the same reason, and anything you
had already typed is discarded. In `monitor` SCOPE, `↑` / `↓` do nothing at all
with one monitor.

`;` reaches us rather than wl-kbptr because it is a compositor binding inside a
Hyprland submap that exists only while the overlay is up. Everywhere else, and
at every other moment, `;` is an ordinary semicolon. The submap is reset
however the overlay exits, including a crash, and `CTRL + ALT + DELETE` resets
it too. The digits and arrows live in that same submap, so they too are
ordinary keys the moment the overlay is gone.

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

### Opacity, per MODE

wl-kbptr has no opacity setting — opacity is the alpha on each colour, and each
MODE draws with different ones. `[imthemousenow.opacity]` is one number per MODE
over the top of that:

```toml
[imthemousenow.opacity]
hints = 0.6     # see more of the page through the hints
grid = 1.2      # dim harder while aiming at a grid
default = 1.0   # any MODE without a line of its own
```

1.0 is the theme's own colours; below that the overlay gets more transparent,
above it more solid, clamped at fully opaque. It scales the *backgrounds* only
— the dim over everything unselectable, and the fill behind each label or
bisect area. Labels, borders and the pointer keep the alpha the theme gave them,
so an overlay you turned right down is see-through rather than unreadable.

The arithmetic happens on whatever colours are in effect, theme included, and
arrives at wl-kbptr as per-run `-o` overrides — which is also what lets `hints`
and `windows` differ even though both draw with `[mode_floating]`. A colour you
set by hand in `config.local` is applied after, and is never scaled.

See what a MODE actually resolves to:

```bash
imthemousenow-config opacity hints    # the override lines it will pass
imthemousenow --mode hints --dry-run  # the whole wl-kbptr command
```

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
bin/imthemousenow           the four choices -> wl-kbptr flags; launches and
                            keeps up one overlay
bin/imthemousenow-steer     what the overlay's own keys run: action, scope,
                            mode, workspace, monitor, stop
bin/imthemousenow-session.sh  the state those two share, one run at a time
bin/imthemousenow-lib.sh    settings, notifications, errors
bin/imthemousenow-config    config superset -> compiled wl-kbptr config
bin/imthemousenow-regions   window rects for hints without OpenCV
bin/imthemousenow-panic     Ctrl+Alt+Delete escape hatch
config.default.toml         shipped defaults and MODEs
templates/wl-kbptr.conf.tpl Omarchy theme template -> theme colours
hypr/imthemousenow.lua      keybindings + layer rules
hooks/{theme-set,font-set,post-update}
tests/                      run them directly; no framework
pkg/{PKGBUILD,source.toml}  from-source build
pkg/*.patch                 what that build changes about wl-kbptr
install.sh / uninstall.sh
```

See [docs/design-notes.md](docs/design-notes.md) for what was verified against
this machine and where the implementation departs from the original plan, and
[docs/lessons-learned.md](docs/lessons-learned.md) for what it cost to find out
— wl-kbptr internals, Hyprland's Lua config surface, and which decisions here
are load-bearing.
