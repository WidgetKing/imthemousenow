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

# What the GitHub API reports, for the release check.
release_stub() {
  echo abc123 >"$WORK/home/.local/state/imthemousenow/commit"
  printf '#!/bin/bash\necho %s\n' "'  \"tag_name\": \"$1\",'" >"$WORK/stub/curl"
  chmod +x "$WORK/stub/curl"
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
new_release()    { release_stub v0.9.9; }
pinned_release() { release_stub v0.4.1; rm "$WORK/stub/omarchy-hyprland-window-close-all"; }
panic_gone()     { rm "$WORK/stub/omarchy-hyprland-window-close-all"; }
everything()     { soname_bump; include_lost; release_stub v0.9.9; rm "$WORK/stub/omarchy-hyprland-window-close-all"; }

check "a healthy system says nothing"      nothing
check "not our install: says nothing"      not_our_install
check "no wl-kbptr: says nothing"          no_wl_kbptr
check "1. soname bump"                     soname_bump    "broke after a library update"
check "2. hyprland.lua include lost"       include_lost   "no longer loaded from hyprland.lua"
check "3. a new upstream release"          new_release    "v0.9.9 was released"
# The pinned release is not news -- but it must not stop the check below it,
# which is what `set -e` and a bare `&&` list used to do.
check "3b. release is the pinned one"      pinned_release "Ctrl+Alt+Delete no longer finds"
check "4. panic command gone"              panic_gone     "Ctrl+Alt+Delete no longer finds"
check "all four at once"                   everything \
  "broke after a library update" "no longer loaded from hyprland.lua" \
  "v0.9.9 was released" "Ctrl+Alt+Delete no longer finds"

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
