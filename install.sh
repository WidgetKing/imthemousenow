#!/bin/bash
# Install the imthemousenow plugin. Idempotent: safe to re-run after edits.
#
#   ./install.sh            copy this checkout into place
#   ./install.sh --dev      symlink it instead, so edits here are live
#   ./install.sh --no-build skip building wl-kbptr (wire up integration only)
#   ./install.sh --rebuild  rebuild wl-kbptr even if this build is already installed
#   ./install.sh --lite     build without OpenCV (hints fall back to window rects)
#   ./install.sh --branch B build the fork's branch B instead, to try it live
#                           before it is merged; a plain run goes back
#   ./install.sh --keybinds    wire up the Hyprland keybindings without asking
#   ./install.sh --no-keybinds leave the Hyprland keybindings out, without asking
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

dev=0 build=1 lite=0 rebuild=0 branch="" keybinds=""
while (($#)); do
  case "$1" in
    --dev) dev=1 ;;
    --no-build) build=0 ;;
    --rebuild) rebuild=1 ;;
    --lite) lite=1 ;;
    --branch) branch="${2:-}"; [[ -n $branch ]] || { echo "install.sh: --branch needs a name" >&2; exit 2; }; shift ;;
    --keybinds) keybinds=1 ;;
    --no-keybinds) keybinds=0 ;;
    -h | --help) sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
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

# --- 0a. omarchy-ascii ---------------------------------------------------------
# Text drawn large in the font the Omarchy wordmark is drawn in. Omarchy grew
# `omarchy ascii` after 4.0.0.alpha, so on a machine at or before that release
# it is simply not there, and the feature that wants it has to bring its own.
# Resolved this early, ahead of the wl-kbptr build, so the banner just below
# can use it on a first install and not only on the second one.
#
# The copy goes in STATE_DIR rather than ~/.local/bin, and that is the whole
# point of this section: ~/.local/bin comes before /usr/bin on PATH, so a copy
# left there would go on shadowing the packaged omarchy-ascii long after
# Omarchy shipped it -- pinning every user of this plugin to whatever upstream
# looked like the day they installed. Nothing but this plugin ever resolves the
# vendored path (see ascii_cmd in bin/imthemousenow-osd), the packaged one
# always wins when it exists, and uninstall.sh takes STATE_DIR with it.
#
# Pinned by commit and checked by hash. A script fetched from a moving branch
# and run unread is a different program on any two days.
ASCII_COMMIT="4baae6bf2afb2c07b617100371c07d8b6dea71a5"
ASCII_SHA256="9640bc210e8cfe016459bc7b4917344403fe49f67ce013f2cff118cdafdcf7c5"
ASCII_VENDORED="$STATE_DIR/bin/omarchy-ascii"

if command -v omarchy-ascii >/dev/null 2>&1; then
  # Omarchy caught up. Drop ours rather than leave two, so there is no question
  # of which one ran.
  if [[ -e $ASCII_VENDORED ]]; then
    say "Omarchy now ships omarchy-ascii; removing the copy this plugin vendored"
    rm -f "$ASCII_VENDORED"
  fi
elif [[ -x $ASCII_VENDORED ]] && "$ASCII_VENDORED" Om >/dev/null 2>&1; then
  say "Using the vendored omarchy-ascii (this Omarchy has none)"
else
  say "This Omarchy has no omarchy-ascii; vendoring ${ASCII_COMMIT:0:9}"
  mkdir -p "$STATE_DIR/bin"
  ascii_tmp="$(mktemp)"
  if ! curl -fsSL --retry 2 \
    "https://raw.githubusercontent.com/basecamp/omarchy/$ASCII_COMMIT/bin/omarchy-ascii" \
    -o "$ascii_tmp"; then
    warn "Could not download omarchy-ascii; anything that draws text large will be unavailable."
    rm -f "$ascii_tmp"
  elif [[ "$(sha256sum <"$ascii_tmp" | cut -d' ' -f1)" != "$ASCII_SHA256" ]]; then
    warn "Downloaded omarchy-ascii does not match its pinned checksum; not installing it."
    rm -f "$ascii_tmp"
  else
    chmod 755 "$ascii_tmp"  # mktemp makes it 0600; +x alone would leave it unreadable
    # Run it before it counts as installed. The font is embedded in the script,
    # so a copy that renders one word renders every word, and a copy that fails
    # here would otherwise fail at the first keypress instead.
    if "$ascii_tmp" Om >/dev/null 2>&1; then
      mv "$ascii_tmp" "$ASCII_VENDORED"
    else
      warn "The downloaded omarchy-ascii does not run here; not installing it."
      rm -f "$ascii_tmp"
    fi
  fi
fi

