# The string tables, and the lookup every other file reaches them through.
# Sourced, never run.
#
# Its own file, rather than a section of imthemousenow-lib.sh, so that a
# reader which wants strings and nothing else can have them: sourcing the lib
# loads and validates the whole merged config, which bin/imthemousenow-strings
# -- run by the bar widget on every panel open -- has no use for. A broken
# config should cost you the setting you were changing, not the words the
# panel is drawn with.

PLUGIN_DIR="${PLUGIN_DIR:-${MOUSENOW_PLUGIN_DIR:-$HOME/.local/share/imthemousenow}}"

# --- localisation ---------------------------------------------------------
# Two string tables per locale, in one directory: `locale/<code>.strings` is
# everything bash draws, and `locale/<code>.panel.strings` is the bar widget's
# own chrome. Split because nothing ever needs both -- the panel is QML and
# reads its table through bin/imthemousenow-strings, while t() here is called
# on paths as hot as a keypress and has no business parsing sixty-odd panel
# keys to answer for one of its own. Same directory, same format, same locale
# rule, so a translator still copies a pair of files and edits only the
# right-hand sides.
#
# Flat `key = "value"`
# lines, TOML-flavoured like everything else here. `<code>` is the first
# underscore- or dot-delimited piece of LC_ALL, LC_MESSAGES or LANG in that
# order (LANG=de_DE.UTF-8 reads as de) -- the same precedence gettext uses --
# because the desktop's own locale is what every other piece of software on it
# is already keying off, and this plugin has no setting of its own to fall out
# of step with it.
#
# Every call site carries the English original as $2 too, so a locale
# missing this one key, a locale with no file at all, or a $PLUGIN_DIR too old
# to have a locale directory at all reads as the English rather than as a
# blank. Translation is additive: a half-finished locale shows English for
# the rest, never a missing string. locale/en.strings ships and is loaded
# like any other locale rather than being special-cased out of the lookup --
# that way `LANG=en_US.UTF-8` exercises the same file-read path a translator's
# locale will, instead of the fallback path being the only one ever tested.
declare -A _locale_strings
_locale_loaded=""

_locale_name() {
  local lc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  lc="${lc%%.*}"
  lc="${lc%%_*}"
  echo "${lc:-en}"
}

# Parse one `<code><suffix>.strings` file into the named associative array.
# The array is the caller's -- this only ever adds to it -- so a table that is
# missing, or a $PLUGIN_DIR too old to have a locale/ directory at all, leaves
# the caller with an empty table rather than an error. That is the whole
# fallback story: every lookup carries its own English.
_strings_read() {
  local file="$1" into="$2" line key value
  [[ -f $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*($|#) ]] && continue
    [[ $line =~ ^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]] || continue
    key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
    printf -v "$into[$key]" '%s' "$value"
  done <"$file"
}

# The path of one table for the running locale. $1 is the table: "" for the
# main one, "panel" for the bar widget's.
strings_file() {
  local table="${1-}"
  [[ -n $table ]] && table=".$table"
  printf '%s' "$PLUGIN_DIR/locale/$(_locale_name)$table.strings"
}

_locale_load() {
  local locale
  locale="$(_locale_name)"
  [[ $_locale_loaded == "$locale" ]] && return 0
  _locale_strings=()
  _strings_read "$(strings_file)" _locale_strings
  _locale_loaded="$locale"
}

# One string, by its dotted key, or $2 (the English original, written where
# it is used) when the running locale has no better answer.
t() {
  _locale_load
  local value="${_locale_strings[$1]-}"
  [[ -n $value ]] && printf '%s' "$value" || printf '%s' "${2-}"
}
