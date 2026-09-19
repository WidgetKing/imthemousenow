#!/bin/bash
# Install the imthemousenow plugin. Idempotent: safe to re-run after edits.
#
#   ./install.sh            copy this checkout into place
#   ./install.sh --dev      symlink it instead, so edits here are live
#   ./install.sh --no-build skip building wl-kbptr (wire up integration only)
#   ./install.sh --rebuild  rebuild wl-kbptr even if this build is already installed
#   ./install.sh --lite     build without OpenCV (hints fall back to window rects)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.local/share/imthemousenow"
BIN_DIR="$HOME/.local/bin"
USER_DIR="$HOME/.config/omarchy/imthemousenow"
SHELL_PLUGIN_DIR="$HOME/.config/omarchy/plugins/imthemousenow"
STATE_DIR="$HOME/.local/state/imthemousenow"
THEMED_DIR="$HOME/.config/omarchy/themed"
HOOKS_DIR="$HOME/.config/omarchy/hooks"
HYPR_ENTRY="$HOME/.config/hypr/hyprland.lua"
MARKER="-- imthemousenow (managed by install.sh; remove with uninstall.sh)"
REQUIRE_LINE='require("omarchy.plugins.imthemousenow.hypr.imthemousenow")'

dev=0 build=1 lite=0 rebuild=0
while (($#)); do
  case "$1" in
    --dev) dev=1 ;;
    --no-build) build=0 ;;
    --rebuild) rebuild=1 ;;
    --lite) lite=1 ;;
    -h | --help) sed -n '2,11p' "$0" | sed 's/^# \?//'; exit 0 ;;
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
# What identifies a build: the upstream commit, the patch set applied to it, and
# whether OpenCV is in. Change any one of those and the installed binary is a
# different program, so all three are recorded and compared. The patch set is
# the reason this is not just the commit -- a new patch against an unmoved pin
# is the normal way this repo changes wl-kbptr, and it has to force a rebuild.
build_id() { printf '%s %s opencv=%s\n' "$1" "$2" "$3"; }
PATCH_STAMP="$("$REPO/pkg/patch-stamp" "$REPO/pkg")"

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
    warn "It is also unpatched: the popup fix in pkg/*.patch is not in it."
    omarchy pkg aur add wl-kbptr
    build_id aur - "${SRC_OPENCV:-true}" >"$STATE_DIR/build-id"
  else
    [[ -n ${SRC_COMMIT:-} ]] || { warn "pkg/source.toml has no commit to build"; exit 1; }
    want="$(build_id "$SRC_COMMIT" "$PATCH_STAMP" "$SRC_OPENCV")"
    have="$(cat "$STATE_DIR/build-id" 2>/dev/null || echo)"

    # Re-running install.sh after editing the bash or the Lua is the common
    # case, and it should not cost a compile. Skipping is only safe when the
    # binary that build id describes is still there and still links.
    skip=0
    if ((rebuild == 0)) && [[ $want == "$have" ]] &&
      pacman -Qq wl-kbptr-omarchy >/dev/null 2>&1 &&
      command -v wl-kbptr >/dev/null 2>&1 &&
      ! ldd "$(command -v wl-kbptr)" 2>/dev/null | grep -q "not found"; then
      skip=1
    fi

    if ((skip)); then
      say "wl-kbptr ${SRC_COMMIT:0:9} ($PATCH_STAMP) is already installed; skipping the build (--rebuild forces it)"
    else
      say "Building wl-kbptr at ${SRC_COMMIT:0:9} with $PATCH_STAMP (opencv=${SRC_OPENCV})"
      for dep in git meson ninja; do
        command -v "$dep" >/dev/null 2>&1 || missing+=" $dep"
      done
      if [[ -n ${missing:-} ]]; then
        say "Installing build dependencies:$missing"
        omarchy pkg add $missing
      fi

      build_dir="$(mktemp -d)"
      trap 'rm -rf "$build_dir"' EXIT
      # patch-stamp goes along: PKGBUILD calls it to build pkgver, and it must
      # see the same patches makepkg is about to apply, not this checkout's.
      cp "$REPO/pkg/PKGBUILD" "$REPO/pkg/patch-stamp" "$REPO"/pkg/*.patch "$build_dir/"
      (
        cd "$build_dir"
        MOUSENOW_COMMIT="$SRC_COMMIT" \
          MOUSENOW_OPENCV="$([[ $SRC_OPENCV == true ]] && echo 1 || echo 0)" \
          makepkg -si --noconfirm
      )
      # After the build, not before: a failed build must leave the id of what
      # is actually installed, or the next run would skip a build that never
      # happened.
      echo "$want" >"$STATE_DIR/build-id"
      echo "$SRC_COMMIT" >"$STATE_DIR/commit"
    fi
  fi
  touch "$STATE_DIR/installed"

  # Verify what we actually got, and fall back rather than ship a broken mode.
  if [[ ${SRC_OPENCV:-true} == true ]] && ! wl-kbptr --version 2>&1 | grep -qi opencv; then
    warn "This build has no OpenCV support; hints will label windows instead of detecting targets."
    warn "Re-run with --lite to make that the intended configuration."
  fi
else
  # --no-build with a stale binary is how the wrapper ends up newer than the
  # thing it drives -- and a wl-kbptr option the installed build does not know
  # makes it reject the whole config file, so every chord silently dies. Say so
  # here rather than leaving it to be discovered at the first keypress.
  have="$(cat "$STATE_DIR/build-id" 2>/dev/null || echo)"
  if [[ -n $have && $have != *" $PATCH_STAMP "* ]]; then
    warn "Installed wl-kbptr was built from a different patch set ($have)."
    warn "This checkout is at $PATCH_STAMP. Re-run without --no-build to rebuild."
  fi
fi

command -v wl-kbptr >/dev/null 2>&1 ||
  warn "wl-kbptr is not on PATH yet -- integration installed, but nothing will launch."

# --- 2. plugin files ----------------------------------------------------------
# Everything this script owns inside PLUGIN_DIR. Named as a list rather than
# copied item by item, because it is also the answer to "what should NOT be in
# there": a file this repo has since deleted or renamed stays installed forever
# otherwise, and the scripts resolve their siblings by path. A `presets.toml`
# from an old version lived on that way for several releases.
MANAGED=(bin config.default.toml hypr qml shell)

say "Installing plugin files ($( ((dev)) && echo symlinked || echo copied ))"
if [[ -d $PLUGIN_DIR ]]; then
  for stale in "$PLUGIN_DIR"/*; do
    [[ -e $stale || -L $stale ]] || continue
    name="${stale##*/}"
    for item in "${MANAGED[@]}"; do
      [[ $name == "$item" ]] && continue 2
    done
    say "Removing $name, which this version no longer installs"
    rm -rf "$stale"
  done
