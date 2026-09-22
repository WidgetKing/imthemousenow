#!/bin/bash
# Does `;` switch left and right click in place, and only when it safely can?
#
# The reload itself is the fork's ("Change the config of a running overlay on
# a signal") and needs a compositor to see. What is testable here is what
# decides it, and every piece fails badly rather than quietly:
#
#   - --overrides-file goes only to a build that knows it (an unknown flag
#     stops wl-kbptr before it draws anything), and SIGUSR1 only to one too
#     (without the flag, the signal kills it).
#   - the lines written for a switch are the ones a relaunch would have
#     passed, from one function, so the two cannot drift apart.
#   - every ACTION shares one mode chain, the ones that press nothing with
#     button `none`, so any switch is done in place on a build that can.
#
#   ./tests/overrides-args.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1"; printf '        want: %s\n        got:  %s\n' "$3" "$2"; fi; }

# A session and a home of this test's own: every config layer hangs off HOME.
export XDG_RUNTIME_DIR="$WORK/run"
export HOME="$WORK/home"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME/.config/omarchy/imthemousenow"
SESSION="$XDG_RUNTIME_DIR/imthemousenow"
# A tint of its own, so the test does not depend on a theme being rendered.
printf '[imthemousenow.action.right-click]\ncolor = "#123456"\n' \
  >"$HOME/.config/omarchy/imthemousenow/config.toml"

setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$SESSION"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$SESSION"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-session.sh,-steer} "$WORK/plugin/bin/"
  printf '#!/bin/bash\necho "$1" >>"%s/osd.log"\n' "$WORK" >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"
  : >"$WORK/osd.log"

  # A build that knows double click, so the window is part of the lines.
  printf '#!/bin/bash\n[[ ${1:-} == --version ]] && echo "wl-kbptr 0.4.1"\nexit 0\n# double_click_ms\n' >"$WORK/stub/wl-kbptr"
  # The tester's own overlay is not ours to signal or kill.
  printf '#!/bin/bash\necho "$*" >>"%s/pkill.log"\n' "$WORK" >"$WORK/stub/pkill"
  printf '#!/bin/bash\nexit 0\n' >"$WORK/stub/notify-send"
  printf '#!/bin/bash\nexit 1\n' >"$WORK/stub/gsettings"
  cat >"$WORK/stub/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  *monitors*) echo '[{"name":"DP-9","x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '{"at":[400,250],"size":[800,600],"address":"0xabc"}' ;;
  *clients*) echo '[]' ;;
  *binds*) echo '[]' ;;
  *) echo '{}' ;;
esac
STUB
  chmod +x "$WORK/stub/"*
  : >"$WORK/pkill.log"

  echo hints >"$SESSION/mode"
  echo window >"$SESSION/scope"
  echo left-click >"$SESSION/action"
  echo left-click >"$SESSION/base-action"
  echo single >"$SESSION/lifetime"
}
knows() { echo '# --overrides-file' >>"$WORK/stub/wl-kbptr"; }

lib() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" /usr/bin/bash -c \
    "source '$WORK/plugin/bin/imthemousenow-lib.sh'; $1"
}
steer() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow-steer" "$@" >/dev/null 2>&1
}
dry_run() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    "$WORK/plugin/bin/imthemousenow" "$@" -n 2>/dev/null
}

# --- 1. the lines -------------------------------------------------------------------
setup
tint="$(lib 'setting action.right-click.color')"
right="$(lib 'double_click_resolve; action_overrides right-click left-click live')"
check "right click from a left chord: button, no window, and the tint" "$right" "mode_click.button=right
mode_click.double_click_ms=0
mode_tile.label_select_color=${tint}ff
mode_tile.selectable_border_color=${tint}aa
mode_floating.label_select_color=${tint}ff
mode_floating.selectable_border_color=${tint}ee
mode_bisect.pointer_color=${tint}dd"
left="$(lib 'double_click_resolve; action_overrides left-click left-click live')"
case "$left" in
  *color*) no "the chord's own action has no tint" ;;
  "mode_click.button=left"*) ok "the chord's own action has no tint" ;;
  *) no "the chord's own action has no tint (got: $left)" ;;
esac

# --- 2. which switches are in place -----------------------------------------------
setup
lib 'action_swappable_in_place left-click right-click' && no "no probe, no switch in place" || ok "no probe, no switch in place"
knows
lib 'action_swappable_in_place left-click right-click' && ok "left to right is in place" || no "left to right is in place"
lib 'action_swappable_in_place right-click left-click' && ok "and back" || no "and back"
for to in move drag hold; do
  lib "action_swappable_in_place left-click $to" && ok "left to $to is in place" || no "left to $to is in place"
done
lib 'action_swappable_in_place move hold' && ok "and so is move to hold" || no "and so is move to hold"

# --- 3. the launcher ------------------------------------------------------------------
setup
case "$(dry_run --action left-click)" in
  *--overrides-file*) no "a build without it is never given --overrides-file" ;;
  *) ok "a build without it is never given --overrides-file" ;;
esac
knows
case "$(dry_run --action left-click)" in
  *"--overrides-file $SESSION/overrides"*) ok "a build with it is pointed at the session's file" ;;
  *) no "a build with it is pointed at the session's file (got: $(dry_run --action left-click))" ;;
esac

# --- 4. steer -------------------------------------------------------------------------
setup; knows
steer action right-click
check "; switches the session to right click" "$(cat "$SESSION/action")" "right-click"
[[ -e $SESSION/switch ]] && no "without asking for a relaunch" || ok "without asking for a relaunch"
check "signals the overlay instead" "$(cat "$WORK/pkill.log")" "-USR1 -x wl-kbptr"
check "having written the lines first" "$(cat "$SESSION/overrides")" "$right"
: >"$WORK/pkill.log"; rm -f "$SESSION/last-bind"
steer action right-click
check "; again goes back to left" "$(cat "$SESSION/action")" "left-click"
check "and writes only the button and window" "$(cat "$SESSION/overrides")" "$left"

setup
steer action right-click
[[ -e $SESSION/switch ]] && ok "a build without the flag still relaunches" || no "a build without the flag still relaunches"
grep -q USR1 "$WORK/pkill.log" && no "and is never sent the signal" || ok "and is never sent the signal"

setup; knows
steer action move
[[ -e $SESSION/switch ]] && no "move is in place too" || ok "move is in place too"
check "and presses nothing" "$(head -1 "$SESSION/overrides")" "mode_click.button=none"

echo
((fails == 0)) && echo "all passed" || { echo "$fails failed"; exit 1; }
