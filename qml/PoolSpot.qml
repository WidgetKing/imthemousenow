// LCD pooling: what a liquid-crystal panel does when a thumb presses into it.
//
// The spot under the thumb stays readable. It is the ring around it that goes
// wrong -- the crystal is squeezed out sideways, and the pixels there flip into
// bands of colour that have nothing to do with the picture, with a dark bruise
// where the pressure is highest. That is exactly the property wanted from a
// mark that says "the click went here": the point itself is left clear, and
// the eye is pulled to it by everything around it misbehaving.
//
// Drawn in whole cells rather than smoothly, because Omarchy is drawn that way
// -- its logo is a handful of chunky squares -- and a soft gradient would look
// like it came from some other desktop. For the same reason it animates in
// steps, a new frame every `frameMs`, rather than at the display's rate: the
// cells flicker the way a stuck LCD does, not the way a shader glides.
//
// Four ways for it to go wrong, `style`, because one mark seen a thousand
// times stops being seen. Each is loud in a different way, and each still
// keeps the same two promises: the press point itself is left clear, and the
// damage is centred on it, so the eye lands on the right pixel whichever one
// comes up.
//
//   pool    the whole bruise: a lobed ring of colour bands round a clear middle
//   patchy  the same pool with big square chunks of it dead -- still a ring,
//           but a broken one that is never the same shape twice
//   lines   the crystal bleeding down (and a little up) the panel in columns,
//           longest nearest the press, with a tight bruise round the middle
//   cross   a dead row and a dead column through the press, running far out
//           and breaking up as they go, round a small pool
//
// Nothing here knows about clicks or holds. It is a spot at (centerX, centerY)
// whose size is `intensity` of `radius`; qml/pool.qml fades that in and out
// once per click, qml/halo.qml leaves it up and moves it for a hold.
import QtQuick

