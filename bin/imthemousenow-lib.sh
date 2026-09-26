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

# Announce an ACTION: one large word, solid then fading.
#   $3  the modifiers toggled on, as the session keeps them: said in front of
#       the word ("Ctrl + Alt + right") when the ACTION holds them at all.
osd_action() {
  local act="$1" scope="${2:-}" mods="${3:-}" label
  label="$(setting "action.${act}.label")"
  # No label configured: the action's own name is already close enough to a
  # word, and a missing entry must not mean a silent OSD.
  [[ -n $label ]] || label="${act%-click}"
  [[ $(setting "action.${act}.modifiers") == true ]] && label="$(modifiers_label "$mods")$label"
  osd_word "$label" "$scope" "$(setting "action.${act}.color")"
}

# One large word on screen, solid then fading. Fire and forget -- `setsid` and
# a detached background job, because this must not hold up the overlay by even
# a frame, and the run loop must not wait on it or inherit it. A missing OSD is
# not an error: the plugin works without it, so a system with no quickshell
# loses the announcement and nothing else.
#   $1  the word
#   $2  the SCOPE, which decides where it is drawn
#   $3  its colour, or empty for the OSD's own
osd_word() {
  local label="$1" scope="${2:-}" color="${3:-}" args=()
  [[ $(setting osd.enabled) == false ]] && return 0
  command -v "${OSD_CMD%% *}" >/dev/null 2>&1 || [[ -x $OSD_CMD ]] || return 0

  [[ -n $color ]] && args+=(--color "$color")
  # Only the negative is passed: the art is the default, and the OSD falls back
  # to plain text on its own whenever it cannot draw it.
  [[ $(setting osd.ascii) == false ]] && args+=(--no-ascii)
  [[ -n $(setting osd.ms) ]] && args+=(--ms "$(setting osd.ms)")
  [[ -n $(setting osd.fade_ms) ]] && args+=(--fade-ms "$(setting osd.fade_ms)")
  [[ -n $(setting osd.size) ]] && args+=(--size "$(setting osd.size)")
  [[ -n $(setting osd.position) ]] && args+=(--position "$(setting osd.position)")
  [[ -n $(setting osd.outro) ]] && args+=(--outro "$(setting osd.outro)")

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

# --- modifiers -----------------------------------------------------------------
# The modifiers toggled on for the next press, as the session keeps them: a
# space-separated list, always in this order whatever order they were tapped
# in, so the word on screen and the flag passed are the same every time.
MODIFIER_ORDER=(ctrl alt shift super)

has_modifiers() { binary_knows --modifiers; }
# A build that reads them from a file at the press, so a toggle while the
# overlay is up needs no relaunch (and so no flicker).
has_modifiers_file() { binary_knows --modifiers-file; }

# $1 with $2 switched: added if it was off, removed if it was on. Prints the
# result in MODIFIER_ORDER, empty when nothing is left on.
modifiers_toggle() {
  local list=" $1 " name out=()
  if [[ $list == *" $2 "* ]]; then list="${list/ $2 / }"; else list="$list $2 "; fi
  for name in "${MODIFIER_ORDER[@]}"; do
    [[ $list == *" $name "* ]] && out+=("$name")
  done
  echo "${out[*]}"
}

# What goes in front of the ACTION's word: "Ctrl + Alt + ", or nothing.
modifiers_label() {
  local name out=""
  for name in $1; do
    case "$name" in
      ctrl) out+="$(t modifiers.ctrl 'Ctrl + ')" ;;
      alt) out+="$(t modifiers.alt 'Alt + ')" ;;
      shift) out+="$(t modifiers.shift 'Shift + ')" ;;
      super) out+="$(t modifiers.super 'Super + ')" ;;
    esac
  done
  echo "$out"
}

# wl-kbptr's spelling of the same list: --modifiers ctrl,alt.
modifiers_arg() {
  local list="$1"
  echo "${list// /,}"
}

