#!/bin/bash
# Is double click wired all the way through, and does it stay out of the way of
# a wl-kbptr that has never heard of it?
#
# The gesture itself -- commit a selection, press the committing key again,
# get a second click -- is wl-kbptr's (the fork's "Click twice when the committing key is pressed again" commit) and is not testable
# from here: it needs a compositor, an overlay and a keyboard. What IS testable
# is everything that has to line up for the key to reach it, and every one of
# those fails silently or catastrophically:
#
#   - `mode_click.double_click_*` must be passed ONLY to a build that knows
#     them. An option wl-kbptr does not recognise makes it reject the whole
#     config and exit before drawing anything, so getting this backwards does
#     not break double click -- it breaks every chord, on every stock build.
#   - they must therefore NOT be compiled into the config file, which is
#     passed through to wl-kbptr wholesale.
#   - only an ACTION with a `button` and `double_click = true` may arm it.
#     Arming `move`, `drag` or `hold` would hand a window to a selection that
#     never clicks, and the overlay would sit there holding the keyboard for
#     nothing.
#   - `ms = "system"` must resolve to a number, with the guard taken off it,
#     and must fall back to off -- not to a garbage window -- when gsettings
#     cannot answer.
#
# None of that shows up as an error. An ungated option looks like a plugin that
# stopped working; a window armed on `move` looks like an overlay that hangs.
#
#   ./tests/double-click.sh
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
check "the window is an [imthemousenow] setting" "$(config get double_click.ms)" "system"
check "left-click asks for it" "$(config get action.left-click.double_click)" "true"
check "right-click does not" "$(config get action.right-click.double_click)" "false"

compiled="$(config compile --force)"
if grep -q 'double_click' "$compiled"; then
  no "and none of it reaches the compiled wl-kbptr config"
  printf '        %s\n' "$(grep -n double_click "$compiled")"
else
  ok "and none of it reaches the compiled wl-kbptr config"
fi

# --- 2. the capability gate --------------------------------------------------
# has_double_click greps the wl-kbptr binary for the option name, because that
# is the only way to ask a build whether it carries one of our patches. The
# stub is a script, so whether the string is in it decides which build this
# pretends to be. gsettings is stubbed too: the window must not depend on what
# the tester's desktop happens to be set to.
setup() {
  rm -rf "$WORK/plugin" "$WORK/stub" "$WORK/run"
  mkdir -p "$WORK/plugin/bin" "$WORK/stub" "$WORK/run"
  cp "$REPO/config.default.toml" "$WORK/plugin/"
  cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-session.sh,-steer} "$WORK/plugin/bin/"
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

  # 400ms is the GNOME default, which makes the expected window 400 - 60.
  cat >"$WORK/stub/gsettings" <<'STUB'
#!/bin/bash
[[ $* == *double-click* ]] && echo 400
exit 0
STUB
  chmod +x "$WORK/stub/gsettings"

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
    "$WORK/plugin/bin/imthemousenow" "$@" -n 2>/dev/null
}

setup
case "$(dry_run --mode hints)" in
  *double_click*) no "a build that does not know the options is not given them" ;;
  *) ok "a build that does not know the options is not given them" ;;
esac

# Same stub, now carrying the string a patched build would.
knows() { echo '# mode_click.double_click_ms' >>"$WORK/stub/wl-kbptr"; }
knows

# --- 3. what gets armed, and with what ---------------------------------------
case "$(dry_run --mode hints)" in
  *"mode_click.double_click_ms=340"*) ok "hints + left-click gets the system window, less the guard" ;;
  *) no "hints + left-click gets the system window, less the guard (got: $(dry_run --mode hints))" ;;
esac
case "$(dry_run --mode grid)" in
  *"mode_click.double_click_ms=340"*) ok "and so does grid -- one gesture, both modes" ;;
  *) no "and so does grid -- one gesture, both modes" ;;
