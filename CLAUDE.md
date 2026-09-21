# Map

A routing table, not documentation. It exists so a task opens two or three
files instead of the whole repo. Read the row, open what it names, stop.

The manual is `docs/manual/`. Why things are the way they are is
`docs/design-notes.md`; what went wrong getting there is
`docs/lessons-learned.md`. Neither is needed to make a change.

## The shape of the thing

`bin/imthemousenow` is the wrapper. Every invocation is four independent
choices -- MODE, SCOPE, ACTION, LIFETIME -- and the wrapper's whole job is to
turn those into a `wl-kbptr` command, run it, and decide what happens after it
exits. `wl-kbptr` is a patched upstream binary (`pkg/*.patch`); the patches are
what make drag, hold, peek and popup-safe mode possible at all. They are
written in a fork, not here: `../wl-kbptr`, branch `imthemousenow`, one commit
per patch, exported by `pkg/sync-patches`.

While an overlay is up, Hyprland is in a submap, and the keys bound there run
`bin/imthemousenow-steer`, which writes to the session state the wrapper's run
loop reads back. So: the wrapper owns the loop, steer owns what a key means,
and they talk through `bin/imthemousenow-session.sh`.

## Where work goes

| Task | Open |
|---|---|
| Add or change an ACTION | `config.default.toml` `[imthemousenow.action.*]` declares what it is -- `button`, `requires`, `patch`, `switchable` -- and the launcher, steer and `check` all read it. Only an action with post-selection flow of its own (drag's two passes, hold's delegation) also needs the run loop in `bin/imthemousenow`, plus its own `bin/imthemousenow-<name>`. See the warning below. |
| Add or change a MODE | `config.default.toml` `[mode.*]` alone. `chain`/`refine`/`source` is the whole interface; `resolve_mode` in `bin/imthemousenow` reads it. |
| A key pressed inside the overlay | `hypr/imthemousenow.lua` `overlay_binds()` for the bind, `bin/imthemousenow-steer` for what it does. Both, always -- a bind with no case is a dead key. |
| A key pressed outside the overlay | `hypr/imthemousenow.lua`, the chord section. Chords compose by `--flip AXIS`; they do not each hardcode a combination. |
| Config: layering, validation, compiling | `bin/imthemousenow-config` only. It is Python despite the name. Layers, later winning: `config.default.toml`, the rendered theme template, `~/.config/omarchy/imthemousenow/config.toml`. `config.local` is raw `wl-kbptr` override lines and is applied by the wrapper, not here. |
| Colours, opacity, theming | `bin/imthemousenow-config` (derivation and opacity) and `templates/wl-kbptr.conf.tpl` (what the theme renders). `hooks/theme-set` only warns; Omarchy does the rendering. |
| The patched wl-kbptr | The fork (`../wl-kbptr`, branch `imthemousenow`): commit there, run its `imthemousenow/test.sh`, then `pkg/sync-patches` here. Never edit `pkg/*.patch` by hand -- the next sync overwrites it. Every patched feature also needs a `has_*()` probe in `bin/imthemousenow`, and its contract test in the fork -- see the warning below. |
| On-screen word, halo, menus | `bin/imthemousenow-osd` + `qml/osd.qml`; `bin/imthemousenow-halo` + `qml/halo.qml`; `bin/imthemousenow-menu`. |
| The key sheet | `bin/imthemousenow-help` + `qml/help.qml`, and the `--help` heredoc in `bin/imthemousenow`. The prose lives in both, plus `docs/manual/`. Changing one means changing the others. |
| The bar widget | `shell/Panel.qml` and `shell/Model.js`. |
| Install, update, uninstall | `install.sh`, `uninstall.sh`, `hooks/post-update`. |

## Two things that will bite

**An unknown key kills every chord.** `wl-kbptr` rejects a config it does not
recognise, so one option the installed binary has never heard of takes the
whole plugin down rather than that one feature. Anything a patch adds must be
gated on a `has_*()` probe in `bin/imthemousenow` and only passed when the
probe says yes.

**ACTION is a registry, with two things left outside it.** Most of what an
action is now lives in its `[imthemousenow.action.*]` table and is read from
there. Two sites still hardcode the list and have to be edited by hand:
`overlay_binds()` in `hypr/imthemousenow.lua` (the key that switches to it --
the lua reads no config, by choice, because a config that failed to parse at
load would take every binding down with it), and `WHEEL` in
`bin/imthemousenow-config` (the order actions sit in around the colour wheel,
which is an argument about colour rather than about actions). Everything else
follows from the table.

## Checking your work

`tests/` is one script per feature, run directly (`./tests/hold-args.sh`), no
runner. Most assert against `--dry-run` output rather than a live overlay.

Every one of them exports a `HOME` of its own. That is not tidiness: all three
config layers hang off `HOME`, so without it a test reads whatever the tester
has in their own `config.toml` and whichever theme they have on, and then
passes or fails according to whose machine is running it -- as a failure that
reads like damage from whatever was last changed. A new test needs the same
line, and a fixture that wants settings of its own writes them into that `HOME`
rather than reaching for the real one.

The install is a dev install: edits to this repo are live, but Lua needs
`hyprctl reload`, the theme template needs a re-render, and `wl-kbptr` needs
`./install.sh --dev --rebuild`. Anything desktop-facing is not done until it
has been seen working on the running compositor.
