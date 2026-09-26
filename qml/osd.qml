// One large word, solid then departing: which ACTION you just moved into --
// drawn as block art in the FIGlet font the Omarchy wordmark is set in, so the
// announcement looks like the desktop it belongs to. bin/imthemousenow-osd does
// the rendering and hands the finished block over; if it could not, the art is
// empty and the plain word is drawn instead, which is what every failure to
// produce art falls back to.
//
// Same trick as qml/pool.qml's click mark, for the same reason: quickshell
// takes longer to start (~300ms) than an announcement lasts, so this process is
// started once and left running rather than once per word. bin/imthemousenow-osd
// writes each announcement to MOUSENOW_OSD_REPORT -- one JSON object, the whole
// file, `stamp` a nanosecond clock so two identical words in a row still count
// as a new one -- and this watches that file the way qml/halo.qml watches the
// hold's position file. A new stamp replays the whole thing from the top; there
// is no more "exit after the fade", because there is no longer a process per
// word to exit.
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
//      what dismisses the popup you were aiming at (the fork's "Take keys from a channel" commit), and it
//      would steal the keys the overlay's own submap is bound to.
//      WlrKeyboardFocus.None, never Exclusive.
//
// `outro` picks how the word leaves, in the same spirit as the overlay's own
// `intro` (config: [imthemousenow] intro, "bytes" | "scanline" | "random"):
//
//   "fade"      the plain opacity fade this always did (default)
//   "bytes"     the word eaten away a square at a time, in no order
//   "interlace" one field then the other, each sweeping down
//   "scanline"  sync loss: bands thrown off true until there are none left
//   "dropout"   scanline stood on its end -- columns pulled out of line
//   "beam"      a raster scan un-painting the word, top to bottom
//   "random"    one of the five, a different one each time
//   "none"      gone the instant the solid time is up
//
// These are the overlay's own entrance run backwards, name for name -- all but
// two of the fork's seven. `roll` throws three copies of the picture across the
// screen at once and `shuffle` reassembles it out of the wrong pieces: both are
// the right size of gesture for a whole overlay arriving, and too much of one
// for a word. They are built the way the fork builds it (../wl-kbptr,
// src/transition.c)
// rather than in a vocabulary of their own -- cell_noise() and snap() below
// are that file's, and each animation is the draw_* of the same name read
// with `t` running the other way. Two of them are one cell mask, two are
// slices of the picture displaced, and the last has a mechanism of its own.
// Two rules come with that and matter more than they look:
//
//   * A cell is there or it is gone. Nothing fades, and nothing is drawn at
//     part opacity -- a translucent word reads as the announcement having lost
//     its colour, which is the one thing the word is for. The earlier version
//     of `bytes` jittered the whole label's opacity between 0.25 and 1, and
//     that is exactly how it read.
//   * Displacement is snapped to the cell. A picture going wrong jumps; it
//     does not slide.
//
// Both work on one snapshot of the word (`wordTexture`), taken when the
// departure begins, so the text is laid out and rasterised once rather than
// per frame -- and so the bands are pieces of one picture rather than many
// redrawings of it.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  function env(name, fallback) {
    const value = Quickshell.env(name);
    return (value === undefined || value === null || value === "") ? fallback : value;
  }

  readonly property string reportPath: env("MOUSENOW_OSD_REPORT", "")
  // A file of its own rather than a field in the report above, and for one
  // reason: a raise and a word can be asked for by two processes in the same
  // instant (the wrapper opening an overlay, imthemousenow-steer announcing
  // the ACTION it opened in), and one file means one of them is lost. A lost
  // raise costs a word its colour; a lost word costs the announcement.
  readonly property string raisePath: env("MOUSENOW_OSD_RAISE", "")

  // Everything below used to be read once from the environment, because a
  // fresh process was started for every word. Now one process outlives many
  // words, so these are the last report read rather than argv, and `trigger()`
  // is what makes a new one show.
  property string stamp: ""
  property string text: ""
  property string art: ""
  readonly property bool drawingArt: root.art !== ""
  property color textColor: "#ffffff"
  property string family: "sans-serif"
  property int size: 120
  property int totalMs: 500
  property int fadeMs: 250
  property string place: "top"
  property string outro: "fade"
  // Resolved once per trigger, so "random" does not re-roll mid-departure.
  property string resolvedOutro: "fade"
  // What "random" picks from: the animations, and never `fade`. A person who
  // asked for random asked for something to happen -- a coin that lands on the
  // plain fade half the time reads as the setting not having worked. `none` is
  // out for the same reason. Adding an animation below means adding it here.
  readonly property var randomOutros: ["bytes", "interlace", "scanline", "dropout", "beam"]
  property string lastOutro: ""

  // The cell: what `bytes` eats a square of, and what a `scanline` band's
  // displacement is snapped to. The fork takes this as a setting (intro_chunk,
  // 48 by default) because it is coming apart a whole screen; here it is tied
  // to the word, so a big word comes apart in big pieces and a small one in
  // small ones. Block art is nine rows of cells already, so it wants a coarser
  // grid than a single line of letters does.
  readonly property int chunk: Math.max(8, Math.round(label.font.pixelSize / (root.drawingArt ? 2 : 4)))
  // A line rather than a square, exactly as draw_scanline does it: the same
  // setting that gives big squares in `bytes` gives thin bands here.
  readonly property int band: Math.max(2, Math.round(root.chunk / 4))

  // 0 while the word is whole, 1 once it is gone. Every departure that is more
  // than a fade reads this rather than animating anything of its own, so there
  // is one clock over fadeMs and the arithmetic below it is the fork's, run
  // backwards -- its `t` is our `1 - departure`.
  property real departure: 0
  // Re-rolled per word, so the same word does not come apart the same way
  // twice. The fork seeds per transition for the same reason.
  property int seed: 0
  // Which mechanism is up, rather than which animation: two of the five are a
  // cell mask, two are slices of the picture displaced, and the last has one
  // of its own. Nothing is up when the word is whole or merely fading.
  readonly property var maskOutros: ["bytes", "interlace"]
  readonly property var sliceOutros: ["scanline", "dropout"]
  property bool masking: false
  property bool slicing: false
  property bool beaming: false
  // True for every departure that hides the live word behind a picture of it.
  readonly property bool pictured: root.masking || root.slicing || root.beaming
  // `dropout` is `scanline` stood on its end, which is the only difference
  // between them, so one Repeater draws both.
  readonly property bool vertical: root.resolvedOutro === "dropout"

  onDepartureChanged: if (root.masking) cellMask.requestPaint();

  // cell_noise() from src/transition.c, in the same arithmetic (Math.imul is
  // what gives JavaScript the C multiply): a fixed, well-scattered number in
  // [0, 1) for a cell, so a cell's turn comes at the same moment in every
  // frame and the order looks random rather than swept.
  function cellNoise(x, y, seed) {
    let h = (Math.imul(x, 0x8da6b343) ^ Math.imul(y, 0xd8163841) ^ Math.imul(seed, 0xcb1ab31f)) >>> 0;
    h = (h ^ (h >>> 15)) >>> 0;
    h = Math.imul(h, 0x2c1b3c6d) >>> 0;
    h = (h ^ (h >>> 12)) >>> 0;
    h = Math.imul(h, 0x297a2d39) >>> 0;
    h = (h ^ (h >>> 15)) >>> 0;
    return (h & 0xffffff) / 0x1000000;
  }

  // snap(): a whole number of cells, so nothing ever lands half a cell out.
  function snapTo(v, size) {
    return Math.floor(v / size) * size;
  }

  // The fork's `t` -- 1 when the picture is whole, 0 when it is not there.
  // Every level function below is the fork's, unchanged, read through this.
  readonly property real t: 1 - root.departure

  // How much of the word a cell shows, 0 or 1 -- level_bytes() and
  // level_interlace(), and the reason both can share one mask.
  function cellLevel(x, y, cols, rows) {
    switch (root.resolvedOutro) {
      case "interlace":
        // One field then the other, each sweeping down the way the beam does.
        const field = (y & 1) ? 0.5 : 0;
        const down = rows > 1 ? y / (rows - 1) : 0;
        return field + down * 0.5 < root.t ? 1 : 0;
      default:
        return root.cellNoise(x, y, root.seed) < root.t ? 1 : 0;
    }
  }

  // Where the word actually is inside the surface, which is not where the
  // label is: the label fills the whole surface and aligns the word inside
  // itself. Everything below works on this box rather than on the surface, so
  // a cell mask is the size of a word and not the size of a monitor.
  readonly property rect wordRect: {
    const w = Math.min(label.contentWidth, label.width);
    const h = Math.min(label.contentHeight, label.height);
    const x = Math.max(0, (label.width - w) / 2);
    const y = label.y + (root.place === "top" ? 0
      : root.place === "bottom" ? Math.max(0, label.height - h)
      : Math.max(0, (label.height - h) / 2));
    return Qt.rect(x, y, w, h);
  }

  // A box to sit inside, monitor-relative, as WxH+X+Y -- what window scope
  // passes so the word lands on the window the overlay is confined to rather
  // than in the middle of a screen the overlay is not covering. Empty means the
  // whole output, which is what monitor scope wants.
  property string regionSpec: ""
  readonly property var region: {
    const m = /^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$/.exec(root.regionSpec);
    return m ? { w: parseInt(m[1]), h: parseInt(m[2]), x: parseInt(m[3]), y: parseInt(m[4]) } : null;
  }
  property string outputName: ""
  // The inset from the edge the word is anchored to. A window is a smaller
  // space than a screen, so the same 80px would read as "most of the way down".
  readonly property int inset: root.region ? 24 : 80

  function readReport() {
    const raw = report.text();
    if (raw === undefined || raw === null || raw === "") return;
    let parsed;
    // A file caught half-written (see bin/imthemousenow-osd's temp-file-then-
    // move) reads as nothing, and the next look -- the watch firing again, or
    // the poll below -- sees the finished write.
    try { parsed = JSON.parse(raw); } catch (e) { return; }
    if (!parsed || parsed.stamp === undefined || parsed.stamp === root.stamp) return;

    root.stamp = parsed.stamp;
    root.text = parsed.text || "";
    root.art = parsed.art || "";
    root.textColor = parsed.color || "#ffffff";
    root.family = parsed.font || "sans-serif";
    root.size = parseInt(parsed.size) || 120;
    root.totalMs = parseInt(parsed.ms) || 500;
    root.fadeMs = Math.min(parseInt(parsed.fadeMs) || 250, root.totalMs);
    root.place = parsed.position || "top";
    root.regionSpec = parsed.region || "";
    root.outputName = parsed.output || "";
    root.outro = parsed.outro || "fade";
    root.trigger();
  }

  FileView {
    id: report
    path: root.reportPath
    // The file is replaced whole on every word, so the watch is what makes a
    // switch show up rather than sitting on whichever word was on screen when
    // this process started.
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.readReport(); }
    onLoaded: root.readReport()
  }

  // The poke. Nothing in this file cares what the file SAYS -- that it
  // changed is the whole message -- so there is no parsing to get wrong.
  property string raiseStamp: ""
  function readRaise() {
    const raw = raiseReport.text();
    if (raw === undefined || raw === null || raw === "" || raw === root.raiseStamp) return;
    const first = root.raiseStamp === "";
    root.raiseStamp = raw;
    // The first read is this process finding whatever poke was last written,
    // which may be from an overlay long gone. Nothing to do about that one:
    // a process that has only just started mapped its surface last anyway.
    if (!first) root.requestRaise();
  }

  FileView {
    id: raiseReport
    path: root.raisePath
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.readRaise(); }
    onLoaded: root.readRaise()
  }

  // The belt to that watch's braces, for the same reason qml/pool.qml and
  // qml/halo.qml both poll too: a watch can be missed when the file is
  // replaced out from under it, and a look ten times a second is far below
  // what a switch needs and far above what "it got missed" takes to notice.
  Timer {
    running: true
    interval: 100
    repeat: true
    onTriggered: { report.reload(); root.readReport(); raiseReport.reload(); root.readRaise(); }
  }

  // Nothing pressed this process into existence forever -- it is started the
  // moment the first word of a session needs somewhere to land, and stays only
  // because more words usually follow. If none do for a long while, quitting
  // is cheaper than sitting idle for a desktop session that may run for days;
  // the next word simply pays the ~300ms start again. Any trigger pushes this
  // back out.
  Timer {
    id: idleTimeout
    running: true
    interval: 15 * 60 * 1000
    onTriggered: Qt.quit()
  }

  // Replace whatever is mid-departure rather than letting two words fight over
  // the same label: stop every mechanism before resetting the state each of
  // them animates, then start the one this word actually asked for.
  function trigger() {
    idleTimeout.restart();
    solid.stop();
    fadeAnim.stop();
    departAnim.stop();
    root.clearPicture();
    root.departure = 0;
    root.seed = Math.floor(Math.random() * 0x7fffffff);
    label.opacity = 1;
    root.resolvedOutro = root.nextOutro();
    solid.start();
  }

  // Put this surface back on top of the overlay layer.
  //
  // wl-kbptr's own surface is on the same layer this one is (`overlay`, the
  // topmost wlr-layer-shell has), and within a layer a compositor stacks by
  // the order surfaces were mapped -- last mapped, on top. That used to be
  // this one for free: a fresh process per word mapped its surface after the
  // overlay had mapped its own. Keeping the process warm quietly reversed it,
  // so every word after the first was announced UNDERNEATH wl-kbptr's dim and
  // its hint labels, which is not a subtle thing to look at: the word keeps
  // its geometry and its animation and loses its colour, exactly as though
  // the theme had washed out.
  //
  // Unmapping and remapping is the whole of the fix -- there is nothing above
  // `overlay` to move to. What it is NOT is something to do per word: the
  // surface takes about 150ms to come back (the configure round trip, and
  // quickshell building the window again), and a word that arrives 150ms
  // after the key gives back most of what keeping this process warm bought.
  //
  // So it happens at the two moments when nothing is on screen to be delayed:
  // when the wrapper says an overlay has just gone up (`--raise`, which is
  // what `raiseReport` carries), and after a word has finished leaving. The
  // second is the backstop for the first: if a poke is ever missed or
  // mistimed, at most the first word of that overlay is dimmed, and every one
  // after it is above where it belongs.
  function raise() {
    root.raisePending = false;
    panel.visible = false;
    // Next event loop turn, so the unmap is a real one rather than two
    // property writes the compositor never sees apart.
    Qt.callLater(() => panel.visible = true);
  }

  // A raise asked for while a word is up would blink that word out mid-
  // sentence, so it waits for the departure that is already coming.
  property bool raisePending: false
  function requestRaise() {
    if (solid.running || fadeAnim.running || departAnim.running || label.opacity > 0) {
      root.raisePending = true;
      return;
    }
    root.raise();
  }

  function clearPicture() {
    root.masking = false;
    root.slicing = false;
    root.beaming = false;
  }

  // Random never picks the one it just showed, so two words in a row always
  // leave differently -- which is most of what "random" is for. The same rule
  // as qml/pool.qml's click mark, for the same reason.
  function nextOutro() {
    if (root.outro !== "random") {
      return root.outro;
    }
    const choices = root.randomOutros.filter(o => o !== root.lastOutro);
    root.lastOutro = choices[Math.floor(Math.random() * choices.length)];
    return root.lastOutro;
  }

  function beginDeparture() {
    if (root.resolvedOutro === "none") {
      root.endDeparture();
      return;
    }
    if (root.resolvedOutro === "fade") {
      fadeAnim.start();
      return;
    }
    // Everything else works on a picture of the word rather than on the word,
    // and the picture has to be taken before the live one is hidden behind it
    // -- which is what `hideSource` does the moment a mechanism goes up.
    wordTexture.scheduleUpdate();
    root.masking = root.maskOutros.indexOf(root.resolvedOutro) >= 0;
    root.slicing = root.sliceOutros.indexOf(root.resolvedOutro) >= 0;
    root.beaming = root.resolvedOutro === "beam";
    if (root.masking) {
      cellMask.requestPaint();
    }
    departAnim.restart();
  }

  // What every departure that is not a fade ends with: the word gone, the
  // pieces put away, and the plain label back in place for the next word.
  function endDeparture() {
    label.opacity = 0;
    root.clearPicture();
    root.departure = 0;
    // Free here and nowhere else: the screen is empty, so the ~150ms the
    // surface takes to come back is 150ms of nothing being shown anyway.
    root.raise();
  }

  // Solid first, then whichever departure was asked for. The solid part is
  // when the word is read; the departure is what says "this is telling you
  // something, not asking you for something", so it can be ignored rather than
  // dismissed.
  SequentialAnimation {
    id: solid
    PauseAnimation { duration: Math.max(1, root.totalMs - root.fadeMs) }
    ScriptAction { script: root.beginDeparture() }
  }

  // The plain fade: opacity to nothing over fadeMs. Still the default, and
  // still what "outro = fade" or an unrecognised value falls back to.
  NumberAnimation {
    id: fadeAnim
    target: label
    property: "opacity"
    from: 1
    to: 0
    duration: root.fadeMs
    easing.type: Easing.InQuad
    onFinished: root.endDeparture()
  }

  // One clock for `bytes` and `scanline` both: 0 to 1 over fadeMs, linear
  // because the fork's own curves are in the arithmetic each of them does with
  // it (the displacement left in a band is `departure` squared) and easing it
  // here would bend those twice.
  NumberAnimation {
    id: departAnim
    target: root
    property: "departure"
    from: 0
    to: 1
    duration: root.fadeMs
    easing.type: Easing.Linear
    onFinished: root.endDeparture()
  }

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
    // Nothing this transient may push a bar or a window aside.
    exclusionMode: ExclusionMode.Ignore
    // The empty input region. See the header: this is the click-through.
    mask: Region {}

    // The word, and the only thing that draws it. A departure takes a picture
    // of this and hides it (`hideSource`), then puts the picture back on
    // screen in pieces -- so this is an Item with the label inside rather than
    // the label itself: a ShaderEffectSource applies its source item's
    // CHILDREN's transforms but not the source item's own, and the art's
    // centring is one of those transforms.
    Item {
      id: stage
      anchors.fill: parent

      Text {
        id: label
        // Filling the surface and aligning inside it, rather than anchoring to an
        // edge: this is what makes `center` mean the middle of the window in
        // window scope and the middle of the screen in monitor scope, with no
        // second code path.
        anchors.fill: parent
        anchors.topMargin: root.place === "top" ? root.inset : 0
        anchors.bottomMargin: root.place === "bottom" ? root.inset : 0
        opacity: 0
        // Qt centres each line on its own, and leaves a line's trailing spaces
        // out of its width when it does, so centred art is sheared row by row.
        // The art is laid out from the left instead, where every row starts in
        // the same column, and the block is moved to the middle as one piece by
        // the Translate below.
        horizontalAlignment: root.drawingArt ? Text.AlignLeft : Text.AlignHCenter
        // One transform: the art, laid out from the left so its rows stay in
        // column, moved to the middle as one piece. Nothing a departure does is
        // a transform of the whole label any more -- see the header.
        transform: Translate { x: root.drawingArt ? Math.max(0, (label.width - label.contentWidth) / 2) : 0 }
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
    }

    // The snapshot every departure works on: the word as drawn, once, at the
    // moment it begins to leave. `hideSource` takes the live word off the
    // screen for as long as the pieces are up, and puts it back after.
    ShaderEffectSource {
      id: wordTexture
      visible: false
      sourceItem: stage
      sourceRect: root.wordRect
      width: root.wordRect.width
      height: root.wordRect.height
      hideSource: root.pictured
      live: false
    }

    // bytes: the word eaten into the screen a square at a time, in no order.
    // One mask, one rect per cell, and the whole word composited through it --
    // the QML of paint_cells(), and a mask here for the reason it is a mask in
    // C: however many cells there are, it stays one paint rather than a scene
    // of thousands of items.
    Canvas {
      id: cellMask
      x: root.wordRect.x
      y: root.wordRect.y
      width: root.wordRect.width
      height: root.wordRect.height
      // Cells are `cw` by `ch`: the same for a grid of squares, and different
      // for the bands `interlace` works in -- paint_cells()'s own two
      // arguments, for the same reason it has two.
      readonly property real cw: root.resolvedOutro === "interlace" ? width : root.chunk
      readonly property real ch: root.resolvedOutro === "interlace" ? root.band : root.chunk
      onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.fillStyle = "white";
        const cols = Math.ceil(width / cw);
        const rows = Math.ceil(height / ch);
        for (let y = 0; y < rows; y++) {
          for (let x = 0; x < cols; x++) {
            // 0 or 1, never in between: a cell is drawn whole or not drawn.
            if (root.cellLevel(x, y, cols, rows) > 0) {
              ctx.fillRect(x * cw, y * ch, cw, ch);
            }
          }
        }
      }
    }

    ShaderEffectSource {
      id: maskTexture
      visible: false
      sourceItem: cellMask
      // The mask is never drawn itself; it only says which cells survive.
      hideSource: true
      live: true
    }

    MultiEffect {
      visible: root.masking
      x: root.wordRect.x
      y: root.wordRect.y
      width: root.wordRect.width
      height: root.wordRect.height
      source: wordTexture
      maskEnabled: true
      maskSource: maskTexture
    }

    // scanline, and dropout which is scanline stood on its end: the word comes
    // apart into bands (or columns), each thrown further off true than the
    // last -- sync loss, and tape dropout. draw_scanline() and draw_dropout()
    // backwards. Each piece is a slice of the one snapshot, so this is a few
    // dozen quads being moved rather than a few dozen redrawings of the word.
    // They exist only while one of the two is running.
    Repeater {
      model: !root.slicing ? 0
        : Math.ceil((root.vertical ? root.wordRect.width : root.wordRect.height)
          / (root.vertical ? root.chunk : root.band))
      delegate: ShaderEffectSource {
        required property int index
        // The same two draws from the same noise the C makes: when this piece
        // gives up, and how far it is thrown.
        readonly property real leavesAt: root.cellNoise(index, 1, root.seed)
        readonly property real thrown: root.cellNoise(index, 0, root.seed)
        readonly property real step: root.vertical ? root.chunk : root.band
        // Half the pieces are there to the end; the rest go over the last
        // half, so it comes apart rather than blinking out.
        visible: leavesAt * 0.5 <= root.t
        // Squared, so it holds together and then lets go rather than sliding
        // apart at a constant rate -- and snapped to the cell, because a
        // picture going wrong jumps.
        readonly property real offset: root.snapTo(
          (thrown * 2 - 1) * (root.vertical ? root.wordRect.height : root.wordRect.width)
            * 0.35 * root.departure * root.departure, root.chunk)
        sourceItem: wordTexture
        sourceRect: root.vertical
          ? Qt.rect(index * step, 0, step, root.wordRect.height)
          : Qt.rect(0, index * step, root.wordRect.width, step)
        width: root.vertical ? step : root.wordRect.width
        height: root.vertical ? root.wordRect.height : step
        live: false
        Component.onCompleted: scheduleUpdate()
        x: root.wordRect.x + (root.vertical ? index * step : offset)
        y: root.wordRect.y + (root.vertical ? offset : index * step)
      }
    }

    // beam: a raster scan, un-painting the word top to bottom, with the line
    // itself brighter than what it is scanning -- draw_beam() backwards. What
    // is left is what the beam has not reached yet.
    // In a Repeater, like the rest, and not for the repetition: a delegate is
    // built when the departure starts, so its `scheduleUpdate` captures THIS
    // word. An item that exists from startup captures whatever was on screen
    // when the process began, which is nothing, and beams an empty picture.
    Repeater {
      model: root.beaming ? 1 : 0
      delegate: Item {
      x: root.wordRect.x
      y: root.wordRect.y
      width: root.wordRect.width
      height: root.wordRect.height
      // A little past the bottom, so the last band goes and the beam is off
      // the word before the departure ends rather than parked on the edge.
      readonly property real edge: root.snapTo(
        root.departure * (height + root.chunk * 2), root.band)
      Item {
        y: parent.edge
        width: parent.width
        height: Math.max(0, parent.height - parent.edge)
        clip: true
        ShaderEffectSource {
          sourceItem: wordTexture
          live: false
          Component.onCompleted: scheduleUpdate()
          y: -parent.y
          width: root.wordRect.width
          height: root.wordRect.height
        }
      }
      // The word's own colour, lightened: the line belongs to the theme
      // without this knowing anything about it, which is what the fork gets
      // out of compositing the overlay onto itself.
      Rectangle {
        visible: parent.edge < parent.height + root.chunk * 2
        y: parent.edge
        width: parent.width
        height: root.band * 2
        color: Qt.lighter(root.textColor, 1.6)
        opacity: 0.8
      }
      }
    }

  }
}
