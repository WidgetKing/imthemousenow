#!/bin/bash
# Exercise hooks/post-update against a fake HOME and a sealed PATH.
#
# The hook only ever talks by sending notifications, so the test is: in this
# situation, does it say exactly the right things? Each scenario breaks one
# thing and asserts which notifications come back.
#
# The PATH is sealed -- the stub directory is the only entry -- because the
# real /usr/bin carries omarchy-hyprland-window-close-all, and with /usr/bin on
# the PATH there is no way to simulate its absence. An earlier version of this
# file got that wrong and reported check 4 as passing when it never ran.
#
#   ./tests/post-update-hook.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/post-update"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

# A working system, which each scenario then breaks one piece of.
setup() {
  rm -rf "$WORK/home" "$WORK/stub"
  mkdir -p "$WORK/home/.local/state/imthemousenow" "$WORK/home/.config/hypr" "$WORK/stub"
  local real
  for real in grep cat cut; do ln -s "$(command -v "$real")" "$WORK/stub/$real"; done
  printf '#!/bin/bash\necho "NOTIFY: ${*: -1}"\n' >"$WORK/stub/omarchy-notification-send"
  printf 'x\n' >"$WORK/stub/wl-kbptr"
  printf '#!/bin/bash\necho "libc.so => /usr/lib/libc.so"\n' >"$WORK/stub/ldd"
  printf '#!/bin/bash\nexit 0\n' >"$WORK/stub/omarchy-hyprland-window-close-all"
  chmod +x "$WORK/stub/omarchy-notification-send" "$WORK/stub/ldd" \
    "$WORK/stub/omarchy-hyprland-window-close-all"
  touch "$WORK/home/.local/state/imthemousenow/installed"
  echo 'require("omarchy.plugins.imthemousenow.hypr.imthemousenow")' \
    >"$WORK/home/.config/hypr/hyprland.lua"
}

# check <label> <break-it> <substring expected in a notification>...
check() {
  local label="$1" break_it="$2"
  shift 2
  setup
  $break_it
  local out rc
  out="$(HOME="$WORK/home" PATH="$WORK/stub" /usr/bin/bash "$HOOK" 2>&1)"
  rc=$?
  local expected=$# got problem=""
  ((rc == 0)) || problem="exited $rc"
  local want
  for want in "$@"; do
    [[ $out == *"$want"* ]] || problem="${problem:+$problem; }no notification about '$want'"
  done
  got=$(grep -c '^NOTIFY:' <<<"$out" || true)
  ((got == expected)) || problem="${problem:+$problem; }expected $expected notifications, got $got"

  if [[ -n $problem ]]; then
    echo "FAIL  $label -- $problem"
    [[ -n $out ]] && sed 's/^/        /' <<<"$out"
    failures=$((failures + 1))
  else
    echo "ok    $label"
  fi
}

nothing()        { :; }
not_our_install() { rm "$WORK/home/.local/state/imthemousenow/installed"; }
no_wl_kbptr()    { rm "$WORK/stub/wl-kbptr"; }
soname_bump()    { printf '#!/bin/bash\necho "libopencv.so => not found"\n' >"$WORK/stub/ldd"; chmod +x "$WORK/stub/ldd"; }
include_lost()   { echo 'nothing here' >"$WORK/home/.config/hypr/hyprland.lua"; }
panic_gone()     { rm "$WORK/stub/omarchy-hyprland-window-close-all"; }
everything()     { soname_bump; include_lost; rm "$WORK/stub/omarchy-hyprland-window-close-all"; }
# Chosen --keybinds none on purpose: the include is never there and the panic
# key is never wired up, so checks 2 and 3 would otherwise nag on every update
# about something that was never installed to begin with.
keybinds_none()  { echo none >"$WORK/home/.local/state/imthemousenow/keybinds-mode"; include_lost; rm "$WORK/stub/omarchy-hyprland-window-close-all"; }

check "a healthy system says nothing"      nothing
check "not our install: says nothing"      not_our_install
check "no wl-kbptr: says nothing"          no_wl_kbptr
check "1. soname bump"                     soname_bump    "broke after a library update"
check "2. hyprland.lua include lost"       include_lost   "no longer loaded from hyprland.lua"
check "3. panic command gone"              panic_gone     "Ctrl+Alt+Delete no longer finds"
check "all three at once"                  everything \
  "broke after a library update" "no longer loaded from hyprland.lua" \
  "Ctrl+Alt+Delete no longer finds"
check "4. --keybinds none: no include/panic nags" keybinds_none

# The hook talks to nothing outside this machine. A stubbed PATH with no curl
# in it is how that is asserted: if a check ever reaches for the network again,
# it has to add the tool here first, and that is the moment to ask why.
[[ ! -e "$WORK/stub/curl" ]] ||
  { echo "FAIL  the hook makes no network call -- something put curl on the stub PATH"; failures=$((failures + 1)); }

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
