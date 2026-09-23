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
// The settings outgrew one scrolling column, so they are in four tabs, each
// with a rule about what belongs in it rather than a feel:
//
//   Behaviour  changes what a keypress does
//   Overlay    what is drawn over the screen while you are choosing
//   Feedback   what is drawn because of what you chose
//   Advanced   needs an explanation before you would touch it
//
// Overlay and Feedback were one "Appearance" tab, and it came out nearly three
// times the size of the others. The line between them is not a count: the
// overlay is the surface you read a label off, and the word, the click mark and
// the scroll mark all appear because of something you did. It is also a seam
// the code already has -- wl-kbptr draws the first, imthemousenow-osd and
// PoolSpot.qml draw the second.
//
// Advanced is not a form for every tuning constant. `continuous.*`,
// `double_click.guard_ms`, `resize.step` and the rest are described in
// config.default.toml as "Not preferences. If one of these needs changing,
// something is wrong and the fix is probably code." A slider on those invites
// exactly the fiddling that warns against, and a wrong value there makes a
// subtly broken overlay rather than an ugly one. They stay behind Edit config.
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
  readonly property bool poolEnabled: Model.boolValue(cfg, "pool.enabled")

  // --- tabs --------------------------------------------------------------------
  readonly property var tabs: ["Behaviour", "Overlay", "Feedback", "Advanced"]
  property int currentTab: 0

  function selectTab(index) {
    var next = Math.max(0, Math.min(tabs.length - 1, index))
    if (next === currentTab) return
    currentTab = next
    // The cursor cannot keep a position that does not exist in the new tab, so
    // it goes to the top rather than to whatever happens to be at that index.
    cursorRow = 0
    chipIndex = -1
    openDropdown = ""
    if (panelFlick) panelFlick.contentY = 0
  }

  // --- cursor ------------------------------------------------------------------
  // One flat list of rows per tab, in the order they are drawn. j/k walks it;
  // h/l works inside whichever row it lands on (chips in a group, the value on
  // a slider, the highlight in a dropdown) and does nothing on a toggle.
  // Building it from the same conditions the rows are `visible` by keeps the
  // two from disagreeing when the action word is off or wl-kbptr is a stock
  // build.
  property bool cursorActive: false
  property int cursorRow: 0
  property int chipIndex: -1

  readonly property var rows: {
    if (currentTab === 0)
      return ["mode", "scope", "lifetime", "modifier-side", "hold-step", "notify"]

    // What is drawn over the screen while you are choosing.
    if (currentTab === 1)
      return ["opacity", "peek", "intro", "intro-ms", "theme-colors", "theme-font"]

    // What is drawn because of what you chose: the word naming the ACTION you
    // switched into, the mark where a click landed, the mark that says the
    // keyboard is a wheel. The seam is the one the code already has --
    // wl-kbptr draws the tab above, imthemousenow-osd and PoolSpot.qml draw
    // this one -- rather than one invented to even out a tab strip.
    if (currentTab === 2) {
      var says = ["word"]
      if (osdEnabled) says = says.concat(["word-position", "word-size", "word-ms", "word-fade", "word-on-start"])
      says.push("pool")
      if (poolEnabled) says = says.concat(["pool-radius", "pool-cell", "pool-style"])
      return says.concat(["scroll-mark"])
    }

    var deep = ["double-click"]
    if (popupsSupported) deep.push("popups")
    return deep.concat(["help-size", "settle", "edit", "check"])
  }

  function rowIndex(id) { return rows.indexOf(id) }
  function hasCursor(id) { return cursorActive && rows[cursorRow] === id }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy !== 0) {
      cursorRow = Math.max(0, Math.min(rows.length - 1, cursorRow + dy))
      chipIndex = -1
      openDropdown = ""
      scrollCursorIntoView()
      return
    }
    if (dx !== 0) nudgeRow(rows[cursorRow], dx)
  }

  // h / l on a row that has somewhere sideways to go. A group steps its chips
  // without committing -- Enter does that -- so walking past a choice does not
  // apply it on the way through. A dropdown steps its highlight the same way,
  // for the same reason and so the two read alike.
  function nudgeRow(id, dx) {
    var group = groupFor(id)
    if (group) {
      var current = chipIndex >= 0 ? chipIndex : group.options.indexOf(currentValue(id))
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
      // A dropdown that is shut opens on Enter; a second Enter commits the
      // highlighted option. Chips have nothing to open, so they commit at once.
      if (group.dropdown && openDropdown !== id) { openDropdown = id; return }
      var index = chipIndex >= 0 ? chipIndex : group.options.indexOf(currentValue(id))
      if (index >= 0) setGroup(id, group.options[index])
      openDropdown = ""
      return
    }
    if (id === "edit") { run("omarchy-launch-editor ~/.config/omarchy/imthemousenow/config.toml"); root.close(); return }
    if (id === "check") { run("omarchy-launch-floating-terminal-with-presentation 'imthemousenow-config check'"); root.close(); return }
    if (sliderFor(id)) return
    toggleSetting(toggleKey(id))
  }

  function toggleKey(id) {
    return ({
      "notify": "notify",
      "theme-colors": "theme_colors",
      "theme-font": "theme_font",
      "word-on-start": "osd.on_start",
      "pool": "pool.enabled",
      "double-click": "double_click.ms",
      "popups": "popups.keep_open"
    })[id] || ""
  }

  // --- the choices -------------------------------------------------------------
  // `dropdown: true` is a presentation choice, not a different kind of setting:
  // a list expected to grow stays one row at any length, where chips are a row
  // that gets longer until it wraps.
  //
  // `key: "word"` is the one group that is not a single config key -- see
  // wordValue() below.
  function groupFor(id) {
    if (id === "mode") return { key: "defaults.mode", options: ["hints", "grid"] }
    if (id === "scope") return { key: "defaults.scope", options: ["window", "monitor"] }
    if (id === "lifetime") return { key: "defaults.lifetime", options: ["single", "continuous"] }
    if (id === "modifier-side") return { key: "keyboard_modifier_side", options: ["left", "right"] }
    if (id === "word") return { key: "word", options: ["off", "font", "block"] }
    if (id === "word-position") return { key: "osd.position", options: ["top", "center", "bottom"] }
    if (id === "intro") return { key: "intro", options: ["bytes", "scanline", "random", "none"], dropdown: true }
    if (id === "pool-style") return { key: "pool.style", options: ["pool", "patchy", "lines", "cross", "random"], dropdown: true }
    return null
  }

  // The action word is three states over two config keys: off, the plain word,
  // or the word drawn as block art. The two keys could be set independently,
  // and were -- which let you turn block letters on for a word that was off,
  // a setting with nothing to mean. Three options is what a person actually
  // chooses between.
  function wordValue() {
    if (!Model.boolValue(cfg, "osd.enabled")) return "off"
    return Model.boolValue(cfg, "osd.ascii") ? "block" : "font"
  }

  function currentValue(id) {
    var group = groupFor(id)
    if (!group) return ""
    if (group.key === "word") return wordValue()
    return Model.value(cfg, group.key, "")
  }

  function setGroup(id, value) {
    var group = groupFor(id)
    if (!group) return
    if (group.key !== "word") { setValue(group.key, value); return }
    if (value === "off") { setValue("osd.enabled", "false"); return }
    // Two writes from one press. The write queue runs them in order, so the
    // second reads the config the first wrote.
    setValue("osd.enabled", "true")
    setValue("osd.ascii", value === "block" ? "true" : "false")
  }

  function optionLabel(id, value) {
    if (id === "word")
      return ({ "off": "Off", "font": "Font", "block": "Block letters" })[value] || value
    return value
  }

  // --- the numbers -------------------------------------------------------------
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
    if (id === "intro-ms")
      return { key: "intro_ms", value: Model.numberValue(cfg, "intro_ms", 250),
               minimum: 0, maximum: 600, step: 25, integer: true }
    // Pixels per keypress during a hold. The big step is five of these and is
    // not a setting of its own, so this one slider moves both -- see
    // [imthemousenow.action.hold] in config.default.toml.
    if (id === "hold-step")
      return { key: "action.hold.step", value: Model.numberValue(cfg, "action.hold.step", 40),
               minimum: 5, maximum: 120, step: 5, integer: true }
    if (id === "word-size")
      return { key: "osd.size", value: Model.numberValue(cfg, "osd.size", 120),
               minimum: 40, maximum: 200, step: 10, integer: true }
    if (id === "word-ms")
      return { key: "osd.ms", value: Model.numberValue(cfg, "osd.ms", 1000),
               minimum: 250, maximum: 3000, step: 250, integer: true }
    if (id === "word-fade")
      return { key: "osd.fade_ms", value: Model.numberValue(cfg, "osd.fade_ms", 250),
               minimum: 0, maximum: 1000, step: 50, integer: true }
    if (id === "pool-radius")
      return { key: "pool.radius", value: Model.numberValue(cfg, "pool.radius", 56),
               minimum: 16, maximum: 120, step: 8, integer: true }
    if (id === "pool-cell")
      return { key: "pool.cell", value: Model.numberValue(cfg, "pool.cell", 6),
               minimum: 2, maximum: 16, step: 1, integer: true }
    if (id === "scroll-mark")
      return { key: "action.scroll.mark_size", value: Model.numberValue(cfg, "action.scroll.mark_size", 44),
               minimum: 16, maximum: 96, step: 4, integer: true }
    if (id === "help-size")
      return { key: "help.size", value: Model.numberValue(cfg, "help.size", 15),
               minimum: 10, maximum: 28, step: 1, integer: true }
    if (id === "settle")
      return { key: "switch.settle_ms", value: Model.numberValue(cfg, "switch.settle_ms", 80),
               minimum: 0, maximum: 200, step: 10, integer: true }
    return null
  }

  // --- dropdowns ---------------------------------------------------------------
  // Which dropdown is showing its list, by row id, or "" for none. One at a
  // time: two open lists in a scrolling column is two things claiming the same
  // space below them.
  property string openDropdown: ""

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

  // --- reading and writing -----------------------------------------------------

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
    // Double click is not a boolean in the config: it is `system`, or a number
    // of ms, or 0 for off. On/off is what anyone actually wants of it, so the
    // toggle writes the two ends and a number set by hand reads as "on".
    if (key === "double_click.ms") {
      setValue(key, Model.value(cfg, key, "system") === "0" ? "system" : "0")
      return
    }
    applyLocally(key, Model.boolValue(cfg, key) ? "false" : "true")
    write(["imthemousenow-config", "toggle", key])
  }

  function isOn(id) {
    var key = toggleKey(id)
    if (key === "double_click.ms") return Model.value(cfg, key, "system") !== "0"
    return Model.boolValue(cfg, key)
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
    openDropdown = ""
    currentTab = 0
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
    // Measured from the content, never from the Flickable: the Flickable is
    // sized from the panel's height, so asking it how tall it is here would be
    // a binding loop.
    contentHeight: panel.fittedContentHeight(header.implicitHeight + Style.space(10) + column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        // An open dropdown swallows the first Escape: shutting the list is
        // what that key means while one is showing.
        if (root.openDropdown !== "") { root.openDropdown = ""; return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        // `[` and `]` move between this panel's own tabs. Tab itself cannot:
        // it is already switchPanel(), moving between widgets in the bar.
        if (t === "[") { root.selectTab(root.currentTab - 1); return }
        if (t === "]") { root.selectTab(root.currentTab + 1); return }
        if (key === "e") { root.selectTab(3); root.cursorRow = root.rowIndex("edit"); root.cursorActive = true; root.activateCursor() }
        else if (key === "c") { root.selectTab(3); root.cursorRow = root.rowIndex("check"); root.cursorActive = true; root.activateCursor() }
      }

      Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

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

        // --- the tab strip ---------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.tabs

            Rectangle {
              required property var modelData
              required property int index

              width: (header.width - Style.space(4) * (root.tabs.length - 1)) / root.tabs.length
              height: tabLabel.implicitHeight + Style.space(10)
              radius: Style.space(4)
              color: index === root.currentTab
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                : "transparent"

              Text {
                id: tabLabel
                anchors.centerIn: parent
                text: modelData
                color: index === root.currentTab ? root.accent : root.foreground
                opacity: index === root.currentTab ? 1.0 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              // The selected tab is underlined as well as tinted: a tint alone
              // is one cue, and one cue is the one a colourblind eye misses.
              Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Style.space(12)
                height: 2
                radius: 1
                color: root.accent
                visible: index === root.currentTab
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selectTab(index)
              }
            }
          }
        }
      }

      // --- the rows ------------------------------------------------------------
      Flickable {
        id: panelFlick
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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

          // ===== Behaviour ====================================================

          ChoiceRow {
            rowId: "mode"
            visible: root.currentTab === 0
            label: "Default Mode"
            description: "What SUPER + ; labels: what looks clickable, or a grid of cells"
          }

          ChoiceRow {
            rowId: "scope"
            visible: root.currentTab === 0
            label: "Default Scope"
            description: "Whether an overlay covers the focused window or the whole monitor"
          }

          ChoiceRow {
            rowId: "lifetime"
            visible: root.currentTab === 0
            label: "Default Lifetime"
            description: "One selection, or overlay after overlay until Escape"
          }

          ModifierSideRow {
            rowId: "modifier-side"
            visible: root.currentTab === 0
          }

          SliderRow {
            rowId: "hold-step"
            visible: root.currentTab === 0
            label: "Hold speed"
            description: "How far a hold moves the pointer per keypress, while the button is down. Shift is five of these."
            valueText: String(Math.round(Model.numberValue(root.cfg, "action.hold.step", 40))) + "px"
          }

          ToggleRow {
            rowId: "notify"
            visible: root.currentTab === 0
            label: "Notifications"
            description: "Desktop notifications for errors and refusals"
          }

          // ===== Appearance ===================================================

          SliderRow {
            rowId: "opacity"
            visible: root.currentTab === 1
            label: "Opacity"
            description: "How much of the screen an overlay hides"
            valueText: Model.percentText(Model.numberValue(root.cfg, "opacity.default", 0.8))
          }

          SliderRow {
            rowId: "peek"
            visible: root.currentTab === 1
            label: "Peek"
            description: "Hold SPACE to fade the overlay and see what is under it. Not in the second half of a grid selection, where SPACE commits."
            valueText: Model.peekText(Model.numberValue(root.cfg, "peek_alpha", 0.1))
          }

          DropdownRow {
            rowId: "intro"
            visible: root.currentTab === 1
            label: "Rad Animations"
            description: "How the overlay arrives. `random` picks a different one every time."
          }

          SliderRow {
            rowId: "intro-ms"
            visible: root.currentTab === 1
            label: "Animation speed"
            description: "How long the overlay takes to arrive. 0 puts it up whole, at once."
            valueText: String(Math.round(Model.numberValue(root.cfg, "intro_ms", 250))) + "ms"
          }

          ToggleRow {
            rowId: "theme-colors"
            visible: root.currentTab === 1
            label: "Theme colours"
            description: "Start from the colours the Omarchy theme renders"
          }

          ToggleRow {
            rowId: "theme-font"
            visible: root.currentTab === 1
            label: "Theme font"
            description: "Use the current Omarchy font for every mode that draws labels"
          }

          ChoiceRow {
            rowId: "word"
            visible: root.currentTab === 2
            label: "Action word"
            description: "A large word naming the action you moved into. Block letters draws it the way the Omarchy wordmark is drawn."
          }

          ChoiceRow {
            rowId: "word-position"
            visible: root.currentTab === 2 && root.osdEnabled
            label: "Position"
            indented: true
          }

          SliderRow {
            rowId: "word-size"
            visible: root.currentTab === 2 && root.osdEnabled
            label: "Size"
            indented: true
            valueText: String(Math.round(Model.numberValue(root.cfg, "osd.size", 120))) + "px"
          }

          SliderRow {
            rowId: "word-ms"
            visible: root.currentTab === 2 && root.osdEnabled
            label: "Time on screen"
            indented: true
            valueText: String(Math.round(Model.numberValue(root.cfg, "osd.ms", 1000))) + "ms"
          }

          SliderRow {
            rowId: "word-fade"
            visible: root.currentTab === 2 && root.osdEnabled
            label: "Fade"
            indented: true
            valueText: String(Math.round(Model.numberValue(root.cfg, "osd.fade_ms", 250))) + "ms"
          }

          ToggleRow {
            rowId: "word-on-start"
            visible: root.currentTab === 2 && root.osdEnabled
            label: "Announce on start"
            indented: true
            description: "Name the action a chord opens in, not only the ones you switch to"
          }

          PanelSeparator { visible: root.currentTab === 2; foreground: root.foreground }

          ToggleRow {
            rowId: "pool"
            visible: root.currentTab === 2
            label: "Click mark"
            description: "The patch of LCD pooling a click leaves where it landed. A hold marks its pointer whatever this says — that mark is the only sign a button is down."
          }

          SliderRow {
            rowId: "pool-radius"
            visible: root.currentTab === 2 && root.poolEnabled
            label: "Size"
            indented: true
            valueText: String(Math.round(Model.numberValue(root.cfg, "pool.radius", 56))) + "px"
          }

          SliderRow {
            rowId: "pool-cell"
            visible: root.currentTab === 2 && root.poolEnabled
            label: "Chunkiness"
            indented: true
            valueText: String(Math.round(Model.numberValue(root.cfg, "pool.cell", 6))) + "px"
          }

          DropdownRow {
            rowId: "pool-style"
            visible: root.currentTab === 2 && root.poolEnabled
            label: "Style"
            indented: true
          }

          PanelSeparator { visible: root.currentTab === 2; foreground: root.foreground }

          SliderRow {
            rowId: "scroll-mark"
            visible: root.currentTab === 2
            label: "Scroll mark size"
            description: "The mark the pointer wears while the keyboard is a mouse wheel"
            valueText: String(Math.round(Model.numberValue(root.cfg, "action.scroll.mark_size", 44))) + "px"
          }

          // ===== Advanced =====================================================

          ToggleRow {
            rowId: "double-click"
            visible: root.currentTab === 3
            label: "Double click"
            description: "Press the same key twice to double click. Off if a second press should always be a second click."
          }

          ToggleRow {
            rowId: "popups"
            visible: root.currentTab === 3 && root.popupsSupported
            label: "Popup-safe overlay"
            description: "Experimental: keep context menus open by re-routing keypresses"
          }

          SliderRow {
            rowId: "help-size"
            visible: root.currentTab === 3
            label: "Key sheet size"
            description: "Body text of the sheet F1 shows, in px"
            valueText: String(Math.round(Model.numberValue(root.cfg, "help.size", 15))) + "px"
          }

          SliderRow {
            rowId: "settle"
            visible: root.currentTab === 3
            label: "Switch settle"
            description: "How long to wait for the compositor after switching workspace or monitor, before measuring the screen again."
            valueText: String(Math.round(Model.numberValue(root.cfg, "switch.settle_ms", 80))) + "ms"
          }

          PanelSeparator { visible: root.currentTab === 3; foreground: root.foreground }

          Row {
            visible: root.currentTab === 3
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

  // --- row components ------------------------------------------------------------
  // Each knows its row id and nothing else about the cursor: `hasCursor(id)`
  // is the single place a row and the keyboard agree on what is highlighted.
  //
  // `indented` marks a row that belongs to the one above it -- the action
  // word's position and size, the click mark's style -- so a group reads as a
  // group without needing a header per pair.

  component RowLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component RowDescription: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component ToggleRow: Item {
    id: toggleRow
    property string rowId: ""
    property string label: ""
    property string description: ""
    property bool indented: false

    width: parent.width
    implicitHeight: toggleColumn.implicitHeight
    height: visible ? implicitHeight : 0

    Component.onCompleted: root.registerRow(rowId, toggleRow)

    Column {
      id: toggleColumn
      x: toggleRow.indented ? Style.space(12) : 0
      width: parent.width - x
      spacing: Style.spacing.labelGap

      // Toggle draws its own label and description -- this wrapper exists only
      // to carry the row id and the indent, which a plain Toggle has no place
      // for.
      Toggle {
        width: parent.width
        label: toggleRow.label
        description: toggleRow.description
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        checked: root.isOn(toggleRow.rowId)
        hasCursor: root.hasCursor(toggleRow.rowId)
        enabled: root.loaded
        onHovered: function(on) { if (on) root.setCursor(toggleRow.rowId) }
        onClicked: { root.setCursor(toggleRow.rowId); root.toggleSetting(root.toggleKey(toggleRow.rowId)) }
      }
    }
  }

  component ChoiceRow: Item {
    id: choiceRow
    property string rowId: ""
    property string label: ""
    property string description: ""
    property bool indented: false

    readonly property var spec: root.groupFor(rowId)
    readonly property string current: root.currentValue(rowId)
    readonly property var labels: {
      var out = []
      if (!spec) return out
      for (var i = 0; i < spec.options.length; i++)
        out.push({ value: spec.options[i], label: root.optionLabel(rowId, spec.options[i]) })
      return out
    }

    width: parent.width
    implicitHeight: choiceColumn.implicitHeight
    height: visible ? implicitHeight : 0

    Component.onCompleted: root.registerRow(rowId, choiceRow)

    Column {
      id: choiceColumn
      x: choiceRow.indented ? Style.space(12) : 0
      width: parent.width - x
      spacing: Style.spacing.labelGap

      RowLabel { text: choiceRow.label }

      ButtonGroup {
        width: parent.width
        options: choiceRow.labels
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
          root.setGroup(choiceRow.rowId, value)
        }
        onHovered: function(index, isHovered) {
          if (!isHovered) return
          root.setCursor(choiceRow.rowId)
          root.chipIndex = index
        }
      }

      RowDescription {
        visible: choiceRow.description !== ""
        width: parent.width
        text: choiceRow.description
      }
    }
  }

  // A list that stays one row however long it gets. The list opens inline,
  // below the row, rather than floating over it: the panel is a Flickable, and
  // a floating list has to be positioned against a surface that scrolls under
  // it. Inline costs a reflow and owes nothing to where the row happens to be.
  component DropdownRow: Item {
    id: dropRow
    property string rowId: ""
    property string label: ""
    property string description: ""
    property bool indented: false

    readonly property var spec: root.groupFor(rowId)
    readonly property string current: root.currentValue(rowId)
    readonly property bool listOpen: root.openDropdown === rowId
    // A value the list does not offer is shown as itself rather than snapped to
    // the first option. `intro` accepts a list -- "bytes,scanline" means pick
    // between those two -- which a dropdown of single values cannot express,
    // and a panel must never quietly rewrite a setting it merely failed to
    // understand.
    readonly property bool unknown: spec && spec.options.indexOf(current) < 0

    width: parent.width
    implicitHeight: dropColumn.implicitHeight
    height: visible ? implicitHeight : 0

    Component.onCompleted: root.registerRow(rowId, dropRow)

    Column {
      id: dropColumn
      x: dropRow.indented ? Style.space(12) : 0
      width: parent.width - x
      spacing: Style.spacing.labelGap

      RowLabel { text: dropRow.label }

      CursorSurface {
        width: parent.width
        height: currentText.implicitHeight + Style.space(12)
        hasCursor: root.hasCursor(dropRow.rowId)
        foreground: root.foreground
        outline: true

        Text {
          id: currentText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          text: dropRow.current === "" ? "—" : dropRow.current
          color: dropRow.unknown ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          text: dropRow.listOpen ? "▴" : "▾"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          enabled: root.loaded
          onEntered: root.setCursor(dropRow.rowId)
          onClicked: root.openDropdown = dropRow.listOpen ? "" : dropRow.rowId
        }
      }

      Column {
        width: parent.width
        visible: dropRow.listOpen
        spacing: 1

        Repeater {
          model: dropRow.spec ? dropRow.spec.options : []

          Rectangle {
            required property var modelData
            required property int index

            width: parent.width
            height: optionText.implicitHeight + Style.space(10)
            radius: Style.space(3)
            readonly property bool highlighted:
              root.hasCursor(dropRow.rowId) && root.chipIndex >= 0
                ? root.chipIndex === index
                : modelData === dropRow.current
            color: highlighted
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
              : "transparent"

            Text {
              id: optionText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              text: root.optionLabel(dropRow.rowId, modelData)
              color: modelData === dropRow.current ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: { root.setCursor(dropRow.rowId); root.chipIndex = index }
              onClicked: {
                root.setCursor(dropRow.rowId)
                root.setGroup(dropRow.rowId, modelData)
                root.openDropdown = ""
              }
            }
          }
        }
      }

      RowDescription {
        visible: dropRow.description !== ""
        width: parent.width
        text: dropRow.description
      }
    }
  }

  // Which half of the keyboard commands, drawn rather than named.
  //
  // The setting is spatial -- it says which side flips SCOPE, MODE and
  // LIFETIME and which side holds modifiers down for the click -- and two
  // chips reading "left" and "right" make you translate that into a picture
  // yourself. A split keyboard is the drawing that states it: the gap down the
  // middle IS the setting. The command half is marked with the three keys it
  // commands with, so the picture says what the side does rather than only
  // which side it is.
  component ModifierSideRow: Item {
    id: sideRow
    property string rowId: "modifier-side"

    readonly property string current: Model.value(root.cfg, "keyboard_modifier_side", "right")
    // The COMMAND side is the other one: `keyboard_modifier_side` names where
    // the modifiers are held, and what a person is choosing between is which
    // hand gives orders.
    readonly property string commandSide: current === "left" ? "right" : "left"

    width: parent.width
    implicitHeight: sideColumn.implicitHeight
    height: visible ? implicitHeight : 0

    Component.onCompleted: root.registerRow(rowId, sideRow)

    Column {
      id: sideColumn
      width: parent.width
      spacing: Style.spacing.labelGap

      RowLabel { text: "Modifier side" }

      Row {
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: ["left", "right"]

          Item {
            id: half
            required property var modelData
            readonly property bool isCommand: modelData === sideRow.commandSide
            readonly property bool highlighted: root.hasCursor(sideRow.rowId) &&
              (root.chipIndex >= 0
                ? (root.chipIndex === 0 ? modelData === "left" : modelData === "right")
                : isCommand)

            width: (sideColumn.width - Style.space(10)) / 2
            height: Style.space(56)

            // The half itself: a slab of keys, tilted away from the middle the
            // way the two halves of a split keyboard sit under the hands.
            Rectangle {
              anchors.centerIn: parent
              width: parent.width - Style.space(8)
              height: parent.height - Style.space(14)
              radius: Style.space(5)
              rotation: half.modelData === "left" ? -6 : 6
              color: half.isCommand
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                : "transparent"
              border.width: half.highlighted ? 2 : 1
              border.color: half.isCommand ? root.accent
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, half.highlighted ? 0.7 : 0.3)
              antialiasing: true

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)

                // Two rows of plain keys, then the row that says what this half
                // is for: the three command keys, or the word "hold".
                Repeater {
                  model: 2
                  Row {
                    spacing: Style.space(3)
                    Repeater {
                      model: 4
                      Rectangle {
                        width: Style.space(9)
                        height: Style.space(7)
                        radius: 2
                        color: half.isCommand ? root.accent : root.foreground
                        opacity: half.isCommand ? 0.5 : 0.25
                      }
                    }
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: half.isCommand ? "⇧ ⌥ ⌃" : "hold"
                  color: half.isCommand ? root.accent : root.foreground
                  opacity: half.isCommand ? 1.0 : 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              enabled: root.loaded
              onEntered: {
                root.setCursor(sideRow.rowId)
                root.chipIndex = half.modelData === "left" ? 0 : 1
              }
              // Clicking a half says "this half commands", so the setting --
              // which names the modifier side -- is written as the other one.
              onClicked: {
                root.setCursor(sideRow.rowId)
                root.setValue("keyboard_modifier_side", half.modelData === "left" ? "right" : "left")
              }
            }
          }
        }
      }

      RowDescription {
        width: parent.width
        text: sideRow.commandSide === "left"
          ? "Left commands: Shift flips scope, Alt flips mode, Ctrl flips lifetime. Right holds modifiers down for the click."
          : "Right commands: Shift flips scope, Alt flips mode, Ctrl flips lifetime. Left holds modifiers down for the click."
      }
    }
  }

  component SliderRow: Item {
    id: sliderRow
    property string rowId: ""
    property string label: ""
    property string description: ""
    property string valueText: ""
    property bool indented: false

    readonly property var spec: root.sliderFor(rowId)

    width: parent.width
    implicitHeight: sliderColumn.implicitHeight
    height: visible ? implicitHeight : 0

    Component.onCompleted: root.registerRow(rowId, sliderRow)

    Column {
      id: sliderColumn
      x: sliderRow.indented ? Style.space(12) : 0
      width: parent.width - x
      spacing: Style.spacing.labelGap

      Row {
        width: parent.width
        RowLabel { id: sliderLabel; text: sliderRow.label }
        Item {
          width: Math.max(0, sliderColumn.width - sliderLabel.implicitWidth - sliderValue.implicitWidth)
          height: 1
        }
        Text {
          id: sliderValue
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

      RowDescription {
        visible: sliderRow.description !== ""
        width: parent.width
        text: sliderRow.description
      }
    }
  }
}
