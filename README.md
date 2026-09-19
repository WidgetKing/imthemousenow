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
| **ACTION** | `left-click` · `right-click` · `move` · `drag` | what happens when you land (`;` `:` `'` switch it live) |
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
leaves it there, clicking nothing. `drag` asks twice — once for the thing to
pick up, once for where it goes — and only then presses, travels and releases.
This is the one axis you do not have to decide up front: `;`, `:` and `'`
switch it while the overlay is on screen, which is the only moment you can
actually see what you are aiming at.

**LIFETIME** — `single` clicks once and gets out of the way. `continuous`
reopens after every click, so a burst of clicking is one invocation; Escape
ends it. Targets are recomputed every pass, so it follows windows that move,
open or close between clicks.

## Keys

`SUPER + ;` is whatever `[imthemousenow.defaults]` says — out of the box hints,
in the window you are already looking at, one left click. Each modifier asks for
the *other* value on exactly one axis, and they compose — so you memorise one
binding plus what three modifiers mean, not eight bindings. ACTION is not among
them, because it is chosen inside the overlay instead.

| Modifier | Flips |
| --- | --- |
| `SHIFT` | SCOPE `window` ↔ `monitor` |
| `ALT` | MODE `hints` ↔ `grid` |
| `CTRL` | LIFETIME `single` ↔ `continuous` |

The flip is resolved when you press the key, not when Hyprland loads, so the
defaults you set in the Pointer widget apply to the next keypress. Change them
to grid-on-monitor and `SUPER + ;` is that, while `SUPER + ALT + ;` is still
"the other mode".

Switch ACTION inside the overlay and its name flashes up in large letters —
solid for a quarter second, then a quarter second of fade. It is the one thing
the overlay cannot show you: `;` changes what a landing does, and a colour tint
is otherwise the only hint that anything changed. Switching back to `left` is
announced too, because by then it is a choice rather than the default.

`SUPER + ;` says nothing, because a left click is what a pointer does when you
have not told it otherwise. `osd.on_start = true` names that one as well, which
is the setting to turn on while the four actions are still new; `osd.enabled =
false` turns the whole thing off. The word is set in the Omarchy font unless
`osd.font` names another.

Where it appears follows the overlay: `osd.position` (`top`, `center`,
`bottom`) is relative to the focused window in `window` scope and to the screen
in `monitor` scope, so the word is always on the thing you are aiming at.

It never eats a click: its input region is empty, so the pointer passes straight
through it, and it takes no keyboard focus.

With the shipped defaults (hints / window / single) the eight chords come out
as below; set your own defaults and the whole table moves with them.

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

**`;`, `:` and `'` switch ACTION**, in either mode, at any point before you
commit:

```
;   right click        the overlay is tinted
:   move, no click     a different tint
'   drag               a different tint again
```

