# Design notes

What was checked against this machine (Omarchy 4.0.1, opencv 5.0.0-9) and how
the implementation differs from the original plan.

## Verified

| Claim | Result |
| --- | --- |
| Omarchy theme templates | Real and first-class. `~/.config/omarchy/themed/<name>.tpl` is rendered by `omarchy-theme-set-templates` into `~/.local/state/omarchy/current/theme/<name>` on every theme change. Placeholders: `{{ key }}`, `{{ key_strip }}` (no `#`), `{{ key_rgb }}`, plus `{{ mix a b 30% }}`. |
| Hook types | `theme-set`, `font-set`, `post-update`, `battery-low`, `pre-refresh-pacman`. Drop an executable in `~/.config/omarchy/hooks/<type>.d/`. |
| Hyprland Lua module path | `package.path` includes `~/.config/?.lua`, so `require("omarchy.plugins.imthemousenow.hypr.imthemousenow")` resolves to `~/.config/omarchy/plugins/imthemousenow/hypr/imthemousenow.lua`. |
| `o.bind` / `hl.layer_rule` | Both exist; `o.bind(keys, description, command)` puts the description in the keybinding overlay. |
| Keys `SUPER + [SHIFT/ALT/CTRL +] SEMICOLON` | All four unbound in Omarchy defaults and in the user's config. |
| wl-kbptr CLI | `-r/--restrict WxH+X+Y`, `-O/--output <name>`, `-o/--option`, `-c/--config`, `-p/--only-print` all confirmed in `src/main.c`. Note it is `--only-print`, not `--print-only`. |
| Upstream commit 0854a51 | Real; makes meson accept opencv4 or opencv5. Not in any tagged release. |
| `'` (apostrophe) as a submap bind | Free, and Hyprland reports it under that keysym name -- which is why `SUBMAP_KEYS` in `bin/imthemousenow` spells it lowercase, matching what `hypr/imthemousenow.lua` registers. |
| `--drag` end to end | Built and run against the live compositor: a drag across a terminal line selects exactly that line, which is only possible if a real press, real intermediate motion and a real release all reached the client. Driven both directly and through the whole `bin/imthemousenow` two-pass path. |
| A virtual pointer with no output crosses monitors | Measured on a two-monitor desk: `zwlr_virtual_pointer_manager_v1.create_virtual_pointer` (no `_with_output`) plus `motion_absolute` against the whole layout box walks the cursor from one screen to the other and lands exactly on the target, both directions. The `_with_output` form does not: its absolute motion is mapped into that output. |
| No pointer-injection tool on this machine | `ydotool` and `wlrctl` are absent; `wtype` is present but keyboard-only; Hyprland exposes no dispatcher that presses a mouse button. Hence the patch. |

## Departures from the plan

**A Quickshell plugin, but not for the overlay.** Omarchy's plugin system
(`omarchy plugin add`) is specifically a *Quickshell* plugin loader: it clones a
git repo with a `manifest.json` into `~/.config/omarchy/plugins/<id>/` and loads
QML inside the shell process. The pointer overlay is not that, and cannot be --
it is wl-kbptr's own layer-shell window, and the parts that need privilege
(building a package) are exactly what that installer promises never to run.
So `install.sh` still does the build and the Hyprland wiring, and always will.

What *is* a shell surface is the settings: the repo ships `shell/manifest.json`
with `kinds: ["bar-widget"]`, and the panel behind it is the whole of this
plugin's configuration UI. The two halves share one directory --
`~/.config/omarchy/plugins/imthemousenow/` holds both the manifest the shell
reads and the `hypr/` module `hyprland.lua` requires by module path. Neither
knows about the other; the shell ignores a directory that is not in a manifest,
and Lua does not care what else is in there.

**Config is layered through `-o`, not merged files.** The plan had a single
generated config. Instead: `-c` points at the theme-rendered colours, then the
font, the preset's options, and finally `~/.config/omarchy/imthemousenow/config.local`
are applied as `-o` flags. Later flags win, so there is no ini-merging code and
user overrides cannot be clobbered by a re-theme.

**`cancellation_status_code=1`.** Upstream defaults it to 0, which makes a
cancelled selection indistinguishable from a successful click. The template
sets 1 so the wrapper can tell them apart.

**The font is applied at launch, not baked into the config.** Theme templates
only receive colours, and wl-kbptr re-reads its config on every invocation, so
the wrapper passes `omarchy-font-current` as `-o <mode>.label_font_family`.
The `font-set` hook is therefore a no-op that exists to document this.

**The config is a superset, by passthrough not enumeration.** `[imthemousenow]`
and `[preset.*]` are reserved; every other section is copied into the compiled
wl-kbptr config unread. This is what keeps "drives, does not reimplement" true
at the config layer: a new upstream mode or option needs no change here. The
compiler (`bin/imthemousenow-config`) is the only thing that knows both
dialects, and the wrapper asks it rather than parsing config itself.

