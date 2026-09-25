#!/bin/bash
# Is the peek wired all the way through, and does it stay out of the way of a
# wl-kbptr that has never heard of it?
#
# Holding SPACE fades the overlay so the target under it can be read. The
# dimming itself is wl-kbptr's (the fork's "Dim the overlay while a key is held" commit) and is not testable from
# here; what is testable is everything that has to line up for the key to reach
# it, and every one of those fails silently or catastrophically:
#
#   - `general.peek_alpha` must be passed ONLY to a build that knows it. An
#     option wl-kbptr does not recognise makes it reject the whole config file
#     and exit before drawing anything, so getting this backwards does not
#     break the peek -- it breaks every chord, on every stock build, including
#     `mode = "aur"` in pkg/source.toml, which is unpatched by definition.
#   - it must therefore NOT be compiled into the config file, which is passed
#     through to wl-kbptr wholesale.
#   - in popup-safe mode the overlay has no keyboard, so SPACE has to be
#     relayed -- and relayed on RELEASE as well as press, or the first peek
#     never ends and the overlay stays faded until it is closed.
#   - only SPACE gets the release treatment; a second key relayed twice would
#     be typed twice.
#
# None of that shows up as an error. A missing release looks like a stuck
# overlay, and an ungated peek_alpha looks like a plugin that stopped working.
#
#   ./tests/peek.sh
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
mkdir -p "$XDG_RUNTIME_DIR" "$HOME"

config() { env MOUSENOW_PLUGIN_DIR="$REPO" "$REPO/bin/imthemousenow-config" "$@"; }

# --- 1. it is ours, not a passthrough ----------------------------------------
check "the shipped default is an [imthemousenow] setting" "$(config get peek_alpha)" "0.1"

compiled="$(config compile --force)"
if grep -q 'peek_alpha' "$compiled"; then
  no "and it is kept OUT of the compiled wl-kbptr config"
  printf '        %s\n' "$(grep -n peek_alpha "$compiled")"
else
  ok "and it is kept OUT of the compiled wl-kbptr config"
fi

# --- 2. the capability gate ---------------------------------------------------
# has_peek greps the wl-kbptr binary for the option name, because that is the
# only way to ask a build whether it carries one of our patches. The stub is a
# script, so whether the string is in it decides which build this pretends to
# be.
setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-locale.sh,-session.sh,-steer} "$WORK/plugin/bin/"
  printf '#!/bin/bash\n:\n' >"$WORK/plugin/bin/imthemousenow-osd"
  chmod +x "$WORK/plugin/bin/imthemousenow-osd"

  cat >"$WORK/stub/wl-kbptr" <<'STUB'
#!/bin/bash
case "${1:-}" in
  --version) echo "wl-kbptr 0.4.1 (opencv)"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$WORK/stub/wl-kbptr"

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
  chmod +x "$WORK/stub/hyprctl"
}

# The wl-kbptr command imthemousenow would run, as one line.
dry_run() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    "$WORK/plugin/bin/imthemousenow" --mode hints -n 2>/dev/null
}

setup
case "$(dry_run)" in
  *peek_alpha*) no "a build that does not know the option is not given it" ;;
  *) ok "a build that does not know the option is not given it" ;;
esac

# Same stub, now carrying the string a patched build would.
echo '# general.peek_alpha' >>"$WORK/stub/wl-kbptr"
case "$(dry_run)" in
  *"general.peek_alpha=0.1"*) ok "a build that does know it is given the configured value" ;;
  *) no "a build that does know it is given the configured value (got: $(dry_run))" ;;
esac

# --- 3. turning it off ---------------------------------------------------------
# 1 is how wl-kbptr itself spells off -- the overlay is already fully drawn --
# so there is nothing to pass, even to a build that would accept it.
mkdir -p "$HOME/.config/omarchy/imthemousenow"
printf '[imthemousenow]\npeek_alpha = 1.0\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
case "$(dry_run)" in
  *peek_alpha*) no "1.0 means off, so nothing is passed at all" ;;
  *) ok "1.0 means off, so nothing is passed at all" ;;
esac
config check >/dev/null 2>&1 && ok "and the config still validates" || no "and the config still validates"
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# --- 4. the relay binds both halves of SPACE ---------------------------------
# Load the real lua with a permissive `hl` stub -- anything it reaches for is a
# no-op function -- and then call the relay binder and look at what it asked
# for. Loading the whole file rather than a trimmed copy is the point: a relay
# that stopped being wired up at all would still pass a test that only read the
# one function.
cat >"$WORK/hlstub.lua" <<'LUA'
local recording = false
binds = {}

-- One value that answers to anything: indexing it or calling it gives it back.
local permissive = {}
setmetatable(permissive, {
  __index = function() return permissive end,
  __call = function() return permissive end,
})

hl = setmetatable({
  bind = function(key, _action, opts)
    if recording then
      table.insert(binds, key .. (opts and opts.release and " (release)" or " (press)"))
    end
  end,
}, { __index = function() return permissive end })

-- Hyprland's own globals (`o`, and whatever else the file reaches for at load
-- time) are stubbed the same way, so this test does not have to track which
-- ones the lua happens to use today.
setmetatable(_G, { __index = function() return permissive end })

dofile(os.getenv("LUA_UNDER_TEST"))

recording = true
imthemousenow_relay_bind("space")
imthemousenow_relay_bind("a")
for _, b in ipairs(binds) do print(b) end
LUA

# imthemousenow_relay_key appends to the key channel; point it at a disposable
# one rather than at the session's real one.
export XDG_RUNTIME_DIR="$WORK/run"

if ! command -v lua >/dev/null 2>&1; then
  printf 'skip  the relay binds (no lua interpreter)\n'
else
  got="$(LUA_UNDER_TEST="$REPO/hypr/imthemousenow-submap.lua" lua "$WORK/hlstub.lua" 2>&1)"
  case "$got" in
    *"space (press)"*) ok "space is relayed on press" ;;
    *) no "space is relayed on press (got: $got)" ;;
  esac
  case "$got" in
    *"space (release)"*) ok "and on release, so a peek can end" ;;
    *) no "and on release, so a peek can end (got: $got)" ;;
  esac
  case "$got" in
    *"a (release)"*) no "an ordinary label is relayed once only (got: $got)" ;;
    *) ok "an ordinary label is relayed once only" ;;
  esac
fi

# --- 5. the two lists that have to agree -------------------------------------
# bin/imthemousenow re-asserts dropped relay binds by name, so a space missing
# from its mirror is a peek that stops working after Hyprland drops a bind.
grep -q 'RELAY_KEYS=(.*\bspace\b' "$REPO/bin/imthemousenow" &&
  ok "bin/imthemousenow still mirrors space in RELAY_KEYS" ||
  no "bin/imthemousenow still mirrors space in RELAY_KEYS"

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"
