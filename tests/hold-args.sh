#!/bin/bash
# What does a hold actually emit, and what does it leave behind?
#
# A hold is one overlay and one press that stays down, and every decision that
# matters is invisible at runtime. An overlay pass that clicks turns the hold
# into a click on the thing it was about to take hold of. A press not said in
# layout coordinates cannot be steered onto another screen. A key pressed after
# the button has gone up would write into a fifo nobody reads. And the one that
# matters more than all of them: whatever happens, the button must come back up.
#
# Nothing is drawn and nothing is pressed: wl-kbptr is stubbed and records its
# own argv and everything fed to it on stdin, hyprctl is stubbed so the pointer
# and the monitors can be whatever the case under test needs.
#
#   ./tests/hold-args.sh
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

setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-locale.sh,-session.sh,-steer,-hold} "$WORK/plugin/bin/"
  # Neither the announcement nor the halo is under test here, and both would
  # put a surface on the tester's real desktop.
  for quiet in imthemousenow-osd imthemousenow-halo; do
    printf '#!/bin/bash\nsleep 30\n' >"$WORK/plugin/bin/$quiet"
    chmod +x "$WORK/plugin/bin/$quiet"
  done

  # Records its argv, and -- when it is the press rather than an overlay --
  # everything said to it, which is the half of a hold that is steered.
  cat >"$WORK/stub/wl-kbptr" <<'STUB'
#!/bin/bash
case "${1:-}" in
  --version) echo "wl-kbptr 0.4.1 (opencv)"; exit 0 ;;
esac
printf '%s\n' "$*" >>"$WL_KBPTR_LOG"
# Spelled in halves so this line is not itself the string has_hold greps the
# binary for: the capability gate looks for the option's name anywhere in the
# file, and a stub that mentions it in passing would always claim to have it.
hold_flag="--ho""ld"
for arg in "$@"; do
  if [[ $arg == "$hold_flag" ]]; then
    # The real one holds a button down and reads where to go next. This one
    # reads the same lines and writes them down, and stops on anything that is
    # not a point -- exactly where the real one lets go.
    while IFS= read -r line; do
      printf '%s\n' "$line" >>"$WL_KBPTR_STDIN_LOG"
      [[ $line =~ ^-?[0-9]+\ -?[0-9]+$ ]] || break
    done
    exit 0
  fi
done
exit 0
STUB
  chmod +x "$WORK/stub/wl-kbptr"
  # has_hold and has_drag grep the binary for the option; the stub is a script,
  # so the strings have to be in it for the real gates to pass.
  printf '# --drag --ho%s\n' "ld" >>"$WORK/stub/wl-kbptr"
  : >"$WORK/argv.log"
  : >"$WORK/stdin.log"
  export WL_KBPTR_LOG="$WORK/argv.log" WL_KBPTR_STDIN_LOG="$WORK/stdin.log"

  # Two monitors side by side, the second one starting at x=1920: the bounds a
  # hold is clamped to are the box around both, so steering right off the first
  # screen must be allowed and steering off the second must not.
  cat >"$WORK/stub/hyprctl" <<STUB
#!/bin/bash
case "\$*" in
  *monitors*) echo '[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true},{"name":"DP-2","x":1920,"y":0,"width":1920,"height":1080,"scale":1,"focused":false}]' ;;
  *activewindow*) echo '{"at":[400,250],"size":[800,600],"address":"0xabc"}' ;;
  *clients*) echo '[]' ;;
  *binds*) echo '[]' ;;
  cursorpos*) echo "500, 400" ;;
  *) : ;;
esac
STUB
  chmod +x "$WORK/stub/hyprctl"
}

# The run loop, in the background: a hold blocks until a key says to let go,
# which is what the test then does.
run_hold() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow" --action hold "$@" >/dev/null 2>&1 &
  echo $!
}

hold_key() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow-hold" "$@" >/dev/null 2>&1
}

# Waits for the press to be up, which is the only moment the fifo exists and
# the position is on file. Polled rather than slept on: how long one overlay
# pass takes is not this test's business.
await_hold() {
  local waited=0
  while ((waited < 100)); do
    # The fifo appears a moment before the press does; waiting for the press is
    # waiting for both, and it is the press the next assertions are about.
    [[ -p $XDG_RUNTIME_DIR/imthemousenow/hold-commands ]] &&
      grep -q -- '--hold' "$WORK/argv.log" && return 0
    sleep 0.05
    waited=$((waited + 1))
  done
  return 1
}