The theme is a *layer*, not the base: shipped defaults sit under it and the
user's config over it, so re-theming cannot clobber a user's setting and a user
cannot accidentally freeze their colours. One trap worth remembering: wl-kbptr
config values start with `#` (colours), so only a *leading* `#` is a comment
when parsing that file -- treating `#` as an inline comment blanks the palette.

## The ACTION announcement

`bin/imthemousenow-osd` is a wrapper; the drawing is `qml/osd.qml`, run by
**quickshell**. That choice is a dependency argument, not a taste one:
`quickshell` is in the `omarchy` package's own `Depends On` list, so it is on
every Omarchy machine and this feature costs nothing to install. An earlier
version of this used gtk4-layer-shell, which turned out to be present here only
because ghostty pulls it in -- and ghostty is not on every client. Anything that
arrives with an application the user merely happens to have is not a dependency
this plugin can take. Quickshell owns argv, so parameters are passed as
`MOUSENOW_OSD_*` environment variables.

Two constraints shaped the QML, and both are easy to get wrong:

- **It must not take the pointer.** wl-kbptr clicks by warping a virtual
  pointer and pressing, so a surface over the target that accepted pointer
  input would swallow the click it was announcing. `mask: Region {}` is an
  empty input region: the compositor routes pointer events as though the
  surface were not there.
- **It must not take the keyboard.** Keyboard focus is exactly what dismisses
  the popup you were aiming at -- the whole subject of
  the fork's "Take keys from a channel" commit -- and it would also steal the
  keys the overlay's submap is bound to. `WlrKeyboardFocus.None`. Note that
  OmaGrid, the obvious QML reference for this, uses
  `WlrKeyboardFocus.Exclusive`: it *is* the thing being driven, where this only
  reports on it.

**`position` is relative to what the overlay covers**, not to the screen: the
focused window in window scope, the whole output in monitor scope. `osd_action`
takes the scope from its caller and passes the window's box as
`--region WxH+X+Y` -- monitor-relative, the same shape and the same arithmetic as
wl-kbptr's own `-r`. No focused window (an empty workspace) falls back to the
output, which is where the overlay went too.

The QML keeps one code path for both: the surface covers the target box and the
word is *aligned inside it*, rather than the surface being label-sized and
placed. A region becomes `anchors { left; top }` plus margins and an implicit
size, because margins are the only coordinates a layer surface has; no region
anchors all four edges. `position` then only picks the alignment, so "centred in
the thing the overlay is covering" is one rule rather than two. The inset from
the anchored edge drops from 80px to 24px inside a window, since the same 80
would read as most of the way down a small one, and `fontSizeMode:
Text.HorizontalFit` shrinks the word rather than clipping it in a narrow window.

`hypr/imthemousenow.lua` gives the `imthemousenow-osd` namespace the same
`no_anim` layer rule the overlay has, and here it matters twice over: the word
is solid for only 250ms before it starts fading, and Hyprland's own fade-in
would spend most of that quarter second arriving on top of a fade this already
does for itself.

Solid, then fading, and the split is deliberate: the word is read during the
solid part, and the fade is what says "this is telling you something, not
asking you for something". It fires once per run, not once per pass, because a
continuous lifetime relaunches the overlay after every click.

**It announces switches, not starts.** `SUPER + ;` is a left click, which is
what a pointer does unaccompanied, so naming it every time is noise; switching
is the event worth a word, and that includes switching back to left-click with a
second `;`, which by then is a decision rather than a default. `osd.on_start`
turns the start announcement on for someone still learning the four actions.

**Startup costs about 300ms**, measured (287-308ms to a mapped surface, against
370-460ms for the gtk4-layer-shell version it replaced). With the defaults at
250ms solid plus 250ms of fade, the word is on screen from roughly 0.3s to 0.8s
after the key. If that lag ever needs to go, the answer is a pre-warmed process
-- or a widget inside Omarchy's already-running quickshell instance, the way
OmaGrid does it -- rather than a faster cold start.

**The word is drawn as the wordmark is drawn.** This used to say the opposite --
that there was no logo font to borrow -- and that was true of *fonts*: the
wordmark ships as outlined SVG paths on a 15px grid
(`/usr/share/omarchy/logo.svg`) and as block-character ASCII art (`logo.txt`),
and the font actually named `omarchy` is an icon font whose only glyphs are
private-use marks (`U+E900` is the Omarchy mark; there are no letters in it).
What changed is that Omarchy grew `omarchy ascii`, which draws arbitrary text in
Delta Corps Priest 1 -- the FIGlet font the wordmark itself is set in -- and
embeds that font in the script, so it needs nothing installed. The announcement
runs the label through it and draws the block art that comes back.

