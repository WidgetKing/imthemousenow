# omarchy-kbptr

Keyboard-driven mouse pointer for [Omarchy](https://omarchy.org), wrapping
[wl-kbptr](https://github.com/moverest/wl-kbptr). It drives wl-kbptr; it does
not reimplement it, so new upstream options pass straight through `-o`.

What the plugin adds on top of the binary:

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

```bash
omarchy-kbptr --list                      # every preset
omarchy-kbptr quick --scope active-window # restrict to the focused window
omarchy-kbptr move                        # move the pointer, don't click
```

## Configuration

User files override the plugin, and survive reinstalls:

```
~/.config/omarchy/kbptr/presets.toml   # replaces the shipped presets entirely
~/.config/omarchy/kbptr/config.local   # one `section.key=value` per line, applied last
~/.config/omarchy/themed/wl-kbptr.conf.tpl   # the colour template itself
```

`config.local` uses wl-kbptr's own `-o` syntax, so anything the binary accepts
works without this plugin knowing about it:

```
general.home_row_keys=arstgmneio
mode_tile.label_symbols=arstgmneio
mode_click.button=left
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

The fix is a **build** fix. One reporter on #99 says floating/detect mode still
dims the screen without drawing labels under OpenCV 5 — the plugin is built so
this degrades cleanly: only `detect` depends on OpenCV, and it refuses to run
(with a notification) rather than dimming your screen, on a build that lacks
OpenCV support. `--lite` makes that configuration explicit.

## Layout

```
bin/omarchy-kbptr           preset -> wl-kbptr flags; the whole CLI
bin/omarchy-kbptr-regions   window rects for floating/stdin mode
presets.toml                shipped presets
templates/wl-kbptr.conf.tpl Omarchy theme template -> theme colours
hypr/kbptr.lua              keybindings + layer rules
hooks/{theme-set,font-set,post-update}
pkg/{PKGBUILD,source.toml}  from-source build
install.sh / uninstall.sh
```

See [docs/design-notes.md](docs/design-notes.md) for what was verified against
this machine and where the implementation departs from the original plan.
