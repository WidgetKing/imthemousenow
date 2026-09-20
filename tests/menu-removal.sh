#!/bin/bash
# Does taking our old menu rows out leave the user's file the way it was?
#
# The settings live in a bar widget now, but earlier versions merged a block of
# rows into the ONE user menu file Omarchy's shell reads -- shared with the user
# and with every other plugin. Removing them is the last thing this plugin does
# to that file, and the risk is not that the rows fail to disappear: it is that
# removing them goes wrong quietly. A comment eaten, a comma left where the
# parser wanted none, or somebody else's row taken along with ours all look
# fine in a diff and break the whole menu at runtime -- on an upgrade, when the
# user did not ask for their menu to be touched at all.
#
# Nothing here touches the real menu file: MOUSENOW_MENU_FILE points the tool at
# a scratch copy.
#
#   ./tests/menu-removal.sh
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

export MOUSENOW_MENU_FILE="$WORK/omarchy-menu.jsonc"
MENU="$REPO/bin/imthemousenow-menu"

BEGIN='  // >>> imthemousenow (managed by install.sh; remove with uninstall.sh) >>>'
END='  // <<< imthemousenow <<<'

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1"; printf '        want: %s\n        got:  %s\n' "$3" "$2"; fi; }

# Valid JSON once comments and trailing commas are gone, which is the only
# property the shell's parser and every assertion below actually depend on.
# Prints the number of top-level rows, or why it could not be read.
parses() { python3 - "$1" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
out, in_string, escaped, i = [], False, False, 0
while i < len(text):
    c = text[i]
    if in_string:
        out.append(c)
        if escaped: escaped = False
        elif c == "\\": escaped = True
        elif c == '"': in_string = False
        i += 1; continue
    if c == '"': in_string = True; out.append(c)
    elif text.startswith("//", i):
        while i < len(text) and text[i] != "\n": i += 1
        continue
    else: out.append(c)
    i += 1
try:
    print(len(json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))))
except Exception as exc:
    print(f"unparsable: {exc}")
PY
}

# A stand-in for what an old install left behind: our marked block, with rows
# whose exact contents no longer matter -- only that they are between the
# markers and are the only thing removal is allowed to touch.
ours() {
  printf '%s\n' "$BEGIN"
  printf '%s\n' '  "pointer": {"icon":"󰇀","label":"Pointer"},'
  printf '%s\n' '  "pointer.notify": {"icon":"󰂚","label":"Notifications","action":"imthemousenow-config toggle notify"},'
  printf '%s\n' "$END"
}

# --- 1. no file at all --------------------------------------------------------
rm -f "$MOUSENOW_MENU_FILE"
"$MENU" remove >/dev/null 2>&1
if [[ -e $MOUSENOW_MENU_FILE ]]; then
  no "removing from nothing does not invent a file"
else
  ok "removing from nothing does not invent a file"
fi

# --- 2. a file with nothing of ours in it ------------------------------------
cat >"$MOUSENOW_MENU_FILE" <<'JSONC'
{
  // A comment the user wrote and would be annoyed to lose.
  "personal": {"icon":"","label":"Personal"}
}
JSONC
untouched="$(cat "$MOUSENOW_MENU_FILE")"
"$MENU" remove >/dev/null
check "a file that never had our rows is not rewritten" "$(cat "$MOUSENOW_MENU_FILE")" "$untouched"

# --- 3. our block, and nothing else ------------------------------------------
{ echo "{"; ours; echo "}"; } >"$MOUSENOW_MENU_FILE"
"$MENU" remove >/dev/null
check "removing our only rows leaves an empty file that still parses" "$(parses "$MOUSENOW_MENU_FILE")" "0"
if grep -q "imthemousenow" "$MOUSENOW_MENU_FILE"; then
  no "and leaves no mention of us behind"
else
  ok "and leaves no mention of us behind"
fi

# --- 4. the user's rows and comments survive ---------------------------------
# Ours first, so removing them is what decides whether the row after the hole
# keeps the comma it needs.
{
  echo "{"
  ours
  printf '%s\n' '  // A comment the user wrote and would be annoyed to lose.'
  printf '%s\n' '  "personal": {"icon":"","label":"Personal"},'
  printf '%s\n' '  "personal.notes": {"icon":"","label":"Notes","action":"true"}'
  echo "}"
} >"$MOUSENOW_MENU_FILE"
"$MENU" remove >/dev/null
check "their rows are all that is left" "$(parses "$MOUSENOW_MENU_FILE")" "2"
grep -q "annoyed to lose" "$MOUSENOW_MENU_FILE" && ok "their comment is still there" || no "their comment is still there"

# --- 5. ours last, which is where the trailing comma goes wrong --------------
{
  echo "{"
  printf '%s\n' '  "personal": {"icon":"","label":"Personal"},'
  ours
  echo "}"
} >"$MOUSENOW_MENU_FILE"
"$MENU" remove >/dev/null
check "a row left last loses the comma it no longer needs" "$(parses "$MOUSENOW_MENU_FILE")" "1"

# --- 6. rows that merely look like ours --------------------------------------
# No markers: the user pasted these in themselves, so they are the user's.
cat >"$MOUSENOW_MENU_FILE" <<'JSONC'
{
  "pointer": {"icon":"󰇀","label":"Pointer"},
  "pointer.notify": {"icon":"󰂚","label":"Notifications","action":"imthemousenow-config toggle notify"}
}
JSONC
pasted="$(cat "$MOUSENOW_MENU_FILE")"
"$MENU" remove >/dev/null
check "rows pasted by hand are the user's and stay" "$(cat "$MOUSENOW_MENU_FILE")" "$pasted"

# --- 7. a broken file is never made worse ------------------------------------
{ echo "{"; ours; printf '%s\n' '  "oops": {"label":'; echo "}"; } >"$MOUSENOW_MENU_FILE"
broken="$(cat "$MOUSENOW_MENU_FILE")"
"$MENU" remove >/dev/null 2>&1
check "a file that would not parse afterwards is left alone" "$(cat "$MOUSENOW_MENU_FILE")" "$broken"

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"
