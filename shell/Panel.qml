import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// imthemousenow's settings, in the bar.
//
// This replaces the rows the installer used to merge into the Omarchy menu.
// The menu could only ever offer a toggle or a pick-one-of-N -- it has no
// slider and no text box -- so opacity was three presets pretending to be a
// range, and every other number was behind "Edit Config...". A bar panel has
// the controls, so the settings that are really numbers are now really
// sliders, and the editor is a footer button rather than the main event.
//
// Everything still goes through `imthemousenow-config`: `env` to read the
// merged result in one subprocess, `set` / `toggle` to write. The panel holds
// no opinion about what a valid value is.
Panel {
  id: root
  moduleName: "imthemousenow"
  ipcTarget: "imthemousenow"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Every merged [imthemousenow] setting, as MOUSENOW_CFG_* -> string.
  //
  // `cfg`, not `settings`: the base Panel already has a `settings`, which is
  // this widget's own entry in shell.json, and Bar.qml assigns into it by name
  // (injectProps(), applySettingsDelta()). A property of ours by that name is
  // shadowing, not sharing -- the bar would overwrite the merged config with
  // the widget entry ({}) on load and on every bar-config change, and every
  // control would silently snap back to its built-in fallback.
  property var cfg: ({})
  property bool loaded: false
  property string lastError: ""
  // The popup-safe overlay needs the wl-kbptr this plugin's install.sh builds.
  // On a stock build the setting is ignored, so offering it would be a switch
  // that does nothing -- the same `when:` test the menu row used.
  property bool popupsSupported: false

  readonly property bool osdEnabled: Model.boolValue(cfg, "osd.enabled")

  // --- cursor ----------------------------------------------------------------
  // One flat list of rows, in the order they are drawn. j/k walks it; h/l
  // works inside whichever row it lands on (chips in a group, value on a
  // slider) and does nothing on a toggle. Building it from the same
  // conditions the rows are `visible` by keeps the two from disagreeing when
  // the OSD is off or wl-kbptr is a stock build.
  property bool cursorActive: false
  property int cursorRow: 0
  property int chipIndex: -1

  readonly property var rows: {
    var list = ["action", "mode", "scope", "lifetime", "opacity", "peek", "hold-step", "osd"]
    if (osdEnabled) list.push("osd-position")
    list.push("notify")
    if (popupsSupported) list.push("popups")
    return list.concat(["edit", "check"])
  }

  function rowIndex(id) { return rows.indexOf(id) }
  function hasCursor(id) { return cursorActive && rows[cursorRow] === id }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy !== 0) {
      cursorRow = Math.max(0, Math.min(rows.length - 1, cursorRow + dy))
      chipIndex = -1
      scrollCursorIntoView()
      return
    }
    if (dx !== 0) nudgeRow(rows[cursorRow], dx)
  }

  // h / l on a row that has somewhere sideways to go. A group steps its chips
  // without committing -- Enter does that -- so walking past a choice does not
  // apply it on the way through.
  function nudgeRow(id, dx) {
    var group = groupFor(id)
    if (group) {
      var current = chipIndex >= 0 ? chipIndex : group.options.indexOf(Model.value(cfg, group.key, ""))
      chipIndex = Math.max(0, Math.min(group.options.length - 1, (current < 0 ? 0 : current) + dx))
      return
    }
    var slider = sliderFor(id)
    if (slider) setNumber(slider.key, slider.value + dx * slider.step, slider.integer, slider.minimum, slider.maximum)
  }

  function activateCursor() {
    var id = rows[cursorRow]
    var group = groupFor(id)
    if (group) {
      var index = chipIndex >= 0 ? chipIndex : group.options.indexOf(Model.value(cfg, group.key, ""))
      if (index >= 0) setValue(group.key, group.options[index])
      return
    }
    if (id === "edit") { run("omarchy-launch-editor ~/.config/omarchy/imthemousenow/config.toml"); root.close(); return }
    if (id === "check") { run("omarchy-launch-floating-terminal-with-presentation 'imthemousenow-config check'"); root.close(); return }
    if (sliderFor(id)) return
    toggleSetting(toggleKey(id))
  }

  function toggleKey(id) {
    return ({
      "osd": "osd.enabled",
      "notify": "notify",
      "popups": "popups.keep_open"
    })[id] || ""
  }

  function groupFor(id) {
    if (id === "action") return { key: "defaults.action", options: ["left-click", "right-click", "move", "drag", "hold"] }
    if (id === "mode") return { key: "defaults.mode", options: ["hints", "grid"] }
    if (id === "scope") return { key: "defaults.scope", options: ["window", "monitor"] }
    if (id === "lifetime") return { key: "defaults.lifetime", options: ["single", "continuous"] }
    if (id === "osd-position") return { key: "osd.position", options: ["top", "center", "bottom"] }
    return null
  }

  function sliderFor(id) {
    if (id === "opacity")
      return { key: "opacity.default", value: Model.numberValue(cfg, "opacity.default", 0.8),
               minimum: 0.3, maximum: 1.0, step: 0.05, integer: false }
    if (id === "peek")
      // Up to 1.0, which is not a peek at all: the overlay is already fully
      // drawn, so holding the key has nothing to do. That is how it is turned
      // off, so the slider has to be able to reach it.
      return { key: "peek_alpha", value: Model.numberValue(cfg, "peek_alpha", 0.1),
               minimum: 0.05, maximum: 1.0, step: 0.05, integer: false }
    // Pixels per keypress during a hold. The big step is five of these and is
    // not a setting of its own, so this one slider moves both -- see
    // [imthemousenow.action.hold] in config.default.toml.
    if (id === "hold-step")
      return { key: "action.hold.step", value: Model.numberValue(cfg, "action.hold.step", 40),
               minimum: 5, maximum: 120, step: 5, integer: true }
    return null
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() { scrollItemIntoView(rowItems[rows[cursorRow]] || null) }

  // Row id -> the Item drawn for it, so the cursor can scroll to a row it
  // moved onto without every control knowing about the Flickable.
  property var rowItems: ({})
  function registerRow(id, item) {
    var next = rowItems
    next[id] = item
    rowItems = next
  }

  // --- reading and writing ---------------------------------------------------

  function refresh() {
    if (!envProcess.running) {
      envProcess.command = ["imthemousenow-config", "env"]
      envProcess.running = true
    }
    if (!supportProcess.running) {
      supportProcess.command = ["bash", "-c", "grep -qa WL_KBPTR_KEY_CHANNEL \"$(command -v wl-kbptr)\" 2>/dev/null"]
      supportProcess.running = true
    }
  }

  // Optimistic: paint the new value now and let the refresh confirm it. A
  // write is a ~40ms subprocess, and a switch that waits for it feels broken
  // even when it worked.
  function applyLocally(key, text) {
    var next = {}
    for (var name in cfg) next[name] = cfg[name]
    next[Model.envName(key)] = text
    cfg = next
  }

  function setValue(key, text) {
    if (Model.value(cfg, key, null) === text) return
    applyLocally(key, text)
    write(["imthemousenow-config", "set", key, text])
  }

  function setNumber(key, number, integer, minimum, maximum) {
    var clamped = Math.max(minimum, Math.min(maximum, number))
    setValue(key, Model.numberText(clamped, integer))
  }

  function toggleSetting(key) {
    if (!key) return
    applyLocally(key, Model.boolValue(cfg, key) ? "false" : "true")
    write(["imthemousenow-config", "toggle", key])
  }

  // One write at a time, queued. Two switches flipped in the same breath both
  // rewrite config.toml, and the second must read what the first wrote.
  property var writeQueue: []
  function write(command) {
    if (writeProcess.running) {
      writeQueue = writeQueue.concat([command])
      return
    }
    writeProcess.command = command
    writeProcess.running = true
  }

  function run(command) {
    if (bar) bar.run(command)
    else Quickshell.execDetached(["bash", "-lc", command])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorRow = 0
    chipIndex = -1
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: envProcess
    running: false
    command: []
    stdout: StdioCollector { id: envOut; waitForEnd: true }
    stderr: StdioCollector { id: envErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.cfg = Model.parseEnv(envOut.text)
        root.loaded = true
        root.lastError = ""
      } else {
        root.lastError = String(envErr.text || "").trim() || "Could not read the config"
      }
    }
  }

  Process {
    id: supportProcess
    running: false
    command: []
    onExited: function(exitCode) { root.popupsSupported = exitCode === 0 }
  }

  Process {
    id: writeProcess
    running: false
    command: []
    stderr: StdioCollector { id: writeErr; waitForEnd: true }
    onExited: function(exitCode) {
      // A refused write is the config program disagreeing with the panel, and
      // the optimistic value on screen is now a lie. Say why, and let the
      // refresh put the real value back.
      if (exitCode !== 0) root.lastError = String(writeErr.text || "").trim() || "The setting could not be written"
      if (root.writeQueue.length > 0) {
        var next = root.writeQueue[0]
        root.writeQueue = root.writeQueue.slice(1)
        writeProcess.command = next
        writeProcess.running = true
        return
      }
      root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰇀"
    onPressed: function(buttonCode) {
      // Right is the chord itself, so the widget is also the pointer's button
      // for anyone who would rather reach for it than for SUPER + ;.
      if (buttonCode === Qt.RightButton) root.run("imthemousenow")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // No cap of our own: this is a list of settings, not a feed, and it has a
    // last row. fittedContentHeight already clamps to the screen, so a display
    // with the room shows the whole thing and a short one scrolls.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "e") { root.cursorRow = root.rowIndex("edit"); root.cursorActive = true; root.activateCursor() }
        else if (key === "c") { root.cursorRow = root.rowIndex("check"); root.cursorActive = true; root.activateCursor() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Pointer"
            meta: root.loaded ? Model.chordSummary(root.cfg) : "Reading the config…"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰇀"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // --- the chord ---------------------------------------------------
          PanelSectionHeader {
            text: "SUPER + ;"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ChoiceRow {
            rowId: "action"
            label: "Default Action"
            options: [
              { value: "left-click", label: Model.actionLabel(root.cfg, "left-click") },
              { value: "right-click", label: Model.actionLabel(root.cfg, "right-click") },
              { value: "move", label: Model.actionLabel(root.cfg, "move") },
              { value: "drag", label: Model.actionLabel(root.cfg, "drag") },
              { value: "hold", label: Model.actionLabel(root.cfg, "hold") }
            ]
          }

          ChoiceRow { rowId: "mode"; label: "Default Mode"; options: ["hints", "grid"] }
          ChoiceRow { rowId: "scope"; label: "Default Scope"; options: ["window", "monitor"] }
          ChoiceRow { rowId: "lifetime"; label: "Default Lifetime"; options: ["single", "continuous"] }

          PanelSeparator { foreground: root.foreground }

          // --- overlay -------------------------------------------------------
          PanelSectionHeader {
            text: "OVERLAY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SliderRow {
            rowId: "opacity"
            label: "Opacity"
            description: "How much of the screen an overlay hides"
            valueText: Model.percentText(Model.numberValue(root.cfg, "opacity.default", 0.8))
          }

          SliderRow {
            rowId: "peek"
            label: "Peek"
            description: "Hold SPACE to fade the overlay and see what is under it. Not in the second half of a grid selection, where SPACE commits."
            valueText: Model.peekText(Model.numberValue(root.cfg, "peek_alpha", 0.1))
          }

          PanelSeparator { foreground: root.foreground }

          // --- hold ------------------------------------------------------------
          // Its own section, short as it is: a hold is the one ACTION with no
          // overlay in it, so it cannot sit under OVERLAY above.
          PanelSectionHeader {
            text: "HOLD"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SliderRow {
            rowId: "hold-step"
            label: "Hold speed"
            description: "How far a hold moves the pointer per keypress, while the button is down. Shift is five of these."
            valueText: String(Math.round(Model.numberValue(root.cfg, "action.hold.step", 40))) + "px"
          }

          PanelSeparator { foreground: root.foreground }

          // --- the action word -----------------------------------------------
          PanelSectionHeader {
            text: "ACTION WORD"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ToggleRow {
            rowId: "osd"
            label: "Action word"
            description: "A large word naming the action you moved into"
          }

          ChoiceRow {
            rowId: "osd-position"
            visible: root.osdEnabled
            label: "Position"
            options: ["top", "center", "bottom"]
          }

          PanelSeparator { foreground: root.foreground }

          // --- everything else -------------------------------------------------
          ToggleRow {
            rowId: "notify"
            label: "Notifications"
            description: "Desktop notifications for errors and refusals"
          }

          ToggleRow {
            rowId: "popups"
            visible: root.popupsSupported
            label: "Popup-safe overlay"
            description: "Experimental: keep context menus open by re-routing keypresses"
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Button {
              text: "Edit config…"
              iconText: ""
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              hasCursor: root.hasCursor("edit")
              tooltipText: "Everything this panel does not cover"
              onHovered: function(on) { if (on) root.setCursor("edit") }
              onClicked: { root.setCursor("edit"); root.activateCursor() }
            }

            Button {
              text: "Check"
              iconText: "󰗠"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              hasCursor: root.hasCursor("check")
              tooltipText: "Validate every config layer"
              onHovered: function(on) { if (on) root.setCursor("check") }
              onClicked: { root.setCursor("check"); root.activateCursor() }
            }
          }
        }
      }
    }
  }

  function setCursor(id) {
    var index = rowIndex(id)
    if (index < 0) return
    cursorActive = true
    cursorRow = index
    chipIndex = -1
  }

  // --- row components ----------------------------------------------------------
  // Each knows its row id and nothing else about the cursor: `hasCursor(id)`
  // is the single place a row and the keyboard agree on what is highlighted.

  component ToggleRow: Toggle {
    id: toggleRow
    property string rowId: ""

    width: parent.width
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    checked: Model.boolValue(root.cfg, root.toggleKey(rowId))
    hasCursor: root.hasCursor(rowId)
    enabled: root.loaded

    Component.onCompleted: root.registerRow(rowId, toggleRow)
    onHovered: function(on) { if (on) root.setCursor(rowId) }
    onClicked: { root.setCursor(rowId); root.toggleSetting(root.toggleKey(rowId)) }
  }

  component ChoiceRow: Column {
    id: choiceRow
    property string rowId: ""
    property string label: ""
    property var options: []

    readonly property var spec: root.groupFor(rowId)
    readonly property string current: spec ? Model.value(root.cfg, spec.key, "") : ""

    width: parent.width
    spacing: Style.spacing.labelGap

    Component.onCompleted: root.registerRow(rowId, choiceRow)

    Text {
      text: choiceRow.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    ButtonGroup {
      width: parent.width
      options: choiceRow.options
      value: choiceRow.current
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      focusable: false
      enabled: root.loaded
      // The panel cursor sits on the chosen chip until h/l moves it, so
      // arriving on the row shows you what is already set.
      cursorIndex: root.hasCursor(choiceRow.rowId)
        ? (root.chipIndex >= 0 ? root.chipIndex : choiceRow.spec.options.indexOf(choiceRow.current))
        : -1
      onChanged: function(value) {
        root.setCursor(choiceRow.rowId)
        root.chipIndex = choiceRow.spec.options.indexOf(value)
        root.setValue(choiceRow.spec.key, value)
      }
      onHovered: function(index, isHovered) {
        if (!isHovered) return
        root.setCursor(choiceRow.rowId)
        root.chipIndex = index
      }
    }
  }

  component SliderRow: Column {
    id: sliderRow
    property string rowId: ""
    property string label: ""
    property string description: ""
    property string valueText: ""

    readonly property var spec: root.sliderFor(rowId)

    width: parent.width
    spacing: Style.spacing.labelGap

    Component.onCompleted: root.registerRow(rowId, sliderRow)

    Row {
      width: parent.width
      Text {
        text: sliderRow.label
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Item {
        width: Math.max(0, sliderRow.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth)
        height: 1
      }
      Text {
        text: sliderRow.valueText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    CursorSurface {
      width: parent.width
      height: slider.implicitHeight + Style.spacing.controlGap
      hasCursor: root.hasCursor(sliderRow.rowId)
      foreground: root.foreground
      outline: true

      PanelSlider {
        id: slider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        enabled: root.loaded
        minimum: sliderRow.spec.minimum
        maximum: sliderRow.spec.maximum
        step: sliderRow.spec.step
        integer: sliderRow.spec.integer
        value: sliderRow.spec.value
        // `released`, not `moved`: a drag across the track is a dozen values,
        // and writing each one would be a dozen rewrites of config.toml to
        // land on the one the user meant.
        onReleased: function(v) {
          root.setCursor(sliderRow.rowId)
          root.setNumber(sliderRow.spec.key, v, sliderRow.spec.integer, sliderRow.spec.minimum, sliderRow.spec.maximum)
        }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) root.setCursor(sliderRow.rowId)
      }
    }

    Text {
      visible: sliderRow.description !== ""
      width: parent.width
      text: sliderRow.description
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
