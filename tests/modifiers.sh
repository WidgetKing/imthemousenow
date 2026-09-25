#!/bin/bash
# Do the modifier toggles reach the press, and only the press they are for?
#
# Holding Ctrl down around the click is wl-kbptr's (the fork's "Hold modifiers
# down around a press" commit) and needs a compositor to see. What is testable
# here is everything that decides what it is asked to hold, and every piece of
# it fails quietly:
#
#   - a tap is a command on one side of the keyboard and a toggle on the
#     other, and which is which is keyboard_modifier_side. Got backwards, CTRL
#     flips the lifetime when you meant a Ctrl click.
#   - the list is always ctrl, alt, shift, super in that order, whatever order
#     it was tapped in, so the word on screen and the flag passed agree.
#   - --modifiers goes only to a build that knows it (an unknown flag stops
#     wl-kbptr before it draws anything), only to an overlay that clicks, and
#     never to move.
#
#   ./tests/modifiers.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1"; printf '        want: %s\n        got:  %s\n' "$3" "$2"; fi; }

# A session and a home of this test's own, so a real overlay on the tester's
# desktop is neither read nor trampled and their config.toml is untouched.
export XDG_RUNTIME_DIR="$WORK/run"
export HOME="$WORK/home"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME/.config/omarchy/imthemousenow"
USER_CONF="$HOME/.config/omarchy/imthemousenow/config.toml"
SESSION="$XDG_RUNTIME_DIR/imthemousenow"

config() { env MOUSENOW_PLUGIN_DIR="$REPO" "$REPO/bin/imthemousenow-config" "$@"; }

# --- 1. the setting -------------------------------------------------------------
check "the modifier side ships as the right" "$(config get keyboard_modifier_side)" "right"
for act in left-click right-click drag hold drop; do
  check "$act holds modifiers" "$(config get "action.$act.modifiers")" "true"
done
check "move does not" "$(config get action.move.modifiers)" "false"
printf '[imthemousenow]\nkeyboard_modifier_side = "middle"\n' >"$USER_CONF"
config check >/dev/null 2>&1 && no "a side that is neither is refused by check" || ok "a side that is neither is refused by check"
rm -f "$USER_CONF"

# --- 2. the list ------------------------------------------------------------------
lib() {
  env MOUSENOW_PLUGIN_DIR="$REPO" /usr/bin/bash -c "source '$REPO/bin/imthemousenow-lib.sh'; $1"
}
check "toggling on keeps the fixed order" "$(lib 'modifiers_toggle "shift" ctrl')" "ctrl shift"
check "whatever order they came in" "$(lib 'modifiers_toggle "super alt" shift')" "alt shift super"
check "toggling one that is on takes it off" "$(lib 'modifiers_toggle "ctrl alt" ctrl')" "alt"
check "and the last one off leaves nothing" "$(lib 'modifiers_toggle "alt" alt')" ""
check "the word's prefix" "$(lib 'modifiers_label "ctrl alt shift super"')" "Ctrl + Alt + Shift + Super + "
check "wl-kbptr's spelling" "$(lib 'modifiers_arg "ctrl alt"')" "ctrl,alt"

# --- 3. a plugin to steer, and a wl-kbptr to ask -------------------------------
setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$SESSION"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$SESSION"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-locale.sh,-session.sh,-steer} "$WORK/plugin/bin/"
  # The word, written down rather than drawn.
  printf '#!/bin/bash\necho "$1" >>"%s/osd.log"\n' "$WORK" >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"
  : >"$WORK/osd.log"

  printf '#!/bin/bash\n[[ ${1:-} == --version ]] && echo "wl-kbptr 0.4.1"\nexit 0\n' >"$WORK/stub/wl-kbptr"
  # A relaunch kills wl-kbptr; the tester's own overlay is not ours to kill.
  printf '#!/bin/bash\necho "$*" >>"%s/pkill.log"\n' "$WORK" >"$WORK/stub/pkill"
  printf '#!/bin/bash\nexit 0\n' >"$WORK/stub/notify-send"
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

  # A run that is up, in left-click, window scope, single.
  echo hints >"$SESSION/mode"
  echo window >"$SESSION/scope"
  echo left-click >"$SESSION/action"
  echo left-click >"$SESSION/base-action"
  echo single >"$SESSION/lifetime"
}
knows() { echo '# --modifiers' >>"$WORK/stub/wl-kbptr"; }

steer() {
  PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    /usr/bin/bash "$WORK/plugin/bin/imthemousenow-steer" "$@" >/dev/null 2>&1
  # The debounce reads a relaunch still in flight as the tail of a chord; the
  # run loop would have taken it by the next tap.
  rm -f "$SESSION/switch"
}
field() { cat "$SESSION/$1" 2>/dev/null; }
last_word() { tail -1 "$WORK/osd.log"; }

# --- 4. the modifier side ---------------------------------------------------------
setup; knows
steer modkey ctrl right
check "right CTRL turns Ctrl on" "$(field modifiers)" "ctrl"
check "and says so" "$(last_word)" "CTRL + LEFT"
[[ -s $WORK/pkill.log ]] && ok "and relaunches the clicking overlay" || no "and relaunches the clicking overlay"
steer modkey shift right; steer modkey alt right
check "they stack, in the fixed order" "$(field modifiers)" "ctrl alt shift"
check "and the word follows the same order" "$(last_word)" "CTRL + ALT + SHIFT + LEFT"
steer modkey ctrl right
check "tapping one again turns it off" "$(field modifiers)" "alt shift"
steer modkey alt right; steer modkey shift right
check "and the last one off clears the field" "$(field modifiers)" ""
check "leaving the bare word" "$(last_word)" "LEFT"
check "the axes are untouched" "$(field scope) $(field mode) $(field lifetime)" "window hints single"