esac
# The window holds the overlay up after the click, and a continuous lifetime
# cannot put the next one up until it closes -- so a continuous lifetime only
# gets it from a build that can hand it on to the next overlay.
case "$(dry_run --mode hints --lifetime continuous)" in
  *"mode_click.double_click_ms=3"*) no "without the handoff, a continuous lifetime is not given the window" ;;
  *) ok "without the handoff, a continuous lifetime is not given the window" ;;
esac
echo '# --double-click-handoff' >>"$WORK/stub/wl-kbptr"
case "$(dry_run --mode hints --lifetime continuous)" in
  *"mode_click.double_click_ms=340"*"--double-click-handoff"*) ok "with it, continuous gets the window and hands it on" ;;
  *) no "with it, continuous gets the window and hands it on (got: $(dry_run --mode hints --lifetime continuous))" ;;
esac
case "$(dry_run --mode hints)" in
  *"--double-click-handoff"*) no "a single lifetime keeps its own window, with no handoff" ;;
  *) ok "a single lifetime keeps its own window, with no handoff" ;;
esac

# Nothing about how the window looks is wl-kbptr's any more: it draws nothing,
# and bin/imthemousenow-pool marks the click. The ring options it used to take
# are gone from the fork, and one passed now would be an unknown option -- which
# takes the whole config down, not just the ring.
mkdir -p "$HOME/.config/omarchy/imthemousenow"
printf '[imthemousenow.action.left-click]\ncolor = "#ff8800"\n' \
  >"$HOME/.config/omarchy/imthemousenow/config.toml"
case "$(dry_run --mode hints)" in
  *double_click_color* | *double_click_radius*) no "no ring option is passed, even with a colour to give it" ;;
  *) ok "no ring option is passed, even with a colour to give it" ;;
esac
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# --- 4. the actions that must NOT be armed -----------------------------------
# An action with no `button` never reaches mode_click at all; one with a button
# can still decline. Both have to come out the same way here.
for act in right-click move drag hold; do
  case "$(dry_run --action "$act")" in
    *double_click*) no "$act is not armed" ;;
    *) ok "$act is not armed" ;;
  esac
done

# --- 5. turning it off --------------------------------------------------------
mkdir -p "$HOME/.config/omarchy/imthemousenow"
printf '[imthemousenow.double_click]\nms = 0\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
case "$(dry_run --mode hints)" in
  *double_click*) no "ms = 0 means off, so nothing is passed at all" ;;
  *) ok "ms = 0 means off, so nothing is passed at all" ;;
esac

# A flat number is that many ms, with no guard taken off it: the guard exists to
# keep `system` under the desktop's own time, and a number typed here is already
# the answer.
printf '[imthemousenow.double_click]\nms = 250\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
case "$(dry_run --mode hints)" in
  *"mode_click.double_click_ms=250"*) ok "a number instead of 'system' is used as given" ;;
  *) no "a number instead of 'system' is used as given (got: $(dry_run --mode hints))" ;;
esac
config check >/dev/null 2>&1 && ok "and the config still validates" || no "and the config still validates"
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# --- 6. no gsettings, no window ----------------------------------------------
# Not an error: the chord still has to open. A desktop that cannot say what its
# double-click time is simply does not get the gesture.
printf '#!/bin/bash\nexit 1\n' >"$WORK/stub/gsettings"
case "$(dry_run --mode hints)" in
  *double_click*) no "a desktop that cannot answer turns it off rather than guessing" ;;
  *) ok "a desktop that cannot answer turns it off rather than guessing" ;;
esac
# ...and the overlay still opens, which is the thing that actually matters.
# `-n` quotes its argv the way a shell would, so the comma in the mode chain
# comes back escaped; match either side of it rather than the pair.
case "$(dry_run --mode hints)" in
  *"modes=floating"*"click"*) ok "and the chord still builds a working command" ;;
  *) no "and the chord still builds a working command (got: $(dry_run --mode hints))" ;;
esac

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"
