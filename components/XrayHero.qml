import QtQuick
import qs.Commons
import qs.Commons as Commons

// The shell's PanelHero with one difference: the second line is not
// upper-cased wholesale. `meta` is shown in capitals like PanelHero's;
// `metaTail` (the delay, "483 ms") follows it as written, because a unit is
// not a word to shout and "MS" reads as something else. Same sizes, weights
// and spacing as PanelHero, so the card keeps the kit's look.
Item {
  id: root

  property Component iconComponent: null
  property string title: ""
  property string meta: ""
  property string metaTail: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real iconOpacity: 1.0

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string metaLine: {
    var head = root.meta.toUpperCase()
    if (root.metaTail === "") return head
    return head !== "" ? head + " · " + root.metaTail : root.metaTail
  }

  implicitHeight: Math.max(iconLoader.implicitHeight, heroLabels.implicitHeight)

  Loader {
    id: iconLoader
    sourceComponent: root.iconComponent
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    opacity: root.iconOpacity
  }

  Column {
    id: heroLabels
    anchors.left: iconLoader.right
    anchors.leftMargin: Style.space(14)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      visible: root.title !== ""
      width: parent.width
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.metaLine
      visible: text !== ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      elide: Text.ElideRight
    }
  }
}
