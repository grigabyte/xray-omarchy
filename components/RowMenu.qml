import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// A small menu for one row: the same look and keys as the header's "more"
// menu. One per page, not one per row: the rows belong to a ListView that
// gets a new array with every poll, and a popup inside a delegate would go
// with it in the middle of a click. The page opens it at the row and keeps
// what the row was about (`subject`) itself. Its `parent` is the whole card,
// so it is placed and clamped inside the card, not inside a scrolled list.
QQC.Popup {
  id: menu

  required property color textColor
  required property string panelFontFamily
  // [{id, text, enabled, checked}]
  property var items: []
  property string subject: ""
  property int cursor: 0

  signal chosen(string id, string subject)

  function openAt(item, x, y, subject) {
    var p = item.mapToItem(menu.parent, x, y)
    menu.subject = subject
    // The cursor starts on the first action that does something.
    var first = 0
    while (first < items.length - 1 && !items[first].enabled) first++
    menu.cursor = first
    // Kept inside the card: the panel's window is the card.
    menu.x = Math.max(0, Math.min(p.x - menu.width, menu.parent.width - menu.width))
    menu.y = Math.max(0, Math.min(p.y, menu.parent.height - menu.implicitHeight))
    menu.open()
  }

  function choose(index) {
    var item = items[index]
    if (!item || !item.enabled) return
    var subject = menu.subject
    close()
    chosen(item.id, subject)
  }

  width: Style.space(200)
  padding: Style.space(4)
  modal: false
  focus: true
  closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside

  background: BorderSurface {
    color: Color.popups.background
    borderSpec: Border.flat(Qt.rgba(menu.textColor.r, menu.textColor.g, menu.textColor.b, 0.25), 1)
    radius: Style.cornerRadius
  }

  contentItem: Column {
    spacing: Style.space(2)
    focus: true
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Down || event.text === "j") menu.cursor = Math.min(menu.items.length - 1, menu.cursor + 1)
      else if (event.key === Qt.Key_Up || event.text === "k") menu.cursor = Math.max(0, menu.cursor - 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) menu.choose(menu.cursor)
      else if (event.key === Qt.Key_Escape) menu.close()
      else return
      event.accepted = true
    }

    Repeater {
      model: menu.items

      delegate: CursorSurface {
        id: row
        required property var modelData
        required property int index
        width: menu.width - menu.leftPadding - menu.rightPadding
        implicitHeight: Style.space(30)
        hasCursor: menu.cursor === index
        foreground: menu.textColor
        opacity: modelData.enabled ? 1.0 : 0.45

        // The rule the host already has: a check, as on the node list.
        ActionIcon {
          id: mark
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          name: "check"
          iconSize: Style.font.caption
          color: Color.accent
          visible: row.modelData.checked === true
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10) + Style.font.caption + Style.space(6)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.text
          color: menu.textColor
          font.family: menu.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onEntered: menu.cursor = row.index
          onClicked: menu.choose(row.index)
        }
      }
    }
  }
}