fi

for item in "${MANAGED[@]}"; do
  link_or_copy "$REPO/$item" "$PLUGIN_DIR/$item"
done

for script in imthemousenow imthemousenow-steer imthemousenow-regions imthemousenow-panic imthemousenow-config imthemousenow-osd imthemousenow-help imthemousenow-menu; do
  ln -sfn "$PLUGIN_DIR/bin/$script" "$BIN_DIR/$script"
done

# The Hyprland module is required by module path, so it must live under
# ~/.config/omarchy/plugins/imthemousenow/ regardless of where the rest goes.
# The bar widget has to be there too, and at the ROOT of it: the shell finds a
# third-party plugin by walking ~/.config/omarchy/plugins/<id>/ for a
# manifest.json, and takes the directory name as the id. So the two things
# share one directory -- `hypr/` is not in the manifest and the shell ignores
# it, and the require() path is not the shell's business.
for item in manifest.json Panel.qml Model.js; do
  link_or_copy "$REPO/shell/$item" "$SHELL_PLUGIN_DIR/$item"
done
link_or_copy "$REPO/hypr" "$SHELL_PLUGIN_DIR/hypr"

# --- 2b. the ACTION announcement ---------------------------------------------
# Nothing to install: it draws through quickshell, which the `omarchy` package
# depends on directly. Checked rather than assumed, because a missing one is a
# feature that silently never appears -- osd_action() skips when the tool cannot
# run, so the plugin stays fully usable either way.
"$REPO/bin/imthemousenow-osd" --self-test >/dev/null 2>&1 ||
  warn "The ACTION announcement is unavailable (no quickshell?); set osd.enabled = false to silence this."

