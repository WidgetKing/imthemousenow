# Shared by imthemousenow and imthemousenow-steer. Sourced, never run.
#
# Config lookups and the two ways this plugin talks to a human.

PLUGIN_DIR="${MOUSENOW_PLUGIN_DIR:-$HOME/.local/share/imthemousenow}"
CONFIG_CMD="$PLUGIN_DIR/bin/imthemousenow-config"
[[ -x $CONFIG_CMD ]] || CONFIG_CMD="imthemousenow-config"

notify() {
  [[ $(setting notify) == false ]] && return 0
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

# Every setting, once, as MOUSENOW_CFG_* variables. This used to be a process
# per lookup -- eight or so per invocation, and one more per pass of the run
# loop -- each of them re-parsing all three config layers.
# Assigned first, then evalled: `eval "$(...)"` succeeds even when the command
# substitution failed, which turns a broken config into empty settings and a
# baffling error several lines later.
_cfg_env="$("$CONFIG_CMD" env)" || die "the config did not load; try: imthemousenow-config check"
eval "$_cfg_env"
unset _cfg_env

# One setting, by its dotted name: `continuous.guard_ms`, `mode.hints.chain`,
# `action.right-click.color`. Unset reads as empty -- the shipped
# config.default.toml is where a default belongs, not here.
setting() {
  local name="MOUSENOW_CFG_${1//[.-]/_}"
  name="${name^^}"
  echo "${!name-}"
}
