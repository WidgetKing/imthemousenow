#!/bin/bash
# Does t() pick a locale off the environment, translate what that locale's
# file has, and fall back to the English at the call site for everything it
# does not?
#
# This is the whole localisation mechanism in one file: a translator only
# ever edits a `locale/<code>.strings`, never the scripts that call t(), so
# what has to hold is that a partial locale (missing this key, or missing the
# file entirely) never shows a blank -- it shows the English right there in
# the call, which is also what a from-scratch install with no locale/
# directory at all falls back to.
#
#   ./tests/locale.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A home and a plugin directory of this test's own: LANG below must not pick
# up a real translation the tester happens to have installed, and a home with
# no config.toml keeps every setting at its shipped default.
export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$WORK/plugin/bin" "$WORK/plugin/locale"
cp "$REPO/config.default.toml" "$WORK/plugin/"
cp "$REPO/bin/imthemousenow-config" "$WORK/plugin/bin/"

failures=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
check() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1"; printf '        want: %s\n        got:  %s\n' "$3" "$2"; fi; }

lib() {
  env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$WORK/plugin" LANG="${TEST_LANG:-}" \
    /usr/bin/bash -c "source '$REPO/bin/imthemousenow-lib.sh'; $1"
}

# --- 1. no locale file at all: every key reads as its own default -------------
# LANG unset resolves to en, and this test's plugin directory (unlike the real
# one) ships no locale/ at all, so this is the "nothing to load" path.
TEST_LANG=""
check "an unset locale reads as the default given at the call" \
  "$(lib 't help.section.aim Aim')" "Aim"
check "an arbitrary key with no translation reads as the default given at the call" \
  "$(lib 't some.key "a default"')" "a default"

# --- 2. a locale with a real file --------------------------------------------
cat >"$WORK/plugin/locale/xx.strings" <<'STRINGS'
# a stand-in locale, not a real language
help.section.aim = "Vise"
STRINGS

TEST_LANG="xx_XX.UTF-8"
check "LANG's first component picks the locale file" \
  "$(lib 't help.section.aim Aim')" "Vise"
check "a key the locale does not have still falls back to the call's default" \
  "$(lib 't help.section.out Out')" "Out"

TEST_LANG="xx"
check "a bare LANG (no territory or encoding) works the same way" \
  "$(lib 't help.section.aim Aim')" "Vise"

# --- 3. modifiers_label() goes through the same table -------------------------
cat >>"$WORK/plugin/locale/xx.strings" <<'STRINGS'
modifiers.ctrl = "Strg + "
STRINGS
TEST_LANG="xx_XX.UTF-8"
check "a translated modifier prefix reaches modifiers_label" \
  "$(lib 'modifiers_label ctrl')" "Strg + "
check "an untranslated one still falls back to English" \
  "$(lib 'modifiers_label alt')" "Alt + "

# --- 4. the key sheet itself picks it up too -----------------------------------
help_sheet() {
  env -u LC_ALL -u LC_MESSAGES MOUSENOW_PLUGIN_DIR="$WORK/plugin" LANG="${TEST_LANG:-}" \
    "$REPO/bin/imthemousenow-help" --print --scope monitor --mode hints \
    --action left-click --lifetime single
}
TEST_LANG="xx_XX.UTF-8"
titles="$(help_sheet | jq -r '[.sections[].title] | join(" | ")')"
if [[ $titles == *"Vise"* ]]; then
  ok "the sheet's Aim section is drawn translated"
else
  no "the sheet's Aim section is drawn translated"
  printf '        titles: %s\n' "$titles"
fi

TEST_LANG=""
titles="$(help_sheet | jq -r '[.sections[].title] | join(" | ")')"
if [[ $titles == *"Aim"* && $titles != *"Vise"* ]]; then
  ok "and back in English with no locale selected"
else
  no "and back in English with no locale selected"
  printf '        titles: %s\n' "$titles"
fi

echo
if ((failures)); then
  echo "$failures failing"
  exit 1
fi
echo "all good"