check() {
  local label="$1" got="$2" want="$3"
  if [[ $got == "$want" ]]; then
    echo "ok    $label"
  else
    echo "FAIL  $label -- wanted '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

# --- one hold, steered and let go --------------------------------------------
setup
loop_pid="$(run_hold --mode grid --scope window)"
if ! await_hold; then
  echo "FAIL  a hold puts a press up and waits to be steered"
  kill "$loop_pid" 2>/dev/null
  echo "1 failing"
  exit 1
fi
echo "ok    a hold puts a press up and waits to be steered"

# The overlay must not click: the press is the separate --hold invocation, and
# a click here would let go of the thing before it was ever steered. It ends
# in the click stage like every overlay, with nothing to press there.
overlay="$(head -1 "$WORK/argv.log")"
if [[ $overlay == *mode_click.button=none* && $overlay != *mode_click.button=left* ]]; then
  echo "ok    the overlay pass does not click"
else
  echo "FAIL  the overlay pass does not click -- got: $overlay"
  failures=$((failures + 1))
fi

# The press starts where the pointer was left, in layout coordinates, with no
# -O: an output-bound virtual pointer could never be steered off its screen.
press="$(grep -- '--hold' "$WORK/argv.log")"
if [[ $press == *"--hold 500,400"* && $press != *"-O "* ]]; then
  echo "ok    the press takes hold at the pointer, in layout coordinates"
else
  echo "FAIL  the press takes hold at the pointer, in layout coordinates -- got: $press"
  failures=$((failures + 1))
fi

# Steering. 40 is the shipped step and 200 the big one it derives -- five of
# those -- so these are the configured numbers rather than any this test
# invented.
hold_key move r
hold_key move d
hold_key move r big
check "each key moves the pointer by the configured step" \
  "$(tail -1 "$XDG_RUNTIME_DIR/imthemousenow/hold-pos")" "740 440"

# Every move reached the press as a point, and in order: this is what the
# client holding the button sees. Polled, because a point is written to the
# fifo and read out of it by another process -- there is no moment at which the
# key that sent it can know the press has finished reading it.
waited=0
while ((waited < 100)) && (($(grep -c . "$WORK/stdin.log") < 3)); do
  sleep 0.05
  waited=$((waited + 1))
done
check "every move is sent to the press, in order" \
  "$(tr '\n' '/' <"$WORK/stdin.log")" "540 400/540 440/740 440/"

# The desk is two screens wide, so right is allowed to leave the first one...
for _ in $(seq 40); do hold_key move r big; done
check "a hold can be steered onto the next monitor" \
  "$(cut -d' ' -f1 <"$XDG_RUNTIME_DIR/imthemousenow/hold-pos")" "3839"

# ...and not allowed to leave the desk. The position on file and the pointer's
# real one must not drift apart, or the next key moves from somewhere the
# pointer is not.
for _ in $(seq 5); do hold_key move d big; done
check "and not off the bottom of it" \
  "$(cut -d' ' -f2 <"$XDG_RUNTIME_DIR/imthemousenow/hold-pos")" "1079"

# Letting go. The word reaches the press, the fifo goes, and the run ends --
# a hold is one pass of a single lifetime, not a state you stay in.
hold_key release
waited=0
while ((waited < 100)) && [[ $(tail -1 "$WORK/stdin.log") != release ]]; do
  sleep 0.05
  waited=$((waited + 1))
done
check "release is what the press is told" "$(tail -1 "$WORK/stdin.log")" "release"

waited=0
while ((waited < 100)) && kill -0 "$loop_pid" 2>/dev/null; do sleep 0.05; waited=$((waited + 1)); done
if kill -0 "$loop_pid" 2>/dev/null; then
  echo "FAIL  letting go ends the run"
  kill "$loop_pid" 2>/dev/null
  failures=$((failures + 1))
else
  echo "ok    letting go ends the run"
fi

if [[ ! -e $XDG_RUNTIME_DIR/imthemousenow/hold-commands ]]; then
  echo "ok    the fifo is gone, so a later key writes into nothing"
else
  echo "FAIL  the fifo is gone, so a later key writes into nothing"
  failures=$((failures + 1))
fi

# A key pressed after the hold is over must be a no-op rather than an error or
# a write into a file that is not there.
if hold_key move r; then
  echo "ok    a key after the hold does nothing at all"
else
  echo "FAIL  a key after the hold does nothing at all -- it failed instead"
  failures=$((failures + 1))
fi

# --- killed rather than released ----------------------------------------------
# The panic key, a crashing run loop, a session ending. The press is a child of
# imthemousenow-hold and must not outlive it: a wl-kbptr left running is a
# button left down.
setup
loop_pid="$(run_hold --mode grid --scope monitor)"
if await_hold; then
  kill "$loop_pid" 2>/dev/null
  waited=0
  while ((waited < 100)) && pgrep -f "imthemousenow-hold begin" >/dev/null 2>&1; do
    sleep 0.05
    waited=$((waited + 1))
  done
  if pgrep -f "imthemousenow-hold begin" >/dev/null 2>&1; then
    echo "FAIL  killing the run lets go of the button"
    pkill -f "imthemousenow-hold begin" 2>/dev/null
    failures=$((failures + 1))
  else
    echo "ok    killing the run lets go of the button"
  fi
else
  echo "FAIL  killing the run lets go of the button -- no hold came up"
  kill "$loop_pid" 2>/dev/null
  failures=$((failures + 1))
fi

# --- a build that cannot hold --------------------------------------------------
# A stock wl-kbptr would reject --hold AFTER the overlay had been aimed, which
# is the worst moment to find out. The chord refuses up front instead.
setup
sed -i '/^# --drag --ho/d' "$WORK/stub/wl-kbptr"
PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
  /usr/bin/bash "$WORK/plugin/bin/imthemousenow" --action hold >/dev/null 2>&1
status=$?
if ((status != 0)) && [[ ! -s $WORK/argv.log ]]; then
  echo "ok    an unpatched wl-kbptr is refused before anything is aimed"
else
  echo "FAIL  an unpatched wl-kbptr is refused before anything is aimed -- exit $status"
  failures=$((failures + 1))
fi

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
