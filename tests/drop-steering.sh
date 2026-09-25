#!/bin/bash
# What do the arrows and the digits do while a drop is half-finished?
#
# The drop pass holds one end of a path and is being aimed at the other, and
# the keys that used to move the world under the overlay are exactly the keys
# that would move what you are aiming at. So during a drop the arrows change
# monitor and nothing else, the digits do nothing at all, and which monitor
# they land on is decided by direction rather than by index.
#
# Nothing is drawn: hyprctl is stubbed with a two-monitor desk and records the
# dispatches it is asked for, so what is asserted is what the compositor would
# have been told.
#
#   ./tests/drop-steering.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A home of this test's own, so the tester's config.toml and whichever theme
# they have on are not merged in underneath the assertions below. Without it
# these pass or fail according to whose machine is running them, and the
# failure reads as damage from whatever was last changed.
export HOME="$WORK/home"
mkdir -p "$HOME"
failures=0

export XDG_RUNTIME_DIR="$WORK/run"

# DP-9 on the left, HDMI-1 to its right and a little lower, LVDS-1 stacked
# above DP-9. Three of them, because "the one that way" is only a real question
# when there is more than one answer to get wrong.
setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-locale.sh,-session.sh,-steer} "$WORK/plugin/bin/"
  printf '#!/bin/bash\n:\n' >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"

  cat >"$WORK/stub/hyprctl" <<STUB
#!/bin/bash
case "\$*" in
  *monitors*)
    echo '[{"name":"DP-9","x":0,"y":200,"width":1920,"height":1080,"scale":1,"focused":true},
           {"name":"HDMI-1","x":1920,"y":300,"width":1920,"height":1080,"scale":1,"focused":false},
           {"name":"LVDS-1","x":0,"y":-880,"width":1920,"height":1080,"scale":1,"focused":false}]'
    ;;
  *activewindow*) echo '{"at":[10,10],"size":[800,600],"address":"0xabc"}' ;;
  *clients*) echo '[]' ;;
  *binds*) echo '[]' ;;
  cursorpos*) echo "500, 400" ;;
  dispatch*) printf '%s\n' "\${*#dispatch }" >>"$WORK/dispatch.log" ;;
  *) : ;;
esac
STUB
  chmod +x "$WORK/stub/hyprctl"
  : >"$WORK/dispatch.log"

  # A run in its drop pass: the axes a real drop borrows, an anchor on DP-9,
  # and the drop aimed where the drag picked up.
  local dir="$XDG_RUNTIME_DIR/imthemousenow"
  mkdir -p "$dir"
  echo hints >"$dir/mode"
  echo monitor >"$dir/scope"
  echo drop >"$dir/action"
  echo left-click >"$dir/base-action"
  echo "DP-9 500 400" >"$dir/drag-anchor"
  echo "hints window" >"$dir/drag-restore"
  echo "DP-9" >"$dir/drop-monitor"
}

steer() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow-steer" "$@" >/dev/null 2>&1
}

drop_monitor() { cat "$XDG_RUNTIME_DIR/imthemousenow/drop-monitor" 2>/dev/null; }
dispatches() { cat "$WORK/dispatch.log" 2>/dev/null; }

is() {
  local label="$1" got="$2" want="$3"
  if [[ $got == "$want" ]]; then
    echo "ok    $label"
  else
    echo "FAIL  $label -- got '$got', wanted '$want'"
    failures=$((failures + 1))
  fi
}

# Right from DP-9 is HDMI-1, even though HDMI-1 is not level with it.
setup; steer arrow r
is "right goes to the monitor on the right" "$(drop_monitor)" "HDMI-1"

# Up from DP-9 is LVDS-1, which is the answer only if direction is read off the
# geometry: by index it is the monitor after HDMI-1, not before it.
setup; steer arrow u
is "up goes to the monitor above" "$(drop_monitor)" "LVDS-1"

# And back again, from a drop that has already been steered once.
steer arrow d
is "down comes back" "$(drop_monitor)" "DP-9"

# The edge of the desk. Nothing to the left of DP-9: the aim stays where it is
# and no relaunch is asked for, because an overlay that flickers and lands
# where it started reads as a key that half-worked.
setup; steer arrow l
is "nothing that way leaves the aim alone" "$(drop_monitor)" "DP-9"
is "nothing that way asks for no relaunch" "$(cat "$XDG_RUNTIME_DIR/imthemousenow/switch" 2>/dev/null)" ""

# The whole point: no arrow may change workspace during a drop.
setup; steer arrow r
if [[ $(dispatches) != *workspace* ]]; then
  echo "ok    an arrow during a drop changes no workspace"
else
  echo "FAIL  an arrow during a drop changes no workspace -- dispatched: $(dispatches)"
  failures=$((failures + 1))
fi

# The focus follows, because the overlay is built from the focused monitor's
# windows -- a drop overlay on one screen made of another screen's windows
# would label things that are not there.
if [[ $(dispatches) == *'monitor="HDMI-1"'* ]]; then
  echo "ok    an arrow during a drop takes the focus with it"
else
  echo "FAIL  an arrow during a drop takes the focus with it -- dispatched: $(dispatches)"
  failures=$((failures + 1))
fi

# A digit can only mean a workspace, and a workspace change under a
# half-finished drag moves what the other end is pointing at.
setup; steer digit 3
is "a digit during a drop changes nothing" "$(dispatches)" ""
is "a digit during a drop leaves the aim alone" "$(drop_monitor)" "DP-9"

# The same for the verbs the digits and steps used to reach directly.
setup; steer workspace 4; steer monitor +1
is "workspace and monitor are no-ops during a drop" "$(dispatches)" ""

# And outside a drop, none of this applies: an arrow in monitor scope is a
# workspace again.
setup
rm -f "$XDG_RUNTIME_DIR/imthemousenow/drag-anchor" "$XDG_RUNTIME_DIR/imthemousenow/drop-monitor"
echo left-click >"$XDG_RUNTIME_DIR/imthemousenow/action"
steer arrow l
if [[ $(dispatches) == *'workspace="-1"'* ]]; then
  echo "ok    outside a drop the arrows still move the view"
else
  echo "FAIL  outside a drop the arrows still move the view -- dispatched: $(dispatches)"
  failures=$((failures + 1))
fi

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