# --- 5. the command side ------------------------------------------------------------
setup; knows
steer modkey shift left
check "left SHIFT flips SCOPE" "$(field scope)" "monitor"
steer modkey alt left
check "left ALT flips MODE" "$(field mode)" "grid"
: >"$WORK/pkill.log"
steer modkey ctrl left
check "left CTRL flips LIFETIME" "$(field lifetime)" "continuous"
check "and says which it is now" "$(last_word)" "CONTINUOUS"
steer modkey ctrl left
check "and back" "$(field lifetime) $(last_word)" "single SINGLE"
steer modkey ctrl left
[[ -s $WORK/pkill.log ]] && no "without relaunching anything" || ok "without relaunching anything"
# SUPER is no axis -- there is no fourth thing to flip -- so on the command side
# it rebuilds the overlay, which is what F5 does. Asserted by the relaunch it
# asks for, and by the axes it must leave exactly as they were.
: >"$WORK/pkill.log"
steer modkey super left
check "left SUPER changes no axis" "$(field scope) $(field mode) $(field lifetime) $(field modifiers)" \
  "monitor grid continuous "
# The relaunch is the assertion; which kind it was is not readable here, because
# the steer() wrapper above clears `switch` after every call on purpose.
[[ -s $WORK/pkill.log ]] && ok "and rebuilds the overlay, as F5 does" || no "and rebuilds the overlay, as F5 does"

# --- 6. swapping the sides -----------------------------------------------------------
setup; knows
printf '[imthemousenow]\nkeyboard_modifier_side = "left"\n' >"$USER_CONF"
steer modkey ctrl left
check "with the sides swapped, left CTRL is a toggle" "$(field modifiers)" "ctrl"
steer modkey ctrl right
check "and right CTRL flips LIFETIME" "$(field lifetime)" "continuous"
rm -f "$USER_CONF"

# --- 7. where toggles mean nothing, or cannot be kept ---------------------------------
setup; knows
echo move >"$SESSION/action"
steer modkey ctrl right
check "move ignores them" "$(field modifiers)" ""

setup
steer modkey ctrl right
check "a build without --modifiers refuses them" "$(field modifiers)" ""

setup; knows
echo drag >"$SESSION/action"
steer modkey ctrl right
check "a drag pass keeps them for later" "$(field modifiers)" "ctrl"
[[ -s $WORK/pkill.log ]] && no "without relaunching an overlay that clicks nothing" ||
  ok "without relaunching an overlay that clicks nothing"
check "and names the drag" "$(last_word)" "CTRL + DRAG"

# --- 8. what the overlay is launched with --------------------------------------------
dry_run() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    "$WORK/plugin/bin/imthemousenow" "$@" -n 2>/dev/null
}
setup
echo "ctrl alt" >"$SESSION/modifiers"
case "$(dry_run --action left-click)" in
  *--modifiers*) no "a build that does not know --modifiers is never given it" ;;
  *) ok "a build that does not know --modifiers is never given it" ;;
esac
knows
case "$(dry_run --action left-click)" in
  *"--modifiers ctrl\,alt"* | *"--modifiers ctrl,alt"*) ok "a left click is launched holding them" ;;
  *) no "a left click is launched holding them (got: $(dry_run --action left-click))" ;;
esac
case "$(dry_run --action right-click)" in
  *--modifiers*) ok "and so is a right click" ;;
  *) no "and so is a right click" ;;
esac
for act in move drag hold; do
  case "$(dry_run --action "$act")" in
    *--modifiers*) no "$act's overlay is not: it clicks nothing" ;;
    *) ok "$act's overlay is not: it clicks nothing" ;;
  esac
done
rm -f "$SESSION/modifiers"
case "$(dry_run --action left-click)" in
  *--modifiers*) no "none on means no flag at all" ;;
  *) ok "none on means no flag at all" ;;
esac

# --- 9. a build that reads them at the click --------------------------------------
# Pointed at the session's file from the start, even with nothing on, so a
# toggle made after the overlay opened still reaches the click -- and so a
# toggle no longer relaunches it, which is what made the overlay flicker.
knows_file() { echo '# --modifiers-file' >>"$WORK/stub/wl-kbptr"; }
setup; knows; knows_file
case "$(dry_run --action left-click)" in
  *"--modifiers-file $SESSION/modifiers"*) ok "a click is pointed at the session's file" ;;
  *) no "a click is pointed at the session's file (got: $(dry_run --action left-click))" ;;
esac
echo ctrl >"$SESSION/modifiers"
case "$(dry_run --action left-click)" in
  *"--modifiers "*) no "and not given the list as well" ;;
  *) ok "and not given the list as well" ;;
esac
# Every overlay is, so one switched to in place still finds it; with its
# button `none`, it presses nothing and so holds nothing.
for act in move drag hold; do
  case "$(dry_run --action "$act")" in
    *--modifiers-file*) ok "$act's overlay is pointed at it too, pressing nothing" ;;
    *) no "$act's overlay is pointed at it too, pressing nothing" ;;
  esac
done
rm -f "$SESSION/modifiers"
steer modkey ctrl right
check "a toggle still lands in the file" "$(field modifiers)" "ctrl"
check "and still says so" "$(last_word)" "CTRL + LEFT"
[[ -s $WORK/pkill.log ]] && no "without relaunching the overlay" || ok "without relaunching the overlay"

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"
