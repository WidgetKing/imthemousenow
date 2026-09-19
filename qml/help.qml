// The key list, on screen, for the overlay you are already inside.
//
// Everything this plugin does is invisible until a key is pressed, and the
// keys are not printed on anything. F1 (or `?`) is the sheet that says what
// they are, drawn the same way the ACTION announcement is and for the same
// reason: quickshell is a dependency of the `omarchy` package itself, so it is
// on every machine this plugin can be installed on.
//
// Two things differ from qml/osd.qml, and both follow from this being read
// rather than glanced at:
//
//   1. It stays up until it is dismissed. There is no fade and no timer.
//   2. It may take the keyboard -- but only when it is safe to. The overlay it
//      replaces is torn down before this appears (bin/imthemousenow shows the
//      sheet between two passes of its run loop), so there is no wl-kbptr grab
//      left to fight over. In popup-safe mode it must still take nothing:
//      keyboard focus is what closes the popup the whole mode exists to keep
//      open, so there the keys arrive as compositor bindings instead and
//      MOUSENOW_HELP_FOCUS is `none`.
//
// The pointer is never taken, in either mode: `mask: Region {}` as ever.
//
// Content arrives as JSON in MOUSENOW_HELP_JSON rather than being written
// here, because what the keys ARE is bash's to know -- bin/imthemousenow-help
// builds the list and can say which of them apply to the overlay that is
// actually up.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root

  function env(name, fallback) {
    const value = Quickshell.env(name);
    return (value === undefined || value === null || value === "") ? fallback : value;
  }

  readonly property color bg: env("MOUSENOW_HELP_BG", "#1e1e2e")
  readonly property color fg: env("MOUSENOW_HELP_FG", "#cdd6f4")
  readonly property color accent: env("MOUSENOW_HELP_ACCENT", "#89b4fa")
  readonly property string family: env("MOUSENOW_HELP_FONT", "sans-serif")
  readonly property int size: parseInt(env("MOUSENOW_HELP_SIZE", "15"))
  readonly property string outputName: env("MOUSENOW_HELP_OUTPUT", "")
  // `none` in popup-safe mode. See the header.
  readonly property bool grabsKeyboard: env("MOUSENOW_HELP_FOCUS", "exclusive") !== "none"

  // A malformed payload must not leave a blank sheet on screen with no way to
  // read what went wrong, so it degrades to a one-line sheet that still says
  // how to get out.
  readonly property var sheet: {
    try {
      return JSON.parse(root.env("MOUSENOW_HELP_JSON", "{}"));
    } catch (e) {
      return { title: "Keys", state: "", sections: [
        { title: "Something went wrong", rows: [["Escape", "close this"]] } ] };
    }
  }

  PanelWindow {
    id: panel
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    screen: {
      if (root.outputName === "") return null;
      const match = Quickshell.screens.find(s => s.name === root.outputName);
      return match !== undefined ? match : null;
    }

    WlrLayershell.namespace: "imthemousenow-help"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.grabsKeyboard
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The empty input region: this cannot swallow a click, the same as the OSD.
    mask: Region {}

    // Dim what is behind, so the sheet reads as a thing in front of the desktop
    // rather than text scattered over it.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(parent.width - 80, Math.max(720, columns.implicitWidth + 64))
      height: Math.min(parent.height - 80, body.implicitHeight + 64)
      radius: 18
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.97)
      border.width: 2
      border.color: root.accent

      ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 32
        spacing: 18

        RowLayout {
          Layout.fillWidth: true
          spacing: 16

          Text {
            text: root.sheet.title || "Keys"
            color: root.fg
            font.family: root.family
            font.pixelSize: root.size + 9
            font.weight: Font.Black
            renderType: Text.NativeRendering
          }
          Item { Layout.fillWidth: true }
          // What the overlay behind this sheet actually is. The keys below
          // depend on it -- half of them are window scope only -- so naming it
          // here is what makes the sheet about THIS overlay rather than about
          // the plugin in general.
          Text {
            text: root.sheet.state || ""
            color: root.accent
            font.family: root.family
            font.pixelSize: root.size + 1
            font.weight: Font.Bold
            font.letterSpacing: 1
            renderType: Text.NativeRendering
          }
        }

        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
        }

        // Two columns of sections. A single column would run off the bottom of
        // a laptop screen; the sheet has to fit without scrolling, because
        // scrolling it would need keys of its own.
        RowLayout {
          id: columns
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 44

          Repeater {
            model: 2

            ColumnLayout {
              id: column
              required property int index
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignTop
              spacing: 16

              Repeater {
                model: (root.sheet.sections || []).filter(
                  (s, i) => i % 2 === column.index)

                ColumnLayout {
                  id: section
                  required property var modelData
                  Layout.fillWidth: true
                  spacing: 5

                  Text {
                    text: section.modelData.title
                    color: root.accent
                    font.family: root.family
                    font.pixelSize: root.size
                    font.weight: Font.Black
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.5
                    renderType: Text.NativeRendering
                  }

                  Repeater {
                    model: section.modelData.rows

                    RowLayout {
                      id: row
                      required property var modelData
                      Layout.fillWidth: true
                      spacing: 14

                      // The key, boxed, so the eye can run down the column of
                      // them without reading the sentences beside them.
                      Rectangle {
                        Layout.preferredWidth: 122
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: keys.implicitHeight + 6
                        radius: 6
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                        border.width: 1
                        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)

                        Text {
                          id: keys
                          anchors.centerIn: parent
                          width: parent.width - 12
                          text: row.modelData[0]
                          color: root.fg
                          horizontalAlignment: Text.AlignHCenter
                          wrapMode: Text.WordWrap
                          font.family: root.family
                          font.pixelSize: root.size - 1
                          font.weight: Font.Bold
                          renderType: Text.NativeRendering
                        }
                      }

                      Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: row.modelData[1]
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.88)
                        wrapMode: Text.WordWrap
                        font.family: root.family
                        font.pixelSize: root.size
                        renderType: Text.NativeRendering
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.sheet.footer || ""
          visible: text !== ""
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
          wrapMode: Text.WordWrap
          font.family: root.family
          font.pixelSize: root.size - 1
          font.italic: true
          renderType: Text.NativeRendering
        }
      }
    }

    // Only reachable when this took the keyboard. In popup-safe mode every key
    // below is a compositor binding instead, and closing the sheet is
    // `imthemousenow-steer help` -- which kills this process.
    Item {
      anchors.fill: parent
      focus: root.grabsKeyboard
      Keys.onPressed: (event) => {
        switch (event.key) {
          case Qt.Key_Escape:
          case Qt.Key_F1:
          case Qt.Key_Q:
          case Qt.Key_Return:
          case Qt.Key_Enter:
          case Qt.Key_Space:
            event.accepted = true;
            Qt.quit();
        }
      }
    }
  }
}
