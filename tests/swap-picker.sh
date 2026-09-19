#!/bin/bash
# What does the Tab picker offer, and where can it look?
#
# Two rules, both of them about what a pick can mean. The window the swap
# started from is never a label -- swapping a window with itself is nothing
# happening, and a label that can only waste a press is worse than no label.
# And the window you want may be on another screen, so the arrows walk the
# picker from monitor to monitor the way a drop pass is walked, while the
# digits -- which could only mean a workspace -- do nothing at all.
#
# Nothing is drawn: hyprctl is stubbed with a two-monitor desk and records the
# dispatches it is asked for, so what is asserted is what the compositor would
# have been told.
#
#   ./tests/swap-picker.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

export XDG_RUNTIME_DIR="$WORK/run"

# DP-9 with two windows on it, HDMI-1 to its right with one. The focused window
# is one of DP-9's, so "the only window left on this screen" and "a window on
# the other screen" are both real cases.
setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-session.sh,-steer,-regions} "$WORK/plugin/bin/"
  printf '#!/bin/bash\n:\n' >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"

  cat >"$WORK/stub/hyprctl" <<STUB
#!/bin/bash
case "\$*" in
  *monitors*)
    echo '[{"name":"DP-9","id":0,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true,
            "activeWorkspace":{"id":1},"specialWorkspace":{"id":0}},
           {"name":"HDMI-1","id":1,"x":1920,"y":0,"width":1920,"height":1080,"scale":1,"focused":false,
            "activeWorkspace":{"id":2},"specialWorkspace":{"id":0}}]'
    ;;
  *activewindow*) echo '{"at":[0,0],"size":[960,1080],"address":"0xaaa"}' ;;
  *clients*)
    echo '[{"address":"0xaaa","monitor":0,"workspace":{"id":1},"at":[0,0],"size":[960,1080],
            "hidden":false,"mapped":true,"focusHistoryID":0},
           {"address":"0xbbb","monitor":0,"workspace":{"id":1},"at":[960,0],"size":[960,1080],
            "hidden":false,"mapped":true,"focusHistoryID":1},
           {"address":"0xccc","monitor":1,"workspace":{"id":2},"at":[1920,0],"size":[1920,1080],
            "hidden":false,"mapped":true,"focusHistoryID":2}]'
    ;;
  *binds*) echo '[]' ;;
  cursorpos*) echo "1000, 400" ;;
  dispatch*) printf '%s\n' "\${*#dispatch }" >>"$WORK/dispatch.log" ;;
  *) : ;;
esac
STUB
  chmod +x "$WORK/stub/hyprctl"
  : >"$WORK/dispatch.log"

  # A run with the picker up: the axes a swap borrows, and the window it
  # started from.
  local dir="$XDG_RUNTIME_DIR/imthemousenow"
  mkdir -p "$dir"
  echo windows >"$dir/mode"
  echo monitor >"$dir/scope"
  echo move >"$dir/action"
  echo left-click >"$dir/base-action"
  echo "0xaaa" >"$dir/swap-from"
  echo "hints window left-click" >"$dir/swap-restore"
}

steer() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow-steer" "$@" >/dev/null 2>&1
}
regions() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow-regions" "$@" 2>/dev/null
}
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

# The window the swap started from is not among the labels; the other one on
# that monitor still is.
setup
is "the picker labels every window on the screen" "$(regions --scope screen | tr '\n' ' ')" "960x1080+960+0 960x1080+0+0 "
is "the window being swapped is not offered" "$(regions --scope screen --exclude 0xaaa | tr '\n' ' ')" "960x1080+960+0 "

# An arrow walks the picker to the monitor in that direction, taking the focus
# with it -- the labels are built from the focused monitor's windows.
setup; steer arrow r
if [[ $(dispatches) == *'monitor="HDMI-1"'* ]]; then
  echo "ok    an arrow takes the picker to the next monitor"
else
  echo "FAIL  an arrow takes the picker to the next monitor -- dispatched: $(dispatches)"
  failures=$((failures + 1))
fi
is "walking the picker asks for a relaunch" \
  "$(cat "$XDG_RUNTIME_DIR/imthemousenow/switch" 2>/dev/null)" "geometry"

# No arrow may change workspace while a pick is half-made: the labels would be
# swapped out from under the choice.
if [[ $(dispatches) != *workspace* ]]; then
  echo "ok    an arrow during a pick changes no workspace"
else
  echo "FAIL  an arrow during a pick changes no workspace -- dispatched: $(dispatches)"
  failures=$((failures + 1))
fi

# The edge of the desk: nothing to the left of DP-9, so nothing happens at all.
setup; steer arrow l
is "nothing that way changes nothing" "$(dispatches)" ""
is "nothing that way asks for no relaunch" \
  "$(cat "$XDG_RUNTIME_DIR/imthemousenow/switch" 2>/dev/null)" ""

# A digit can only mean a workspace, and a workspace is not where a picker
# looks.
setup; steer digit 3
is "a digit during a pick changes nothing" "$(dispatches)" ""

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