# Milliseconds as the seconds `sleep` takes, without a process to divide.
# Anything that is not a whole number is 0.
ms_to_s() {
  local ms="$1"
  [[ $ms =~ ^[0-9]+$ ]] || ms=0
  ms=$((10#$ms))
  printf '%d.%03d\n' $((ms / 1000)) $((ms % 1000))
}

die() {
  echo "${0##*/}: $1" >&2
  exit 1
}

# --- localisation ---------------------------------------------------------
# Its own file; see its header for why. Sourced here so that every script
# which already sources this one keeps t() without knowing that changed.
# shellcheck source=imthemousenow-locale.sh
source "$(dirname "${BASH_SOURCE[0]}")/imthemousenow-locale.sh"


# Every setting, once, as MOUSENOW_CFG_* variables. This used to be a process
# per lookup -- eight or so per invocation, and one more per pass of the run
# loop -- each of them re-parsing all three config layers.
# Assigned first, then evalled: `eval "$(...)"` succeeds even when the command
# substitution failed, which turns a broken config into empty settings and a
# baffling error several lines later.
#
# And kept, in the runtime directory, until one of the layers it was made from
# changes: every script sources this, imthemousenow-steer on every overlay key,
# and a Python start is most of what one of those costs. The first line is a
# key -- which HOME and plugin, and which layers were there -- because tests
# run with a HOME of their own against the same runtime directory, and a layer
# that is deleted has no mtime left to be newer than the cache.
_cfg_cache="${XDG_RUNTIME_DIR:-/tmp}/imthemousenow/env.sh"
_cfg_layers=(
  "$PLUGIN_DIR/config.default.toml"
  "$HOME/.local/state/omarchy/current/theme/wl-kbptr.conf"
  "$HOME/.config/omarchy/imthemousenow/config.toml"
  "$PLUGIN_DIR/bin/imthemousenow-config"
)
_cfg_key="# $HOME|$PLUGIN_DIR|"
for _cfg_layer in "${_cfg_layers[@]}"; do
  [[ -e $_cfg_layer ]] && _cfg_key+=1 || _cfg_key+=0
done
_cfg_fresh() {
  local first layer
  [[ -f $_cfg_cache ]] || return 1
  IFS= read -r first <"$_cfg_cache" || return 1
  [[ $first == "$_cfg_key" ]] || return 1
  for layer in "${_cfg_layers[@]}"; do
    [[ $layer -nt $_cfg_cache ]] && return 1
  done
  return 0
}
if _cfg_fresh; then
  source "$_cfg_cache"
  # The compiled file lives beside the cache but can be cleaned up without it.
  [[ -z $MOUSENOW_COMPILED || -f $MOUSENOW_COMPILED ]] ||
    MOUSENOW_COMPILED="$("$CONFIG_CMD" compile 2>/dev/null || true)"
else
  _cfg_env="$("$CONFIG_CMD" env)" || die "the config did not load; try: imthemousenow-config check"
  eval "$_cfg_env"
  if mkdir -p "${_cfg_cache%/*}" 2>/dev/null; then
    printf '%s\n%s\n' "$_cfg_key" "$_cfg_env" >"$_cfg_cache.$$" 2>/dev/null &&
      mv -f "$_cfg_cache.$$" "$_cfg_cache" 2>/dev/null || rm -f "$_cfg_cache.$$"
  fi
  unset _cfg_env
fi
unset _cfg_layer _cfg_layers _cfg_key
unset -f _cfg_fresh

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

has_double_click() { binary_knows double_click_ms; }
has_double_click_handoff() { binary_knows --double-click-handoff; }

# How long the second press has to land, in ms, or 0 for "do not arm it".
#
# `system` follows the desktop's own double-click time, because that is the
# number the application being clicked is measuring against -- one setting, in
# the place the desktop already keeps it, rather than a number here to be kept
# in sync with one there. The guard comes off it because the second click goes
# out when the key is pressed and not when the window closes: a press at the
# very edge of the system's time would land just past it and read as two
# separate clicks rather than one double one.
#
# Anything gsettings cannot answer -- not installed, schema absent, a value
# that is not a number -- turns the feature off rather than refusing to open an
# overlay. It is a nicety, and a chord that does nothing would be worse than a
# chord that cannot be double clicked.
#
# Asked once per run and remembered: gsettings is a process, and build_args
# runs again for every ACTION a switch moves through.
#
# Remembered in the calling shell only if it is resolved there: a `$(...)`
# around it is a subshell, and the answer dies with it. So double_click_resolve
# sets the cache without printing, and the callers that can call it directly
# do, before anything reads it through a substitution.
double_click_cache=""
double_click_window() {
  double_click_resolve
  echo "$double_click_cache"
}
double_click_resolve() {
  [[ -n $double_click_cache ]] && return 0

  local want system guard
  want="$(setting double_click.ms)"
  [[ -n $want ]] || want=system

  if [[ $want == system ]]; then
    system="$(gsettings get org.gnome.desktop.peripherals.mouse double-click 2>/dev/null || true)"
    [[ $system =~ ^[0-9]+$ ]] || system=0
    guard="$(setting double_click.guard_ms)"
    [[ $guard =~ ^[0-9]+$ ]] || guard=0
    ((system > guard)) && want=$((system - guard)) || want=0
  elif [[ ! $want =~ ^[0-9]+$ ]]; then
    want=0
  fi

  double_click_cache="$want"
}

# Whether a double click is on the table for this ACTION right now: it has a
# button to press twice, it wants the window, the window is not 0, and the
# binary knows what to do with it. Asked by the launcher, to decide what to
# pass, and by the key sheet, to decide whether to say so.
#
# In a continuous lifetime only with a build that can hand the window on to
# the next overlay (--double-click-handoff). The window is the overlay staying
# up after the click, and without the handoff the next overlay cannot open
# until it closes -- every pass would start ~340 ms late. With it, the
# overlay that clicked goes at once and the next one keeps the window, while
# its intro plays. The caller's `lifetime` if it has one (the run loop's is
# the pass being built), else the session's (steer, switching in place).
double_click_armed() {
  local lt="${lifetime:-}"
  [[ -n $lt ]] || ! declare -F session_get >/dev/null || lt="$(session_get lifetime)"
  [[ $lt == continuous ]] && ! has_double_click_handoff && return 1
  [[ -n $(setting "action.$1.button") ]] || return 1
  [[ $(setting "action.$1.double_click") == true ]] || return 1
  double_click_resolve
  ((double_click_cache > 0)) || return 1
  has_double_click
}

# A build that takes config lines from a file each time it is sent SIGUSR1, so
# a switch of ACTION needs no relaunch (and so no flicker).
# Without this flag SIGUSR1 kills wl-kbptr, so nothing sends it unasked.
has_overrides_file() { binary_knows --overrides-file; }

# The config lines that make an overlay ACTION $1 rather than any other, when
# the chord's own ACTION is $2 (and $3 is `live` for a switch in place): the
# button, the double-click window, and the tint. One list, printed a line each, read by both the launcher (as -o) and
# steer (as the overrides file), so a relaunch and a switch in place cannot
# come to look different.
action_overrides() {
  local act="$1" base="$2" button tint
  button="$(setting "action.$act.button")"
  # Every overlay ends in the click stage, and an ACTION that presses nothing
  # there -- move, both halves of a drag, hold -- says `none`: the pointer
  # lands and nothing is pressed, held or reported. One mode chain for all of
  # them is what lets `;` `:` `'` `"` switch between any two in place.
  echo "mode_click.button=${button:-none}"
  if [[ -n $button ]]; then
    # An option the binary has never heard of takes the whole config down, so
    # the window is only said when armed -- except for a switch in place
    # ($3 = live), which lands on a config that may already have one open
    # for left click, and has to turn it off rather than leave it out.
    if double_click_armed "$act"; then
      echo "mode_click.double_click_ms=$double_click_cache"
    elif [[ ${3:-} == live ]] && has_double_click; then
      echo "mode_click.double_click_ms=0"
    fi
  fi

  # A different ACTION must look different, or you cannot tell which overlay
  # you are in.
  if [[ $act != "$base" ]]; then
    tint="$(setting "action.${act}.color")"
    if [[ -n $tint ]]; then
      echo "mode_tile.label_select_color=${tint}ff"
      echo "mode_tile.selectable_border_color=${tint}aa"
      echo "mode_floating.label_select_color=${tint}ff"
      echo "mode_floating.selectable_border_color=${tint}ee"
      echo "mode_bisect.pointer_color=${tint}dd"
    fi
  fi
}

# Whether `;` `:` `'` `"` can move from one ACTION to another by signalling
# the overlay that is up rather than relaunching it. Every ACTION now shares
# the mode chain and differs only in config lines, so this is only a question
# of whether the build can take them.
action_swappable_in_place() { has_overrides_file; }

# The click mark (bin/imthemousenow-pool). wl-kbptr has to say where each click
# went for there to be anything to mark, and quickshell has to be there to
# draw it. When either is missing the mark falls back to wl-kbptr's own ring.
has_click_report() { binary_knows WL_KBPTR_CLICK_REPORT; }
pool_armed() {
  [[ $(setting pool.enabled) != false ]] || return 1
  command -v quickshell >/dev/null 2>&1 || return 1
  has_click_report
}

# How long a mark lasts: the double-click window, so it is gone at the moment
# a second press would stop counting. A right click marks for the same time
# though it has no window of its own, and with double click turned off
# altogether the mark still needs a length.
pool_ms() {
  local ms
  ms="$(double_click_window)"
  ((ms > 0)) || ms=400
  echo "$ms"
}

# The colours the pooled crystal flips into. The theme's own, rendered into
# [imthemousenow.pool] by the theme template; with theme_colors off, the
# ACTION wheel, which is the nearest thing to a set of colours the config has.
pool_colors() {
  local colors action
  colors="$(setting pool.colors)"
  if [[ -z $colors ]]; then
    for action in left-click right-click move drag drop; do
      colors+="$(setting "action.$action.color") "
    done
  fi
  echo "$colors" | xargs
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
# registry rather than the message, so an action that moves to another commit
# does not leave the wrong name behind in two scripts.
action_requirement() {
  local patch
  patch="$(setting "action.$1.patch")"
  echo "--action $1 needs the wl-kbptr built by install.sh (${patch:-see pkg/source.toml})"
}
