# Design notes

What was checked against this machine (Omarchy 4.0.1, opencv 5.0.0-9) and how
the implementation differs from the original plan.

## Verified

| Claim | Result |
| --- | --- |
| Omarchy theme templates | Real and first-class. `~/.config/omarchy/themed/<name>.tpl` is rendered by `omarchy-theme-set-templates` into `~/.local/state/omarchy/current/theme/<name>` on every theme change. Placeholders: `{{ key }}`, `{{ key_strip }}` (no `#`), `{{ key_rgb }}`, plus `{{ mix a b 30% }}`. |
| Hook types | `theme-set`, `font-set`, `post-update`, `battery-low`, `pre-refresh-pacman`. Drop an executable in `~/.config/omarchy/hooks/<type>.d/`. |
| Hyprland Lua module path | `package.path` includes `~/.config/?.lua`, so `require("omarchy.plugins.kbptr.hypr.kbptr")` resolves to `~/.config/omarchy/plugins/kbptr/hypr/kbptr.lua`. |
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
font, the preset's options, and finally `~/.config/omarchy/kbptr/config.local`
are applied as `-o` flags. Later flags win, so there is no ini-merging code and
user overrides cannot be clobbered by a re-theme.

**`cancellation_status_code=1`.** Upstream defaults it to 0, which makes a
cancelled selection indistinguishable from a successful click. The template
sets 1 so the wrapper can tell them apart.

**The font is applied at launch, not baked into the config.** Theme templates
only receive colours, and wl-kbptr re-reads its config on every invocation, so
the wrapper passes `omarchy-font-current` as `-o <mode>.label_font_family`.
The `font-set` hook is therefore a no-op that exists to document this.

## Known gaps

- **Mouse mode** (sticky submap: `hjkl` movement, press/release for drag,
  scroll, indicator pill) is not implemented. Hyprland submaps have no `o.*`
  helper in Omarchy's Lua API and no in-tree precedent, so it needs its own
  investigation. Drag also needs `wlrctl` (not installed, not in the repos as a
  package on this machine) or `ydotool` (installed) with a uinput group.
- **All-monitors mode**: upstream PR #79 was closed, not merged. The wrapper
  always passes `-O <focused monitor>`.
- **AT-SPI region source** is not implemented; `omarchy-kbptr-regions` has a
  `--source` switch with only `windows` behind it so far.
- **Menu entry**: `~/.config/omarchy/extensions/omarchy-menu.jsonc` is a single
  user-owned file, so `install.sh` deliberately does not edit it. Add a Pointer
  submenu by hand if you want one.
