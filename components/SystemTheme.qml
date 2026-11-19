import "../ThemeColors.js" as Swatches
import QtQuick
import Quickshell.Io
import qs.Commons as Shell

// The current Omarchy theme's green and yellow, for the delay scale: this
// object is the reader of the theme's colors.toml itself, the file the
// shell's Color singleton takes its palette from (Color.currentThemePath).
// It is watched, since a theme switch rewrites it, and re-read on an accent
// change as well, in case the switch landed before the watch saw it. A theme
// without those colours, or no readable file, gives the accent.
FileView {
  readonly property color green: swatch.green
  readonly property color yellow: swatch.yellow

  // The pair from the file, with the shell's accent standing in for a colour
  // the theme does not define (all of it until the file is read).
  property var swatch: Swatches.read("", Shell.Color.accent)

  readonly property color accentNow: Shell.Color.accent
  onAccentNowChanged: reload()

  onLoaded: swatch = Swatches.read(text(), accentNow)
  onLoadFailed: swatch = Swatches.read("", accentNow)
  onFileChanged: reload()
  watchChanges: true
  printErrors: false
  path: Shell.Color.currentThemePath + "/colors.toml"
}
