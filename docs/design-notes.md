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

## Departures from the plan

**No Quickshell plugin, for now.** Omarchy's plugin system (`omarchy plugin
add`) is specifically a *Quickshell* plugin loader: it clones a git repo with a
`manifest.json` into `~/.config/omarchy/plugins/<id>/` and loads QML inside the
shell process. Its installer explicitly "never runs plugin code, install hooks,
or sudo". Since nothing here is a shell surface yet — the pointer overlay is
wl-kbptr's own layer-shell window, not a Quickshell one — a manifest would be
ceremony around an empty QML file. The parts that need privilege (building a
package) and the parts that touch config live in `install.sh` instead.

This changes when the mouse-mode indicator lands: that *is* a bar widget, and
at that point the repo gains a `manifest.json` with
`kinds: ["bar-widget"]` and becomes installable with `omarchy plugin add` as
well, with `install.sh` still doing the build and the Hyprland wiring.

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
  `pkg/0002-read-keys-from-a-channel-*.patch` -- and it would also steal the
  keys the overlay's submap is bound to. `WlrKeyboardFocus.None`. Note that
  OmaGrid, the obvious QML reference for this, uses
  `WlrKeyboardFocus.Exclusive`: it *is* the thing being driven, where this only
  reports on it.

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

**The font is the Omarchy font, not the Omarchy logo.** There is no logo font to
borrow: the wordmark ships as outlined SVG paths on a 15px grid
(`/usr/share/omarchy/logo.svg`) and as block-character ASCII art (`logo.txt`),
and the font actually named `omarchy` is an icon font whose only glyphs are
private-use marks -- `U+E900` is the Omarchy mark itself, and there are no
letters in it. Everywhere Omarchy sets text it uses fontconfig's monospace
(JetBrainsMono Nerd Font, itself an `omarchy` dependency), which is what
`osd.font = ""` follows.

## Known gaps

- **Mouse mode** (sticky submap: `hjkl` movement, press/release for drag,
  scroll, indicator pill) is not implemented. The announcement in
  `bin/imthemousenow-osd` covers the "which action am I in" half of that pill,
  but a sticky mode needs a persistent indicator rather than a fading one. Hyprland submaps have no `o.*`
  helper in Omarchy's Lua API and no in-tree precedent, so it needs its own
  investigation. Drag also needs `wlrctl` (not installed, not in the repos as a
  package on this machine) or `ydotool` (installed) with a uinput group.
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

- **Menu entry**: `~/.config/omarchy/extensions/omarchy-menu.jsonc` is a single
  user-owned file, so `install.sh` deliberately does not edit it. Add a Pointer
  submenu by hand if you want one.

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
- `pkg/0002-read-keys-from-a-channel-*.patch` teaches wl-kbptr to take
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
