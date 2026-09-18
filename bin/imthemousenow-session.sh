# The state one overlay run shares with the keys pressed inside it. Sourced by
# imthemousenow (which owns the run) and imthemousenow-steer (which is what
# those keys invoke); never run on its own.
#
# wl-kbptr holds the keyboard, so every key that changes the overlay is a
# compositor binding firing a separate process. Files in $XDG_RUNTIME_DIR are
# how that process and the waiting run loop speak to each other. This module
# is the only place that knows their names, their defaults, and what it means
# for a run to be over.
#
#   session_begin <mode> <scope> <action>   start a run
#   session_get <field>                     a field, or its default
#   session_set <field> <value>             write a field
#   session_has <field>                     false when nothing has been written
#   session_active                          true while a run is live
#   session_end                             forget the run entirely
#
#   session_relaunch <reason>               ask the run loop to rebuild the overlay
#   session_take_relaunch                   consume that request; prints the reason
#   session_stamp_bind / session_recent_bind <ms>   chord-vs-tap debouncing
#
# Fields: mode, scope, action, base-action, switch, last-bind.

SESSION_DIR="${XDG_RUNTIME_DIR:-/tmp}/imthemousenow"

# Every field, and what it reads as before anything has written it. A caller
# that wants "the current action" must not have to know that it is left-click
# when no overlay is up -- that is this module's fact, not theirs.
_session_default() {
  case "$1" in
    mode) echo hints ;;
    scope) echo window ;;
    action | base-action) echo left-click ;;
    last-bind) echo 0 ;;
    switch) echo "" ;;
    *) die "no such session field '$1'" ;;
  esac
}

session_get() {
  local value
  value="$(cat "$SESSION_DIR/$1" 2>/dev/null || true)"
  [[ -n $value ]] && echo "$value" || _session_default "$1"
}

session_set() {
  mkdir -p "$SESSION_DIR"
  _session_default "$1" >/dev/null
  echo "$2" >"$SESSION_DIR/$1"
}

# Distinguishes "no overlay" from "an overlay whose scope happens to be the
# default". The keys that flip an axis must do nothing at all when no overlay
# is up, even though their binding only exists while one is.
session_has() {
  [[ -s $SESSION_DIR/$1 ]]
}

# True while a run is live. base-action is written once at the start of a run
# and cleared at its end, so it is the marker: the overlay's keys are bound
# only inside the submap, but a stray invocation must still change nothing.
session_active() {
  session_has base-action
}

session_begin() {
  mkdir -p "$SESSION_DIR"
  session_set mode "$1"
  session_set scope "$2"
  session_set action "$3"
  session_set base-action "$3"
  rm -f "$SESSION_DIR/switch" "$SESSION_DIR/last-bind"
}

# Every field goes, action included: a run that is over must leave nothing a
# later one could read back. Teardown lived in two hand-written lists before
# this and they had already drifted apart.
session_end() {
  rm -f "$SESSION_DIR"/{mode,scope,action,base-action,switch,last-bind}
}

# Ask the run loop to tear the overlay down and put it back up. $1 says why,
# which is all the loop needs to know whether the world moved under it.
session_relaunch() {
  session_set switch "$1"
  pkill -x wl-kbptr >/dev/null 2>&1 || true
}

# True when a relaunch was requested, printing its reason. Consumes it, so the
# loop cannot act on the same request twice.
session_take_relaunch() {
  session_has switch || return 1
  local reason
  reason="$(session_get switch)"
  rm -f "$SESSION_DIR/switch"
  echo "${reason:-action}"
}

# Record that one of our submap binds just fired, for session_recent_bind to
# find. Only the non-modifier binds stamp: two SHIFT taps in a row are a toggle
# and a toggle back, which must not debounce each other.
session_stamp_bind() {
  session_set last-bind $(($(date +%s%N) / 1000000))
}

# True when another of our submap binds fired within $1 milliseconds, which
# means a modifier release is the tail of a chord rather than a tap of its own.
session_recent_bind() {
  # A relaunch already in flight means a chord fired and the overlay has not
  # come back yet -- the SHIFT being released is that chord's, however long it
  # was held. This is what catches `:` when the debounce window has passed.
  session_has switch && return 0
  session_has last-bind || return 1
  local stamp now
  stamp="$(session_get last-bind)"
  now=$(($(date +%s%N) / 1000000))
  ((now - stamp < $1))
}