The text font is therefore still fontconfig's monospace (JetBrainsMono Nerd
Font, itself an `omarchy` dependency, which `osd.font = ""` follows); it is now
setting block characters rather than letters, which is why the QML drops the
letter spacing and the Black weight when it is drawing art -- both break a grid
-- and tightens the line height to 0.82 so nine rows read as one letter instead
of nine stripes. `size` is reinterpreted too: it is a cap height for a word but
a *cell* height for art, so the art takes a quarter of it as its ceiling. At the
full 120 a nine-row block fills a 4K screen corner to corner.

**Every way of failing to draw the art ends in the plain word.** This is a look,
not a feature, and a missing announcement is a real loss where a plain one is
not. `bin/imthemousenow-osd` renders the art itself and hands the finished block
to the QML, so the QML's rule is simply "art if I was given any". It falls back
when there is no `omarchy ascii` to run, when the command fails, when what comes
back is whitespace, and -- before asking at all -- when the label is not letters
and spaces. That last one is not a failure the tool reports: Delta Corps Priest
1 has no digits or punctuation and silently drops what it cannot draw, so a
label like `2X` would come back as a perfectly good picture of `X`. A confidently
wrong announcement is worse than a plain right one. `osd.ascii = false` turns the
art off outright.

Omarchy only grew `omarchy ascii` after 4.0.0.alpha, so a machine at or before
that release does not have it. `install.sh` vendors a copy (pinned by commit and
checked by hash) into `~/.local/state/imthemousenow/bin/` for those, deletes it
again once Omarchy ships its own, and deliberately does **not** put it in
`~/.local/bin`: that directory precedes `/usr/bin` on `PATH`, so a copy there
would shadow the packaged command forever after.

## The key sheet (`F1`)

`bin/imthemousenow-help` builds the list, `qml/help.qml` draws it, the same
split and for the same reason as the ACTION announcement: quickshell is already
a dependency of the `omarchy` package, and quickshell owns argv, so the content
arrives as JSON in an environment variable.

Three decisions, each of which had an obvious-looking alternative.

**The sheet replaces the overlay; it does not cover it.** A sheet on top would
have to read its own keyboard, and in the ordinary submap wl-kbptr is holding a
grab. So `imthemousenow-steer help` asks for a relaunch exactly the way `;`
does, and the run loop shows the sheet in the gap between two passes -- a
`show_help` next to `run_once`, blocking. The overlay that comes back is the
one that went away: same MODE, SCOPE, ACTION. Nothing new had to be invented
for this; the relaunch machinery that exists for switching ACTION is the whole
implementation.

**The list is built in bash, not written in the QML.** Which keys are live
depends on the overlay that is up -- the resize keys and `Tab` are window scope
only, `grid` ends in a bisect and `hints` does not, and a drag's drop pass and
the `Tab` picker each read the digits and the arrows differently from every
other overlay. Only the
process that can read the session knows that, and a sheet that lists keys which
currently do nothing teaches the wrong thing.

**`Escape` stopped being a plain relay in popup-safe mode.** It was in
`RELAY_KEYS`: bound in the submap, appended to the channel, read by wl-kbptr.
But with the sheet up there is no wl-kbptr to cancel, and the sheet takes no
keyboard in that mode (taking it is exactly what closes the popup the mode
exists to keep open), so an `Escape` that only ever relays is a key that cannot
close what it opened. It is now its own bind, `imthemousenow-steer escape`,
which closes the sheet if one is showing and relays `Escape` if not. Both
halves of `RELAY_KEYS` -- the lua's list and the bash mirror that re-asserts
dropped binds -- had to lose it together; `tests/help-sheet.sh` asserts that
they did.

One thing measured rather than assumed: the pid the sheet is closed by must be
**quickshell's**, not the wrapper's. Signalling the wrapper left the surface on
screen with nothing holding its pid -- bash died, the sheet stayed, and the run
loop came back to an overlay underneath a panel of text. So the wrapper
backgrounds quickshell, records *that* pid, and waits on it.

### `?` was a second way in, and is not

It shipped bound to `question` and did not work: the `?` went through the
overlay and was typed into whatever was underneath. `hyprctl -j binds` showed
the bind at `modmask=0` while the key arrives with SHIFT in the mask, because
on a QWERTY keyboard the keysym only exists *because* SHIFT is held -- the same
trap as the bare `Shift_L` tap, which this file's neighbours already document.

`SHIFT + question` fixes that case, but `?` is not on SHIFT on every layout, so
covering it means a pair of binds that are each only right for some keymaps --
and in popup-safe mode the catchall deliberately passes chords through to the
window underneath, so a mask that does not match is a `?` typed into a text
field rather than a key that quietly does nothing. F1 is the help key on every
keymap there is, so `?` was dropped rather than patched. `tests/help-sheet.sh`
asserts it stays dropped.

Worth recording separately: this could not be verified with synthetic input.
`wtype` attaches a virtual keyboard with its own keymap, which both fails to
exercise the shifted bind and leaves the seat's main keyboard with
`active keymap: error` -- after which wl-kbptr refuses to start at all
(`0x26 symkey does not have a UTF-8 representation in given keymap`), and every
later test fails for that reason instead of its own. `systemctl --user restart
omarchy-fcitx5.service` repairs it. Drive the overlay through
`imthemousenow-steer <verb>` instead, which is what the binds run anyway.

