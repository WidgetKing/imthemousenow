#!/bin/bash
# When wl-kbptr refuses to start, does anybody find out?
#
# This is the plugin's worst failure and was its quietest: wl-kbptr rejects a
# config it does not recognise outright, so one unknown key -- or one value the
# installed build no longer has, an `intro` transition removed from the fork
# being the usual way -- stops every chord rather than the one feature it names.
# It says so on stderr, and the wrapper runs from a keybinding, so stderr goes
# nowhere. The keys simply stopped working.
#
# So: an `err:` line has to become a notification, that notification has to be
# clickable through to an agent with the facts, and none of it may fire on the
# ordinary way out (Escape, which also exits nonzero, and the `info:` and
# `warn:` lines a perfectly good run prints).
#
#   ./tests/launch-failure.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
has() { if [[ $2 == *"$3"* ]]; then ok "$1"; else no "$1"; printf '        wanted to find: %s\n        in: %s\n' "$3" "$2"; fi; }
hasnt() { if [[ $2 != *"$3"* ]]; then ok "$1"; else no "$1"; printf '        did not want: %s\n        in: %s\n' "$3" "$2"; fi; }

# A home and a runtime dir of this test's own: every config layer hangs off
# HOME, and without it this reads whichever settings the tester happens to have.
export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME/.config/omarchy/imthemousenow" "$XDG_RUNTIME_DIR" "$WORK/stub"

SENT="$WORK/sent"
LOG="$WORK/launch-log"

# Stands in for both halves of the toast: the sender records its argv, one
# argument per line, so what is asserted is the vector rather than a string that
# a shell might have re-split. omarchy-agent only has to exist -- whether it is
# there is what decides between a clickable toast and a plain one.
cat >"$WORK/stub/omarchy-notification-send" <<STUB
#!/bin/bash
printf '%s\n' "\$@" >>"$SENT"
STUB
printf '#!/bin/bash\n:\n' >"$WORK/stub/omarchy-agent"
chmod +x "$WORK/stub/omarchy-notification-send" "$WORK/stub/omarchy-agent"

# What wl-kbptr says when it will not start, colours and all: they are in the
# real output, and a notification body with escape codes in it is a bug.
printf 'info: Loading config file\nerr: \x1b[31mInvalid transition '\''squeeze'\''. Should be...\x1b[0m\n' >"$LOG"

# notify_launch_failure, called the way the wrapper calls it, with the lib's own
# PATH-found helpers stubbed out from under it.
fire() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$REPO" bash -c '
    source "$MOUSENOW_PLUGIN_DIR/bin/imthemousenow-session.sh"
    source "$MOUSENOW_PLUGIN_DIR/bin/imthemousenow-lib.sh"
    notify_launch_failure "$1" "$2"
  ' _ "$@"
}

: >"$SENT"
fire "Overlay did not open" "$LOG"
sent="$(cat "$SENT")"

has "a rejected config is announced" "$sent" "Overlay did not open"
has "at critical urgency, because every chord is down" "$sent" "critical"
has "the body says what wl-kbptr actually objected to" "$sent" "Invalid transition 'squeeze'"
has "and offers the click" "$sent" "click to diagnose with AI"
hasnt "without wl-kbptr's escape codes" "$sent" $'\x1b'
has "the click runs the diagnose script" "$sent" "imthemousenow-diagnose"
has "and is handed the log to read" "$sent" "$LOG"
# --exec consumes the rest of the line, so anything after it would be argv for
# the click command rather than options for the toast.
if [[ "$(grep -c -- '^--exec$' "$SENT")" == 1 ]] &&
  [[ "$(sed -n '/^--exec$/,$p' "$SENT" | sed -n '2p')" == "$REPO/bin/imthemousenow-diagnose" ]]; then
  ok "--exec comes last, with the command as separate words"
else
  no "--exec comes last, with the command as separate words"
  sed 's/^/        /' "$SENT"
fi

# `notify = false` means no notifications. Not "except the important one": a
# person who turned them off did so knowing what they were turning off.
: >"$SENT"
printf '[imthemousenow]\nnotify = false\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
fire "Overlay did not open" "$LOG"
if [[ ! -s $SENT ]]; then ok "notify = false is honoured even here"; else no "notify = false is honoured even here"; fi
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# No agent to click through to: still a toast, and still says where the facts
# are, because the log is the same facts by hand.
: >"$SENT"
fire_no_agent() {
  env MOUSENOW_AGENT_CMD="imthemousenow-no-such-agent" PATH="$WORK/stub:$PATH" \
    MOUSENOW_PLUGIN_DIR="$REPO" bash -c '
      source "$MOUSENOW_PLUGIN_DIR/bin/imthemousenow-session.sh"
      source "$MOUSENOW_PLUGIN_DIR/bin/imthemousenow-lib.sh"
      notify_launch_failure "$1" "$2"
    ' _ "$@"
}
fire_no_agent "Overlay did not open" "$LOG"
sent="$(cat "$SENT")"
has "with no agent installed, the toast still goes out" "$sent" "Overlay did not open"
has "and points at the log instead of a click" "$sent" "$LOG"
hasnt "and does not promise a diagnosis it cannot give" "$sent" "diagnose with AI"

# --- the prompt -------------------------------------------------------------
# --print: the prompt written out rather than handed to an agent. The same thing
# a machine with no agent installed gets, so this is the prompt itself under
# test, not a stand-in for it.
prompt="$(env MOUSENOW_PLUGIN_DIR="$REPO" \
  "$REPO/bin/imthemousenow-diagnose" --print "$LOG" "Overlay did not open" 2>&1)"

has "the prompt carries the error" "$prompt" "Invalid transition 'squeeze'"
hasnt "and not its escape codes" "$prompt" $'\x1b'
has "says which config layers there are" "$prompt" "config.local"
has "and which file the user's own settings are in" "$prompt" ".config/omarchy/imthemousenow/config.toml"
has "warns that a rejected config stops everything" "$prompt" "stops every keybinding"
has "and that config.local is applied last" "$prompt" "applied after everything else"

# A log that is gone -- the runtime directory is cleared on reboot, and the
# toast outlives it. It must say so rather than hand an agent an empty prompt.
out="$(env MOUSENOW_PLUGIN_DIR="$REPO" \
  "$REPO/bin/imthemousenow-diagnose" --print "$WORK/no-such-log" 2>&1)"
if (($? != 0)) || [[ $out == *"no such log"* ]]; then
  ok "a log that is gone says so"
else
  no "a log that is gone says so"
  printf '        %s\n' "$out"
fi

((fails == 0)) && echo && echo "all checks passed" || { echo; echo "$fails failed"; }
exit $((fails > 0))
