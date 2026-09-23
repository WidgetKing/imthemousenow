#!/bin/bash
# Does every setting the bar widget writes still exist, and do the settings it
# no longer offers stay gone?
#
# The panel deliberately holds no opinion about what a valid value is -- it
# reads `imthemousenow-config env` and writes back through `set` and `toggle`,
# so the config program is the only thing that interprets the config. The cost
# of that arrangement is that a key renamed or removed in config.default.toml
# leaves a row in Panel.qml writing into nothing, and the panel finds out at the
# moment a user clicks it. This is the check that would have caught it: every
# key named in Panel.qml is put to the real `set`, against the real defaults.
#
# The keys come out of Panel.qml by pattern rather than by being listed here.
# A list here would be a third copy of the vocabulary, and a third copy is the
# thing this whole arrangement exists to avoid.
#
#   ./tests/panel-settings.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL="$REPO/shell/Panel.qml"

# A home of this test's own, for the reason the other tests have one: `set`
# writes to ~/.config/omarchy/imthemousenow/config.toml, and a test that wrote
# into the tester's own config would be a test that edits the machine it runs
# on.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" MOUSENOW_PLUGIN_DIR="$REPO"

pass=0 fail=0
ok() { printf 'ok    %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }

config() { "$REPO/bin/imthemousenow-config" "$@" 2>&1; }

# --- 1. every key the panel writes is a key the config knows ------------------
# `key: "x"` covers groupFor() and sliderFor(); the toggleKey() map is
# `"row": "key"`; setValue() calls name theirs outright.
keys="$(
  {
    grep -oE 'key: "[a-z_.]+"' "$PANEL" | sed 's/key: "//; s/"//'
    grep -oE '"[a-z-]+": "[a-z_.]+"' "$PANEL" | sed 's/.*: "//; s/"//'
    grep -oE 'setValue\("[a-z_.]+"' "$PANEL" | sed 's/setValue("//; s/"//'
  } | sort -u
)"

[[ -n $keys ]] || { echo "FAIL  no config keys found in $PANEL -- has it been restructured?"; exit 1; }

for key in $keys; do
  # `word` is the action word's three-way row, which is two real keys behind one
  # control (osd.enabled and osd.ascii); both are written by setValue and so are
  # checked in their own right.
  [[ $key == word ]] && continue
  reply="$(config set "$key" "$(config env | grep -m1 "^MOUSENOW_CFG_$(echo "$key" | tr '[:lower:].-' '[:upper:]__')=" | cut -d= -f2- | tr -d "'")")"
  if [[ $reply == *"is not a settable"* || $reply == *"unknown"* ]]; then
    no "the panel writes $key, which the config does not accept: $reply"
  else
    ok "$key"
  fi
done

# --- 2. the settings that were removed stay removed ---------------------------
# The hold's pulsing ring and drag's per-drag drop MODE. Both were dropped
# rather than hidden: the ring because the mark drawn over it replaced it, and
# drop_mode because a drop is the far end of a gesture already under way and
# relabelling the screen halfway is a way to lose track of what you are
# carrying. A key that comes back is a key some row will offer again.
for gone in action.hold.halo_size action.drag.drop_mode; do
  if grep -q "^${gone##*.} = " "$REPO/config.default.toml"; then
    no "$gone is back in config.default.toml"
  else
    ok "$gone is gone from the defaults"
  fi
  if config env | grep -q "MOUSENOW_CFG_$(echo "$gone" | tr '[:lower:].' '[:upper:]_')="; then
    no "$gone is still in the merged config"
  else
    ok "$gone is not in the merged config"
  fi
done

if grep -rq "halo_size\|drop_mode" "$REPO/bin" "$REPO/qml" "$REPO/shell"; then
  no "something still reads halo_size or drop_mode"
  grep -rn "halo_size\|drop_mode" "$REPO/bin" "$REPO/qml" "$REPO/shell" | sed 's/^/        /'
else
  ok "nothing reads them any more"
fi

# --- 3. double click sits below the ADVANCED divider --------------------------
# It is a preference in the sense that it has no wrong answer, and not one in
# the sense that matters here: you would only change it once someone explained
# what pressing the committing key twice is for. The panel puts it in Advanced,
# and the config file should agree about where it belongs.
divider="$(grep -n '^# ADVANCED' "$REPO/config.default.toml" | cut -d: -f1)"
dbl="$(grep -n '^\[imthemousenow.double_click\]' "$REPO/config.default.toml" | cut -d: -f1)"
if [[ -n $divider && -n $dbl ]] && ((dbl > divider)); then
  ok "double_click is below the ADVANCED divider"
else
  no "double_click is at line ${dbl:-?}, the divider at ${divider:-?}"
fi

# --- 4. the tabs and the rows agree ------------------------------------------
# Every row id in the `rows` lists has a row drawn for it, and every drawn row
# is in a list. A row in one and not the other is either a cursor stop with
# nothing under it or a control the keyboard cannot reach.
listed="$(sed -n '/readonly property var rows: {/,/^  }/p' "$PANEL" |
  grep -oE '"[a-z-]+"' | tr -d '"' | sort -u)"
drawn="$(grep -oE 'rowId: "[a-z-]+"' "$PANEL" | sed 's/rowId: "//; s/"//' | sort -u)"
# The two footer buttons are drawn as Buttons rather than rows, and are reached
# by hasCursor("edit") / hasCursor("check").
drawn="$(printf '%s\nedit\ncheck\n' "$drawn" | sort -u)"

missing="$(comm -23 <(echo "$listed") <(echo "$drawn"))"
extra="$(comm -13 <(echo "$listed") <(echo "$drawn"))"
[[ -z $missing ]] && ok "every row the cursor walks is drawn" || no "walked but not drawn: $(echo $missing)"
[[ -z $extra ]] && ok "every drawn row is walked" || no "drawn but not walked: $(echo $extra)"

echo
if ((fail)); then
  echo "$fail failing, $pass passing"
  exit 1
fi
echo "all $pass checks passed"
