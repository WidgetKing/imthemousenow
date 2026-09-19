// One large word, solid then fading: which ACTION you just moved into.
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
  readonly property color textColor: env("MOUSENOW_OSD_COLOR", "#ffffff")
  readonly property string family: env("MOUSENOW_OSD_FONT", "sans-serif")
  readonly property int size: parseInt(env("MOUSENOW_OSD_SIZE", "120"))
  readonly property int totalMs: parseInt(env("MOUSENOW_OSD_MS", "500"))
  readonly property int fadeMs: Math.min(parseInt(env("MOUSENOW_OSD_FADE_MS", "250")), totalMs)
  readonly property string place: env("MOUSENOW_OSD_POSITION", "top")

  PanelWindow {
    id: panel

    // Anchored left and right so the surface spans the output and the word is
    // centred on the screen rather than on a guess at its own width.
    anchors {
      left: true
      right: true
      top: root.place === "top"
      bottom: root.place === "bottom"
    }
    margins.top: root.place === "top" ? 80 : 0
    margins.bottom: root.place === "bottom" ? 80 : 0
    implicitHeight: label.implicitHeight + 24
    color: "transparent"

    Text {
      id: label
      anchors.centerIn: parent
      text: root.text.toUpperCase()
      color: root.textColor
      font.family: root.family
      font.pixelSize: root.size
      font.weight: Font.Black
      font.letterSpacing: 6
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
