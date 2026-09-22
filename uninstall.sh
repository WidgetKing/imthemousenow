#!/bin/bash
# Remove everything install.sh created. Leaves user overrides in
# ~/.config/omarchy/imthemousenow/ alone unless --purge is given.
set -euo pipefail

PLUGIN_DIR="$HOME/.local/share/imthemousenow"
BIN_DIR="$HOME/.local/bin"
USER_DIR="$HOME/.config/omarchy/imthemousenow"
STATE_DIR="$HOME/.local/state/imthemousenow"
HYPR_ENTRY="$HOME/.config/hypr/hyprland.lua"
REQUIRE_LINE='require("omarchy.plugins.imthemousenow.hypr.imthemousenow")'

purge=0
[[ ${1:-} == --purge ]] && purge=1

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# Take the bar widget off the bar before its files go. A widget id left in
# shell.json after the plugin directory is gone is a gap on the bar that only
# hand-editing that file explains.
if command -v omarchy >/dev/null 2>&1 && grep -q '"imthemousenow"' "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
  say "Removing the Pointer widget from the bar"
  omarchy plugin disable imthemousenow >/dev/null 2>&1 || true
fi

# Versions before the bar widget merged rows into the user's Omarchy menu file.
# Anyone upgrading past that has had them removed already, but going straight
# from one of those to no plugin at all has not. Only what is between our
# markers: the rest of that file is the user's, and may be every other
# plugin's too.
if [[ -x "$PLUGIN_DIR/bin/imthemousenow-menu" ]]; then
  "$PLUGIN_DIR/bin/imthemousenow-menu" remove || true
fi

say "Removing plugin files"
rm -rf "$PLUGIN_DIR" "$HOME/.config/omarchy/plugins/imthemousenow"
rm -f "$BIN_DIR/imthemousenow" "$BIN_DIR/imthemousenow-steer" "$BIN_DIR/imthemousenow-regions" "$BIN_DIR/imthemousenow-panic" "$BIN_DIR/imthemousenow-config" "$BIN_DIR/imthemousenow-osd" "$BIN_DIR/imthemousenow-help" \
  "$BIN_DIR/imthemousenow-hold" "$BIN_DIR/imthemousenow-halo" "$BIN_DIR/imthemousenow-pool" "$BIN_DIR/imthemousenow-menu" "$BIN_DIR/imthemousenow-scroll"
rm -f "$HOME/.config/omarchy/themed/wl-kbptr.conf.tpl"
rm -f "$HOME/.local/state/omarchy/current/theme/wl-kbptr.conf"
rm -f "$HOME/.config/omarchy/hooks"/{theme-set,font-set,post-update}.d/imthemousenow.hook


if grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY" 2>/dev/null; then
  say "Removing the Hyprland include"
  cp "$HYPR_ENTRY" "$HYPR_ENTRY.bak.$(date +%s)"
  sed -i "/imthemousenow (managed by install.sh/d;\|$REQUIRE_LINE|d" "$HYPR_ENTRY"
  hyprctl reload >/dev/null 2>&1 || true
fi

# Only remove the package if this plugin is the thing that built it.
if [[ -f "$STATE_DIR/installed" ]] && pacman -Qq wl-kbptr-omarchy >/dev/null 2>&1; then
  say "Removing the wl-kbptr package this plugin built"
  sudo pacman -Rns --noconfirm wl-kbptr-omarchy
fi

rm -rf "$STATE_DIR" "${XDG_RUNTIME_DIR:-/tmp}/imthemousenow"
((purge)) && { say "Removing user overrides"; rm -rf "$USER_DIR"; }

say "Done."
