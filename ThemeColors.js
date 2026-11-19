.pragma library

// Reads the two signal colours the panel uses for node delay out of an
// Omarchy theme's colors.toml. The shell's Color singleton carries only
// foreground, background, accent, urgent and muted; the delay scale needs a
// "good" and a "so-so" colour, and the theme file is where those live.
//
// Only `key = "#rrggbb"` entries count (quotes optional); comments, tables and
// anything else are skipped. The named key wins at its first appearance; the
// terminal slot that stands in for it (color2 for green, color3 for yellow)
// counts at its last. Neither present: "".

var ENTRY = /^\s*([\w-]+)\s*=\s*["']?(#[0-9a-fA-F]{6})/

function entries(text) {
  var found = []
  var rows = String(text || "").split("\n")
  for (var n = 0; n < rows.length; n++) {
    var hit = ENTRY.exec(rows[n])
    if (hit !== null) found.push({ key: hit[1], value: hit[2] })
  }
  return found
}

function lookup(text, key, standIn) {
  var list = entries(text)
  var spare = ""
  for (var n = 0; n < list.length; n++) {
    if (list[n].key === key) return list[n].value
    if (list[n].key === standIn) spare = list[n].value
  }
  return spare
}

// Both colours at once, as SystemTheme stores them; `otherwise` stands in for
// a colour the text does not define.
function read(text, otherwise) {
  var g = lookup(text, "green", "color2")
  var y = lookup(text, "yellow", "color3")
  return { green: g !== "" ? g : otherwise, yellow: y !== "" ? y : otherwise }
}
