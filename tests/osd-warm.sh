#!/bin/bash
# Does a second word reuse a quickshell that is still alive, instead of
# starting a new one? That is the whole fix for the OSD's startup lag: a
# switch happens faster than quickshell can start, so after the very first
# word of a session every later one has to be a file write, not a process.
# See bin/imthemousenow-osd's own header for the reasoning and qml/pool.qml
# for the precedent this follows.
#
# Nothing is drawn: the stub standing in for quickshell just sits there and
# logs its own pid, so what is asserted here is process reuse and the report
# file's contents, not anything on screen.
#
#   ./tests/osd-warm.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A home and a runtime dir of this test's own -- see the other tests in this
# directory for why: every config layer hangs off HOME, and the pidfile and
# report both live under XDG_RUNTIME_DIR.
export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
failures=0

RUNDIR="$XDG_RUNTIME_DIR/imthemousenow"
REPORT="$RUNDIR/osd-report"
PIDFILE="$RUNDIR/osd.pid"
STUB_LOG="$WORK/stub.log"

# A "quickshell" that never quits on its own and never touches the QML it is
# handed -- it only has to stay alive long enough for the next check, and say
# which invocation it was.
mkdir -p "$WORK/stub"
cat >"$WORK/stub/quickshell" <<STUB
#!/bin/bash
echo "\$\$" >>"$STUB_LOG"
sleep 30
STUB
chmod +x "$WORK/stub/quickshell"

run_osd() {
  PATH="$WORK/stub:$PATH" "$REPO/bin/imthemousenow-osd" "$@" >/dev/null 2>&1
}

wait_for() {
  local file="$1" waited=0
  while [[ ! -s $file ]] && ((waited < 150)); do sleep 0.02; waited=$((waited + 1)); done
}

wait_for_lines() {
  local file="$1" n="$2" waited=0
  while (($(wc -l <"$file" 2>/dev/null || echo 0) < n)) && ((waited < 150)); do
    sleep 0.02; waited=$((waited + 1))
  done
}

wait_gone() {
  local pid="$1" waited=0
  while kill -0 "$pid" 2>/dev/null && ((waited < 150)); do sleep 0.02; waited=$((waited + 1)); done
}

# Waits for the report's stamp to move past $1, so a check right after does
# not race the write this test just asked for.
wait_for_stamp_past() {
  local prev="$1" waited=0 now
  while ((waited < 150)); do
    now="$(grep -o '"stamp":"[0-9]*"' "$REPORT" 2>/dev/null || true)"
    [[ -n $now && $now != "$prev" ]] && return 0
    sleep 0.02; waited=$((waited + 1))
  done
  return 1
}

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok    $label"
  else
    echo "FAIL  $label"
    failures=$((failures + 1))
  fi
}

# --- the first word of a session: nothing alive yet, so it has to start one --
run_osd LEFT
wait_for "$REPORT"
wait_for "$PIDFILE"
wait_for_lines "$STUB_LOG" 1
first_pid="$(cat "$PIDFILE" 2>/dev/null || true)"

check "the first word starts a quickshell" bash -c '[[ -n "$1" ]] && kill -0 "$1" 2>/dev/null' _ "$first_pid"
check "the report names the word" grep -q '"text":"LEFT"' "$REPORT"
first_stamp="$(grep -o '"stamp":"[0-9]*"' "$REPORT")"

# --- a second word, while the first quickshell is still alive -------------
run_osd RIGHT
wait_for_stamp_past "$first_stamp"
second_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
second_stamp="$(grep -o '"stamp":"[0-9]*"' "$REPORT")"

check "a live quickshell is reused rather than replaced" bash -c '[[ "$1" == "$2" ]]' _ "$first_pid" "$second_pid"
check "the report is rewritten for the new word" grep -q '"text":"RIGHT"' "$REPORT"
check "the new word gets a new stamp" bash -c '[[ "$1" != "$2" ]]' _ "$first_stamp" "$second_stamp"
check "still only one quickshell was ever started" bash -c '(($(wc -l <"$1") == 1))' _ "$STUB_LOG"

# --- a third word, once the warm one is gone -------------------------------
kill "$first_pid" 2>/dev/null || true
wait_gone "$first_pid"

run_osd MOVE
wait_for_lines "$STUB_LOG" 2

check "a new quickshell starts once the old one is gone" bash -c '(($(wc -l <"$1") == 2))' _ "$STUB_LOG"
check "the report names the third word" grep -q '"text":"MOVE"' "$REPORT"

third_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
kill "$third_pid" 2>/dev/null || true

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
