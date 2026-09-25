#!/bin/bash
# Does the key sheet describe the overlay that is actually up, and is Escape
# still Escape?
#
# The sheet is the only written-down account of a keyboard that is printed on
# nothing, so the way it fails is by being WRONG rather than by being absent:
# a sheet that lists the resize keys over a monitor, or the workspace digits
# during a drag, teaches a key that does nothing. Those are the branches.
#
# The other half is Escape, which this feature quietly rearranged. In
# popup-safe mode Escape used to be a plain relay into wl-kbptr's channel; it
# is now a binding of its own, because with a sheet up there is no overlay to
# cancel and the sheet cannot read its own keyboard there. Get that wrong in
# either direction and the cost is a key that cannot close what it opened, or
# an overlay that can no longer be cancelled at all.
#
#   ./tests/help-sheet.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# A session and a home of this test's own: the sheet reads the live session to
# find out what the overlay is, and a real overlay on the tester's desktop must
# not answer for it.
export XDG_RUNTIME_DIR="$WORK/run"
export HOME="$WORK/home"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME"

sheet() { env MOUSENOW_PLUGIN_DIR="$REPO" "$REPO/bin/imthemousenow-help" --print "$@"; }

# Every key named in a `keys` column, space separated, so a test can ask
# whether one is offered without caring which section put it there.
keys_of() { jq -r '[.sections[].rows[][0]] | join(" | ")'; }

has() {
  local label="$1" listing="$2" key="$3"
  if [[ " $listing " == *"$key"* ]]; then ok "$label"; else
    no "$label"; printf '        keys: %s\n' "$listing"; fi
}
lacks() {
  local label="$1" listing="$2" key="$3"
  if [[ " $listing " != *"$key"* ]]; then ok "$label"; else
    no "$label"; printf '        keys: %s\n' "$listing"; fi
}

# --- 1. the sheet is about THIS overlay --------------------------------------
window="$(sheet --scope window --mode hints --action left-click | keys_of)"
has   "window scope offers the resize keys" "$window" "-  ="
has   "window scope offers Tab, which swaps this window" "$window" "Tab"

monitor="$(sheet --scope monitor --mode hints --action left-click | keys_of)"
lacks "monitor scope does not, because there is no one window" "$monitor" "-  ="
lacks "and does not offer Tab either" "$monitor" "Tab"

# The digits and the arrows exist in both, meaning different things. What must
# never happen is the sheet promising a workspace move during a drag.
drop="$(sheet --scope monitor --mode grid --action drag --stage drop | keys_of)"
has   "a drag's drop pass offers the arrows, which move between monitors there" "$drop" "arrows"

drop_text="$(sheet --scope monitor --mode grid --action drag --stage drop \
  | jq -r '[.sections[].rows[][1]] | join(" | ")')"
for phrase in "nothing during a drag" "call the drag off"; do
  if [[ $drop_text == *"$phrase"* ]]; then
    ok "and says '$phrase', which is what those keys mean only there"
  else
    no "and says '$phrase', which is what those keys mean only there"
    printf '        text: %s\n' "$drop_text"
  fi
done

# grid ends in a bisect and hints does not, so they do not share an Aim section.
grid="$(sheet --scope monitor --mode grid --action left-click | keys_of)"
has   "grid names the home row, which is how a bisect is steered" "$grid" "home row"
lacks "hints does not, because it has no bisect in it" "$monitor" "home row"

# --- 2. Escape ----------------------------------------------------------------
has "every sheet says how to get out" "$window" "Escape"

# Escape must NOT be a plain relay key any more -- in popup-safe mode it is
# bound to `imthemousenow-steer escape`, which closes the sheet if one is up
# and relays Escape if not. Both halves of that are written down twice, in the
# lua and in the bash that re-asserts dropped binds, so both are checked.
if grep -q 'RELAY_KEYS = { "comma", "BackSpace"' "$REPO/hypr/imthemousenow-submap.lua"; then
  ok "Escape is out of the lua's relay list"
else
  no "Escape is out of the lua's relay list"
fi
if grep -q 'RELAY_KEYS=(comma BackSpace' "$REPO/bin/imthemousenow"; then
  ok "and out of the bash mirror of it, which must stay in step"
else
  no "and out of the bash mirror of it, which must stay in step"
fi
if grep -q 'imthemousenow-steer escape' "$REPO/hypr/imthemousenow-submap.lua" &&
  grep -q 'imthemousenow-steer escape' "$REPO/bin/imthemousenow"; then
  ok "and bound on its own in both, so the overlay is still cancellable"
else
  no "and bound on its own in both, so the overlay is still cancellable"
fi

# --- 3. the sheet has a way in ------------------------------------------------
# F1 opens it, in both submaps, and a dropped bind is re-asserted before every
# launch the way the arrows are -- Hyprland drops binds across an overlay, and
# a help key that works only on the first overlay of a session is worse than
# none.
if grep -q '"F1", hl.dsp.exec_cmd("imthemousenow-steer help")' "$REPO/hypr/imthemousenow-submap.lua"; then
  ok "F1 opens the sheet"
else
  no "F1 opens the sheet"
fi
if grep -q '^  "F1:imthemousenow-steer help' "$REPO/bin/imthemousenow"; then
  ok "and is re-asserted if Hyprland drops it"
else
  no "and is re-asserted if Hyprland drops it"
fi

# And `?` is NOT a second way in. It was, briefly, and it did not work: on a
# QWERTY keyboard the keysym only exists while SHIFT is held, so a bare
# `question` bind registers at modmask 0, never fires, and the `?` falls
# through and is typed into the window underneath. Binding it properly means a
# pair of binds that are only right for some keymaps, which is a worse trade
# than one key that is right for all of them. Asserted so it does not come
# back by accident.
if grep -q 'question' "$REPO/hypr/imthemousenow-submap.lua" &&
  ! grep -q 'hl.bind("[^"]*question"' "$REPO/hypr/imthemousenow-submap.lua"; then
  ok "\`?\` is not bound, and the lua says why"
else
  no "\`?\` is not bound, and the lua says why"
fi
if ! grep -q 'question:imthemousenow-steer' "$REPO/bin/imthemousenow"; then
  ok "and is not in the binds that get re-asserted either"
else
  no "and is not in the binds that get re-asserted either"
fi
if ! grep -q 'F1  /  ?' "$REPO/bin/imthemousenow-help"; then
  ok "and the sheet does not offer a key that does nothing"
else
  no "and the sheet does not offer a key that does nothing"
fi

echo
if ((fails)); then echo "$fails failing"; exit 1; fi
echo "all good"
