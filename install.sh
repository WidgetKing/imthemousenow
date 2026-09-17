#!/bin/bash
# Install the omarchy-kbptr plugin. Idempotent: safe to re-run after edits.
#
#   ./install.sh            copy this checkout into place
#   ./install.sh --dev      symlink it instead, so edits here are live
#   ./install.sh --no-build skip building wl-kbptr (wire up integration only)
#   ./install.sh --lite     build without OpenCV (drops the `detect` preset)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.local/share/omarchy-kbptr"
BIN_DIR="$HOME/.local/bin"
USER_DIR="$HOME/.config/omarchy/kbptr"
STATE_DIR="$HOME/.local/state/omarchy-kbptr"
THEMED_DIR="$HOME/.config/omarchy/themed"
HOOKS_DIR="$HOME/.config/omarchy/hooks"
HYPR_ENTRY="$HOME/.config/hypr/hyprland.lua"
MARKER="-- omarchy-kbptr (managed by install.sh; remove with uninstall.sh)"
REQUIRE_LINE='require("omarchy.plugins.kbptr.hypr.kbptr")'

dev=0 build=1 lite=0
while (($#)); do
  case "$1" in
    --dev) dev=1 ;;
    --no-build) build=0 ;;
    --lite) lite=1 ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$1" >&2; }

link_or_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  if ((dev)); then ln -s "$src" "$dst"; else cp -r "$src" "$dst"; fi
}

mkdir -p "$PLUGIN_DIR" "$BIN_DIR" "$USER_DIR" "$STATE_DIR" "$THEMED_DIR"

# --- 1. wl-kbptr itself -------------------------------------------------------
if ((build)); then
  eval "$(awk -F'=' '
    /^[[:space:]]*(mode|commit|opencv)[[:space:]]*=/ {
      key = $1; gsub(/[[:space:]]/, "", key)
      val = $2; sub(/#.*/, "", val); gsub(/[[:space:]"]/, "", val)
      printf "SRC_%s=%s\n", toupper(key), val
    }' "$REPO/pkg/source.toml")"
  ((lite)) && SRC_OPENCV=false

  if [[ ${SRC_MODE:-commit} == aur ]]; then
    say "Installing wl-kbptr from the AUR"
    warn "The AUR package is 0.4.1, which does not build against opencv 5."
    omarchy pkg aur add wl-kbptr
  else
    say "Building wl-kbptr at ${SRC_COMMIT:0:9} (opencv=${SRC_OPENCV})"
    for dep in git meson ninja; do
      command -v "$dep" >/dev/null 2>&1 || missing+=" $dep"
    done
    if [[ -n ${missing:-} ]]; then
      say "Installing build dependencies:$missing"
      omarchy pkg add $missing
    fi

    build_dir="$(mktemp -d)"
    trap 'rm -rf "$build_dir"' EXIT
    cp "$REPO/pkg/PKGBUILD" "$build_dir/"
    (
      cd "$build_dir"
      KBPTR_COMMIT="$SRC_COMMIT" \
        KBPTR_OPENCV="$([[ $SRC_OPENCV == true ]] && echo 1 || echo 0)" \
        makepkg -si --noconfirm
    )
    echo "$SRC_COMMIT" >"$STATE_DIR/commit"
  fi
  touch "$STATE_DIR/installed"

  # Verify what we actually got, and fall back rather than ship a broken preset.
  if [[ ${SRC_OPENCV:-true} == true ]] && ! wl-kbptr --version 2>&1 | grep -qi opencv; then
    warn "This build has no OpenCV support; the 'detect' preset will refuse to run."
    warn "Re-run with --lite to make that the intended configuration."
  fi
fi

command -v wl-kbptr >/dev/null 2>&1 ||
  warn "wl-kbptr is not on PATH yet -- integration installed, but nothing will launch."

# --- 2. plugin files ----------------------------------------------------------
say "Installing plugin files ($( ((dev)) && echo symlinked || echo copied ))"
for item in bin presets.toml hypr; do
  link_or_copy "$REPO/$item" "$PLUGIN_DIR/$item"
done

for script in omarchy-kbptr omarchy-kbptr-regions; do
  ln -sfn "$PLUGIN_DIR/bin/$script" "$BIN_DIR/$script"
done

# The Hyprland module is required by module path, so it must live under
# ~/.config/omarchy/plugins/kbptr/ regardless of where the rest goes.
link_or_copy "$REPO/hypr" "$HOME/.config/omarchy/plugins/kbptr/hypr"

# --- 3. theme template --------------------------------------------------------
link_or_copy "$REPO/templates/wl-kbptr.conf.tpl" "$THEMED_DIR/wl-kbptr.conf.tpl"

# --- 4. hooks -----------------------------------------------------------------
for hook in theme-set font-set post-update; do
  mkdir -p "$HOOKS_DIR/$hook.d"
  link_or_copy "$REPO/hooks/$hook" "$HOOKS_DIR/$hook.d/kbptr.hook"
done

# --- 5. Hyprland include ------------------------------------------------------
if ! grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY"; then
  say "Adding the Hyprland include to hyprland.lua"
  cp "$HYPR_ENTRY" "$HYPR_ENTRY.bak.$(date +%s)"
  printf '\n%s\n%s\n' "$MARKER" "$REQUIRE_LINE" >>"$HYPR_ENTRY"
fi

# --- 6. apply -----------------------------------------------------------------
say "Rendering the theme template"
omarchy theme set "$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo)" >/dev/null 2>&1 ||
  warn "Could not re-apply the theme; run 'omarchy theme set <name>' to render wl-kbptr.conf."

hyprctl reload >/dev/null 2>&1 || true
errors="$(hyprctl configerrors 2>/dev/null | grep -v "^no errors" | grep -v "^[[:space:]]*$" || true)"
if [[ -n $errors ]]; then
  warn "Hyprland reported config errors:"
  echo "$errors" >&2
fi

say "Done. Try: omarchy-kbptr quick   (or SUPER + ;)"
((dev)) && say "Dev mode: edits in $REPO are live. Re-run only after changing install.sh itself."
exit 0
