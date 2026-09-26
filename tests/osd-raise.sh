#!/bin/bash
# The raise poke: what `imthemousenow-osd --raise` writes, and what it must
# never touch.
#
# What is being protected here is not the stacking itself -- that needs a
# compositor, and is checked by eye -- but the two rules the poke has to keep
# for the stacking fix to be safe at all: it must not start a quickshell that
# nobody asked for, and it must not overwrite the announcement report, because
# a word and a raise are asked for in the same instant every time an overlay
# opens in an announced ACTION.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSD="$SELF_DIR/../bin/imthemousenow-osd"

# A HOME and a runtime of its own: see CLAUDE.md. All three config layers hang
# off HOME, and the report files hang off XDG_RUNTIME_DIR.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$TMP/bin"
# A quickshell that cannot start anything. Nothing here wants a real one --
# these checks are about what the script writes and when -- and a test that
# leaves a shell process behind on the tester's desktop every run is a test
# that has to be cleaned up after by hand.
cat >"$TMP/bin/quickshell" <<'STUB'
#!/bin/bash
exec sleep 30
STUB
chmod +x "$TMP/bin/quickshell"
export PATH="$TMP/bin:$PATH"
RUNTIME="$XDG_RUNTIME_DIR/imthemousenow"

fails=0
ok()   { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if [[ $2 == "$3" ]]; then ok "$1"; else fail "$1"; printf '        want %q\n        got  %q\n' "$3" "$2"; fi; }

# --- with nothing running ----------------------------------------------------
"$OSD" --raise
check "a poke with no OSD running succeeds" "$?" "0"
[[ -e $RUNTIME/osd-raise ]] && fail "a poke with no OSD running writes nothing" \
  || ok "a poke with no OSD running writes nothing"
[[ -e $RUNTIME/osd.pid ]] && fail "a poke with no OSD running starts nothing" \
  || ok "a poke with no OSD running starts nothing"

# --- with something that looks like one --------------------------------------
# osd_alive() wants a live pid whose cmdline says osd.qml. A shell sleeping
# under that name is the cheapest thing that satisfies both.
mkdir -p "$RUNTIME"
# Not `bash -c 'sleep 30'`: bash execs a lone command in place, and the name
# this is given -- the whole point of it -- goes with the shell when it does.
bash -c 'sleep 30; :' "quickshell -p osd.qml" &
faux=$!
echo "$faux" >"$RUNTIME/osd.pid"
trap 'kill "$faux" 2>/dev/null; rm -rf "$TMP"' EXIT

# A word first, so there is something the poke could destroy.
"$OSD" WORD --ms 100 >/dev/null 2>&1
before="$(cat "$RUNTIME/osd-report")"

"$OSD" --raise
check "a poke with an OSD running succeeds" "$?" "0"
[[ -s $RUNTIME/osd-raise ]] && ok "the poke writes its own file" \
  || fail "the poke writes its own file"
check "the poke leaves the announcement report alone" "$(cat "$RUNTIME/osd-report")" "$before"

first="$(cat "$RUNTIME/osd-raise")"
"$OSD" --raise
[[ "$(cat "$RUNTIME/osd-raise")" != "$first" ]] \
  && ok "a second poke is a new stamp, so a watcher sees it" \
  || fail "a second poke is a new stamp, so a watcher sees it"

"$OSD" --raise WORD >/dev/null 2>&1
check "a poke with a word is rejected" "$?" "2"

# --- a pid file that outlived its process ------------------------------------
# The file outlives the process, and by the time it is read the number may
# belong to something else entirely -- so a poke must believe the cmdline, not
# the file.
kill "$faux" 2>/dev/null
wait "$faux" 2>/dev/null
# Reaped is not the same as gone from /proc, and this test is about what a
# poke reads there.
for _ in {1..50}; do
  [[ -e /proc/$faux ]] || break
  sleep 0.02
done
rm -f "$RUNTIME/osd-raise"
"$OSD" --raise
check "a poke with a stale pid file succeeds" "$?" "0"
[[ -e $RUNTIME/osd-raise ]] && fail "a poke with a stale pid file writes nothing" \
  || ok "a poke with a stale pid file writes nothing"

echo
if ((fails)); then
  echo "$fails failed"
  exit 1
fi
echo "all checks passed"
