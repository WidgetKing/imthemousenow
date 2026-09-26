#!/bin/bash
# Do the bar widget's strings and locale/en.panel.strings still agree?
#
# The panel is QML and cannot call t(), so its words make a longer trip than
# anything else here: locale/<code>.panel.strings -> bin/imthemousenow-strings
# -> Model.parseStrings -> root.str(). Every step is covered below.
#
# What is being protected is the KEYS, and nothing about the English. The file
# is where the words live: rewording a row there is the point of it, and it
# takes effect everywhere the table loads, which is everywhere it works.
#
# A key is another matter. The panel carries no English of its own, so a key
# that stopped matching the file shows as the bracketed key name -- loud, but
# only once someone opens that tab. Checks 1 and 2 below are what catch it
# before that, in both directions: a row reaching for a key nobody wrote, and
# a key nobody reaches for.
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

# --- 3. no call site carries English of its own ------------------------------
# The panel has no fallbacks, on purpose. A second English at the call site is
# a second place to edit for every rename, and -- worse -- it hides the failure
# it exists for: a table that never loaded, or a key renamed on one side only,
# reads as a perfectly good English panel that no locale can ever reach. Now a
# missing string renders as the bracketed key and the panel says so.
#
# So a `root.str(key, "...")` creeping back in is a regression, not a style
# preference, and this is what sees it.
carried="$(grep -nE 'root\.str\("[^"]+",' "$PANEL" | head -5)"
if [[ -z $carried ]]; then
  ok "no call site carries an English fallback"
else
  no "a call site still carries English of its own:"
  printf '        %s\n' "$carried"
fi

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
#
# And, since the panel carries no English of its own any more, the table has to
# arrive WHOLE: English underneath, the locale over the top. A half-translated
# locale is the normal case, not an edge one -- every translation starts there
# -- and it must read as its own words where it has them and English
# everywhere else, not as bracketed key names.
FAKE="$WORK/plugin"
mkdir -p "$FAKE/locale" "$FAKE/bin"
cp "$REPO/bin/imthemousenow-lib.sh" "$REPO/bin/imthemousenow-locale.sh" "$FAKE/bin/"
printf 'panel.title = "Pointer"\npanel.tab.overlay = "Overlay"\n' >"$FAKE/locale/en.panel.strings"
printf 'panel.title = "Zeiger"\n' >"$FAKE/locale/de.panel.strings"

dump() {
  env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$FAKE" LANG="$1" \
    "$REPO/bin/imthemousenow-strings" panel
}

got="$(dump de_DE.UTF-8)"
if [[ $got == *"panel.title='Zeiger'"* ]]; then
  ok "LANG picks the panel table for that locale"
else
  no "a de panel table was not read: $got"
fi
if [[ $got == *"panel.tab.overlay='Overlay'"* ]]; then
  ok "a key that locale has not translated comes back in English"
else
  no "a half-translated locale dropped the untranslated key: $got"
fi

# Missing entirely is the same case with nothing translated, and reads the
# same way. There is no third behaviour to have: the panel would otherwise
# show bracketed key names to everyone whose language nobody has got to yet.
got="$(dump fr_FR.UTF-8)"
rc=$?
if ((rc == 0)) && [[ $got == *"panel.title='Pointer'"* && $got == *"panel.tab.overlay='Overlay'"* ]]; then
  ok "a locale with no panel file gets the English table"
else
  no "an untranslated locale should read as English (rc=$rc, out=$got)"
fi

# The one case that IS a fault, and the reason the panel may treat an empty
# table as one: no locale directory at all. A plugin directory this broken has
# no English to offer either, so nothing comes back and the caller says so.
rm -rf "$FAKE/locale"
got="$(dump en_GB.UTF-8)"
rc=$?
if ((rc == 0)) && [[ -z $got ]]; then
  ok "a plugin directory with no locale/ prints nothing and succeeds"
else
  no "a missing locale/ should be silent and exit 0 (rc=$rc, out=$got)"
fi

echo
if ((failures)); then
  printf '%d failed\n' "$failures"
  exit 1
fi
echo "all good"
