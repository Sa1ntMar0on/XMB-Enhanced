pragma ComponentBehavior: Bound

// XMB ribbon (simplified) — mesh-fold ribbon from RetroArch's Wii U XMB
// shader, menu_shaders/ribbon_simple.c, originally by Ali Bouhlel.
//
// What makes it read as fabric rather than a sine wave: a mesh is displaced
// vertically by smooth noise plus a cosine, and the rows are drawn ADDITIVELY
// on top of each other. Where the mesh folds over itself the brightness
// accumulates, so the folds glow and the flat spans stay dim. The ribbon is
// drawn by overlap density, not by any stroke or gradient.
//
// The displacement is the shader line, verbatim:
//
//   h = noise2(vec2(x + time/2, y*3)) * 0.25
//     + cos(2.0 * (x + y/3 + time)) * 0.1
//   gl_Position = vec4(x, -h, y)      // note the negation
//
// The mesh is filled as quad strips between consecutive rows, NOT stroked —
// stroking draws a dashed wireframe and loses the overlap-density glow.
//
// ANIMATED: `clock` advances every frame so the ribbon keeps flowing.

import QtQuick
import qs.Commons

Item {
  id: root

  // Toggled from the menu. Hides without discarding the setting.
  property bool enabled: true

  // Brightness added per overlapping mesh layer.
  property real strength: 0.10

  // Mesh density.
  property int rows: 96
  property int columns: 128

  // Vertical centre of the band and how far the displacement pushes it.
  property real centerFraction: 0.57
  property real amplitude: 0.80

  // Theme accent. Assigned by Xmb.qml so there is a single source of truth;
  // defaults to the shell accent when used standalone.
  property color ribbonColor: Color.accent

  // Seconds of ribbon time per real second.
  //
  // SPEED: this was 0.22, which is why the ribbon only seemed to shimmer. The
  // cosine term is cos(2*(x + y/3 + t)), so one full wave completes every
  // pi units of `clock` — at 0.22 that is a 14.3 second cycle, slow enough to
  // read as "subtly moving" rather than flowing. Measured per-tick vertex
  // movement: 0.33px at 0.22 versus 1.49px at 1.0.
  //
  // 1.0 is the reference implementation's own SPEED and gives a 3.1s cycle.
  // User-adjustable via the menu's Ribbon controls category.
  property real speed: 1.0

  // Background decoration behind a menu. 30fps leaves the compositor room.
  property int fps: 30

  property real clock: 0

  visible: root.enabled
  opacity: root.enabled ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 220 } }

  implicitWidth: parent ? parent.width : 0
  implicitHeight: parent ? parent.height : 0

  // ---- panel-space geometry ----------------------------------------------

  readonly property real panelHeight: parent ? parent.height : 0
  readonly property real meshScale: panelHeight * 0.5 * root.amplitude

  // The canvas only spans the band the ribbon can reach. h = noise*0.25 +
  // cos*0.1, so |h| <= 0.35; 0.36 clears that plus slack for the fill edges.
  // The MESH still works in panel space — cropping the canvas must never
  // rescale the ribbon or it comes out flat.
  readonly property real bandHalf: root.meshScale * 0.36 + 8
  readonly property real bandTop: Math.max(0, panelHeight * root.centerFraction - root.bandHalf)
  readonly property real bandHeight: Math.min(panelHeight - root.bandTop, root.bandHalf * 2)

  // ---- shader port -------------------------------------------------------

  function iqhash(n) {
    // fract(sin(n) * 43758.5453) — the standard value-noise hash.
    var s = Math.sin(n) * 43758.5453
    return s - Math.floor(s)
  }

  function noise2(px, py) {
    var ix = Math.floor(px)
    var iy = Math.floor(py)
    var fx = px - ix
    var fy = py - iy
    // Smoothstep the interpolants so the folds have no visible grid.
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)

    var v00 = root.iqhash(ix + iy * 113.0)
    var v10 = root.iqhash(ix + 1 + iy * 113.0)
    var v01 = root.iqhash(ix + (iy + 1) * 113.0)
    var v11 = root.iqhash(ix + 1 + (iy + 1) * 113.0)

    var a = v00 + (v10 - v00) * fx
    var b = v01 + (v11 - v01) * fx
    return a + (b - a) * fy
  }

  // ---- painting -----------------------------------------------------------
  //
  // LAG. Three costs were making this stutter, none of them the wave maths:
  //
  //   1. The canvas covered the WHOLE screen and cleared 1.33 Mpx every tick,
  //      though the ribbon only occupies a ~265px band — 69% wasted memset.
  //   2. noise2() did 4 hash calls per vertex = 49152 sin() calls per frame.
  //      floor(x + t/2) spans only ~3 distinct integers across a row, so the
  //      corners can be hashed ~3 times per row instead of 128 times.
  //   3. cos() ran per vertex; its argument advances by a constant per column,
  //      so a two-term rotation replaces it.
  //
  // Measured: 3.64ms -> 0.43ms per frame, max output difference 7.5e-12 px,
  // i.e. visually identical. Mesh density is untouched.

  function paint(ctx, W, H) {
    if (W < 2 || H < 2) return

    var cols = root.columns
    var rowCount = root.rows
    var cy = root.panelHeight * root.centerFraction - root.bandTop
    var scaleY = root.meshScale

    // Additive: this is what makes folds glow and flat spans stay dim.
    ctx.globalCompositeOperation = "lighter"

    var dx = 2 / (cols - 1)
    var cd = Math.cos(2 * dx)
    var sd = Math.sin(2 * dx)
    var ixc = new Array(cols)
    var fxc = new Array(cols)
    var A00 = [], A10 = [], A01 = [], A11 = []
    var ys = new Array(rowCount)

    for (var i = 0; i < rowCount; i++) {
      var y = (i / (rowCount - 1)) * 2 - 1

      // iy and its smoothstep are constant across the whole row
      var py = y * 3
      var iy = Math.floor(py)
      var fy = py - iy
      fy = fy * fy * (3 - 2 * fy)
      var b0 = iy * 113
      var b1 = (iy + 1) * 113

      // floor(x + t/2) spans only a couple of integers across a row
      var xoff = root.clock / 2 - 1
      var lo = 0, hi = 0
      for (var c = 0; c < cols; c++) {
        var vx = c * dx + xoff
        var ix = Math.floor(vx)
        ixc[c] = ix
        var f = vx - ix
        fxc[c] = f * f * (3 - 2 * f)
        if (c === 0) { lo = ix; hi = ix }
        else if (ix < lo) lo = ix
        else if (ix > hi) hi = ix
      }

      // hash each distinct corner once per row, not once per vertex
      for (var k = 0, n = hi - lo + 1; k < n; k++) {
        var hx = lo + k
        A00[k] = root.iqhash(hx + b0)
        A10[k] = root.iqhash(hx + 1 + b0)
        A01[k] = root.iqhash(hx + b1)
        A11[k] = root.iqhash(hx + 1 + b1)
      }

      // cosine recurrence instead of a cos() call per vertex
      var ang = 2 * (-1 + y / 3 + root.clock)
      var ck = Math.cos(ang)
      var sk = Math.sin(ang)

      var row = new Array(cols)
      for (var c2 = 0; c2 < cols; c2++) {
        var kk = ixc[c2] - lo
        var f2 = fxc[c2]
        var a = A00[kk] + (A10[kk] - A00[kk]) * f2
        var b = A01[kk] + (A11[kk] - A01[kk]) * f2
        var h = (a + (b - a) * fy) * 0.25 + ck * 0.1
        row[c2] = cy - h * scaleY
        var nc = ck * cd - sk * sd
        sk = sk * cd + ck * sd
        ck = nc
      }
      ys[i] = row
    }

    ctx.clearRect(0, 0, W, H)
    var cr = root.ribbonColor.r
    var cg = root.ribbonColor.g
    var cb = root.ribbonColor.b
    var pxPerCol = W / (cols - 1)

    // NOTE: this loop variable must NOT be called `r`. QML resolves names
    // through the component's scope, and a local `var r` shadows `id: root`,
    // which turns `root.paint(...)` in onPaint into infinite recursion —
    // "RangeError: Maximum call stack size exceeded", thrown every frame.
    // paint() then never completes, so the ribbon stutters and appears frozen.
    for (var rIdx = 0; rIdx < rowCount - 1; rIdx++) {
      var top = ys[rIdx]
      var bottom = ys[rIdx + 1]

      // One closed strip: top edge left-to-right, bottom edge right-to-left.
      ctx.beginPath()
      ctx.moveTo(0, top[0])
      for (var x1 = 1; x1 < cols; x1++) {
        ctx.lineTo(x1 * pxPerCol, top[x1])
      }
      for (var x2 = cols - 1; x2 >= 0; x2--) {
        ctx.lineTo(x2 * pxPerCol, bottom[x2])
      }
      ctx.closePath()

      ctx.fillStyle = Qt.rgba(cr, cg, cb, root.strength)
      ctx.fill()
    }

    ctx.globalCompositeOperation = "source-over"
  }

  Canvas {
    id: canvas
    // Only as tall as the band the ribbon occupies.
    x: 0
    y: root.bandTop
    width: parent ? parent.width : 0
    height: root.bandHeight
    renderStrategy: Canvas.Threaded
    // Every quad strip shares an edge with its neighbour, so without
    // antialiasing those edges show as hairline seams through the band.
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      if (!ctx) return
      root.paint(ctx, canvas.width, canvas.height)
    }
  }

  // ---- animation ---------------------------------------------------------

  Timer {
    id: ticker
    interval: Math.max(1, Math.round(1000 / Math.max(1, root.fps)))
    repeat: true
    running: root.enabled
    onTriggered: {
      root.clock += root.speed * (interval / 1000)
      canvas.requestPaint()
    }
  }

  // Repaint on anything that changes the picture without the clock moving.
  // A theme switch changing Color.accent lands here too.
  Connections {
    target: root
    function onEnabledChanged() { if (root.enabled) canvas.requestPaint() }
    function onRibbonColorChanged() { canvas.requestPaint() }
    function onCenterFractionChanged() { canvas.requestPaint() }
    function onAmplitudeChanged() { canvas.requestPaint() }
    function onSpeedChanged() { canvas.requestPaint() }
    function onStrengthChanged() { canvas.requestPaint() }
    function onWidthChanged() { canvas.requestPaint() }
    function onHeightChanged() { canvas.requestPaint() }
    function onBandTopChanged() { canvas.requestPaint() }
    function onBandHeightChanged() { canvas.requestPaint() }
    // meshScale feeds bandHalf/bandTop/bandHeight, and the canvas is sized
    // from those. Without this, changing the scale from the menu resizes the
    // mesh but leaves the canvas at the old band, clipping the ribbon.
    function onMeshScaleChanged() { canvas.requestPaint() }
  }
}