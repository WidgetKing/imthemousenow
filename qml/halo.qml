// A pulsing halo around the pointer, for as long as a hold holds the button
// down.
//
// Everything else this plugin draws is an answer to "where do you want to go":
// labels, a grid, a word naming the ACTION. This one is the opposite. During a
// hold nothing is drawn over the screen at all -- you are watching the thing
// you are dragging -- and the desktop therefore looks exactly as it does when
// nothing is happening, while every key on the keyboard means something else
// and a mouse button is down. The halo is the only thing that says so, so it
// pulses rather than sitting still: a static ring reads as decoration, and
// movement is what makes it read as a state.
//
// The same two properties the ACTION announcement gets right matter more here
// than how it looks, and for a sharper reason -- this one is on screen for as
// long as a hold lasts, right on top of what is being dragged:
//
//   1. It must not take the pointer. `mask: Region {}` is an empty input
//      region, so the compositor routes pointer events as though the surface
//      were not there. Without it the halo would swallow the drag it is
//      drawing.
//   2. It must not take the keyboard. Every key of a hold is a compositor
//      binding; a surface that took focus would take them instead, and would
//      dismiss whatever popup the hold is being performed inside.
//
// Where the pointer is comes from a file bin/imthemousenow-hold rewrites on
// every move. Not from polling the compositor: that position is already known
// over there, and a process per frame is not affordable when a held arrow key
// repeats twenty-five times a second.
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

  readonly property color ringColor: env("MOUSENOW_HALO_COLOR", "#89b4fa")
  readonly property int ringSize: parseInt(env("MOUSENOW_HALO_SIZE", "44"))
  readonly property string posPath: env("MOUSENOW_HALO_POS", "")
  // LCD pooling instead of the rings: the same mark a click leaves (see
  // qml/PoolSpot.qml), worn by the pointer for as long as the button is down,
  // so a hold and a click say "pressed here" the same way. Off when the pool is
  // turned off, and the rings below are drawn as they always were.
  readonly property bool pool: env("MOUSENOW_HALO_POOL", "") === "1"
  // Chosen once per hold: a hold is one press, and a mark that changed shape
  // partway through it would read as a second one.
  readonly property string poolStyle: {
    const style = env("MOUSENOW_POOL_STYLE", "pool");
    if (style !== "random") return style;
    const styles = ["pool", "patchy", "lines", "cross"];
    return styles[Math.floor(Math.random() * styles.length)];
  }
  readonly property var poolColours: env("MOUSENOW_POOL_COLORS", "").split(/\s+/).filter(c => c !== "")

  // Layout coordinates -- the space the monitors are laid out in, which is what
  // the file is written in and the only space that can name a point on any
  // screen. Each panel subtracts its own screen's origin.
  property real pointerX: 0
  property real pointerY: 0
  property bool located: false

  // Whether the compositor has told us where the pointer really is. Once it
  // has, the file is no longer read for position: see `cursor` below.
  property bool tracking: false

  function readPosition() {
    const text = positionFile.text();
    if (text === undefined || text === null) return;
    const match = /(-?\d+)\s+(-?\d+)/.exec(text);
    if (!match) return;
    root.filedX = parseInt(match[1]);
    root.filedY = parseInt(match[2]);
    if (root.tracking) return;
    root.pointerX = parseInt(match[1]);
    root.pointerY = parseInt(match[2]);
    root.located = true;
  }

  // What the file last said, kept apart from where the halo is drawn so the
  // two can be compared.
  property int filedX: 0
  property int filedY: 0

  // Where the pointer really is, asked of Hyprland every 30 ms.
  //
  // The file only knows about the moves the hold's keys make. Someone with a
  // real mouse can take hold of something by keyboard and then carry it with
  // the mouse -- the button stays down, the drag goes on -- and a halo read
  // from the file would sit where the keys last left it while the thing being
  // dragged went elsewhere. So the compositor is asked instead: its own
  // socket, the request `hyprctl cursorpos` makes, answered in a line with no
  // process started, which is what makes asking this often affordable. The
  // socket closes after every answer, so each ask is a new connection.
  //
  // With no Hyprland socket to ask, `tracking` never comes on and the halo
  // follows the file as it always did.
  readonly property string hyprSocket: {
    const sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
    const run = Quickshell.env("XDG_RUNTIME_DIR");
    return sig && run ? run + "/hypr/" + sig + "/.socket.sock" : "";
  }

  Socket {
    id: cursor
    path: root.hyprSocket
    // The answer has no newline on the end; an empty marker takes whatever
    // arrives as it arrives.
    parser: SplitParser {
      splitMarker: ""
      onRead: data => root.cursorRead(data)
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

  // How long the pointer has sat still, in polls.
  property int stillFor: 0

  function cursorRead(data) {
    const match = /(-?\d+),\s*(-?\d+)/.exec(data);
    if (!match) return;
    const x = parseInt(match[1]), y = parseInt(match[2]);
    const moved = !root.tracking || x !== root.pointerX || y !== root.pointerY;
    root.pointerX = x;
    root.pointerY = y;
    root.tracking = true;
    root.located = true;
    root.stillFor = moved ? 0 : root.stillFor + 1;

    // The mouse took the pointer somewhere the keys did not, and has let it
    // rest there. Tell the hold, or the next key steps from where the file
    // says the pointer is -- and wl-kbptr, which is told where to go rather
    // than how far, snaps it back there. Only once it has rested ~150 ms: a
    // key's own move is walked in steps, and a pointer caught partway through
    // one must not be written back over the place it is on its way to.
    if (root.stillFor === 5 && (x !== root.filedX || y !== root.filedY)) {
      root.filedX = x;
      root.filedY = y;
      positionFile.setText(x + " " + y + "\n");
    }
  }

  FileView {
    id: positionFile
    path: root.posPath
    // The file is rewritten in place on every move, so the watch is what makes
    // the halo follow the pointer rather than sit where the hold started.
    watchChanges: true
    onFileChanged: { reload(); root.readPosition(); }
    onLoaded: root.readPosition()
  }

  // The belt to that watch's braces. An inotify watch can be missed -- the file
  // is replaced rather than appended to, and a reader can be between watches
  // when it happens -- and a halo left behind at the last position would be
  // pointing at somewhere the pointer no longer is, which is worse than no halo
  // at all. Ten times a second is far below what a moving pointer needs and far
  // above what "it got stuck" takes to notice.
  Timer {
    running: true
    interval: 100
    repeat: true
    onTriggered: { positionFile.reload(); root.readPosition(); }
  }

  // One surface per monitor, because a hold can be steered across a boundary
  // and the halo has to be able to follow it there. The ring is only visible on
  // the screen the pointer is actually on; the others are drawing nothing.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      anchors { left: true; top: true; right: true; bottom: true }
      color: "transparent"

      WlrLayershell.namespace: "imthemousenow-halo"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Nothing that floats over the desktop may push a bar or a window aside.
      exclusionMode: ExclusionMode.Ignore
      // The empty input region. See the header: this is the click-through, and
      // during a hold there is a button down going through it.
      mask: Region {}

      PoolSpot {
        visible: root.pool && halo.visible
        centerX: root.pointerX - panel.screen.x
        centerY: root.pointerY - panel.screen.y
        radius: parseFloat(root.env("MOUSENOW_POOL_RADIUS", "56"))
        cell: parseInt(root.env("MOUSENOW_POOL_CELL", "6"))
        colours: root.poolColours
        style: root.poolStyle
        seed: Math.random() * 1000
        shade: root.env("MOUSENOW_POOL_SHADE", "#000000")
        // A press that stays pressed: never let go, but never quite still,
        // so it reads as a state rather than a stain left on the screen.
        SequentialAnimation on intensity {
          running: root.pool
          loops: Animation.Infinite
          NumberAnimation { from: 0.8; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1.0; to: 0.8; duration: 700; easing.type: Easing.InOutSine }
        }
      }

      Item {
        id: halo
        width: root.ringSize * 2
        height: root.ringSize * 2
        x: root.pointerX - panel.screen.x - root.ringSize
        y: root.pointerY - panel.screen.y - root.ringSize
        // Off this screen, or nothing read yet: draw nothing rather than a ring
        // clamped to an edge, which would look like a pointer that is there.
        visible: root.located &&
          root.pointerX >= panel.screen.x &&
          root.pointerX < panel.screen.x + panel.screen.width &&
          root.pointerY >= panel.screen.y &&
          root.pointerY < panel.screen.y + panel.screen.height

        // Three rings rather than a gradient: Qt's radial gradient lives in
        // Qt5Compat.GraphicalEffects, which is a module this cannot assume is
        // installed, and three circles of falling alpha read as a glow anyway.
        Repeater {
          model: root.pool ? [] : [
            { scale: 1.00, alpha: 0.22, thickness: 2 },
            { scale: 0.70, alpha: 0.45, thickness: 3 },
            { scale: 0.42, alpha: 0.95, thickness: 3 },
          ]

          Rectangle {
            required property var modelData
            anchors.centerIn: parent
            width: halo.width * modelData.scale
            height: width
            radius: width / 2
            color: "transparent"
            border.width: modelData.thickness
            border.color: Qt.rgba(root.ringColor.r, root.ringColor.g,
              root.ringColor.b, modelData.alpha)
            antialiasing: true
          }
        }

        // The pulse. Scale and opacity together, out and back, forever: the
        // hold ends when the button goes up, and this process is killed with
        // it, so there is no end state to animate to.
        SequentialAnimation on scale {
          running: true
          loops: Animation.Infinite
          NumberAnimation { from: 0.86; to: 1.12; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1.12; to: 0.86; duration: 700; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
          running: true
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.55; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.55; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        }

        // The halo keeps up with the pointer rather than teleporting with it:
        // wl-kbptr walks each move in a few steps, and a ring that jumped the
        // whole distance would arrive before the thing being dragged does.
        Behavior on x { NumberAnimation { duration: 40; easing.type: Easing.OutQuad } }
        Behavior on y { NumberAnimation { duration: 40; easing.type: Easing.OutQuad } }
      }
    }
  }
}
