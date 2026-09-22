// The mark the pointer wears while the keyboard is turning the wheel.
//
// A scroll draws nothing over the screen -- you are reading the page that is
// moving -- so the pointer says the mode is on, in the hold halo's language:
// the same LCD pooling (qml/PoolSpot.qml) or, with the pool off, the same
// rings. What is its own is that it moves with the wheel. Each notch shoves
// the spot the way the content travels and squashes it along that
// axis, then lets it spring back, and throws a few chunky cells out ahead of
// it; a held key's run of notches keeps it leaning that way for as long as it
// lasts. Up and down read as up and down, left and right as left and right,
// without a word on screen.
//
// Underneath, the modifiers carried in from the overlay are spelled out --
// CTRL, ALT, SHIFT, SUPER -- since they stay held for the whole scroll, and a
// Ctrl nobody is pressing zooms the page instead of scrolling it.
//
// It takes neither the pointer (an empty input region) nor the keyboard, for
// the halo's reasons: the wheel has to reach what is under it, and every key
// of a scroll is a compositor binding.
//
// Where the pointer is: asked of Hyprland's socket every 30 ms, as the halo
// does, since a scroll can be started anywhere and a real mouse can move
// during one. What the wheel did and what is held: two files
// bin/imthemousenow-scroll rewrites, watched.
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

  readonly property color markColor: env("MOUSENOW_SCROLL_COLOR", "#89b4fa")
  readonly property int markSize: parseInt(env("MOUSENOW_SCROLL_SIZE", "44"))
  readonly property bool pool: env("MOUSENOW_SCROLL_POOL", "") === "1"
  readonly property var poolColours: env("MOUSENOW_POOL_COLORS", "").split(/\s+/).filter(c => c !== "")
  readonly property int cell: parseInt(env("MOUSENOW_POOL_CELL", "6"))

  property real pointerX: 0
  property real pointerY: 0
  property bool located: false

  Component.onCompleted: {
    const start = /(-?\d+)\s+(-?\d+)/.exec(env("MOUSENOW_SCROLL_START", ""));
    if (start) {
      root.pointerX = parseInt(start[1]);
      root.pointerY = parseInt(start[2]);
      root.located = true;
    }
  }

  // --- where the pointer is ---------------------------------------------------
  readonly property string hyprSocket: {
    const sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
    const run = Quickshell.env("XDG_RUNTIME_DIR");
    return sig && run ? run + "/hypr/" + sig + "/.socket.sock" : "";
  }

  Socket {
    id: cursor
    path: root.hyprSocket
    parser: SplitParser {
      splitMarker: ""
      onRead: data => {
        const match = /(-?\d+),\s*(-?\d+)/.exec(data);
        if (!match) return;
        root.pointerX = parseInt(match[1]);
        root.pointerY = parseInt(match[2]);
        root.located = true;
      }
    }
    onConnectedChanged: {
      if (connected) { write("cursorpos"); flush(); }
    }
  }

  Timer {
    running: root.hyprSocket !== ""
    interval: 30
    repeat: true
    onTriggered: if (!cursor.connected) cursor.connected = true
  }

  // --- what the wheel did -------------------------------------------------------
  // The way the last notch went, as a unit vector on screen: the way the
  // content travels, so `down` shoves the mark up. The way the key points was
  // tried first and read as backwards on the running desktop.
  property real dirX: 0
  property real dirY: 0
  property int lastSeq: 0
  // 0 at rest, 1 the instant a notch lands; decays. Everything that moves is
  // driven off this and the direction.
  property real kick: 0
  // How many notches in the last short run, so a held key leans harder than a
  // single tap does.
  property int streak: 0

  function readEvent() {
    const text = eventFile.text();
    if (!text) return;
    const match = /(\d+)\s+(\w+)/.exec(text);
    if (!match) return;
    const seq = parseInt(match[1]);
    if (seq === root.lastSeq) return;
    root.lastSeq = seq;
    const vectors = { up: [0, 1], down: [0, -1], left: [1, 0], right: [-1, 0] };
    const v = vectors[match[2]];
    if (!v) return;
    root.streak = (v[0] === root.dirX && v[1] === root.dirY && streakReset.running)
      ? Math.min(root.streak + 1, 6) : 1;
    root.dirX = v[0];
    root.dirY = v[1];
    streakReset.restart();
    kickAnim.restart();
    root.sparkSeq += 1;
  }

  Timer { id: streakReset; interval: 180 }

  SequentialAnimation {
    id: kickAnim
    NumberAnimation { target: root; property: "kick"; to: 1; duration: 40; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "kick"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
  }

  // How far the spot is shoved, in px, and how much it stretches along the
  // axis it is shoved on.
  readonly property real lean: root.kick * root.markSize * (0.35 + 0.08 * root.streak)
  readonly property real stretch: 1 + root.kick * (0.25 + 0.04 * root.streak)

  property int sparkSeq: 0

  FileView {
    id: eventFile
    path: root.env("MOUSENOW_SCROLL_EVENT", "")
    watchChanges: true
    onFileChanged: { reload(); root.readEvent(); }
    onLoaded: root.readEvent()
  }

  // --- what is held -----------------------------------------------------------
  property var mods: []

  FileView {
    id: modsFile
    path: root.env("MOUSENOW_SCROLL_MODS", "")
    watchChanges: true
    onFileChanged: { reload(); root.readMods(); }
    onLoaded: root.readMods()
  }

  function readMods() {
    const text = modsFile.text() || "";
    root.mods = text.split(/\s+/).filter(m => m !== "").map(m => m.toUpperCase());
  }

  // The belt to the watches' braces, as in the halo: a missed inotify event
  // would leave a mark naming modifiers that are no longer held.
  Timer {
    running: true
    interval: 100
    repeat: true
    onTriggered: {
      eventFile.reload(); root.readEvent();
      modsFile.reload(); root.readMods();
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      anchors { left: true; top: true; right: true; bottom: true }
      color: "transparent"

      WlrLayershell.namespace: "imthemousenow-scroll"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      readonly property real localX: root.pointerX - panel.screen.x
      readonly property real localY: root.pointerY - panel.screen.y
      readonly property bool here: root.located &&
        localX >= 0 && localX < panel.screen.width &&
        localY >= 0 && localY < panel.screen.height

      // The spot, shoved and squashed. The pool snaps itself to the screen's
      // cell grid, so a shove steps a cell at a time, like the rest of it.
      PoolSpot {
        id: spot
        visible: root.pool && panel.here
        centerX: panel.localX + root.dirX * root.lean
        centerY: panel.localY + root.dirY * root.lean
        radius: parseFloat(root.env("MOUSENOW_POOL_RADIUS", "56")) * 0.8
        cell: root.cell
        colours: root.poolColours
        style: "pool"
        seed: root.sparkSeq
        shade: root.env("MOUSENOW_POOL_SHADE", "#000000")
        intensity: 0.75 + 0.25 * root.kick
        transform: Scale {
          origin.x: spot.centerX - spot.x
          origin.y: spot.centerY - spot.y
          xScale: root.dirX !== 0 ? root.stretch : 1 / Math.sqrt(root.stretch)
          yScale: root.dirY !== 0 ? root.stretch : 1 / Math.sqrt(root.stretch)
        }
      }

      // With the pool off: two rings, squashed the same way.
      Item {
        visible: !root.pool && panel.here
        width: root.markSize * 2
        height: root.markSize * 2
        x: panel.localX + root.dirX * root.lean - root.markSize
        y: panel.localY + root.dirY * root.lean - root.markSize
        transform: Scale {
          origin.x: root.markSize
          origin.y: root.markSize
          xScale: root.dirX !== 0 ? root.stretch : 1 / Math.sqrt(root.stretch)
          yScale: root.dirY !== 0 ? root.stretch : 1 / Math.sqrt(root.stretch)
        }
        Repeater {
          model: [{ scale: 1.0, alpha: 0.3 }, { scale: 0.55, alpha: 0.95 }]
          Rectangle {
            required property var modelData
            anchors.centerIn: parent
            width: parent.width * modelData.scale
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: Qt.rgba(root.markColor.r, root.markColor.g, root.markColor.b, modelData.alpha)
          }
        }
      }

      // Cells thrown out ahead of the spot, the way the page is going. Three,
      // staggered, in whole cells: a chevron made of pixels, gone in a blink.
      Repeater {
        model: 3
        Rectangle {
          required property int index
          readonly property real reach: root.markSize * (1.1 + 0.45 * index) +
            root.markSize * 0.6 * (1 - root.kick)
          readonly property real side: root.cell * (3 - index)
          visible: panel.here && root.kick > 0.02
          width: side
          height: side
          color: root.pool && root.poolColours.length > index
            ? root.poolColours[index] : root.markColor
          opacity: root.kick * (1 - index * 0.28)
          x: Math.floor((panel.localX + root.dirX * reach) / root.cell) * root.cell - side / 2
          y: Math.floor((panel.localY + root.dirY * reach) / root.cell) * root.cell - side / 2
        }
      }

      // A slow breath while nothing is turning, so a scroll left on reads as a
      // mode that is on rather than a mark left behind.
      Rectangle {
        id: breath
        visible: panel.here
        width: root.markSize * 2.4
        height: width
        radius: width / 2
        x: panel.localX - width / 2
        y: panel.localY - height / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(root.markColor.r, root.markColor.g, root.markColor.b, 0.5)
        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: true
          NumberAnimation { from: 0.15; to: 0.6; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.6; to: 0.15; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      // The modifiers held for the wheel.
      Row {
        visible: panel.here && root.mods.length > 0
        spacing: 4
        x: panel.localX - width / 2
        y: panel.localY + root.markSize * 1.4
        Repeater {
          model: root.mods
          Rectangle {
            required property string modelData
            width: label.implicitWidth + 12
            height: label.implicitHeight + 6
            color: Qt.rgba(0, 0, 0, 0.75)
            border.width: 2
            border.color: root.markColor
            Text {
              id: label
              anchors.centerIn: parent
              text: modelData
              color: root.markColor
              font.bold: true
              font.pixelSize: 13
            }
          }
        }
      }
    }
  }
}
