# Shared by imthemousenow and imthemousenow-steer. Sourced, never run.
#
# Config lookups and the two ways this plugin talks to a human.

PLUGIN_DIR="${MOUSENOW_PLUGIN_DIR:-$HOME/.local/share/imthemousenow}"
CONFIG_CMD="$PLUGIN_DIR/bin/imthemousenow-config"
[[ -x $CONFIG_CMD ]] || CONFIG_CMD="imthemousenow-config"
OSD_CMD="$PLUGIN_DIR/bin/imthemousenow-osd"
[[ -x $OSD_CMD ]] || OSD_CMD="imthemousenow-osd"

notify() {
  [[ $(setting notify) == false ]] && return 0
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -u low "I'm the mouse now" "$1"
  else
    command -v notify-send >/dev/null 2>&1 && notify-send "I'm the mouse now" "$1"
  fi
}

# Announce an ACTION: one large word, solid then fading. Fire and forget --
# `setsid` and a detached background job, because this must not hold up the
# overlay by even a frame, and the run loop must not wait on it or inherit it.
# A missing OSD is not an error: the plugin works without it, so a system with
# no quickshell loses the announcement and nothing else.
osd_action() {
  local act="$1"
  [[ $(setting osd.enabled) == false ]] && return 0
  command -v "${OSD_CMD%% *}" >/dev/null 2>&1 || [[ -x $OSD_CMD ]] || return 0

  local label color args=()
  label="$(setting "action.${act}.label")"
  # No label configured: the action's own name is already close enough to a
  # word, and a missing entry must not mean a silent OSD.
  [[ -n $label ]] || label="${act%-click}"
  color="$(setting "action.${act}.color")"

  [[ -n $color ]] && args+=(--color "$color")
  [[ -n $(setting osd.ms) ]] && args+=(--ms "$(setting osd.ms)")
  [[ -n $(setting osd.fade_ms) ]] && args+=(--fade-ms "$(setting osd.fade_ms)")
  [[ -n $(setting osd.size) ]] && args+=(--size "$(setting osd.size)")
  [[ -n $(setting osd.position) ]] && args+=(--position "$(setting osd.position)")

  # A named family wins; otherwise follow the Omarchy font, which is the same
  # one the overlay's own labels get and what Omarchy sets its own text in.
  local font
  font="$(setting osd.font)"
  if [[ -z $font ]] && command -v omarchy-font-current >/dev/null 2>&1; then
    font="$(omarchy-font-current 2>/dev/null || true)"
  fi
  [[ -n $font ]] && args+=(--font "$font")

  setsid "$OSD_CMD" "${label^^}" "${args[@]}" >/dev/null 2>&1 &
  disown 2>/dev/null || true
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
