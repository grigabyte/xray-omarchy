import QtQuick
import qs.Commons

// The plugin's mark: a lightning bolt with a flat cap. Three states, all on
// one canvas so they scale together, from 16 px in the bar up to the panel's
// header:
//   plain   — connected;
//   crossed — off: a backslash over the bolt, with a gap cut along each side
//             of it so both halves stay legible when small;
//   warning — something failed: a filled disc at the lower right with an "!"
//             punched out of it, ringed by a cut-out gap.
// Painted, not loaded from an image file, so it stays crisp at 16 px.
Canvas {
  id: mark

  // Off: struck through. `ringed` is accepted so callers that set it still
  // load; the mark has no ring.
  property bool crossed: false
  property bool ringed: false
  // Failed: the badge, and its fill.
  property bool warning: false
  property color badgeColor: Color.urgent
  // Size of the square and the ink.
  property real iconSize: Style.font.icon
  property color color: Color.foreground

  // Everything the picture depends on; any change repaints.
  readonly property var look: [crossed, warning, badgeColor, color, iconSize]
  onLookChanged: requestPaint()

  implicitWidth: iconSize
  implicitHeight: implicitWidth
  width: implicitWidth
  height: implicitHeight
  antialiasing: true

  // The bolt on a unit square: cap, the step at the waist, the long stroke
  // down to the tip, back up to the inner notch.
  readonly property var outline: [
    [0.36, 0.04], [0.76, 0.04], [0.57, 0.37], [0.81, 0.37],
    [0.31, 0.97], [0.45, 0.55], [0.20, 0.55]
  ]

  onPaint: {
    var g = getContext("2d")
    g.reset()
    var side = Math.min(width, height)
    if (!(side > 0)) return
    var u = v => v * side
    // Erasing draws through what is already painted; painting draws on top.
    var erase = on => { g.globalCompositeOperation = on ? "destination-out" : "source-over" }
    var disc = (x, y, radius) => { g.beginPath(); g.arc(x, y, radius, 0, 2 * Math.PI); g.fill() }
    var slash = (from, to) => { g.beginPath(); g.moveTo(from, from); g.lineTo(to, to); g.stroke() }

    g.fillStyle = mark.color
    g.beginPath()
    outline.forEach((p, k) => (k > 0 ? g.lineTo : g.moveTo).call(g, u(p[0]), u(p[1])))
    g.fill()

    if (mark.crossed) {
      var weight = Math.max(1.5, side * 0.1)
      var from = u(0.1)
      var to = u(0.9)
      g.lineCap = "round"
      // The gap first: erase a wider band, then lay the bar into it.
      erase(true)
      g.lineWidth = weight + Math.max(2, side * 0.14)
      slash(from, to)
      erase(false)
      g.strokeStyle = mark.color
      g.lineWidth = weight
      slash(from, to)
    }

    if (mark.warning) {
      var r = Math.max(3.5, side * 0.23)
      var cx = side - r
      var cy = side - r
      var gap = Math.max(1, side * 0.07)
      erase(true)
      disc(cx, cy, r + gap)
      erase(false)
      g.fillStyle = mark.badgeColor
      disc(cx, cy, r)
      // The "!" as a bar and a dot, cut out so the badge reads on any surface.
      erase(true)
      var bar = Math.max(1, r * 0.34)
      g.fillRect(cx - bar / 2, cy - r * 0.62, bar, r * 0.78)
      disc(cx, cy + r * 0.48, bar * 0.62)
      erase(false)
    }
  }
}
