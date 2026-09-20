# Shared by imthemousenow and imthemousenow-steer. Sourced, never run.
#
# Config lookups and the two ways this plugin talks to a human.

PLUGIN_DIR="${MOUSENOW_PLUGIN_DIR:-$HOME/.local/share/imthemousenow}"
CONFIG_CMD="$PLUGIN_DIR/bin/imthemousenow-config"
[[ -x $CONFIG_CMD ]] || CONFIG_CMD="imthemousenow-config"
OSD_CMD="$PLUGIN_DIR/bin/imthemousenow-osd"
[[ -x $OSD_CMD ]] || OSD_CMD="imthemousenow-osd"

# name, x, y, width, height of the focused monitor, tab separated. Logical
# pixels, not physical: everything that places a surface -- wl-kbptr's -r, a
# layer surface's margins -- is in the scaled coordinate space Hyprland reports
# windows in. Lives here rather than in the wrapper because the ACTION
# announcement needs it too, from whichever process is doing the announcing.
_MONITOR_FIELDS='[.name, .x, .y, (.width / .scale | floor), (.height / .scale | floor)] | @tsv'

focused_monitor() {
  hyprctl -j monitors | jq -r ".[] | select(.focused) | $_MONITOR_FIELDS"
}

# The same five fields for a monitor named outright, for the times the answer
# must not be "whichever one has the focus now": a drag's drop pass follows the
# monitor it is aimed at, and the focus can have moved since.
monitor_by_name() {
  hyprctl -j monitors | jq -r --arg n "$1" ".[] | select(.name == \$n) | $_MONITOR_FIELDS"
}

# The monitor that lies in direction $2 (l|r|u|d) from the monitor named $1,
# as its name, or nothing when there is none that way. Used by the drop pass of
# a drag, where the arrows move between screens rather than workspaces.
#
# Direction is decided on monitor centres, which is the only thing that holds
# for monitors of different sizes, stacked or side by side. Among the ones that
# lie that way, the winner is the nearest along the direction, with distance
# across it counting four times as much: of two screens equally far to the
# right, the one level with this one is the one "right" means, and a screen far
# off the axis is not to the right of anything.
monitor_in_direction() {
  hyprctl -j monitors | jq -r --arg from "$1" --arg dir "$2" '
    map({ name, cx: (.x + .width / .scale / 2), cy: (.y + .height / .scale / 2) })
    | . as $all
    | ($all[] | select(.name == $from)) as $here
    | [ $all[]
        | select(.name != $from)
        | . + { along: (
            if $dir == "l" then $here.cx - .cx
            elif $dir == "r" then .cx - $here.cx
            elif $dir == "u" then $here.cy - .cy
            else .cy - $here.cy end),
            across: (
            if $dir == "l" or $dir == "r" then (.cy - $here.cy | fabs)
            else (.cx - $here.cx | fabs) end) }
        | select(.along > 0)
      ]
    | sort_by(.along + 4 * .across)
    | .[0].name // ""
  '
}

# Where the pointer is now, as `x y` in the same logical pixels the monitor
# helpers above report. hyprctl prints it as `x, y`; nothing else should have
# to know that.
pointer_position() {
  hyprctl cursorpos | tr -d ','
}

# The rendered theme's surface colours, as `background foreground`, six hex
# digits each with a leading `#`. The theme template writes wl-kbptr's colours
# with two alpha digits on the end; the help sheet paints its own alpha, so the
# pairing that comes back here is the flat one.
#
# mode_floating is the section to read, not mode_tile: its labels sit on top of
# whatever is on screen, so the template already made that background near
# opaque and that pairing readable against itself -- which is exactly what a
# panel of text needs. A theme that has not been rendered falls back to
# Catppuccin Mocha, which is Omarchy's own default.
THEME_CONF="$HOME/.local/state/omarchy/current/theme/wl-kbptr.conf"