## Dragging

A drag is the one ACTION that cannot be expressed as "put the pointer here and
then do a thing". It is three events across two decisions -- press at A, motion
while held, release at B -- and the second decision cannot be made until the
first one has been.

**Two passes, and nothing held between them.** The overlay comes up, you pick
the thing to drag, and the pointer moves onto it and stops. Nothing is pressed.
The overlay comes back, you pick where it goes, and only then does the button
go down, travel, and come up -- all inside one short-lived process. This is
worth stating as a rule because the obvious alternative is not: pressing at the
end of the first pass and releasing at the end of the second would leave a
button held across a window in which the user can press Escape, switch ACTION,
or have the run die on `continuous.max_quick_exits`. A held button nobody
releases is a desktop that has to be rescued, and the rescue would have to live
in `bin/imthemousenow-panic` and in the run's cleanup path and be correct in
both. Deferring the press until both ends are known deletes that whole class of
failure instead of handling it: `;`, `:`, `'` and Escape all abandon a
half-finished drag, and there is nothing to undo, because nothing happened.

**The press comes from wl-kbptr, via a patch.** `move_pointer` emits a press
and a release together, as the process exits; there was no way to ask for a
lone press, let alone motion between two of them. Four routes were weighed.
`ydotool` and `wlrctl` are not installed and `wtype` is keyboard-only. A uinput
device sidesteps Wayland and makes the landing position approximate, which is
the one thing this tool exists to get exact. A small standalone Wayland client
would work but duplicates the registry, seat, output and transform setup
wl-kbptr already carries, and adds a second compiled artifact to build,
version and uninstall. So: the fork's "Walk a path with a button held" commit
adds `--drag x1,y1,x2,y2,duration_ms`, which stops before any surface is
created and reuses everything above that point. The rebuild being automatic
(then `pkg/patch-stamp`; now the fork's tip commit, which `install.sh` checks)
is what made this the cheap option rather than the expensive one.

**The travel is not instant, and could not be.** A client reads drag-and-drop
out of the stream of motion events under a held button. One jump from A to B is
a single event to infer everything from, and a toolkit that arms on a movement
threshold, autoscrolls on dwell, or animates a drop target never gets the
chance. `action.drag.duration_ms` (300 by default) is spread over frames about
8ms apart, with a short hold at each end so that the press is not coalesced
into the first motion and the release does not land before the client has
processed where the pointer got to.

**The drop pass covers the monitor, whatever SCOPE says.** You are usually
dropping onto something other than the window you picked up from, and window
scope would put the overlay over the one place you are least likely to be
aiming. It starts on the anchor's monitor, and the session field `drop-monitor`
is what it actually follows -- not the focus, so nothing a window or the
pointer does in between can move the overlay out from under a half-finished
drag.

**A drag can cross monitors, because the path is said in layout coordinates.**
the fork's "Say a drag path in layout coordinates" commit creates the virtual
pointer WITHOUT an output. A pointer bound to an output has its absolute motion
mapped into that output and can never leave it, whatever coordinates it is
given; unbound, the same motion is mapped over the box every output sits
inside, so one device walks the whole path. One device is the point: a press on
one device followed by motion on another is a gap an application's drag session
can fall into, and there is no such gap here. Verified on a two-monitor desk --
the pointer crosses the boundary and lands exactly where it was aimed, both
directions.

**During a drop, the arrows mean monitors and the digits mean nothing.** This
is a usability rule, not a technical one. Outside a drag the digits and arrows
are read by SCOPE and move the view under the overlay -- workspace left,
workspace right, monitor up, monitor down. Mid-drag that is exactly the wrong
set of meanings: "left" is far more likely to mean the screen on the left, and
a key that might mean either leaves you unsure which of the two you just did
while one end of a path is already held. So during the drop pass the arrows
change monitor by direction (`monitor_in_direction`, decided on monitor centres
rather than index, so it holds for stacked or uneven desks), and every key that
could change a workspace -- the digits, and the `workspace` and `monitor` verbs
-- is a no-op. The focus follows the arrow, because `imthemousenow-regions`
labels windows on the focused monitor and an overlay made of another screen's
windows would label things that are not there.

**The two halves get their own colours**, which the ACTION palette makes cheap
-- see "Deriving the ACTION palette" below. Drag and drop land 72 degrees apart
on the same wheel as everything else, so they read as two distinct states rather
than one state twice, and the OSD still names which half you are in.

## Deriving the ACTION palette

Five ACTIONs need five tints an eye can separate. Picking them by hand does not
survive contact with 22 themes: an earlier version of this file chose `red` and
`magenta` by surveying which semantic colour names least often collapse into the
accent, which worked for three colours and ran out at five -- the best remaining
pair still read alike in 5 of the 22 themes. So only one colour is chosen now.

**`left-click` is the theme's accent**, because the untinted overlay is what a
pointer does when you have not said otherwise, and it should look like the rest
of the desktop. It is also the seed: the other four are turned off it, 72 degrees
apart (360/5). A theme gets a whole palette by having an accent.

**The wheel is an OkLCh wheel, not an HSL one.** This is the substantive part. In
HSL, equal hue steps are not equal steps to an eye: at a fixed lightness number,
yellows and cyans come out glaring while blues sink into the background, so a
wheel divided evenly there gives a set where some members shout and others are
missed -- which is the opposite of what signal colours are for. OkLCh is built on
a model of human vision, so holding L and C still and moving only H yields
colours of genuinely equal weight. Equal spacing in a perceptually uniform space
is also simply the documented way to build a categorical palette; there was no
need to invent a scheme.

Two guard rails, both found by measuring all 22 shipped themes rather than by
reasoning about colour in the abstract:

- **A chroma floor.** Four themes have an accent with almost no chroma
  (`vantablack` and `white` are grey, `solitude` and `last-horizon` nearly so).
  Rotating the hue of a grey produces five greys, and a palette whose entire job
  is to say whether the next keypress right-clicks or drags becomes unreadable.
  The derived four therefore get at least `CHROMA_FLOOR` even when the accent has
  less. `left-click` keeps the accent exactly, so a monochrome theme still looks
  monochrome until you switch ACTION -- which is the moment being told matters
  more than being consistent.
- **A lightness ceiling.** sRGB is not a cylinder: available chroma collapses as
  lightness rises, from roughly 0.32 at mid lightness to 0.13 for blues.
  `hackerman` and `kanagawa` have accents at L 0.88, where five hues plateaued at
  a barely-visible 0.066 separation whatever floor was asked for. Pulling the
  derived four down to `L_MAX` buys the chroma back, at the cost of their weight
  differing a little from `left-click`'s.

One chroma is shared by all five, taken from the most gamut-limited hue in the
set, rather than each hue taking its own maximum: per-hue maxima would give the
set an uneven weight, which is the thing this is avoiding.

Measured result: every shipped theme separates its five by at least 0.096 in
Oklab, where 1.0 is black to white. `tests/action-colors.sh` asserts that, and
asserts the two guard rails by the themes that need them, so a new theme or a
tweaked constant cannot quietly regress it. Anything written by hand -- in
`config.toml`, or in a user's own template -- is left alone; only gaps are
derived.

## Known gaps

- **Mouse mode** (sticky submap: `hjkl` movement, press/release for drag,
  scroll, indicator pill) is not implemented. The announcement in
  `bin/imthemousenow-osd` covers the "which action am I in" half of that pill,
  but a sticky mode needs a persistent indicator rather than a fading one. Hyprland submaps have no `o.*`
  helper in Omarchy's Lua API and no in-tree precedent, so it needs its own
  investigation. (The drag half of it is done, by a different route: see
  "Dragging" below. So is the scroll half: `SUPER + '` and `/` in the overlay
  start bin/imthemousenow-scroll, a submap of its own feeding a
  `wl-kbptr --scroll`, built the way a hold is.)
- **All-monitors mode**: upstream PR #79 was closed, not merged. The wrapper
  always passes `-O <focused monitor>`.
- **AT-SPI region source** is not implemented; `imthemousenow-regions` has a
  `--source` switch with only `windows` behind it so far.
- **A right click cannot be followed up inside a continuous lifetime.** The
  overlay is a `zwlr_layer_surface_v1` with `set_keyboard_interactivity`
  exclusive (its clicks go through `zwlr_virtual_pointer_v1`, which is why the
  click itself needs no focus). Taking keyboard focus takes it *from* the
  window under it, and Chromium, GTK and Firefox all tear a context menu down
  on focus-out; the compositor invalidates the xdg_popup grab as well. So the
  continuous loop's own relaunch kills the menu the click just opened: click,
  wl-kbptr exits, focus returns, the menu opens, the next pass grabs the
  keyboard, the menu is gone. There is no state where the overlay is up *and*
  a menu is open, so hint-clicking a menu entry is not reachable by any flag
  or layer rule -- the fix has to be to stop relaunching, e.g. pausing the
  loop after a right click and letting the menu be driven by the keyboard
  until a key asks for the overlay back. Not implemented; the pause costs a
  keypress per right click and that trade has not been accepted yet.

- **The peek is a group, not a palette**: holding `Space` fades the whole
  overlay to `general.peek_alpha`. The obvious implementation -- scale the alpha
  on every colour, the way `[imthemousenow.opacity]` does -- is wrong here, and
  for a reason worth writing down: opacity exists so a *readable* overlay can be
  more or less intrusive, which is why it deliberately leaves labels, borders
  and the bisect pointer at full alpha. The peek wants the opposite. It wants
  everything out of the way, labels included, because the labels are what is
  covering the target. So it is `cairo_push_group` around `mode_render` and one
  `cairo_paint_with_alpha`: the overlay as a single image, faded as a whole, and
  no mode has to know it happened.

  The catch is that buffers are recycled. A mode normally overwrites every pixel
  of the surface, so nobody clears it first; a group composited on top does not,
  and the previous frame shows through underneath at full strength. The clear is
  therefore part of the peek path, not an accident of it.

- **The peek gives up at bisect, deliberately**: `space` already commits an area
  there, exactly as `Return` does. The options were to move the commit key, to
  make `space` mean different things depending on how long it is held, or to let
  the peek not exist in the modes that have spoken for the key. The third is the
  only one that never surprises anyone: a key that dims sometimes and clicks
  other times is worse than one that only dims where it can. Modes say which
  they are with `takes_space` on their `mode_interface`, next to everything else
  they declare about keys, so a mode that starts using `space` cannot forget to
  mention it.

  This costs the feature in the second half of a `grid` selection and nothing in
  `hints`, which has no bisect. That asymmetry is the price and it is worth
  naming rather than hiding.

- **peek_alpha is gated on the binary, not shipped in the config**: it is an
  `[imthemousenow]` setting that `bin/imthemousenow` turns into a `-o
  general.peek_alpha=` only after grepping the installed wl-kbptr for the
  option name -- the same capability check `--drag` and the key channel use.
  The obvious alternative, putting it in the `[general]` passthrough where it
  reads more naturally, was written first and was a live footgun: wl-kbptr
  rejects the WHOLE config file over one unrecognised option and exits before
  drawing, so a stock build -- including `mode = "aur"` in pkg/source.toml,
  which is unpatched by definition -- would answer every chord by doing
  nothing at all. Caught by running the installed binary against the compiled
  config, which is the only way it shows up: the config compiles fine, the
  plugin's own `check` passes, and the failure is entirely at the far end.

- **Releases on the key channel**: the popup-safe overlay has no keyboard, so
  every key is a compositor binding appended to a file -- and a binding fires on
  press. The peek is the first thing here that needs to know a key was let go,
  so the channel grew a release: `space` is a press, `-space` is a release. The
  prefix marks the *new* case rather than both, so a compositor that only knows
  how to write presses keeps working and its existing lines are not
  reinterpreted. Only `space` is relayed twice; relaying an ordinary label on
  release as well would type it twice.

- **Where the settings live**: a bar widget, not a menu entry. The first version
  merged rows into `~/.config/omarchy/extensions/omarchy-menu.jsonc` because that
  was the only user-reachable surface a plugin could write to -- a single
  user-owned file, no drop-in directory (`shell/plugins/menu/Menu.qml` hardcodes
  two paths: its own defaults and that one). It worked, and it was the wrong
  shape: a menu row can be a toggle or a pick-one-of-N and nothing else, so
  opacity shipped as three presets pretending to be a range and every numeric
  constant stayed behind an "Edit Config" row.

  The shell's plugin registry is the surface that fits. A `manifest.json` in
  `~/.config/omarchy/plugins/<id>/` declaring `kinds: ["bar-widget"]` is
  discovered without touching a file the user owns, the widget sits beside the
  ones for sound, Wi-Fi and battery -- which is where someone looks for a
  setting they can see -- and the panel has sliders, so the settings that are
  really numbers are really sliders.

  The panel holds no opinion about what a valid value is. It reads every merged
  setting with one `imthemousenow-config env` on open and writes with `set` /
  `toggle`, which validate against the same vocabulary `check` uses. That is
  what stopped the menu rows from drifting out of step with the config, and it
  is worth keeping for the same reason: exactly one program interprets this
  config.

  Two details the first version got wrong and this one does not. Writes are
  queued one at a time -- two switches flipped in the same breath both rewrite
  `config.toml`, and the second has to read what the first wrote. And a slider
  writes on release, not on move: a drag across the track is a dozen values, and
  writing each one is a dozen rewrites to land on the one the user meant.

  `bin/imthemousenow-menu` survives, trimmed to `remove`. An install that still
  has the rows has to be cleaned up, and only what is between the markers may
  go: the rest of that file is the user's, and may be every other plugin's too.
  `tests/menu-removal.sh` is about that and nothing else.

## home_row_keys, and where right-click came from

wl-kbptr's `home_row_keys` defaults to empty, but empty does not mean "no
keys": `load_home_row()` in `src/main.c` derives them from the active keymap at
keyboard-enter time, from hard-coded keycodes — `a s d f j k l m` for the eight
bisect sub-areas, then `g`, `h`, `b` for left, right and middle click.

So per-selection right-click already existed; it was on `h` and undocumented
here. `src/mode_bisect.c` sets `state->click` from the matched index and calls
`enter_next_mode()` immediately, which is exactly the one-off semantics we
wanted: the button applies to this selection only, with no persistent state.

We set the key explicitly to `asdfjklmg;b` — upstream's own eight, with
right-click moved from `h` to `;` so it matches the key that opens the overlay.
Setting it explicitly means it no longer follows a non-QWERTY keymap the way
the derived default does; that is the trade for a predictable right-click key,
and a user with another layout can override the whole string in their config.

Two consequences worth remembering:

- The string must be **exactly 11 characters** or wl-kbptr rejects the entire
  config file, so every chord becomes a silent no-op. This cost us a debugging
  session once; `imthemousenow-config check` now tests for it, and any change
  to it must be run against the real binary, not just dry-run flag assembly.
- The click keys only exist at the **bisect** stage. At the label stage the
  keys are `label_symbols`, so `;` does nothing there.

Because the keypress *is* the click, there is no right-click state to render,
so the overlay cannot change colour to signal it. Colour-on-ACTION needs either
relaunching wl-kbptr with a different compiled config (flicker, and it discards
any typed label prefix) or owning the overlay ourselves.

## Switching ACTION from inside the overlay

wl-kbptr reads its configuration once at startup and holds a keyboard grab, so
there is no way to change the click button of a running overlay. `bisect` and
`split` do bind per-selection click keys (`g`/`h`/`b`, derived from the keymap),
but those are one keypress that clicks immediately, so nothing can indicate
which button is armed -- and `hints` has no such stage at all.

Switching ACTION is therefore a teardown and relaunch: `;` is bound inside a
Hyprland submap, and writes the new action, drops a flag file and kills
wl-kbptr; the wrapper's run loop finds the flag, treats the exit as "not a
result", and relaunches with the new button and a red tint. The flicker and the
loss of any typed prefix are accepted costs, chosen deliberately over the
alternatives (deciding before the overlay appears, or an extra keypress per
left click).

Two Hyprland details this depends on, both specific to the Lua config parser
Omarchy uses:

- `hyprctl keyword` does not work at all ("keyword can't work with non-legacy
  parsers"), so binds cannot be added at runtime that way. `hyprctl eval` and
  `hyprctl dispatch` both take Lua, and `hl`/`o` are in scope.
- The dispatch is `hyprctl dispatch 'hl.dsp.submap("name")'`; the bare
  `hyprctl dispatch submap name` form fails to parse. The key is `SEMICOLON`,
  not `;`, which is rejected as an unknown keysym.

Later, the fork learned `--overrides-file`, and `;` between left and right
click no longer relaunches. Steer writes the new ACTION's lines -- button,
double-click window, tint -- to a file in the session and sends SIGUSR1; the
fork rebuilds its config as at launch, applies the file on top, and redraws.
A signal plus a file rather than anything else because: it has to reach a
process that is already running and holding the keyboard; "launch config plus
the file" means an empty file cleanly puts the chord's own ACTION back, with
no memory of what was switched through; and a stock wl-kbptr dies on SIGUSR1,
so the flag doubles as the thing the probe looks for, and nothing is ever
signalled without it. The mode chain is read once, so it had to stop varying:
move, drag and hold used to leave the `click` stage out, and now keep it with
`mode_click.button=none`, which wl-kbptr already treats as "land and press
nothing" -- no press, no modifiers, no double-click window, no click report.
With every ACTION on one chain, every switch is config lines and none needs a
relaunch.

A submap is the right scope for this: it rebinds one key for exactly the
overlay's lifetime and lets every other key through to wl-kbptr, so `;` keeps
its ordinary meaning at all other times. The risk is a submap left active,
which would make `;` do nothing system-wide -- so it is reset from the
wrapper's EXIT/INT/TERM/HUP trap, from `--stop`, and from the panic key.

## Keeping popups open (experimental, `popups.keep_open`)

The overlay used to be unusable for the one thing people most want to aim at:
a context menu, or a browser extension popup. Opening the overlay closed them.

It is not the click, and it is not the application noticing it lost focus. It
is the compositor, and the chain was read in Hyprland 0.56.2 and then measured:

1. wl-kbptr asks for keyboard interactivity on its layer surface
   (`src/main.c`, `set_keyboard_interactivity`).
2. `src/desktop/view/LayerSurface.cpp` computes `GRABSFOCUS` on map -- true for
   `EXCLUSIVE` *and* for `ON_DEMAND`, false only for `NONE` -- and when set it
   calls `g_pSeatManager->setGrab(nullptr)`.
3. Dropping that seat grab ends the xdg-popup grab, and
   `CXDGShellProtocol::onPopupDestroy` sends `xdg_popup.popup_done` to every
   grabbed popup. The client then tears its menu down, correctly.

Measured, not assumed: a wl-kbptr built with `NONE` leaves a Brave context menu
standing under the labels, and the same build with the stock value closes it
the instant it maps. `ON_DEMAND` is not a way out; the code above treats it
exactly like `EXCLUSIVE` at map time.

So an overlay that wants popups to survive cannot take keyboard focus at all,
and then it cannot be typed at either -- which is the whole feature. The way
out is that Hyprland keybindings fire regardless of who has focus, which is
already how `;`, `F5`, `Tab` and the arrows reach us while wl-kbptr holds the
keyboard. In this mode *every* key the overlay needs is a binding:

- `hypr/imthemousenow.lua` defines a second submap, `imthemousenow-popups`,
  with the ordinary overlay binds plus one relay bind per label key, plus
  `Escape`, `BackSpace` and `Return`.
- Each relay bind appends its keysym name to `$XDG_RUNTIME_DIR/imthemousenow/keys`.
- the fork's "Take keys from a channel" commit teaches wl-kbptr to take
  `WL_KBPTR_KEY_CHANNEL`: with it set, the layer surface asks for no keyboard
  interactivity and the keys come from that file instead, through the same
  `mode_handle_key()` a real keypress goes through.

Three things this rests on, each checked on this machine rather than assumed:

- **A Lua function is a valid dispatcher** (`hl.bind(key, function() ... end)`),
  and `io` is available inside Hyprland's Lua runtime. So a keypress is a
  write from the compositor's own thread -- no process spawn per key, and no
  way for two fast keystrokes to arrive out of order, which is exactly what a
  two-character label cannot survive. `exec_cmd` per key would risk both.
- **A plain file, not a fifo.** Opening a fifo that has no reader blocks the
  opener, and the opener here is the compositor: a wedged Hyprland is a far
  worse failure than a dropped keystroke. wl-kbptr truncates the file when it
  starts (so a previous overlay's keys cannot be replayed into this one) and
  watches it with inotify.
- **`catchall` is the whole key string**, `hl.bind("catchall", ...)`, and it
  only matches with no modifiers held (`CTRL + catchall` does not parse). So
  plain keys the overlay does not use are swallowed -- verified: `/` no longer
  reaches GitHub's search box -- but chords are not: `CTRL + T` still opens a
  tab in the window underneath. That is the known hole in this mode.

Off by default, and it needs the patched wl-kbptr: `bin/imthemousenow` looks
for the environment variable's name inside the installed binary and stays on
the ordinary submap when it is not there, because relay binds with nothing
reading them would be a keyboard that does nothing at all.

## Double click, and why the first click is not held back

The gesture is "press again the key that just selected". Which key that is
falls out of the MODE without either mode knowing about it: `grid` commits on
`Space` or `Return`, `hints` on the last letter of a label, and both already
funnel through the single point in `main.c` where `has_last_mode_returned()`
goes true. That is where the window opens, so neither `mode_bisect.c` nor
`mode_floating.c` was touched, and a mode added later gets the gesture for
free by committing the way the others do.

The real decision was *when the first click goes out*, and there were only two
answers.

**Hold it back** until the window closes, then emit one click or two. Nothing
is ever swallowed, and the gap between the two clicks is ours to pick, so the
application is guaranteed to read them as a double. The price is a flat delay
in front of **every** click in the session — some 340ms — to buy the occasional
double one.

**Emit it immediately**, then click again if the key repeats. This is what
ships. The first click of a double click *is* a single click; a mouse does not
know which one it is making either, and neither does the application until the
second one arrives. So there is nothing to decide and nothing to wait for, and
double click costs a single click exactly nothing.

Two consequences follow from that choice and are worth naming, because both
are real:

- **The window has to be shorter than the desktop's double-click time**, not
  equal to it. The second click goes out when the key is pressed, not when the
  window closes, so a press at the very edge of the system's time would land
  just past it and read as two separate clicks. Hence `guard_ms`, taken off
  the number `gsettings` reports rather than baked into a constant here —
  that number is what the applications are measuring against, and it is a
  setting the desktop already owns.
- **One keystroke can be eaten.** The overlay still holds the keyboard while
  the window is open, so a key typed in that instant does not reach what was
  just clicked. It is bounded at one: any key that is not the committing one
  closes the window immediately rather than being swallowed for the rest of
  it. Clicking into a text field and typing in the same breath is the case
  where it shows, and `ms = 0` is the way out for anyone who hits it.

What is on screen during the window is not the overlay. Leaving the labels up
would hide the thing just clicked — which is also the thing being decided
about — so the surface is cleared and a ring is drawn round the selection
instead, the same three fading rings `imthemousenow-halo` puts round the
pointer during a hold. A hold and this window are the same kind of moment: the
desktop looks normal while the keyboard does not mean what it usually does,
and that ought to look the same both times.

Two things inside `wl-kbptr` had to move to make room. The **two main loops
became one** — the bare `wl_display_dispatch()` used when the keyboard was the
only event source cannot be given a deadline, and rather than keep two loops
and teach only one of them to wake up on time, the `poll()` loop the key
channel already needed now runs in both cases, with its second fd simply `-1`
when there is no channel. And **clicks are emitted by the loop**, not by the
key handler that decided on one: `move_pointer()` round-trips the display, and
a round trip from inside a dispatch is a dispatch inside a dispatch.
