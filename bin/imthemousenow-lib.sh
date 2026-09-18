# Shared by imthemousenow and imthemousenow-steer. Sourced, never run.
#
# Config lookups and the two ways this plugin talks to a human.

PLUGIN_DIR="${MOUSENOW_PLUGIN_DIR:-$HOME/.local/share/imthemousenow}"
CONFIG_CMD="$PLUGIN_DIR/bin/imthemousenow-config"
[[ -x $CONFIG_CMD ]] || CONFIG_CMD="imthemousenow-config"

notify() {
  [[ $("$CONFIG_CMD" get notify 2>/dev/null || echo true) == false ]] && return 0
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -u low "I'm the mouse now" "$1"
  else
    command -v notify-send >/dev/null 2>&1 && notify-send "I'm the mouse now" "$1"
  fi
}

die() {
  echo "${0##*/}: $1" >&2
  exit 1
}

# One [imthemousenow] setting, or $2 when it is unset.
setting() {
  local value
  value="$("$CONFIG_CMD" get "$1" 2>/dev/null || true)"
  echo "${value:-$2}"
}
