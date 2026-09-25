#!/bin/bash
# Is the intro passed to a wl-kbptr that can draw it, and kept away from one
# that cannot?
#
# The transition itself is the fork's ("Bring the overlay in through a
# transition") and is only seen on the compositor. What this checks is the
# gate: `general.intro` is an option a stock build has never heard of, and one
# unknown option makes it reject the whole config -- so passing it ungated
# would not break the intro, it would break every chord.
#
#   ./tests/intro.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# A session and a home of this test's own: every config layer hangs off HOME.
export XDG_RUNTIME_DIR="$WORK/run"
export HOME="$WORK/home"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME"

config() { env MOUSENOW_PLUGIN_DIR="$REPO" "$REPO/bin/imthemousenow-config" "$@"; }

compiled="$(config compile --force)"
if grep -q 'intro' "$compiled"; then
  no "the intro is kept OUT of the compiled wl-kbptr config"
else
  ok "the intro is kept OUT of the compiled wl-kbptr config"
fi

mkdir -p "$WORK/plugin/bin" "$WORK/stub"
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
cat >"$WORK/stub/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  *monitors*) echo '[{"name":"DP-9","x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '{"at":[400,250],"size":[800,600],"address":"0xabc"}' ;;
  *clients*|*binds*) echo '[]' ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$WORK/stub/wl-kbptr" "$WORK/stub/hyprctl"

dry_run() {
  env PATH="$WORK/stub:$PATH" MOUSENOW_PLUGIN_DIR="$WORK/plugin" \
    "$WORK/plugin/bin/imthemousenow" --mode hints -n 2>/dev/null
}

case "$(dry_run)" in
  *general.intro*) no "a build that does not know the intro is not given it" ;;
  *) ok "a build that does not know the intro is not given it" ;;
esac

# The stub now carries the string a build with the transition does.
echo '# general.intro_ms' >>"$WORK/stub/wl-kbptr"
case "$(dry_run)" in
  *"general.intro=random"*"general.intro_ms=250"*"general.intro_chunk=48"*) ok "a build that knows it is given the configured intro" ;;
  *) no "a build that knows it is given the configured intro (got: $(dry_run))" ;;
esac

mkdir -p "$HOME/.config/omarchy/imthemousenow"
for off in 'intro = "none"' 'intro_ms = 0'; do
  printf '[imthemousenow]\n%s\n' "$off" >"$HOME/.config/omarchy/imthemousenow/config.toml"
  case "$(dry_run)" in
    *general.intro*) no "$off means off, so nothing is passed" ;;
    *) ok "$off means off, so nothing is passed" ;;
  esac
  config check >/dev/null 2>&1 && ok "and the config still validates" || no "and the config still validates"
done

echo
if ((fails)); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"