# --- 0b. the banner --------------------------------------------------------
# Same tool, same rule as the ACTION announcement in imthemousenow-osd: every
# way of failing to draw the art ends in the plain word, never a blank line.
# The font has letters and spaces only (see imthemousenow-osd), hence "IM"
# rather than "I'M" -- an apostrophe is exactly the kind of glyph it drops
# silently, and a banner is not worth a second fallback path to get right.
banner_ascii_bin() {
  command -v omarchy-ascii >/dev/null 2>&1 && { command -v omarchy-ascii; return 0; }
  [[ -x $ASCII_VENDORED ]] && { printf '%s\n' "$ASCII_VENDORED"; return 0; }
  return 1
}

art=""
if ascii_bin="$(banner_ascii_bin)" && art="$("$ascii_bin" "IM THE MOUSE NOW" 2>/dev/null)" &&
  [[ -n ${art//[[:space:]]/} ]]; then
  printf '%s\n' "$art"
else
  printf "I'm the mouse now\n"
fi
printf 'v%s\n\n' "$(jq -r '.version // "unknown"' "$REPO/shell/manifest.json" 2>/dev/null || echo unknown)"

# --- 0c. the keybindings opt-in ------------------------------------------------
# Wiring SUPER + ; and CTRL+ALT+DELETE into the user's own hyprland.lua is the
# one thing this installer does outside its own directories (see section 5),
# so it is the one thing it asks about rather than just doing. --keybinds and
# --no-keybinds answer this without a prompt, for a scripted install; with
# neither and no terminal to ask at, the safer default is to leave the
# keybindings out rather than assume consent that was never given.
if [[ -z $keybinds ]]; then
  if [[ -t 0 && -t 1 ]]; then
    read -r -p "Wire up SUPER + ; (and its chords) and CTRL+ALT+DELETE in ${HYPR_ENTRY/#$HOME/\~}? [Y/n] " reply
    case "$reply" in
      [Nn]*) keybinds=0 ;;
      *) keybinds=1 ;;
    esac
  else
    keybinds=0
    warn "Not running at a terminal; leaving the Hyprland keybindings out (pass --keybinds to wire them up)."
  fi
fi

# --- 1. wl-kbptr itself -------------------------------------------------------
# Built from the tip of the fork's branch (pkg/source.toml). What identifies a
# build is that commit plus whether OpenCV is in; install.sh asks GitHub which
# commit the tip is, and rebuilds only when that is not what is installed.
build_id() { printf '%s opencv=%s\n' "$1" "$2"; }

eval "$(awk -F'=' '
  /^[[:space:]]*(mode|repo|branch|opencv)[[:space:]]*=/ {
    key = $1; gsub(/[[:space:]]/, "", key)
    val = $2; sub(/#.*/, "", val); gsub(/[[:space:]"]/, "", val)
    printf "SRC_%s=%s\n", toupper(key), val
  }' "$REPO/pkg/source.toml")"
((lite)) && SRC_OPENCV=false
# A work branch in the fork, pushed but not merged: build it to see it on the
# compositor. The build id records its commit like any other, so the next
# plain run finds the tip of the real branch differs and builds that again.
[[ -n $branch ]] && SRC_BRANCH="$branch"
have="$(cat "$STATE_DIR/build-id" 2>/dev/null || echo)"

# The commit the branch points at right now, or nothing if GitHub cannot be
# reached.
fork_tip() {
  git ls-remote "$SRC_REPO" "refs/heads/$SRC_BRANCH" 2>/dev/null | cut -f1
}

if ((build)); then
  if [[ ${SRC_MODE:-fork} == aur ]]; then
    say "Installing wl-kbptr from the AUR"
    warn "The AUR package is 0.4.1, which does not build against opencv 5."
    warn "It is also stock upstream: popup-safe mode, drag, hold, peek and double click are gone."
    omarchy pkg aur add wl-kbptr
    build_id aur "${SRC_OPENCV:-true}" >"$STATE_DIR/build-id"
  else
    [[ -n ${SRC_REPO:-} && -n ${SRC_BRANCH:-} ]] ||
      { warn "pkg/source.toml needs a repo and a branch to build"; exit 1; }
    tip="$(fork_tip)"

    # Re-running install.sh after editing the bash or the Lua is the common
    # case, and it should not cost a compile. Skipping is only safe when the
    # binary that build id describes is still there and still links.
    installed_ok=0
    if pacman -Qq wl-kbptr-omarchy >/dev/null 2>&1 &&
      command -v wl-kbptr >/dev/null 2>&1 &&
      ! ldd "$(command -v wl-kbptr)" 2>/dev/null | grep -q "not found"; then
      installed_ok=1
    fi

    if [[ -z $tip && -n $branch ]] && git ls-remote "$SRC_REPO" >/dev/null 2>&1; then
      warn "The fork has no branch '$branch' on GitHub. Push it first: git push -u origin $branch"
      exit 1
    elif [[ -z $tip ]]; then
      # Offline, or the fork is gone. Keeping a working build beats failing
      # the whole install over a rebuild that may not even be due.
      if ((installed_ok)); then
        warn "Could not reach $SRC_REPO; keeping the installed wl-kbptr (${have:-unknown build})."
      else
        warn "Could not reach $SRC_REPO to find the $SRC_BRANCH branch, and no wl-kbptr is installed."
        exit 1
      fi
    elif ((rebuild == 0 && installed_ok)) && [[ $(build_id "$tip" "$SRC_OPENCV") == "$have" ]]; then
      say "wl-kbptr ${tip:0:9} ($SRC_BRANCH) is already installed; skipping the build (--rebuild forces it)"
    else
      say "Building wl-kbptr from $SRC_BRANCH at ${tip:0:9} (opencv=${SRC_OPENCV})"
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
        MOUSENOW_REPO="$SRC_REPO" MOUSENOW_COMMIT="$tip" \
          MOUSENOW_OPENCV="$([[ $SRC_OPENCV == true ]] && echo 1 || echo 0)" \
          makepkg -si --noconfirm
      )
      # After the build, not before: a failed build must leave the id of what
      # is actually installed, or the next run would skip a build that never
      # happened.
      build_id "$tip" "$SRC_OPENCV" >"$STATE_DIR/build-id"
    fi
  fi
  touch "$STATE_DIR/installed"

  # Left behind by the upstream-release check, which this plugin no longer
  # does: it asked GitHub after every system update whether wl-kbptr had
  # tagged a release, which is the maintainer's business and not news the
  # person using it can act on. Clear the files it kept rather than leave
  # state nothing reads.
  rm -f "$STATE_DIR/commit" "$STATE_DIR/release-seen"

  # Verify what we actually got, and fall back rather than ship a broken mode.
  if [[ ${SRC_OPENCV:-true} == true ]] && ! wl-kbptr --version 2>&1 | grep -qi opencv; then
    warn "This build has no OpenCV support; hints will label windows instead of detecting targets."
    warn "Re-run with --lite to make that the intended configuration."
  fi
else
  # --no-build with a stale binary is how the wrapper ends up newer than the
  # thing it drives -- and a wl-kbptr option the installed build does not know
  # makes it reject the whole config file, so every chord silently dies. Say so
  # here rather than leaving it to be discovered at the first keypress. Only if
  # GitHub answers: --no-build must not fail for being offline.
  if [[ ${SRC_MODE:-fork} != aur ]]; then
    tip="$(fork_tip)"
    if [[ -n $tip && -n $have && $have != "$tip "* ]]; then
      warn "Installed wl-kbptr (${have%% *}) is not the tip of $SRC_BRANCH (${tip:0:9})."
      warn "Re-run without --no-build to rebuild."
    fi
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

for script in imthemousenow imthemousenow-steer imthemousenow-regions imthemousenow-panic imthemousenow-config imthemousenow-osd imthemousenow-help imthemousenow-hold imthemousenow-halo imthemousenow-pool imthemousenow-menu imthemousenow-scroll; do
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

# The halo a hold wears is drawn the same way, by the same quickshell, and is
# checked separately because it is the only thing on screen during a hold: with
# no overlay drawn, a hold with no halo is a button held down with nothing at
# all to say so.
"$REPO/bin/imthemousenow-halo" --self-test >/dev/null 2>&1 ||
  warn "The hold halo is unavailable (no quickshell?); a hold will still work, with nothing on screen to show it."

# --- 3. theme template --------------------------------------------------------
link_or_copy "$REPO/templates/wl-kbptr.conf.tpl" "$THEMED_DIR/wl-kbptr.conf.tpl"

# --- 4. hooks -----------------------------------------------------------------
for hook in theme-set font-set post-update; do
  mkdir -p "$HOOKS_DIR/$hook.d"
  link_or_copy "$REPO/hooks/$hook" "$HOOKS_DIR/$hook.d/imthemousenow.hook"
done

# --- 5. Hyprland include ------------------------------------------------------
if ((keybinds)); then
  if ! grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY"; then
    say "Adding the Hyprland include to hyprland.lua"
    cp "$HYPR_ENTRY" "$HYPR_ENTRY.bak.$(date +%s)"
    printf '\n%s\n%s\n' "$MARKER" "$REQUIRE_LINE" >>"$HYPR_ENTRY"
  fi
elif grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY" 2>/dev/null; then
  # Already wired up from an earlier install; declining now must not rip out
  # keybindings that were opted into before.
  say "Keybindings are already wired up in hyprland.lua; leaving them as they are."
else
  warn "Skipping the Hyprland keybindings, as requested."
  warn "imthemousenow still runs from the CLI: try 'imthemousenow'. See docs/manual/02-keybindings.md, \"Bring your own keybinding\", to wire a key of your own to it."
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

if ((keybinds)); then
  say "Done. Try: SUPER + ;   (or: imthemousenow)"
else
  say "Done. No keybindings were wired up; try: imthemousenow"
fi
((dev)) && say "Dev mode: edits in $REPO are live. Re-run only after changing install.sh itself."
exit 0