theme_surface_colors() {
  local bg="" fg=""
  if [[ -f $THEME_CONF ]]; then
    # Only within [mode_floating]: the same key names appear in every section.
    read -r bg fg < <(awk -F= '
      /^\[/ { in_section = ($0 ~ /^\[mode_floating\]/) }
      in_section && $1 == "unselectable_bg_color" { bg = $2 }
      in_section && $1 == "label_color" { fg = $2 }
      END { print bg, fg }
    ' "$THEME_CONF")
  fi
  # Strip the alpha the template appends, and refuse anything that is not a
  # colour -- a malformed value would reach QML and paint the sheet black.
  [[ $bg =~ ^#[0-9a-fA-F]{6} ]] && bg="${BASH_REMATCH[0]}" || bg="#1e1e2e"
  [[ $fg =~ ^#[0-9a-fA-F]{6} ]] && fg="${BASH_REMATCH[0]}" || fg="#cdd6f4"
  echo "$bg $fg"
}

# The key sheet, which is one process at a time and is owned by whoever opened
# it. The pid file is written by imthemousenow-help and removed when it exits,
# but a pid file can still name a recycled pid, so the process is checked to be
# one of ours before it is signalled -- the same guard the OSD uses.
help_pid() {
  local pid
  pid="$(cat "${XDG_RUNTIME_DIR:-/tmp}/imthemousenow/help.pid" 2>/dev/null || true)"
  [[ $pid =~ ^[0-9]+$ ]] || return 1
  grep -qa "help.qml" "/proc/$pid/cmdline" 2>/dev/null ||
    grep -qa "imthemousenow-help" "/proc/$pid/cmdline" 2>/dev/null || return 1
  echo "$pid"
}

# True when a sheet is on screen. `help` is a toggle, and this is what tells it
# which way it is toggling.
help_showing() {
  help_pid >/dev/null
}

# Take the sheet down. The run loop is blocked on that process, so this is also
# what puts the overlay back: imthemousenow-help returning is the signal.
help_stop() {
  local pid
  pid="$(help_pid)" || return 0
  kill "$pid" 2>/dev/null || true
}

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
  local act="$1" scope="${2:-}"
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

  # In window scope the word belongs to the window, not to the screen: an
  # overlay confined to one window that announces itself in the middle of the
  # monitor is pointing somewhere the overlay is not. Monitor scope keeps the
  # screen, which is where its overlay is.
  if [[ $scope == window ]]; then
    local mon_name mon_x mon_y mon_w mon_h win
    IFS=$'\t' read -r mon_name mon_x mon_y mon_w mon_h < <(focused_monitor)
    win="$(hyprctl -j activewindow)"
    if [[ -n $mon_name && $(jq -r '.at // "null"' <<<"$win") != null ]]; then
      local wx wy ww wh
      read -r wx wy ww wh < <(jq -r '[.at[0], .at[1], .size[0], .size[1]] | @tsv' <<<"$win")
      # Monitor-relative, because that is the coordinate space a layer surface's
      # margins live in. Same shape as wl-kbptr's -r, and computed the same way.
      args+=(--output "$mon_name")
      args+=(--region "${ww}x${wh}+$((wx - mon_x))+$((wy - mon_y))")
    fi
    # No focused window (an empty workspace) falls through to the monitor, which
    # is where the overlay went too.
  fi

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

# Whether the installed wl-kbptr is one of ours, asked by looking for a string
# that is in the build this plugin's install.sh makes and not in a stock one.
#
# It has to be asked this way. None of what the patches add is a flag or a
# version upstream would report -- `--drag` and `--hold` are arguments a stock
# build rejects, the key channel is an environment variable it would ignore,
# and `peek_alpha` is a config key it has never heard of -- so the only thing
# that can answer is the binary itself.
#
# The cost of guessing wrong is not the same in each case but is never small:
# a rejected argument comes back AFTER the overlay has been aimed, an ignored
# environment variable hands over a keyboard nothing is listening to, and an
# unknown config key makes wl-kbptr reject the WHOLE file and draw nothing at
# all -- which would turn every chord into a silent no-op on a stock build.
binary_knows() {
  local binary
  binary="$(command -v wl-kbptr)" || return 1
  grep -qa -- "$1" "$binary"
}

# Whether this build can do what an ACTION needs of it. An action that names no
# `requires` works on any build, which is most of them.
action_supported() {
  local needs
  needs="$(setting "action.$1.requires")"
  [[ -n $needs ]] || return 0
  binary_knows "$needs"
}

# Why it cannot, in the one sentence a person gets. The patch comes from the
# registry rather than the message, so an action that moves to another patch
# does not leave the wrong filename behind in two scripts.
action_requirement() {
  local patch
  patch="$(setting "action.$1.patch")"
  echo "--action $1 needs the wl-kbptr built by install.sh (${patch:-see pkg/})"
}
