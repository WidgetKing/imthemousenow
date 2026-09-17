#!/bin/bash
# Remove everything install.sh created. Leaves user overrides in
# ~/.config/omarchy/kbptr/ alone unless --purge is given.
set -euo pipefail

PLUGIN_DIR="$HOME/.local/share/omarchy-kbptr"
BIN_DIR="$HOME/.local/bin"
USER_DIR="$HOME/.config/omarchy/kbptr"
STATE_DIR="$HOME/.local/state/omarchy-kbptr"
HYPR_ENTRY="$HOME/.config/hypr/hyprland.lua"
REQUIRE_LINE='require("omarchy.plugins.kbptr.hypr.kbptr")'

purge=0
[[ ${1:-} == --purge ]] && purge=1

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

say "Removing plugin files"
rm -rf "$PLUGIN_DIR" "$HOME/.config/omarchy/plugins/kbptr"
rm -f "$BIN_DIR/omarchy-kbptr" "$BIN_DIR/omarchy-kbptr-regions" "$BIN_DIR/omarchy-kbptr-panic"
rm -f "$HOME/.config/omarchy/themed/wl-kbptr.conf.tpl"
rm -f "$HOME/.local/state/omarchy/current/theme/wl-kbptr.conf"
rm -f "$HOME/.config/omarchy/hooks"/{theme-set,font-set,post-update}.d/kbptr.hook

if grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY" 2>/dev/null; then
  say "Removing the Hyprland include"
  cp "$HYPR_ENTRY" "$HYPR_ENTRY.bak.$(date +%s)"
  sed -i "/omarchy-kbptr (managed by install.sh/d;\|$REQUIRE_LINE|d" "$HYPR_ENTRY"
  hyprctl reload >/dev/null 2>&1 || true
fi

# Only remove the package if this plugin is the thing that built it.
if [[ -f "$STATE_DIR/installed" ]] && pacman -Qq wl-kbptr-omarchy >/dev/null 2>&1; then
  say "Removing the wl-kbptr package this plugin built"
  sudo pacman -Rns --noconfirm wl-kbptr-omarchy
fi

rm -rf "$STATE_DIR"
((purge)) && { say "Removing user overrides"; rm -rf "$USER_DIR"; }

say "Done."
