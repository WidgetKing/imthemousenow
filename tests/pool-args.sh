#!/bin/bash
# Is the click mark wired through, and does it fall back to the ring whenever
# it cannot be drawn?
#
# The mark itself -- LCD pooling where the click landed -- is quickshell's and
# needs a compositor and a pair of eyes (qml/PoolSpot.qml). What is testable is
# the handover, and it fails quietly either way round:
#
#   - wl-kbptr must never be passed the ring options it used to take. They are
#     gone from the fork, and an option it does not know takes every chord down.
#   - the colours must come from the theme, through the same config layers as
#     every other colour.
#
#   ./tests/pool-args.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1"; printf '        want: %s\n        got:  %s\n' "$3" "$2"; fi; }

# A session and a home of this test's own: every config layer hangs off HOME.
export XDG_RUNTIME_DIR="$WORK/run"
export HOME="$WORK/home"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME"

config() { env MOUSENOW_PLUGIN_DIR="$REPO" "$REPO/bin/imthemousenow-config" "$@"; }

mkdir -p "$WORK/plugin/bin" "$WORK/stub"
cp "$REPO/config.default.toml" "$WORK/plugin/"
cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-session.sh,-steer} "$WORK/plugin/bin/"
printf '#!/bin/bash\n:\n' >"$WORK/plugin/bin/imthemousenow-osd"
chmod +x "$WORK/plugin/bin/imthemousenow-osd"

# A build that knows double click but not the click report, to start with.
cat >"$WORK/stub/wl-kbptr" <<'STUB'
#!/bin/bash
# mode_click.double_click_ms
[[ ${1:-} == --version ]] && echo "wl-kbptr 0.4.1 (opencv)"
exit 0
STUB
printf '#!/bin/bash\n[[ $* == *double-click* ]] && echo 400\nexit 0\n' >"$WORK/stub/gsettings"
# Present, so the only thing deciding is the build. Never actually run: -n.
printf '#!/bin/bash\nexit 0\n' >"$WORK/stub/quickshell"
cat >"$WORK/stub/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  *monitors*) echo '[{"name":"DP-9","x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '{"at":[400,250],"size":[800,600],"address":"0xabc"}' ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$WORK/stub/"*

dry_run() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    "$WORK/plugin/bin/imthemousenow" --mode hints "$@" -n 2>/dev/null
}

# --- 1. wl-kbptr is never asked to draw a ring ---------------------------------
# The ring is gone from the fork; marking the click is this plugin's alone. An
# option for it passed now would be one wl-kbptr rejects, with every chord.
for build in "without" "with"; do
  [[ $build == with ]] && echo '# WL_KBPTR_CLICK_REPORT' >>"$WORK/stub/wl-kbptr"
  case "$(dry_run)" in
    *double_click_radius* | *double_click_color*) no "no ring options, $build the click report" ;;
    *) ok "no ring options, $build the click report" ;;
  esac
done
case "$(dry_run)" in
  *"double_click_ms=340"*) ok "the double-click window itself is untouched" ;;
  *) no "the double-click window itself is untouched" ;;
esac
mkdir -p "$HOME/.config/omarchy/imthemousenow"
printf '[imthemousenow.pool]\nenabled = false\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
config check >/dev/null 2>&1 && ok "pool.enabled = false validates" || no "pool.enabled = false validates"
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# --- 3b. style -------------------------------------------------------------------
check "the style defaults to random" "$(config get pool.style)" "random"
printf '[imthemousenow.pool]\nstyle = "cross"\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
check "and can be pinned to one" "$(config get pool.style)" "cross"
rm -f "$HOME/.config/omarchy/imthemousenow/config.toml"

# --- 4. colours ----------------------------------------------------------------
# No theme rendered in this HOME: the ACTION wheel stands in, and with nothing
# pinned there is no wheel either -- so pin one and look for it.
printf '[imthemousenow.action.left-click]\ncolor = "#ff8800"\n' >"$HOME/.config/omarchy/imthemousenow/config.toml"
colors="$(env MOUSENOW_PLUGIN_DIR="$REPO" bash -c "source '$REPO/bin/imthemousenow-lib.sh'; pool_colors")"
case "$colors" in
  "#ff8800 "*) ok "no theme: the ACTION wheel, left-click first" ;;
  *) no "no theme: the ACTION wheel, left-click first (got: $colors)" ;;
esac

# A rendered theme template is a layer like any other, and its six win.
mkdir -p "$HOME/.local/state/omarchy/current/theme"
printf '[imthemousenow.pool]\ncolors=#111111 #222222 #333333\nshade=#000001\n' \
  >"$HOME/.local/state/omarchy/current/theme/wl-kbptr.conf"
check "the theme's colours reach the mark" "$(config get pool.colors)" "#111111 #222222 #333333"
check "and its shade" "$(config get pool.shade)" "#000001"

# The template itself renders every name it uses from every shipped theme.
# A name a theme lacks is left in as `{{ ... }}` and the mark gets garbage.
if [[ -d /usr/share/omarchy/themes ]]; then
  missing=""
  for key in $(sed -n '/^\[imthemousenow.pool\]/,$p' "$REPO/templates/wl-kbptr.conf.tpl" |
    grep -o '{{ [a-z_]*_strip }}' | sed 's/{{ \(.*\)_strip }}/\1/' | sort -u); do
    for theme in /usr/share/omarchy/themes/*/colors.toml; do
      grep -q "^$key *=" "$theme" || missing+=" $(basename "$(dirname "$theme")"):$key"
    done
  done
  [[ -z $missing ]] && ok "every shipped theme has every colour the mark asks for" ||
    no "themes missing a colour the mark asks for:$missing"
fi

((fails == 0)) && echo "all passed" || { echo "$fails failed"; exit 1; }
