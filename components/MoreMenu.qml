import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// The "more" menu in the header: four pages and one fetch. Nothing in it cuts
// the tunnel — the switch beside it does that; switching subscriptions,
// restarting the core for the fallback and updating the core each sit
// behind a confirmation on their own page.
Item {
  id: root

  required property color textColor
  required property string panelFontFamily
  required property var strings
  property bool updating: false

  readonly property bool menuOpen: menu.opened

  signal subscriptionsRequested()
  signal sitesRequested()
  signal settingsRequested()
  signal coreRequested()
  signal updateRequested()

  implicitWidth: button.width
  implicitHeight: button.height

  function closeMenu() { menu.close() }

  function openMenu() {
    menu.cursor = 0
    menu.open()
  }

  PanelActionButton {
    id: button
    size: Style.space(26)
    tooltipText: root.strings.t("menu.open")
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    onClicked: menu.opened ? menu.close() : root.openMenu()

    ActionIcon {
      anchors.centerIn: parent
      name: "more"
      iconSize: Style.font.icon
      color: root.textColor
    }
  }

  QQC.Popup {
    id: menu
    property int cursor: 0
    readonly property var items: [
      { id: "subs", text: root.strings.t("menu.subs"), enabled: true },
      { id: "sites", text: root.strings.t("menu.sites"), enabled: true },
      { id: "settings", text: root.strings.t("menu.settings"), enabled: true },
      { id: "core", text: root.strings.t("menu.core"), enabled: true },
      { id: "update", text: root.updating ? root.strings.t("menu.updating") : root.strings.t("menu.update"), enabled: !root.updating }
    ]

    x: button.width - width
    y: button.height + Style.space(4)
    width: Style.space(200)
    padding: Style.space(4)
    modal: false
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside

    function choose(index) {
      var item = items[index]
      if (!item || !item.enabled) return
      close()
      if (item.id === "subs") root.subscriptionsRequested()
      else if (item.id === "sites") root.sitesRequested()
      else if (item.id === "settings") root.settingsRequested()
      else if (item.id === "core") root.coreRequested()
      else root.updateRequested()
    }

    background: BorderSurface {
      color: Color.popups.background
      borderSpec: Border.flat(Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.25), 1)
      radius: Style.cornerRadius
    }

    contentItem: Column {
      id: menuItems
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
          foreground: root.textColor
          opacity: modelData.enabled ? 1.0 : 0.45

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: row.modelData.text
            color: root.textColor
            font.family: root.panelFontFamily
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
}
