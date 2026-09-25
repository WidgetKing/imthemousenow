# How it is built

## OpenCV 5, and why wl-kbptr is built from source

Arch ships opencv 5. wl-kbptr 0.4.1 — the tagged release, and what the AUR
still packages — does not build against it (upstream issue #99). Upstream
commit `0854a51` makes meson accept opencv 4 **or** 5, but it is not in any
release yet.

So imthemousenow builds wl-kbptr from source, with `makepkg`, which means pacman
owns the binary (`wl-kbptr-omarchy`, which `provides`/`conflicts` with
`wl-kbptr`, so it swaps cleanly with the AUR package later). `mode = "aur"` in
`pkg/source.toml` is there for when the AUR catches up and you want stock
upstream instead — without any of the features below.

## The fork

What gets built is not upstream directly but a fork,
[WidgetKing/wl-kbptr](https://github.com/WidgetKing/wl-kbptr), labelled as a
fork of [moverest/wl-kbptr](https://github.com/moverest/wl-kbptr), whose README
says so first: the program is moverest's. Its `imthemousenow` branch is
upstream's history untouched up to a pinned commit (tagged `pin/<commit>`),
with this plugin's changes committed on top — popup-safe mode, drag, hold,
peek, double click, and one crash fix. None of it is headed upstream.

`pkg/source.toml` names the fork and the branch, and `install.sh` builds the
branch's **tip**. It asks GitHub which commit that is, builds exactly that
commit, and records it; a later run rebuilds only when the tip has moved, and
skips the compile otherwise, so re-running after a bash edit is cheap.
`--rebuild` forces it. Offline, it keeps the installed build rather than
failing. `--no-build` warns when the installed binary is not the tip.

The package version carries the commit — `1:0.4.1.r<count>.g<hash>` — so
`pacman -Q wl-kbptr-omarchy` names exactly which commit of the fork is
installed.

Trusting the tip means a push to that branch is what the next install or
update everywhere builds. So the fork carries its own tests,
`imthemousenow/test.sh`, to run before pushing: it builds the branch and
checks it against what this plugin sends it — that every capability probe
finds its string, that every option and argument the wrapper builds is
accepted, and, given this checkout next to it, that the wrapper's real
`--dry-run` commands all parse. Moving the pin is a rebase in the fork, then
those tests, then a push; nothing changes in this repository.

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
locale/en.strings           the translatable strings, one file per locale;
                            installed with the plugin, so a locale only takes
                            effect once install.sh has copied (or, with --dev,
                            symlinked) it into ~/.local/share/imthemousenow/
templates/wl-kbptr.conf.tpl Omarchy theme template -> theme colours
hypr/imthemousenow.lua      entry keys (SUPER + ; and '), requires the submap
hypr/imthemousenow-submap.lua  the submap itself, layer rules, panic key
hooks/{theme-set,font-set,post-update}
tests/                      run them directly; no framework
pkg/{PKGBUILD,source.toml}  from-source build of the fork's branch
install.sh / uninstall.sh
```

See [design notes](../design-notes.md) for what was verified against
this machine and where the implementation departs from the original plan, and
[lessons learned](../lessons-learned.md) for what it cost to find out
— wl-kbptr internals, Hyprland's Lua config surface, and which decisions here
are load-bearing.

---

[← Getting unstuck](11-troubleshooting.md) · [Manual contents](README.md)