The tints are not fixed hues. `left-click` is your theme's accent, and the other
four are turned off it — see [Colours](#colours).

All three are toggles — press the same key again to go back — and all three are
one-offs: after the pointer lands, the overlay returns to whatever ACTION the
chord asked for, even in a continuous lifetime. So a right click or a bare move
costs one extra keypress and neither changes what the next click does.

### Seeing through the overlay: hold `Space`

The overlay covers the thing you are aiming at. That is the whole point of it
and also its one blind spot: the usual way a selection goes wrong is a label
landing on top of the word that would have told you which target you wanted.

**Hold `Space` and the overlay fades almost away.** Let go and it comes back.
Nothing moves and nothing is selected, so the labels are exactly where they
were once you can read what is underneath them — look, let go, type the label.

```toml
[imthemousenow]
peek_alpha = 0.1   # what it fades to; 1 turns the peek off
```

This is not [per-MODE opacity](#opacity-per-mode). That one is how the overlay
looks the whole time it is up, and it scales the theme's colours so that labels
stay readable at any setting. The peek is the opposite: the *entire* surface —
dimming, labels, borders, the bisect pointer — faded at once, for as long as
the key is held, precisely so that none of it is in the way.

**Not available in the second half of a `grid` selection.** Once a grid reaches
bisect, `Space` commits the area the way `Return` does, and it keeps that job.
`hints` has no bisect in it, so the peek is there throughout; in `grid` you get
it while picking the cell and lose it once you start halving. A key that dims
sometimes and clicks other times would be worse than one that only dims where
it can.

Needs the wl-kbptr this plugin builds. On a stock build the option is not
passed through at all, and deliberately: wl-kbptr rejects an entire config file
over one option it does not recognise, so shipping this unconditionally would
not cost you the peek — it would cost you every chord. `bin/imthemousenow` asks
the installed binary whether it knows the option and stays quiet if it does
not, the same way it gates `--drag` and the popup-safe overlay.

### Dragging

`'` starts a drag, and a drag is two questions rather than one.

```
'          DRAG   aim at the thing to pick up, land on it
           DROP   the overlay comes back; aim at where it goes
                  press, travel, release
```

The first pass only moves the pointer onto what you are picking up — nothing is
pressed yet. The second pass asks the other half of the question, and only when
both ends are known does the button go down, travel to the drop point and come
back up. Nothing is ever held while you are still deciding, so `;`, `:`, `'` and
Escape all abandon a half-finished drag and leave the desktop exactly as it was.

The travel is not instant, and cannot be. A client reads drag-and-drop out of
the stream of motion events under a held button; one jump from start to finish
gives it a single event to infer everything from, and toolkits that arm on a
movement threshold, autoscroll on dwell, or animate a drop target never get the
chance. `action.drag.duration_ms` is how long the pointer takes to cross —
300ms by default. Raise it if an application keeps missing the drop.

The drop pass is drawn over the whole monitor the drag picked up on, whatever
SCOPE says: you are usually dropping onto something other than the window you
picked up from. It uses the same MODE the drag started in; set
`action.drag.drop_mode` to `grid` to always drop in the grid, which is the one
MODE that can reach a pixel no hint names — blank canvas, or the gap between
two list items.

A drop can be on another monitor. The drop overlay starts on the monitor the
drag picked up on, and the arrow keys carry it to the screen that way — `→` to
the one on the right, `↑` to the one above, by where the monitors actually are
rather than by index. Pick a target there and the pointer walks the whole path,
across the boundary, with the button held the whole way.

During a drop pass, and only there, the arrows mean monitors and nothing else,
and the digits do nothing at all:

| Key | Does, during a drop |
| --- | --- |
| `←` `→` `↑` `↓` | aim at the monitor that way |
| `1` … `9` | nothing |

Mid-drag, "left" means the screen on the left far more often than it means the
workspace before this one, and one key that might mean either leaves you unsure
which you just did — while one end of a path is already held. So the ambiguity
is removed rather than explained: no key changes workspace while a drag is
half-finished.

Drag needs the `wl-kbptr` this plugin builds (`pkg/0003-walk-a-path-*.patch`
and `pkg/0004-Say-a-drag-path-*.patch`);
with a stock one the chord says so rather than half-running.

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
`:` to not click at all. The tint is what tells you which one you are in, and
where it comes from is [below](#colours).

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

(During the drop pass of a drag all four arrows change monitor instead, by
direction, and the digits do nothing — see [Dragging](#dragging).)

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

### The bar widget

`install.sh` adds a **Pointer** widget to the Omarchy bar, beside the ones for
sound, Wi-Fi and battery, so the settings worth changing are reachable without
opening a config file at all. Click it for the panel; right-click it to fire the
chord itself.

It is an ordinary third-party shell plugin: a `manifest.json` and its QML in
`~/.config/omarchy/plugins/imthemousenow/`, which is the directory the shell
walks looking for them. `install.sh` puts them there and runs `omarchy plugin
enable`; `uninstall.sh` takes the widget off the bar before removing the files,
so you never get a gap that only hand-editing `shell.json` explains.

To manage it yourself:

```bash
omarchy plugin enable imthemousenow --section right   # put it on the bar
omarchy plugin disable imthemousenow                  # take it off
omarchy bar move imthemousenow <section>              # move it
omarchy-shell imthemousenow toggle                    # open it from a script
```

Everything in the panel goes through `imthemousenow-config`, so the widget and
the config file are the same settings seen twice. It reads the fully merged
value -- not just what is literally in your own file -- with a single
`imthemousenow-config env` when it opens, and a write lands in
`~/.config/omarchy/imthemousenow/config.toml` with your comments left alone. A
value the config program refuses is reported in the panel and the real value
comes back, rather than the panel and the file quietly disagreeing.

The panel covers the four axes of the default chord, overlay opacity, the
action word and its position and size, and the three switches. Everything else
-- the timing constants, the MODE definitions, per-MODE opacity -- is behind
**Edit config…**, which is why that button is not optional. **Check** validates
every layer in a floating terminal.

Two rows hide themselves rather than lying: **Popup-safe overlay** appears only
when the installed wl-kbptr is the one this plugin builds (the same question
`bin/imthemousenow` asks before turning it on), and the action word's position
and size appear only while the word itself is on.

The panel is fully keyboard-driven, like every other Omarchy bar panel: `j`/`k`
walk the rows, `h`/`l` move between chips or nudge a slider, Enter commits,
`e` and `c` are Edit and Check, and Escape closes.

Earlier versions put these settings in the Omarchy menu instead. A menu row can
only ever be a toggle or a pick-one-of-N — there is no text box and no slider —
so opacity was three presets pretending to be a range and every real number was
behind "Edit Config…". Upgrading removes those rows from
`~/.config/omarchy/extensions/omarchy-menu.jsonc`; only what is between the
markers goes, and `bin/imthemousenow-menu remove` is still there to do it by
hand.

### Colours

Five ACTIONs need five tints you can tell apart, and only one of them is chosen:
`left-click` is your theme's accent, because the ordinary overlay should look
like the rest of the desktop rather than announcing itself. The other four are
turned off it, 72° apart around the colour wheel — so a new theme repaints the
whole set, and no hue is ever picked by hand.

The turning happens in **OkLCh**, not HSL, and that is the part that matters. In
HSL, equal hue steps are not equal steps to an eye: at one lightness number,
yellows and cyans come out glaring while blues sink away, so a wheel divided
evenly there gives you a set where some members shout and others get missed.
OkLCh is built on a model of human vision, so holding lightness and chroma still
and moving only the hue produces colours of genuinely equal weight — which is
what a set of signal colours has to be, none louder than the rest.

Two guard rails, both measured across all 22 shipped themes rather than guessed:

- Four themes have an accent with almost no colour in it (`vantablack` and
  `white` are grey; `solitude` and `last-horizon` nearly so). Rotating the hue
  of a grey gives five greys, so the derived four get a floor of chroma even
  when the accent has less. They stay muted, and `left-click` keeps the accent
  exactly as the theme wrote it — a monochrome theme still looks monochrome
  until you switch ACTION, which is the moment you need telling.
- sRGB is not a cylinder: the chroma available at a hue collapses as lightness
  rises. Two themes (`hackerman`, `kanagawa`) have accents up at a lightness
  where no hue can hold enough chroma to separate five of them, so the derived
  four are pulled down far enough to buy it back.

The result: every shipped theme separates its five by at least 0.096 in Oklab,
where 1.0 is black to white. `tests/action-colors.sh` asserts it, so a new theme
cannot quietly break it.

To repaint everything, override the one line in your own copy of
`~/.config/omarchy/themed/wl-kbptr.conf.tpl`. To pin a single ACTION, name it in
`config.toml` — anything written by hand is left alone and only the gaps are
derived:

```toml
[imthemousenow.action.drag]
color = "#9a9af1"
```

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

For the other kind of transparency — the whole overlay, only while a key is
held — see [Seeing through the overlay](#seeing-through-the-overlay-hold-space).

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
package later). There is no mode that tracks the latest release: the patches in
`pkg/` are written against one upstream tree, so moving the pin is a change to
this repo — rebase the patches, test, bump `commit` — and never something that
happens on your machine during an update. `mode = "aur"` is there for when the
AUR catches up and you want the unpatched upstream package instead.

The patch set is part of the built version: `pkg/patch-stamp` hashes `pkg/*.patch`
into a `pN.<hash>` component, so `pacman -Q wl-kbptr-omarchy` reports which
patches a binary was built with, and `install.sh` rebuilds when that hash moves
even though the pinned commit has not. It also skips the build when the recorded
build is the one already installed, so re-running after a bash edit is cheap;
`--rebuild` forces it, and `--no-build` warns when the installed binary was
built from different patches than this checkout carries.

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
bin/imthemousenow-osd       the large word that names the ACTION you moved into
qml/osd.qml                 what draws it, through quickshell
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

## Licence

Copyright (C) 2026 Tristan Ward.

imthemousenow is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE) for the full text.

GPL rather than something permissive because `pkg/*.patch` modifies
[wl-kbptr](https://github.com/moverest/wl-kbptr), which is GPL-3.0-or-later —
so those patches are a derivative work and carry its terms regardless. The rest
of the plugin is licensed the same way to keep one licence across the tree.
The `wl-kbptr-omarchy` package built by `install.sh` ships upstream's own
LICENSE, as its PKGBUILD has always done.
