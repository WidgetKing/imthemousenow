#!/bin/bash
# What does a scroll emit, and what does it leave behind?
#
# SUPER + ' must turn the wheel where the pointer already is, and `/` must put
# the pointer somewhere first and then turn it there -- and neither may click.
# Escape must leave nothing held and nothing
# listening.
#
# wl-kbptr is stubbed and records its argv and everything fed to it on stdin;
# hyprctl is stubbed; the mark is never drawn.
#
#   ./tests/scroll-args.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A home of this test's own: see tests/hold-args.sh.
export HOME="$WORK/home"
mkdir -p "$HOME"
export XDG_RUNTIME_DIR="$WORK/run"
failures=0

setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/plugin/qml" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-session.sh,-steer,-scroll} "$WORK/plugin/bin/"
  # No qml/scroll.qml in the copy, so no mark is put on the tester's desktop.
  printf '#!/bin/bash\nsleep 30\n' >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"

  cat >"$WORK/stub/wl-kbptr" <<'STUB'
#!/bin/bash
case "${1:-}" in
  --version) echo "wl-kbptr 0.4.1 (opencv)"; exit 0 ;;
esac
printf '%s\n' "$*" >>"$WL_KBPTR_LOG"
# In halves, so the stub does not claim the option by mentioning it.
flag="--scr""oll"
for arg in "$@"; do
  if [[ $arg == "$flag" ]]; then
    while IFS= read -r line; do
      printf '%s\n' "$line" >>"$WL_KBPTR_STDIN_LOG"
      [[ $line =~ ^(up|down|left|right|mods.*)$ ]] || break
    done
    exit 0
  fi
done
exit 0
STUB
  printf '# --drag --hold --modifiers --scr%s\n' "oll" >>"$WORK/stub/wl-kbptr"
  chmod +x "$WORK/stub/wl-kbptr"
  : >"$WORK/argv.log"
  : >"$WORK/stdin.log"
  export WL_KBPTR_LOG="$WORK/argv.log" WL_KBPTR_STDIN_LOG="$WORK/stdin.log"

  cat >"$WORK/stub/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  *monitors*) echo '[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '{"at":[400,250],"size":[800,600],"address":"0xabc"}' ;;
  *clients*) echo '[]' ;;
  *binds*) echo '[]' ;;
  cursorpos*) echo "500, 400" ;;
  *) : ;;
esac
STUB
  chmod +x "$WORK/stub/hyprctl"
  # Neither the mark nor quickshell: a scroll without one must still work.
  PATH="$WORK/stub:/usr/bin:/bin"
  export PATH
}

scroll() {
  MOUSENOW_PLUGIN_DIR="$WORK/plugin" /usr/bin/bash "$WORK/plugin/bin/imthemousenow-scroll" "$@" >/dev/null 2>&1
}

await_scroll() {
  local waited=0
  while ((waited < 100)); do
    [[ -p $XDG_RUNTIME_DIR/imthemousenow/scroll-commands ]] &&
      grep -q -- '--scroll' "$WORK/argv.log" && return 0
    sleep 0.05
    waited=$((waited + 1))
  done
  return 1
}

await_lines() {
  local waited=0
  while ((waited < 100)) && (($(grep -c . "$WORK/stdin.log") < $1)); do
    sleep 0.05
    waited=$((waited + 1))
  done
}

await_exit() {
  local waited=0
  while ((waited < 100)) && kill -0 "$1" 2>/dev/null; do
    sleep 0.05
    waited=$((waited + 1))
  done
  ! kill -0 "$1" 2>/dev/null
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

# --- SUPER + ': here, no overlay ---------------------------------------------
setup
scroll begin &
pid=$!
if ! await_scroll; then
  echo "FAIL  SUPER + ' starts a scroll"
  kill "$pid" 2>/dev/null
  exit 1
fi
check "SUPER + ' scrolls where the pointer is, with no overlay" \
  "$(cat "$WORK/argv.log")" "--scroll here"

scroll down
scroll right
scroll up
scroll left
await_lines 4
check "each notch reaches the wheel, in order" \
  "$(tr '\n' '/' <"$WORK/stdin.log")" "down/right/up/left/"

# A held key keeps turning the wheel until it comes up, and then stops.
: >"$WORK/stdin.log"
scroll down
sleep 0.6
scroll release
sleep 0.2
held="$(grep -c . "$WORK/stdin.log")"
sleep 0.4
after="$(grep -c . "$WORK/stdin.log")"
if ((held > 5 && after == held)); then echo "ok    a held key repeats until it is released ($held notches)"; else
  echo "FAIL  a held key repeats until it is released -- $held notches, then $after"; failures=$((failures + 1))
fi

scroll stop
if await_exit "$pid"; then echo "ok    Escape ends it"; else
  echo "FAIL  Escape ends it"; failures=$((failures + 1)); kill "$pid" 2>/dev/null
fi
leftover="$(ls "$XDG_RUNTIME_DIR/imthemousenow" 2>/dev/null | grep scroll)"
check "and leaves nothing behind" "$leftover" ""

# --- `/`: the overlay picks the spot -------------------------------------------
setup
MOUSENOW_PLUGIN_DIR="$WORK/plugin" /usr/bin/bash "$WORK/plugin/bin/imthemousenow" --action scroll >/dev/null 2>&1 &
pid=$!
if await_scroll; then
  overlay="$(head -1 "$WORK/argv.log")"
  if [[ $overlay == *mode_click.button=none* ]]; then
    echo "ok    the overlay pass does not click"
  else
    echo "FAIL  the overlay pass does not click -- got: $overlay"
    failures=$((failures + 1))
  fi
  check "then the wheel turns where it put the pointer" \
    "$(grep -- '--scroll' "$WORK/argv.log")" "--scroll 500,400"
  scroll stop
  await_exit "$pid" || { echo "FAIL  / ends on Escape"; failures=$((failures + 1)); kill "$pid"; }
else
  echo "FAIL  / starts a scroll after the overlay"
  failures=$((failures + 1))
  kill "$pid" 2>/dev/null
fi

# --- a build without it -----------------------------------------------------------
setup
printf '#!/bin/bash\n[[ ${1:-} == --version ]] && echo "wl-kbptr 0.4.1"\nexit 0\n' >"$WORK/stub/wl-kbptr"
scroll begin
check "a stock build is refused before anything starts" "$(cat "$WORK/argv.log")" ""

((failures == 0)) && echo "all passed" || echo "$failures failing"
exit $((failures > 0))
