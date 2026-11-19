import QtQuick
import qs.Commons

// Small action pictograms for rows and buttons, painted on a Canvas. They
// are used at 12-16 px, where an SVG file comes out blurred and an icon font
// puts each sign at its own size and baseline; a painted path does neither.
//
// Each pictogram is a short path on a 16 x 16 grid, written in a subset of
// SVG path syntax: M (move), L (line), C (cubic curve), Z (close), plus O for
// a filled disc ("O cx cy r"). Stroked ones share one round-capped weight,
// which is what makes them look like one family; one made only of discs is
// filled. A new pictogram is one more entry in `paths`. XrayIcon, the logo,
// is drawn separately.
Canvas {
  id: glyph

  // Which pictogram, how big, in what colour, and the stroke weight in grid
  // units.
  property string name: ""
  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property real strokeScale: 1.4

  readonly property var paths: ({
    "back":         "M13 8 L3 8 M7 4 L3 8 L7 12",
    "chevron-down": "M3.5 6 L8 10.5 L12.5 6",
    "chevron-up":   "M3.5 10 L8 5.5 L12.5 10",
    "check":        "M2.8 8.6 L6.3 12 L13.2 4.3",
    "close":        "M3.6 3.6 L12.4 12.4 M12.4 3.6 L3.6 12.4",
    // Traffic arrows keep a shaft: a bare chevron reads as "expand".
    "download":     "M8 2.5 L8 13 M4 9 L8 13 L12 9",
    "upload":       "M8 13.5 L8 3 M4 7 L8 3 L12 7",
    // Two opposed arrows: traffic moved over to the other node.
    "fallback":     "M2.5 5.5 L12.5 5.5 M10 3 L12.5 5.5 L10 8 M13.5 10.5 L3.5 10.5 M6 8 L3.5 10.5 L6 13",
    // Flat top, straight shoulders, curved down to a point.
    "shield":       "M8 1.8 L13 3.6 L13 8 C13 11 10.8 13 8 14.4 C5.2 13 3 11 3 8 L3 3.6 Z",
    // Discs: three for a menu, one for "carries traffic".
    "more":         "O8 3.2 1.35 O8 8 1.35 O8 12.8 1.35",
    "dot":          "O8 8 2.6"
  })

  // Everything the picture depends on; any change repaints.
  readonly property var look: [name, color, iconSize]
  onLookChanged: requestPaint()

  implicitWidth: iconSize
  implicitHeight: implicitWidth
  width: implicitWidth
  height: implicitHeight
  antialiasing: true

  onPaint: {
    var g = getContext("2d")
    g.reset()
    var unit = width / 16
    var spec = paths[name]
    if (unit <= 0 || typeof spec !== "string") return

    var tokens = spec.match(/[MLCZO]|-?\d*\.?\d+/g)
    var at = 0
    var filled = true
    function next() { return Number(tokens[at++]) * unit }

    g.beginPath()
    while (at < tokens.length) {
      var op = tokens[at++]
      if (op === "M") {
        g.moveTo(next(), next())
        filled = false
      } else if (op === "L") {
        g.lineTo(next(), next())
      } else if (op === "C") {
        g.bezierCurveTo(next(), next(), next(), next(), next(), next())
      } else if (op === "Z") {
        g.closePath()
      } else if (op === "O") {
        var cx = next(), cy = next(), r = next()
        g.moveTo(cx + r, cy)
        g.arc(cx, cy, r, 0, Math.PI * 2)
      }
    }

    if (filled) {
      g.fillStyle = glyph.color
      g.fill()
    } else {
      g.strokeStyle = glyph.color
      g.lineWidth = Math.max(1, glyph.strokeScale * unit)
      g.lineCap = "round"
      g.lineJoin = "round"
      g.stroke()
    }
  }
}
