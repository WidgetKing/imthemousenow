#!/bin/bash
# What does a drag actually emit, and in what order?
#
# A drag is three wl-kbptr invocations -- pick up, drop, then the press-travel-
# release -- and every decision that matters is invisible at runtime. A pass
# that clicks turns the drag into a click. Coordinates that are not relative to
# the anchor's monitor land the drop somewhere plausible but wrong. An anchor
# left behind wedges the next run in a drop pass it never started. None of that
# shows on screen, so it is asserted here.
#
# Nothing is drawn and nothing is pressed: wl-kbptr is stubbed and records its
# own argv, hyprctl is stubbed so the pointer can be somewhere different on
# each pass without a human moving it.
#
#   ./tests/drag-args.sh
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

# A session directory of this test's own, so a real overlay running on the
# tester's desktop is neither read nor trampled.
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$XDG_RUNTIME_DIR"

setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-session.sh,-steer} "$WORK/plugin/bin/"
  printf '#!/bin/bash\n:\n' >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"

  # Records every invocation as one line, and reports the patched build so the
  # capability gate lets the drag through.
  cat >"$WORK/stub/wl-kbptr" <<'STUB'
#!/bin/bash
case "${1:-}" in
  --version) echo "wl-kbptr 0.4.1 (opencv)"; exit 0 ;;
esac
printf '%s\n' "$*" >>"$WL_KBPTR_LOG"
# Stand in for Escape: exit non-zero on the nth overlay, the way a cancelled
# selection does (general.cancellation_status_code).
if [[ -n ${WL_KBPTR_FAIL_ON:-} ]]; then
  n=$(grep -c . "$WL_KBPTR_LOG")
  ((n == WL_KBPTR_FAIL_ON)) && exit 1
fi
exit 0
STUB
  chmod +x "$WORK/stub/wl-kbptr"
  : >"$WORK/argv.log"
  export WL_KBPTR_LOG="$WORK/argv.log"

  # has_drag greps the binary for the option; the stub is a script, so the
  # string has to be in it for the real gate to pass.
  echo '# --drag' >>"$WORK/stub/wl-kbptr"
}

# The pointer is somewhere different on each pass, which is the whole point:
# the anchor is read after the first and the drop point after the second.
# A monitor at 100,50 is there to be ignored: the press is said in layout
# coordinates, so the numbers that reach --drag are the pointer's own, with
# nothing subtracted.
hyprctl_stub() {
  cat >"$WORK/stub/hyprctl" <<STUB
#!/bin/bash
case "\$*" in
  *monitors*) echo '[{"name":"DP-9","x":100,"y":50,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '{"at":[400,250],"size":[800,600],"address":"0xabc"}' ;;
  *clients*) echo '[]' ;;
  *binds*) echo '[]' ;;
  cursorpos*)
    n=\$(cat "$WORK/cursor.n" 2>/dev/null || echo 0)
    echo \$((n + 1)) >"$WORK/cursor.n"
    if ((n == 0)); then echo "500, 400"; else echo "1200, 900"; fi
    ;;
  *) : ;;
esac
STUB
  chmod +x "$WORK/stub/hyprctl"
  rm -f "$WORK/cursor.n"
}

run_drag() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    WL_KBPTR_FAIL_ON="${WL_KBPTR_FAIL_ON:-}" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow" --action drag "$@" >/dev/null 2>&1
}

# check <label> <expected fragment>...  -- "" negates the fragment after it.
check() {
  local label="$1"
  shift
  local out problem="" want negate=0
  out="$(cat "$WORK/argv.log" 2>/dev/null || true)"
  for want in "$@"; do
    if [[ -z $want ]]; then negate=1; continue; fi
    if ((negate)); then
      [[ $out != *"$want"* ]] || problem="${problem:+$problem; }should not have passed '$want'"
      negate=0
    else
      [[ $out == *"$want"* ]] || problem="${problem:+$problem; }missing '$want'"
    fi
  done
  if [[ -n $problem ]]; then
    echo "FAIL  $label -- $problem"
    [[ -n $out ]] && sed 's/^/        argv: /' <<<"$out"
    failures=$((failures + 1))
  else
    echo "ok    $label"
  fi
}

setup; hyprctl_stub; run_drag --mode grid --scope window

# Three invocations: two overlays and the press. Fewer means a pass was
# skipped; more means the run loop went round again when it should have stopped.
lines="$(grep -c . "$WORK/argv.log" 2>/dev/null || echo 0)"
if [[ $lines == 3 ]]; then
  echo "ok    one drag is two overlays and one press"
else
  echo "FAIL  one drag is two overlays and one press -- got $lines invocations"
  sed 's/^/        argv: /' "$WORK/argv.log"
  failures=$((failures + 1))
fi

# Neither overlay may press anything: the press is emitted afterwards, by the
# third invocation, once both ends are known. Both end in the click stage like
# every overlay does, with nothing to press there; a real button would make
# the first pass a click and the drag a no-op after it.
check "neither overlay pass clicks" "mode_click.button=none" "" "mode_click.button=left" "" "mode_click.button=right" "" "mode_click.button=middle"

# The anchor at 500,400 and the drop at 1200,900, as Hyprland reports them,
# over the configured 300ms. No -O on that invocation: an output-bound virtual
# pointer cannot leave its output, and a drop on another monitor is the whole
# point of saying the path in layout coordinates.
check "the press walks from anchor to drop in layout coordinates" \
  "--drag 500,400,1200,900,300"

presses="$(grep -- '--drag' "$WORK/argv.log" || true)"
if [[ $presses != *"-O "* ]]; then
  echo "ok    the press is not pinned to one output"
else
  echo "FAIL  the press is not pinned to one output -- got: $presses"
  failures=$((failures + 1))
fi

# The drop pass covers the monitor even though the run asked for window scope,
# so -r (which confines an overlay to a window) must appear once, not twice.
restricts="$(grep -o -- '-r [0-9x+]*' "$WORK/argv.log" | wc -l)"
if [[ $restricts == 1 ]]; then
  echo "ok    the drop pass is not confined to the window"
else
  echo "FAIL  the drop pass is not confined to the window -- $restricts passes were restricted"
  failures=$((failures + 1))
fi

# Escape during the drop pass. This is the assertion the whole design exists to
# make true: the press is emitted after both ends are known, so a drag called
# off halfway must leave NO press behind -- not a press and a release in the
# same place, not a press at the anchor. Nothing at all.
setup; hyprctl_stub
WL_KBPTR_FAIL_ON=2 run_drag --mode grid --scope window
check "a drag abandoned at the drop pass presses nothing" "" "--drag"

# A duration of the caller's choosing, to prove the number is read rather than
# hard-coded at 300 by coincidence.
setup; hyprctl_stub
mkdir -p "$WORK/plugin"
cat >>"$WORK/plugin/config.default.toml" <<'EOF'

[imthemousenow.action.drag-duration-probe]
EOF
python3 - "$WORK/plugin/config.default.toml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read().replace("duration_ms = 300", "duration_ms = 900", 1)
open(p, "w").write(s)
PY
run_drag --mode grid --scope monitor
check "the travel time comes from the config" "--drag 500,400,1200,900,900"

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
