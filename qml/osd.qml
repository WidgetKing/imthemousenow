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
//   "scanline"  a CRT-off collapse -- squashed flat, with a bright line where
//               it was, which fades a moment after
//   "bytes"     a burst of glitchy flicker and jitter before it cuts out
//   "random"    scanline or bytes, a different one each time
//   "none"      gone the instant the solid time is up
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

  readonly property string reportPath: env("MOUSENOW_OSD_REPORT", "")

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

  // The belt to that watch's braces, for the same reason qml/pool.qml and
  // qml/halo.qml both poll too: a watch can be missed when the file is
  // replaced out from under it, and a look ten times a second is far below
  // what a switch needs and far above what "it got missed" takes to notice.
  Timer {
    running: true
    interval: 100
    repeat: true
    onTriggered: { report.reload(); root.readReport(); }
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
    scanlineAnim.stop();
    glitchTimer.stop();
    label.opacity = 1;
    glitchOffset.x = 0;
    glitchOffset.y = 0;
    scanScale.yScale = 1;
    scanFlash.opacity = 0;
    root.resolvedOutro = root.outro === "random"
      ? (Math.random() < 0.5 ? "scanline" : "bytes")
      : root.outro;
    solid.start();
  }

  function beginDeparture() {
    switch (root.resolvedOutro) {
      case "none":
        label.opacity = 0;
        break;
      case "scanline":
        scanlineAnim.start();
        break;
      case "bytes":
        glitchTimer.ticks = 0;
        glitchTimer.maxTicks = Math.max(1, Math.round(root.fadeMs / glitchTimer.interval));
        glitchTimer.start();
        break;
      default:
        fadeAnim.start();
        break;
    }
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
  }

  // A CRT switched off: the word squashes flat toward its own centre, and a
  // bright line flashes where it was for a moment before that fades too.
  SequentialAnimation {
    id: scanlineAnim
    ParallelAnimation {
      NumberAnimation {
        target: scanScale
        property: "yScale"
        from: 1
        to: 0
        duration: Math.max(1, Math.round(root.fadeMs * 0.7))
        easing.type: Easing.InCubic
      }
      SequentialAnimation {
        NumberAnimation {
          target: scanFlash
          property: "opacity"
          from: 0
          to: 1
          duration: Math.max(1, Math.round(root.fadeMs * 0.3))
        }
        NumberAnimation {
          target: scanFlash
          property: "opacity"
          to: 0
          duration: Math.max(1, Math.round(root.fadeMs * 0.7))
        }
      }
    }
    ScriptAction { script: label.opacity = 0 }
  }

  // A burst of corruption rather than a curve: opacity and position jitter a
  // handful of times, faster than the eye settles on any one frame of it, and
  // then it is simply gone. A Timer rather than an animation because each tick
  // needs a fresh random jump, not an eased path between two points.
  Timer {
    id: glitchTimer
    interval: 25
    repeat: true
    property int ticks: 0
    property int maxTicks: 6
    onTriggered: {
      ticks++;
      if (ticks >= maxTicks) {
        stop();
        label.opacity = 0;
        glitchOffset.x = 0;
        glitchOffset.y = 0;
        return;
      }
      label.opacity = 0.25 + Math.random() * 0.75;
      glitchOffset.x = (Math.random() - 0.5) * 10;
      glitchOffset.y = (Math.random() - 0.5) * 4;
    }
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

    // The bright line a scanline departure leaves behind for a moment. Sized
    // and placed off the label's own box so it sits across the word's middle
    // whichever edge `place` anchors to.
    Rectangle {
      id: scanFlash
      x: label.x
      y: label.y + label.height / 2 - height / 2
      width: label.width
      height: 3
      color: root.textColor
      opacity: 0
      visible: opacity > 0
    }

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
      // Three transforms, applied in order: centre the art (a no-op for the
      // plain word), jitter it for a "bytes" departure (a no-op otherwise),
      // then squash it for a "scanline" one (a no-op otherwise).
      transform: [
        Translate { x: root.drawingArt ? Math.max(0, (label.width - label.contentWidth) / 2) : 0 },
        Translate { id: glitchOffset; x: 0; y: 0 },
        Scale { id: scanScale; origin.x: label.width / 2; origin.y: label.height / 2; yScale: 1 }
      ]
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
}
