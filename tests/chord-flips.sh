#!/bin/bash
# Do the eight chords follow [imthemousenow.defaults]?
#
# They used to not. The keybindings named every axis outright
# (`imthemousenow --mode hints --scope window --lifetime single`), so the three
# defaults a user can set were read by nothing that a key press went through --
# the bar could write them, `imthemousenow-config env` would report them, and
# the chord would still open the overlay the lua had been compiled with. The
# only visible symptom was a settings panel that appeared to do nothing.
#
# So what is asserted here is the join: a config with non-default values on all
# three axes, and every chord's resolved MODE / SCOPE / LIFETIME read back out
# of --dry-run. A modifier flips its own axis and leaves the other two alone --
# which is only true if the base came from the config in the first place.
#
#   ./tests/chord-flips.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

export XDG_RUNTIME_DIR="$WORK/run"
export HOME="$WORK/home"
export MOUSENOW_PLUGIN_DIR="$WORK/plugin"
mkdir -p "$WORK/run" "$WORK/stub" "$WORK/plugin/bin" "$HOME/.config/omarchy/imthemousenow"

cp "$REPO/config.default.toml" "$WORK/plugin/"
cp "$REPO"/bin/imthemousenow{,-config,-lib.sh,-locale.sh,-session.sh,-steer} "$WORK/plugin/bin/"
printf '#!/bin/bash\n:\n' >"$WORK/plugin/bin/imthemousenow-osd"
chmod +x "$WORK/plugin/bin/imthemousenow-osd"

# Nothing is drawn: --dry-run prints the command instead of running it, and
# these two only have to answer the questions asked on the way there.
printf '#!/bin/bash\n[[ ${1:-} == --version ]] && echo "wl-kbptr 0.4.1"\nexit 0\n' >"$WORK/stub/wl-kbptr"
cat >"$WORK/stub/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  *monitors*) echo '[{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"focused":true}]' ;;
  *activewindow*) echo '{"at":[100,100],"size":[800,600],"address":"0xabc"}' ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$WORK/stub/wl-kbptr" "$WORK/stub/hyprctl"
export PATH="$WORK/stub:$PATH"

# Every axis the other way round from the shipped defaults, so a value that
# came from config.default.toml instead of here is visible as itself.
cat >"$HOME/.config/omarchy/imthemousenow/config.toml" <<'CONF'
[imthemousenow.defaults]
mode = "grid"
scope = "monitor"
lifetime = "continuous"
CONF

# --dry-run's first line is `# MODE / SCOPE / ACTION / LIFETIME`.
chord() {
  "$WORK/plugin/bin/imthemousenow" --dry-run "$@" 2>&1 |
    sed -n '1s/^# //p' |
    awk -F' / ' '{print $1, $2, $4}'
}

check() {
  local want="$1"; shift
  local got
  got="$(chord "$@")"
  if [[ $got == "$want" ]]; then
    printf 'ok   %-46s %s\n' "imthemousenow $*" "$got"
  else
    printf 'FAIL %-46s want [%s] got [%s]\n' "imthemousenow $*" "$want" "$got"
    ((failures++))
  fi
}

echo "== the bare chord is the config, flags and all =="
check "grid monitor continuous"

echo
echo "== one modifier moves one axis =="
check "grid window continuous"  --flip scope
check "hints monitor continuous" --flip mode
check "grid monitor single"     --flip lifetime

echo
echo "== and they compose =="
check "hints window continuous" --flip scope --flip mode
check "hints window single"     --flip lifetime --flip scope --flip mode

echo
echo "== an explicit flag still wins outright =="
check "hints monitor continuous" --mode hints
check "grid window single" --scope window --lifetime single

echo
echo "== a flip nobody can resolve is refused, not guessed =="
# Captured rather than piped: it exits non-zero, which is the point, and
# `set -o pipefail` would read that as the test itself having failed.
refusal="$("$WORK/plugin/bin/imthemousenow" --flip banana --dry-run 2>&1)"
if grep -q "does not know the axis" <<<"$refusal"; then
  printf 'ok   %s\n' "--flip banana is refused"
else
  printf 'FAIL %s\n' "--flip banana was not refused"
  ((failures++))
fi

echo
if ((failures)); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
