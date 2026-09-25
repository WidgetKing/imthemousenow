#!/bin/bash
# Do the bar widget's strings and locale/en.panel.strings still agree?
#
# The panel is QML and cannot call t(), so its words make a longer trip than
# anything else here: locale/<code>.panel.strings -> bin/imthemousenow-strings
# -> Model.parseStrings -> root.str(). Every step is covered below, but the
# one that matters is the first and last together. Each str() call carries the
# English as its fallback, exactly as t() does, which means a key that has
# quietly stopped matching the file does not fail loudly -- the panel just
# goes on showing English and no locale can ever reach it. So the drift IS the
# bug, and this is the only thing that can see it.
#
#   ./tests/locale-panel.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The same reason every test here does this: all three config layers and the
# locale hang off HOME, so without one of its own this reads whatever the
# tester happens to have installed and translated.
export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

PANEL="$REPO/shell/Panel.qml"
STRINGS="$REPO/locale/en.panel.strings"

failures=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

strings_cmd() {
  env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$REPO" LANG="${TEST_LANG:-}" \
    "$REPO/bin/imthemousenow-strings" "$@"
}

# --- 1. every key the panel asks for exists in the file ----------------------
# Extracted the same way a reader would: root.str("<key>", "<english>").
# The English may contain anything but a double quote, which is also the rule
# the .strings parser works to, so nothing here needs escaping either side.
missing=0
while IFS= read -r key; do
  grep -qE "^[[:space:]]*${key//./\\.}[[:space:]]*=" "$STRINGS" || {
    no "$key is asked for by the panel but is not in en.panel.strings"
    missing=$((missing + 1))
  }
done < <(grep -oE 'root\.str\("[^"]+"' "$PANEL" | sed 's/root\.str("//; s/"$//' | sort -u)
((missing == 0)) && ok "every key the panel asks for is in en.panel.strings"

# --- 2. and nothing in the file is unreachable -------------------------------
# A key with no call site is a string a translator will translate for nothing.
unused=0
while IFS= read -r key; do
  grep -qF "root.str(\"$key\"" "$PANEL" || {
    no "$key is in en.panel.strings but nothing in the panel asks for it"
    unused=$((unused + 1))
  }
done < <(sed -nE 's/^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=.*/\1/p' "$STRINGS" | sort -u)
((unused == 0)) && ok "every key in en.panel.strings is asked for by the panel"

# --- 3. the English in the file is the English at the call site --------------
# The fallback is what the panel shows when there is no locale, and the file
# is what an English desktop actually reads. If they drift, en is subtly not
# en, and it would take someone reading both files side by side to notice.
drift=0
while IFS=$'\t' read -r key english; do
  want="$(sed -nE "s/^[[:space:]]*${key//./\\.}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "$STRINGS")"
  [[ -z $want ]] && continue  # already reported by check 1
  if [[ $want != "$english" ]]; then
    no "$key: the call site's English and en.panel.strings disagree"
    printf '        file: %s\n        call: %s\n' "$want" "$english"
    drift=$((drift + 1))
  fi
done < <(grep -oE 'root\.str\("[^"]+", "[^"]*"\)' "$PANEL" |
  sed -E 's/root\.str\("([^"]+)", "(.*)"\)/\1\t\2/' | sort -u)
((drift == 0)) && ok "each fallback matches the English in en.panel.strings"

# --- 4. the dumper reaches all of it -----------------------------------------
dumped="$(strings_cmd panel | wc -l)"
declared="$(sed -nE 's/^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=.*/\1/p' "$STRINGS" | sort -u | wc -l)"
if [[ $dumped == "$declared" ]]; then
  ok "imthemousenow-strings panel dumps all $declared keys"
else
  no "imthemousenow-strings panel dumped $dumped of $declared keys"
fi

# --- 5. the two tables stay apart --------------------------------------------
# The split is the point: the panel's table must not drag the key sheet's
# sixty-odd strings along with it, or there was no reason to have two files.
if strings_cmd panel | grep -q '^help\.'; then
  no "the panel table leaked keys from the main table"
else
  ok "the panel table carries only its own keys"
fi
if strings_cmd | grep -q '^panel\.'; then
  no "the main table leaked keys from the panel table"
else
  ok "the main table carries only its own keys"
fi

# --- 6. quoting survives the trip --------------------------------------------
# Model.parseStrings reads shlex.quote()'s dialect, not bash's %q. An
# apostrophe is the case that tells them apart, and the panel has strings with
# em dashes and ellipses in them too.
line="$(strings_cmd panel | grep '^panel.row.edit.label=')"
if [[ $line == "panel.row.edit.label='Edit config…'" ]]; then
  ok "a value with no quote in it comes back single-quoted and unmangled"
else
  no "unexpected quoting for panel.row.edit.label: $line"
fi

apostrophe="$(env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$REPO" LANG="" \
  "$REPO/bin/imthemousenow-strings" | grep '^app.title=')"
if [[ $apostrophe == "app.title='I'\"'\"'m the mouse now'" ]]; then
  ok "an apostrophe is quoted the way shell/Model.js unquotes it"
else
  no "unexpected quoting for app.title: $apostrophe"
fi

# --- 7. a translated panel locale is actually read ---------------------------
# The whole point of the file being in locale/ next to the other one: copy,
# translate the right-hand sides, and the panel picks it up off LANG.
FAKE="$WORK/plugin"
mkdir -p "$FAKE/locale" "$FAKE/bin"
cp "$REPO/bin/imthemousenow-lib.sh" "$FAKE/bin/"
printf 'panel.title = "Zeiger"\n' >"$FAKE/locale/de.panel.strings"
got="$(env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$FAKE" LANG="de_DE.UTF-8" \
  "$REPO/bin/imthemousenow-strings" panel)"
if [[ $got == "panel.title='Zeiger'" ]]; then
  ok "LANG picks the panel table for that locale"
else
  no "a de panel table was not read: $got"
fi

# A locale with a panel file that translates one key and nothing else is not
# broken: the panel shows that key translated and English everywhere else,
# because the English lives at the call site. Nothing to assert in the dump
# beyond its being short -- the fallback happens in QML -- but a file that is
# missing entirely must still exit 0 and print nothing, or the panel would
# show an error where it should show English.
got="$(env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$FAKE" LANG="fr_FR.UTF-8" \
  "$REPO/bin/imthemousenow-strings" panel)"
rc=$?
if ((rc == 0)) && [[ -z $got ]]; then
  ok "a locale with no panel file prints nothing and succeeds"
else
  no "an untranslated locale should be silent and exit 0 (rc=$rc, out=$got)"
fi

echo
if ((failures)); then
  printf '%d failed\n' "$failures"
  exit 1
fi
echo "all good"
