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

## Known gaps

- **Mouse mode** (sticky submap: `hjkl` movement, press/release for drag,
  scroll, indicator pill) is not implemented. Hyprland submaps have no `o.*`
  helper in Omarchy's Lua API and no in-tree precedent, so it needs its own
  investigation. Drag also needs `wlrctl` (not installed, not in the repos as a
  package on this machine) or `ydotool` (installed) with a uinput group.
- **All-monitors mode**: upstream PR #79 was closed, not merged. The wrapper
  always passes `-O <focused monitor>`.
- **AT-SPI region source** is not implemented; `imthemousenow-regions` has a
  `--source` switch with only `windows` behind it so far.
- **Menu entry**: `~/.config/omarchy/extensions/omarchy-menu.jsonc` is a single
  user-owned file, so `install.sh` deliberately does not edit it. Add a Pointer
  submenu by hand if you want one.
