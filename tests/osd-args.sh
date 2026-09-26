#!/bin/bash
# What does osd_action() ask the OSD to draw, and where?
#
# The interesting part is the geometry: the word belongs to whatever the overlay
# is covering, which is the focused window in window scope and the screen in
# monitor scope. All three of those decisions are invisible at runtime -- a wrong
# one puts the word somewhere plausible-looking -- so they are asserted here
# rather than discovered by eye.
#
# Nothing is drawn: osd_action fires the OSD detached with its output discarded,
# so the stub standing in for it appends its argv to a file instead. hyprctl is
# stubbed too, which is the only way to exercise the "no focused window" branch
# without switching the tester to an empty workspace.
#
#   ./tests/osd-args.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A home of this test's own, so the tester's config.toml and whichever theme
# they have on are not merged in underneath the assertions below. Without it
# these pass or fail according to whose machine is running them, and the
# failure reads as damage from whatever was last changed.
export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
failures=0

# A plugin directory that is real enough for the lib to load: the shipped
# defaults and the config tool that reads them, plus a stub where the OSD goes.
setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/args.log"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO/bin/imthemousenow-config" "$WORK/plugin/bin/"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"%s/args.log"\n' "$WORK" >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"
}

# A monitor at the origin, and a window inset on it. The numbers are arbitrary
# but the arithmetic is not: the region must be monitor-relative.
hyprctl_stub() {
  local window="$1"
  cat >"$WORK/stub/hyprctl" <<STUB
#!/bin/bash
case "\$*" in
  *monitors*) echo '[{"name":"DP-9","x":100,"y":50,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '$window' ;;
esac
STUB
  chmod +x "$WORK/stub/hyprctl"
}

# check <label> <action> <scope> <expected argv fragment>...
# A fragment of "" asserts the argv does NOT contain the one after it.
check() {
  local label="$1" action="$2" scope="$3"
  shift 3
  local out problem=""
  # PATH keeps the stub first but not alone: the lib needs jq and the config
  # tool needs python.
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash -c "source '$REPO/bin/imthemousenow-lib.sh'; osd_action '$action' '$scope'" >/dev/null 2>&1
  # osd_action detaches, so wait for the stub to land rather than assuming it has.
  local waited=0
  while [[ ! -f $WORK/args.log ]] && ((waited < 50)); do sleep 0.02; waited=$((waited + 1)); done
  out="$(cat "$WORK/args.log" 2>/dev/null || true)"

  local want negate=0
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

# The word itself, upper-cased, and the action's own colour from the theme layer
# -- which is absent in this fake plugin dir, so only the label is asserted here.
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "the action's label, upper-cased" right-click monitor "RIGHT"
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "move is a word, not a click name" move monitor "MOVE"

# Monitor scope is the screen: no box, and so no output to put one on.
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "monitor scope passes no region" left-click monitor "LEFT" "" "--region" "" "--output"

# Window scope is the window, in the monitor's own coordinates: a window at
# 400,250 on a monitor at 100,50 is 300,200 into that monitor.
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "window scope passes the window box" left-click window "--region 800x600+300+200" "--output DP-9"

# An empty workspace has nothing to aim at, so the word goes where the overlay
# went: the monitor.
setup; hyprctl_stub '{}'
check "no focused window falls back to the screen" left-click window "LEFT" "" "--region"

# The axes the config owns, which a caller must not have to repeat.
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "timings and placement come from the config" left-click monitor \
  "--ms 1000" "--fade-ms 250" "--position top" "--size 120"

# The wordmark is the default, so the flag that turns it off is the only one
# that should ever appear -- and it must appear the moment the config says so.
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "the art is on by default, so no flag is passed" left-click monitor "LEFT" "" "--no-ascii"
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
mkdir -p "$HOME/.config/omarchy/imthemousenow"
printf '[imthemousenow.osd]\nascii = false\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
check "ascii = false asks for the plain word" left-click monitor "LEFT" "--no-ascii"
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# The departure style, same shape as the timings above: the default ships in
# config.default.toml, and a caller must not have to repeat it.
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
check "the departure style comes from the config" left-click monitor "--outro fade"
setup; hyprctl_stub '{"at":[400,250],"size":[800,600]}'
mkdir -p "$HOME/.config/omarchy/imthemousenow"
printf '[imthemousenow.osd]\noutro = "scanline"\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
check "a configured outro overrides the default" left-click monitor "--outro scanline"
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all checks passed"