Item {
  id: pool

  // Where the press is, in the parent's coordinates.
  property real centerX: 0
  property real centerY: 0
  // The outer edge at full strength, in px. `lines` and `cross` reach further
  // than this, but it sets their scale too.
  property real radius: 56
  // One pixel of the effect, in px. The chunkiness.
  property int cell: 6
  // 0 is nothing drawn, 1 is the whole spot. Everything is scaled by it, so a
  // fade in or out is just an animation on this.
  property real intensity: 1
  // pool | patchy | lines | cross. Anything else is drawn as `pool`. Choosing
  // one at random is the caller's business, not this component's.
  property string style: "pool"
  // Mixed into every random choice, so two clicks on the same spot in the same
  // style are still two different shapes. Callers change it per click.
  property real seed: 0
  // The colours the crystal flips into, outward from the centre, and the dark
  // of the bruise. The theme's own: see bin/imthemousenow-pool.
  // `colours`, not `palette`: every Item already has a `palette`, Qt's own.
  // Empty falls back to a set that reads on most themes.
  property var colours: []
  readonly property var fallbackColours: ["#f7768e", "#e0af68", "#9ece6a", "#449dab", "#7aa2f7", "#ad8ee6"]
  property color shade: "#1a1b26"
  // How much of the radius, from the middle, is left clear. The press itself.
  property real core: 0.3
  property int frameMs: 70
  property bool running: visible && intensity > 0

  // How far the style reaches, in multiples of `radius`, across and down.
  readonly property real reachX: style === "cross" ? 4 : 1.35
  readonly property real reachY: style === "cross" ? 4 : style === "lines" ? 4.5 : 1.35

  // The whole spot, snapped to the cell grid of the screen rather than of the
  // pointer, so a spot being moved by a hold steps across the screen a cell at
  // a time instead of dragging its cells smoothly with it -- which would read
  // as a sprite sliding, not as pixels going wrong in place.
  readonly property int spanX: Math.ceil(radius * reachX / cell) + 1
  readonly property int spanY: Math.ceil(radius * reachY / cell) + 1
  x: Math.floor(centerX / cell) * cell - spanX * cell
  y: Math.floor(centerY / cell) * cell - spanY * cell
  width: spanX * 2 * cell + cell
  height: spanY * 2 * cell + cell

  property int frame: 0

  Timer {
    interval: pool.frameMs
    repeat: true
    running: pool.running
    onTriggered: { pool.frame++; canvas.requestPaint(); }
  }
  onIntensityChanged: canvas.requestPaint()
  onCenterXChanged: canvas.requestPaint()
  onCenterYChanged: canvas.requestPaint()
  onStyleChanged: canvas.requestPaint()

  // A number in [0, 1) that is always the same for the same inputs. Per-cell
  // randomness has to be stable from frame to frame, or every cell flickers at
  // once and the spot is noise rather than a shape.
  function hash(a, b, c) {
    const v = Math.sin(a * 12.9898 + b * 78.233 + c * 37.719 + pool.seed * 7.13) * 43758.5453;
    return v - Math.floor(v);
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    // No smoothing anywhere: every cell is a hard-edged square.
    antialiasing: false
    renderStrategy: Canvas.Cooperative

    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      const k = pool.intensity;
      if (k <= 0.01) return;

      const cell = pool.cell;
      const reach = pool.radius * k / cell;
      if (reach < 1) return;

      // Everything a style needs, worked out once per frame.
      const f = {
        ctx: ctx, k: k, cell: cell, reach: reach, t: pool.frame,
        colours: pool.colours && pool.colours.length ? pool.colours : pool.fallbackColours,
        // The press point inside this item, in cells, before snapping.
        px: (pool.centerX - pool.x) / cell,
        py: (pool.centerY - pool.y) / cell,
        // The screen cell at this item's corner, so a cell's randomness
        // belongs to its place on the screen rather than its place in the spot.
        gx: Math.round(pool.x / cell),
        gy: Math.round(pool.y / cell),
      };

      if (pool.style === "lines") drawLines(f);
      else if (pool.style === "cross") drawCross(f);
      else drawPool(f, pool.style === "patchy");
    }

    function put(f, i, j, colour, alpha) {
      f.ctx.globalAlpha = Math.max(0, Math.min(1, alpha)) * Math.min(1, f.k * 1.4);
      f.ctx.fillStyle = colour;
      f.ctx.fillRect(i * f.cell, j * f.cell, f.cell, f.cell);
    }

    function band(f, d, angle) {
      const n = f.colours.length;
      const b = d * 6.5 - f.t * 0.3 + 0.5 * Math.sin(2 * angle + f.t * 0.17);
      return f.colours[((Math.floor(b) % n) + n) % n];
    }

    // The bruise ring hugging the clear middle, which every style keeps: it is
    // the one part of the mark that says exactly which pixel was pressed.
    function bruise(f, gi, gj, d, width) {
      const b = Math.max(0, 1 - (d - pool.core) / width);
      return pool.hash(gi + 101, gj - 57, Math.floor(f.t / 2)) < 0.07 + b * 0.6;
    }

    function drawPool(f, patchy) {
      const t = f.t;
      for (let j = 0; j <= pool.spanY * 2; j++) {
        for (let i = 0; i <= pool.spanX * 2; i++) {
          const dx = i + 0.5 - f.px, dy = j + 0.5 - f.py;
          const d = Math.sqrt(dx * dx + dy * dy) / f.reach;
          if (d > 1.35 || d < pool.core) continue;
          const gi = f.gx + i, gj = f.gy + j;

          // An edge that is not a circle: lobed, slowly turning, and nibbled
          // cell by cell, the way pooling spreads unevenly into the panel.
          const angle = Math.atan2(dy, dx);
          const edge = 1 + 0.16 * Math.sin(3 * angle + t * 0.23)
                         + 0.10 * Math.sin(5 * angle - t * 0.31)
                         + 0.18 * (pool.hash(gi, gj, Math.floor(t / 4)) - 0.5)
                         + (patchy ? 0.2 : 0);
          if (d > edge) continue;

          // Patchy: whole 4x4 blocks of it dead, reshuffled every few frames.
          // Never the bruise ring round the middle, which is what still marks
          // the spot when most of the rest has dropped out.
          if (patchy && d > pool.core + 0.14 &&
              pool.hash(Math.floor(gi / 4), Math.floor(gj / 4), Math.floor(t / 5) + 11) < 0.4)
            continue;

          // Dithered off towards the edge: cells drop out rather than fade,
          // because a half-transparent chunky pixel is a contradiction.
          const toEdge = (edge - d) / (edge - pool.core);
          if (pool.hash(gi, gj, t) > toEdge * 3.2) continue;

          const colour = bruise(f, gi, gj, d, 0.12) ? pool.shade : band(f, d, angle);
          put(f, i, j, colour, 0.55 + toEdge * 0.4);
        }
      }
    }

    function drawLines(f) {
      const t = f.t, n = f.colours.length;
      const half = Math.ceil(f.reach * 0.95);
      const ci = Math.floor(f.px);
      for (let i = ci - half; i <= ci + half; i++) {
        const gi = f.gx + i;
        const off = Math.abs(i + 0.5 - f.px) / f.reach;
        // Not every column bleeds, and the ones nearest the press run longest:
        // the lines fan out from it, which is what points at it.
        if (pool.hash(gi, 3, 0) < 0.1 + off * 0.3) continue;
        const down = f.reach * (1.2 + 3.2 * pool.hash(gi, 5, 0)) * (1 - off * 0.7) * f.k;
        const up = down * (0.25 + 0.3 * pool.hash(gi, 7, 0));
        const colour = f.colours[Math.floor(pool.hash(gi, 9, 0) * n) % n];
        // Drips: each column's end creeps and stalls rather than sitting still.
        const creep = (pool.hash(gi, 13, Math.floor(t / 3)) - 0.5) * 2;
        for (let j = Math.floor(f.py - up - creep); j <= Math.ceil(f.py + down + creep); j++) {
          if (j < 0 || j > pool.spanY * 2) continue;
          const gj = f.gy + j;
          const dx = i + 0.5 - f.px, dy = j + 0.5 - f.py;
          const d = Math.sqrt(dx * dx + dy * dy) / f.reach;
          if (d < pool.core) continue;
          const along = dy >= 0 ? dy / down : -dy / up;
          if (pool.hash(gi, gj, Math.floor(t / 2)) < along * 0.45) continue;
          const dark = d < pool.core + 0.35 && bruise(f, gi, gj, d, 0.2);
          put(f, i, j, dark ? pool.shade : colour, 0.9 - along * 0.45);
        }
      }
      // And the bruise closing the ring round the middle, so the columns have
      // an obvious place they are all coming from.
      ring(f, 0.22);
    }

    function drawCross(f) {
      const t = f.t, n = f.colours.length;
      const far = f.reach * 4 * f.k;
      const ci = Math.floor(f.px), cj = Math.floor(f.py);
      // One or two cells thick, decided per arm, so the lines are not a ruler.
      const arms = [
        { dx: 1, dy: 0 }, { dx: -1, dy: 0 }, { dx: 0, dy: 1 }, { dx: 0, dy: -1 },
      ];
      for (let a = 0; a < 4; a++) {
        const arm = arms[a];
        const thick = pool.hash(a, 17, 0) < 0.5 ? 1 : 2;
        const length = far * (0.6 + 0.4 * pool.hash(a, 19, 0));
        for (let s = Math.floor(f.reach * pool.core); s <= length; s++) {
          for (let w = 0; w < thick; w++) {
            const i = ci + arm.dx * s + (arm.dx === 0 ? w : 0);
            const j = cj + arm.dy * s + (arm.dy === 0 ? w : 0);
            if (i < 0 || j < 0 || i > pool.spanX * 2 || j > pool.spanY * 2) continue;
            const gi = f.gx + i, gj = f.gy + j;
            const along = s / length;
            // Broken into segments that flicker, more broken further out.
            if (pool.hash(Math.floor(s / 3), a, Math.floor(t / 2)) < along * 0.7) continue;
            const colour = pool.hash(gi, gj, Math.floor(t / 3)) < 0.3
              ? pool.shade : f.colours[(Math.floor(s / 4) + a) % n];
            put(f, i, j, colour, 0.95 - along * 0.5);
          }
        }
      }
      // A small pool at the crossing, so the middle is unmistakable.
      const saved = f.reach;
      f.reach = saved * 0.6;
      drawPool(f, false);
      f.reach = saved;
    }

    // Just the bruise ring, dithered, for the styles that are not a pool.
    function ring(f, width) {
      const r = Math.ceil(f.reach * (pool.core + width)) + 1;
      const ci = Math.floor(f.px), cj = Math.floor(f.py);
      for (let j = cj - r; j <= cj + r; j++) {
        for (let i = ci - r; i <= ci + r; i++) {
          const dx = i + 0.5 - f.px, dy = j + 0.5 - f.py;
          const d = Math.sqrt(dx * dx + dy * dy) / f.reach;
          if (d < pool.core || d > pool.core + width) continue;
          const gi = f.gx + i, gj = f.gy + j;
          if (pool.hash(gi, gj, f.t) < 0.3) continue;
          const angle = Math.atan2(dy, dx);
          put(f, i, j, bruise(f, gi, gj, d, width) ? pool.shade : band(f, d, angle), 0.9);
        }
      }
    }
  }
}
