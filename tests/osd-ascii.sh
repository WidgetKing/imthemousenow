#!/bin/bash
# When does the OSD draw the Omarchy wordmark, and when does it fall back?
#
# The art is a look, not a feature: every way of failing to produce it has to
# end in the plain word still being announced. That makes the fallbacks the
# whole point of this file -- they are the paths nobody sees until the day the
# announcement comes up blank, or comes up saying something other than the
# action it is naming.
#
# Nothing is drawn: imthemousenow-osd writes the announcement to its report file
# and only starts quickshell when nothing is alive to read one, so what is read
# back here is that file -- and a stub named quickshell on PATH keeps a real one
# from ever starting. omarchy-ascii is stubbed the same way, which is how the
# "no such command" and "renders nothing" branches are reached on a machine that
# has a good one.
#
#   ./tests/osd-ascii.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The tester's real state directory, read before HOME is moved: it is where
# install.sh puts the vendored copy, and copying the real one in makes these
# assertions about the real renderer rather than about a stub of it.
STATE_HOME="$HOME"
export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$WORK/stub" "$WORK/state/bin"
failures=0

# Stands in for the thing that would draw: it does nothing and exits, because
# these assertions are about the report the script writes before it ever looks
# for a process, not about a process. It is here so a machine with a real
# quickshell does not put a word on the tester's screen once per check.
cat >"$WORK/stub/quickshell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$WORK/stub/quickshell"

REPORT="$XDG_RUNTIME_DIR/imthemousenow/osd-report"

# The report, in the shape the old stub printed: the word, and how many rows of
# art went with it. An empty `art` is exactly what "draw the plain word" looks
# like from inside qml/osd.qml, and it stays the thing being asserted.
#
# `art` is one JSON string with the rows escaped as \n, so the row count is the
# escapes plus one -- which is what `wc -l` on the unescaped text came to.
report_fields() {
  local text art
  text="$(sed -n 's/.*"text":"\([^"]*\)".*/\1/p' "$REPORT")"
  art="$(sed -n 's/.*"art":"\(.*\)","color".*/\1/p' "$REPORT")"
  printf 'TEXT=%s\n' "$text"
  if [[ -z ${art//[[:space:]\\n]/} ]]; then
    printf 'ART_ROWS=0\n'
  else
    printf 'ART_ROWS=%s\n' "$(($(grep -o '\\n' <<<"$art" | wc -l) + 1))"
  fi
}

# The real thing, when this machine has one to copy; otherwise a stand-in that
# draws the one shape these assertions actually care about -- some rows out, and
# only for letters. The tests must not need the network.
real_ascii="$(command -v omarchy-ascii || true)"
[[ -n $real_ascii ]] || real_ascii="$STATE_HOME/.local/state/imthemousenow/bin/omarchy-ascii"
if [[ -x $real_ascii ]]; then
  cp "$real_ascii" "$WORK/state/bin/omarchy-ascii"
else
  cat >"$WORK/state/bin/omarchy-ascii" <<'STUB'
#!/bin/bash
[[ $* =~ ^[A-Za-z\ ]+$ ]] || { echo "nothing to draw" >&2; exit 1; }
for i in 1 2 3 4 5 6 7 8 9; do echo "### $* ###"; done
STUB
  chmod +x "$WORK/state/bin/omarchy-ascii"
fi

# check <label> <expected TEXT> <art|plain> [extra osd args...]
check() {
  local label="$1" want_text="$2" want_art="$3"
  shift 3
  local out problem=""
  # Gone first, so a run that bails out early is read as no announcement at all
  # rather than as the one before it.
  rm -f "$REPORT"
  out="$(PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    MOUSENOW_STATE_DIR="$STATE" "$REPO/bin/imthemousenow-osd" "$want_text" "$@" 2>&1)"
  [[ -s $REPORT ]] && out+=$'\n'"$(report_fields)"

  # Strictly: anything else in `out` is an error message, and feeding that to
  # (( )) would evaluate it as an expression rather than report it.
  local rows
  rows="$(sed -n 's/^ART_ROWS=\([0-9][0-9]*\)$/\1/p' <<<"$out" | tail -1)"
  [[ $rows =~ ^[0-9]+$ ]] || rows=-1
  [[ $out == *"TEXT=$want_text"* ]] ||
    problem="${problem:+$problem; }the plain word did not survive"
  if [[ $want_art == art ]]; then
    ((rows > 1)) || problem="${problem:+$problem; }expected art, got $rows rows"
  else
    ((rows == 0)) || problem="${problem:+$problem; }expected the plain word, got $rows rows of art"
  fi

  if [[ -n $problem ]]; then
    echo "FAIL  $label -- $problem"
    sed 's/^/        /' <<<"$out"
    failures=$((failures + 1))
  else
    echo "ok    $label"
  fi
}

# A tool where install.sh puts it, and a label the font can draw.
STATE="$WORK/state"
check "a plain word becomes art" DRAG art

# Asked for the plain word outright.
check "--no-ascii draws the word" DRAG plain --no-ascii

# The font has letters and spaces and nothing else. It does not say so -- it
# quietly draws what it can -- so "2X" would announce a confident, wrong "X".
check "a label with a digit stays a word" 2X plain
check "a label that is all digits stays a word" 42 plain
check "a label of punctuation stays a word" "..." plain
# Spaces are drawable, so a two-word label is still a wordmark.
check "spaces are drawable" "LEFT CLICK" art

# No tool at all: an Omarchy too old for `omarchy ascii`, on which install.sh
# could not reach the network either. The announcement still happens.
STATE="$WORK/empty"
check "no ascii command falls back to the word" DRAG plain

# A tool that runs and draws nothing readable. Whitespace is not an
# announcement, and this is the backstop that catches it.
STATE="$WORK/blank"
mkdir -p "$WORK/blank/bin"
printf '#!/bin/bash\nprintf "   \\n   \\n"\n' >"$WORK/blank/bin/omarchy-ascii"
chmod +x "$WORK/blank/bin/omarchy-ascii"
check "art that is all whitespace falls back" DRAG plain

# A tool that fails outright. Its exit status must not take the announcement
# down with it -- imthemousenow-osd runs under `set -e`.
STATE="$WORK/broken"
mkdir -p "$WORK/broken/bin"
printf '#!/bin/bash\nexit 3\n' >"$WORK/broken/bin/omarchy-ascii"
chmod +x "$WORK/broken/bin/omarchy-ascii"
check "a failing ascii command falls back" DRAG plain

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
