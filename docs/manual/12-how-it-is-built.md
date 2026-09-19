# How it is built

## OpenCV 5, and why wl-kbptr is built from source

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

## Repository layout

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
bin/imthemousenow-help      the key sheet F1 opens, built for the overlay that
                            is up
qml/osd.qml                 what draws the word, through quickshell
qml/help.qml                what draws the sheet, the same way
config.default.toml         shipped defaults and MODEs
templates/wl-kbptr.conf.tpl Omarchy theme template -> theme colours
hypr/imthemousenow.lua      keybindings + layer rules
hooks/{theme-set,font-set,post-update}
tests/                      run them directly; no framework
pkg/{PKGBUILD,source.toml}  from-source build
pkg/*.patch                 what that build changes about wl-kbptr
install.sh / uninstall.sh
```

See [design notes](../design-notes.md) for what was verified against
this machine and where the implementation departs from the original plan, and
[lessons learned](../lessons-learned.md) for what it cost to find out
— wl-kbptr internals, Hyprland's Lua config surface, and which decisions here
are load-bearing.

---

[← Getting unstuck](11-troubleshooting.md) · [Manual contents](README.md)