# --- 3. theme template --------------------------------------------------------
link_or_copy "$REPO/templates/wl-kbptr.conf.tpl" "$THEMED_DIR/wl-kbptr.conf.tpl"

# --- 4. hooks -----------------------------------------------------------------
for hook in theme-set font-set post-update; do
  mkdir -p "$HOOKS_DIR/$hook.d"
  link_or_copy "$REPO/hooks/$hook" "$HOOKS_DIR/$hook.d/imthemousenow.hook"
done

# --- 5. Hyprland include ------------------------------------------------------
if ! grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY"; then
  say "Adding the Hyprland include to hyprland.lua"
  cp "$HYPR_ENTRY" "$HYPR_ENTRY.bak.$(date +%s)"
  printf '\n%s\n%s\n' "$MARKER" "$REQUIRE_LINE" >>"$HYPR_ENTRY"
fi

# --- 5b. the bar widget -------------------------------------------------------
# The settings used to be rows merged into the one user menu file Omarchy's
# shell reads. A menu row can only ever be a toggle or a pick-one-of-N, so
# opacity was three presets pretending to be a range and every real number was
# behind "Edit Config...". The bar has sliders, so the settings live there now
# -- in a widget beside the ones for sound, Wi-Fi and battery, which is where
# someone looks for a setting they can see.
#
# Take the old rows back out first. They are still in the user's file from an
# earlier install, and left there they would point at a menu that no longer
# has anything to say. Only what is between our markers; the rest of that file
# is the user's, and may be every other plugin's too.
if [[ -x "$PLUGIN_DIR/bin/imthemousenow-menu" ]]; then
  "$PLUGIN_DIR/bin/imthemousenow-menu" remove ||
    warn "Could not remove the old Omarchy menu rows; run 'imthemousenow-menu remove' to see why."
fi

# The shell only re-walks the plugin directories when asked, and only puts a
# widget on the bar when its id is in shell.json. Both are its own commands,
# and both are no-ops on the second run. A shell that is not up yet is not an
# error: it discovers the plugin at startup either way, and `omarchy plugin
# enable` is the only part that has to wait.
if command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  if ! omarchy-shell shell listPlugins 2>/dev/null | grep -q '"id"[[:space:]]*:[[:space:]]*"imthemousenow"'; then
    warn "The shell did not pick up the bar widget; run 'omarchy-shell shell rescanPlugins'."
  elif ! grep -q '"imthemousenow"' "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
    say "Adding the Pointer widget to the bar"
    omarchy plugin enable imthemousenow --section right >/dev/null 2>&1 ||
      warn "Could not add the widget to the bar; run 'omarchy plugin enable imthemousenow --section right'."
  fi
else
  say "The shell is not running; the Pointer widget appears when it next starts."
  say "Then: omarchy plugin enable imthemousenow --section right"
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

# Fail loudly here rather than at the first keypress.
if ! "$PLUGIN_DIR/bin/imthemousenow-config" check >/dev/null; then
  warn "The config did not validate; see the errors above."
fi

say "Done. Try: SUPER + ;   (or: imthemousenow)"
((dev)) && say "Dev mode: edits in $REPO are live. Re-run only after changing install.sh itself."
exit 0
