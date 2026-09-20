// One large word, solid then fading: which ACTION you just moved into -- drawn
// as block art in the FIGlet font the Omarchy wordmark is set in, so the
// announcement looks like the desktop it belongs to. bin/imthemousenow-osd does
// the rendering and hands the finished block over; if it could not, the art is
// empty and the plain word is drawn instead, which is what every failure to
// produce art falls back to.
//
// Quickshell rather than any toolkit of our own choosing, for one reason: it is
// a dependency of the `omarchy` package itself, so it is on every Omarchy
// machine. Everything else that can put a layer surface on screen -- including
// gtk4-layer-shell, which an earlier version of this used -- arrives only with
// some application the user happens to have installed.
//
// Two properties matter more than how this looks:
//
//   1. It must not take the pointer. wl-kbptr clicks by warping a virtual
//      pointer and pressing, so anything over the target that accepted pointer
//      input would swallow the very click this announces. `mask: Region {}` is
//      an empty input region: the compositor routes pointer events as though
//      the surface were not there.
//   2. It must not take the keyboard. An overlay that takes keyboard focus is
//      what dismisses the popup you were aiming at (pkg/0002-*.patch), and it
//      would steal the keys the overlay's own submap is bound to.
//      WlrKeyboardFocus.None, never Exclusive.
//
// Parameters arrive as environment variables because quickshell owns argv.
// bin/imthemousenow-osd sets them.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root

  function env(name, fallback) {
    const value = Quickshell.env(name);
    return (value === undefined || value === null || value === "") ? fallback : value;
  }

  readonly property string text: env("MOUSENOW_OSD_TEXT", "")
  // The rendered block, or "" when there is none to draw. Only the shell knows
  // whether the art could be made, so this is the single thing that decides
  // which of the two the label is.
  readonly property string art: env("MOUSENOW_OSD_ART", "")
  readonly property bool drawingArt: root.art !== ""
  readonly property color textColor: env("MOUSENOW_OSD_COLOR", "#ffffff")
  readonly property string family: env("MOUSENOW_OSD_FONT", "sans-serif")
  readonly property int size: parseInt(env("MOUSENOW_OSD_SIZE", "120"))
  readonly property int totalMs: parseInt(env("MOUSENOW_OSD_MS", "500"))
  readonly property int fadeMs: Math.min(parseInt(env("MOUSENOW_OSD_FADE_MS", "250")), totalMs)
  readonly property string place: env("MOUSENOW_OSD_POSITION", "top")

  // A box to sit inside, monitor-relative, as WxH+X+Y -- what window scope
  // passes so the word lands on the window the overlay is confined to rather
  // than in the middle of a screen the overlay is not covering. Empty means the
  // whole output, which is what monitor scope wants.
  readonly property string regionSpec: env("MOUSENOW_OSD_REGION", "")
  readonly property var region: {
    const m = /^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$/.exec(root.regionSpec);
    return m ? { w: parseInt(m[1]), h: parseInt(m[2]), x: parseInt(m[3]), y: parseInt(m[4]) } : null;
  }
  readonly property string outputName: env("MOUSENOW_OSD_OUTPUT", "")
  // The inset from the edge the word is anchored to. A window is a smaller
  // space than a screen, so the same 80px would read as "most of the way down".
  readonly property int inset: root.region ? 24 : 80

  PanelWindow {
    id: panel

    // With a region, the surface covers exactly that box: anchored to the top
    // left corner of the output and pushed into place by its margins, because
    // margins are the only coordinates a layer surface has. Without one it
    // spans the output, and `position` is then relative to the screen.
    //
    // Either way the surface covers the whole target area and the word is
    // aligned inside it, rather than the surface being label-sized and placed.
    // That keeps one rule for both scopes: "centred in the thing the overlay is
    // covering".
    anchors {
      left: true
      top: true
      right: !root.region
      bottom: !root.region
    }
    margins.left: root.region ? root.region.x : 0
    margins.top: root.region ? root.region.y : 0
    implicitWidth: root.region ? root.region.w : 0
    implicitHeight: root.region ? root.region.h : 0
    color: "transparent"

    // The window may be on a monitor other than the focused one by the time
    // this draws; the caller names which, and an unknown name falls back to
    // wherever quickshell would have put it.
    screen: {
      if (root.outputName === "") return null;
      const match = Quickshell.screens.find(s => s.name === root.outputName);
      return match !== undefined ? match : null;
    }

    WlrLayershell.namespace: "imthemousenow-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Nothing this short-lived may push a bar or a window aside.
    exclusionMode: ExclusionMode.Ignore
    // The empty input region. See the header: this is the click-through.
    mask: Region {}

    Text {
      id: label
      // Filling the surface and aligning inside it, rather than anchoring to an
      // edge: this is what makes `center` mean the middle of the window in
      // window scope and the middle of the screen in monitor scope, with no
      // second code path.
      anchors.fill: parent
      anchors.topMargin: root.place === "top" ? root.inset : 0
      anchors.bottomMargin: root.place === "bottom" ? root.inset : 0
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: root.place === "top" ? Text.AlignTop
        : root.place === "bottom" ? Text.AlignBottom : Text.AlignVCenter
      // A window can be narrower than the word is wide at 120px. Shrink to fit
      // rather than clip: a truncated ACTION name is worse than a smaller one.
      // The art is nine rows tall as well as wide, so it has to fit in both
      // directions; a single line only ever has to fit across.
      fontSizeMode: root.drawingArt ? Text.Fit : Text.HorizontalFit
      minimumPixelSize: root.drawingArt ? 4 : 16
      // Already the right shape: the art is drawn from capitals, and upper-casing
      // block characters would do nothing but cost a pass over a long string.
      text: root.drawingArt ? root.art : root.text.toUpperCase()
      color: root.textColor
      font.family: root.family
      // `size` is the height of a WORD, and the art would spend all of it on
      // each of its nine rows -- 120 there fills a 4K screen corner to corner.
      // A quarter of it puts the block at about twice the height the plain word
      // would have had: bigger, because a wordmark is meant to be, but still an
      // announcement rather than a takeover. Text.Fit shrinks from here to
      // whatever the surface actually allows, so this is a ceiling, not a size.
      font.pixelSize: root.drawingArt ? Math.max(4, Math.round(root.size / 4)) : root.size
      // Block art is a grid, and both of these break the grid: a bold weight
      // thickens cells until neighbours bleed into each other, and letter
      // spacing pushes every row out of column with the one above it.
      font.weight: root.drawingArt ? Font.Normal : Font.Black
      font.letterSpacing: root.drawingArt ? 0 : 6
      // The rows of a FIGlet glyph are meant to touch: at the font's natural
      // line height the stack reads as nine separate stripes rather than one
      // letter.
      lineHeight: root.drawingArt ? 0.82 : 1.0
      lineHeightMode: Text.ProportionalHeight
      renderType: Text.NativeRendering
      // The word lands on whatever happens to be on screen, and the theme
      // foreground alone is not guaranteed to be readable against it.
      style: Text.Outline
      styleColor: Qt.rgba(0, 0, 0, 0.85)
    }

    // Solid first, then the fade. The solid part is when the word is read; the
    // fade is what says "this is telling you something, not asking you for
    // something", so it can be ignored rather than dismissed.
    SequentialAnimation {
      running: true
      PauseAnimation { duration: Math.max(1, root.totalMs - root.fadeMs) }
      NumberAnimation {
        target: label
        property: "opacity"
        from: 1
        to: 0
        duration: root.fadeMs
        easing.type: Easing.InQuad
      }
      ScriptAction { script: Qt.quit() }
    }
  }

  // Belt and braces: whatever happens to the animation above, nothing this
  // process draws may outlive its welcome and sit on the desktop forever.
  Timer {
    running: true
    interval: root.totalMs + 2000
    onTriggered: Qt.quit()
  }
}
