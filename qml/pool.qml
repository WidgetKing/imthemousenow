// The mark a click leaves: a patch of LCD pooling where the pointer pressed,
// for as long as a second press would still count as a double click.
//
// It used to be three rings drawn by wl-kbptr itself, on its own surface, in
// the gap after the overlay went. Here instead because a ring is all a C
// program drawing with cairo was ever going to manage, and because wl-kbptr
// only drew it when a double-click window was open -- a right click, which has
// none, left no mark at all. This process does not care which click it was.
//
// It is started with the overlay, not with the click, so it is already on
// screen and waiting when the click comes: quickshell takes longer to start
// than a double-click window lasts. wl-kbptr tells it where each click went
// by rewriting a file (WL_KBPTR_CLICK_REPORT), one line per click:
//
//     <output name> <x> <y> <ms>
//
// x and y in that output's own coordinates, and the timestamp so that the
// second click of a double click, on the very same spot, is still news.
//
// The same two rules as every other surface this plugin floats over the
// desktop: it takes neither the pointer (`mask: Region {}`) nor the keyboard.
// It is on screen at the exact moment the pointer is clicking through it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  function env(name, fallback) {
    const value = Quickshell.env(name);
    return (value === undefined || value === null || value === "") ? fallback : value;
  }

  readonly property string reportPath: env("MOUSENOW_POOL_REPORT", "")
  readonly property int durationMs: parseInt(env("MOUSENOW_POOL_MS", "400"))
  readonly property real poolRadius: parseFloat(env("MOUSENOW_POOL_RADIUS", "56"))
  readonly property int poolCell: parseInt(env("MOUSENOW_POOL_CELL", "6"))
  readonly property var poolColours: env("MOUSENOW_POOL_COLORS", "").split(/\s+/).filter(c => c !== "")
  readonly property color poolShade: env("MOUSENOW_POOL_SHADE", "#000000")
  // A style, or `random` for a different one every click. See PoolSpot.qml.
  readonly property string poolStyle: env("MOUSENOW_POOL_STYLE", "pool")
  readonly property var styles: ["pool", "patchy", "lines", "cross"]
  property string lastStyle: ""

  // Random never picks the one it just showed, so two clicks in a row always
  // look different -- which is most of what "random" is for.
  function nextStyle() {
    if (root.poolStyle !== "random") return root.poolStyle;
    const choices = root.styles.filter(s => s !== root.lastStyle);
    root.lastStyle = choices[Math.floor(Math.random() * choices.length)];
    return root.lastStyle;
  }

  // The last click read: which output, where on it, and the stamp that says
  // whether it is a new one.
  property string output: ""
  property real clickX: 0
  property real clickY: 0
  property string stamp: ""
  // Bumped once per new click; every panel watches it and plays from the top.
  property int clicks: 0

  function readReport() {
    const text = report.text();
    if (text === undefined || text === null) return;
    const match = /^(\S+)\s+(-?\d+)\s+(-?\d+)\s+(\d+)/.exec(text);
    // A file caught half-written reads as nothing, and the next look sees it.
    // The wrapper removes the file before starting this, so the first line
    // ever read is a real click rather than one a previous run left behind.
    if (!match || match[4] === root.stamp) return;
    root.stamp = match[4];
    root.output = match[1];
    root.clickX = parseInt(match[2]);
    root.clickY = parseInt(match[3]);
    root.clicks++;
  }

  FileView {
    id: report
    path: root.reportPath
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.readReport(); }
    onLoaded: root.readReport()
  }

  // A watch can be missed when the file is rewritten under it; the look every
  // 50 ms is what makes a missed one late rather than lost. Quick, because the
  // whole effect only lasts a few hundred.
  Timer {
    running: true
    interval: 50
    repeat: true
    onTriggered: { report.reload(); root.readReport(); }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      anchors { left: true; top: true; right: true; bottom: true }
      color: "transparent"

      WlrLayershell.namespace: "imthemousenow-pool"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Connections {
        target: root
        function onClicksChanged() {
          if (root.output !== panel.screen.name) {
            // A click on another monitor ends any spot still fading here.
            play.stop();
            spot.intensity = 0;
            return;
          }
          spot.style = root.nextStyle();
          spot.seed = Math.random() * 1000;
          spot.centerX = root.clickX;
          spot.centerY = root.clickY;
          play.restart();
        }
      }

      PoolSpot {
        id: spot
        radius: root.poolRadius
        cell: root.poolCell
        colours: root.poolColours
        shade: root.poolShade
        intensity: 0
        visible: intensity > 0
      }

      // Pressed in fast, then let go slowly across the rest of the window: the
      // crystal flows back more slowly than it was squeezed out. It is gone by
      // the time a second press would no longer count.
      SequentialAnimation {
        id: play
        NumberAnimation {
          target: spot; property: "intensity"
          from: 0.35; to: 1; duration: Math.min(90, root.durationMs / 4)
          easing.type: Easing.OutQuad
        }
        NumberAnimation {
          target: spot; property: "intensity"
          to: 0; duration: Math.max(60, root.durationMs - Math.min(90, root.durationMs / 4))
          easing.type: Easing.InQuad
        }
      }
    }
  }
}
