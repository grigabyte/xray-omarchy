import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import qs.Commons as Commons
import "../Model.js" as Model

// Where the sites went: the CLI folds the last connections by host and says
// how many there were. Each row says which way the host left — through the
// tunnel (and on which node), straight out, or blocked — in words; the colour
// only repeats it. A ListView with a bounded viewport: up to 60 hosts.
//
// Each host can be sent always direct or always through the tunnel: a "⋮"
// on the hovered row, or a right click anywhere on it, opens the actions.
// A host a rule decides is marked. The rules themselves are listed above the
// hosts, each with a button that removes it; the block is absent when there
// are none. Hosts reach the CLI only as the CLI reported them.
//
// Above everything, the checked sites: does each open, and which way it
// went (the CLI checks them; the panel shows the last result). "Add site…"
// opens the form; a × removes one. With none, one line says what it is for.
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily
  // The card: the row menu is placed inside it.
  required property Item menuHost
  property real maxHeight: Style.space(400)

  readonly property var status: service.status
  readonly property var recent: status ? status.recent : []
  readonly property var rules: status ? Model.ruleRows(status.rules) : []
  readonly property var sites: status ? status.sites : null
  readonly property var siteItems: sites ? sites.items : []

  signal addSiteRequested()

  function ruleText(side) { return side === "direct" ? root.strings.t("rules.direct") : root.strings.t("rules.tunnel") }

  function openRowMenu(item, x, y, host) {
    if (host === "") return
    var exact = Model.ruleFor(root.status.rules, host)
    rowMenu.items = [
      { id: "direct", text: root.strings.t("rules.makeDirect"), enabled: exact !== "direct", checked: exact === "direct" },
      { id: "tunnel", text: root.strings.t("rules.makeTunnel"), enabled: exact !== "tunnel", checked: exact === "tunnel" },
      { id: "remove", text: root.strings.t("rules.remove"), enabled: exact !== "", checked: false }
    ]
    rowMenu.openAt(item, x, y, host)
  }

  RowMenu {
    id: rowMenu
    parent: root.menuHost
    textColor: root.textColor
    panelFontFamily: root.panelFontFamily
    onChosen: function(id, host) {
      if (id === "remove") root.service.removeRule(host)
      else root.service.addRule(id, host)
    }
  }
  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)

  function count(n) { return Commons.I18n.formatNumber(n) }

  function scrollBy(dy) {
    var step = (list.stride > 0 ? list.stride : Style.space(48)) * dy
    list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + step))
  }

  spacing: Style.space(6)

  // ---- checked sites: one row each, a × removes it -------------------------
  Column {
    id: checksBlock
    visible: root.sites !== null && root.sites.known
    width: parent.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(checksHeader.implicitHeight, addSiteButton.implicitHeight)

      Text {
        id: checksHeader
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.strings.t("sites.header")
        color: root.dim
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Button {
        id: addSiteButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: !root.service.addingSite && root.siteItems.length < Model.MAX_SITES
        opacity: enabled ? 1.0 : 0.45
        text: root.strings.t("sites.add")
        foreground: root.textColor
        bordered: true
        fontFamily: root.panelFontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.space(3)
        horizontalPadding: Style.space(8)
        onClicked: root.addSiteRequested()
      }
    }

    Text {
      visible: root.siteItems.length === 0
      width: parent.width
      textFormat: Text.PlainText
      text: root.strings.t("sites.hint")
      color: root.dim
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.siteItems

      delegate: Item {
        id: checkRow
        required property var modelData
        readonly property bool opens: modelData.result !== null && modelData.result.ok
        width: checksBlock.width
        implicitHeight: checkName.implicitHeight + checkDetail.implicitHeight + Style.space(2)

        Text {
          id: checkName
          anchors.left: parent.left
          anchors.right: checkRemove.left
          anchors.rightMargin: Style.space(8)
          anchors.top: parent.top
          textFormat: Text.PlainText
          text: checkRow.modelData.name
          color: checkRow.opens ? root.textColor : root.dim
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          id: checkDetail
          anchors.left: parent.left
          anchors.right: checkRemove.left
          anchors.rightMargin: Style.space(8)
          anchors.top: checkName.bottom
          anchors.topMargin: Style.space(2)
          textFormat: Text.PlainText
          text: checkRow.modelData.host + " · " + root.service.siteDetail(checkRow.modelData.result)
          color: root.dim
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        PanelActionButton {
          id: checkRemove
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(22)
          enabled: root.service.pendingSite === "" && !root.service.addingSite
          tooltipText: root.strings.t("sites.remove")
          foreground: root.textColor
          fontFamily: root.panelFontFamily
          onClicked: root.service.removeSite(checkRow.modelData.name)

          ActionIcon {
            anchors.centerIn: parent
            name: "close"
            iconSize: Style.font.caption
            color: root.textColor
          }
        }
      }
    }

    Item { width: 1; height: Style.space(4) }

    PanelSeparator {
      width: parent.width
      foreground: root.textColor
    }

    Item { width: 1; height: Style.space(2) }
  }

  // ---- the rules: one row each, with a button that removes it -------------
  Column {
    id: rulesBlock
    visible: root.rules.length > 0
    width: parent.width
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: root.strings.t("rules.header")
      color: root.dim
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    Repeater {
      model: root.rules

      delegate: Item {
        id: ruleRow
        required property var modelData
        width: rulesBlock.width
        implicitHeight: Math.max(ruleHostText.implicitHeight, removeButton.height)

        Text {
          id: ruleHostText
          anchors.left: parent.left
          anchors.right: ruleSide.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: ruleRow.modelData.host
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }

        Text {
          id: ruleSide
          anchors.right: removeButton.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.ruleText(ruleRow.modelData.side)
          color: ruleRow.modelData.side === "tunnel" ? Color.accent : root.dim
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        PanelActionButton {
          id: removeButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(22)
          enabled: root.service.pendingRule === ""
          tooltipText: root.strings.t("rules.remove")
          foreground: root.textColor
          fontFamily: root.panelFontFamily
          onClicked: root.service.removeRule(ruleRow.modelData.host)

          ActionIcon {
            anchors.centerIn: parent
            name: "close"
            iconSize: Style.font.caption
            color: root.textColor
          }
        }
      }
    }

    Item { width: 1; height: Style.space(4) }

    PanelSeparator {
      width: parent.width
      foreground: root.textColor
    }

    Item { width: 1; height: Style.space(2) }
  }

  Text {
    visible: root.recent.length === 0
    width: parent.width
    textFormat: Text.PlainText
    text: root.status && root.status.running ? root.strings.t("recent.none") : root.strings.t("recent.notRunning")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  ListView {
    id: list
    width: parent.width
    visible: root.recent.length > 0
    // The checks and the rules take their room out of the list's, so the
    // page as a whole stays inside the card.
    readonly property real room: Math.max(Style.space(160), root.maxHeight
      - (rulesBlock.visible ? rulesBlock.height + root.spacing : 0)
      - (checksBlock.visible ? checksBlock.height + root.spacing : 0))
    // One row and its gap (the rows are all one height). A list taller than
    // its room shows whole rows only, so no row is ever cut in half at the
    // bottom; the scroll bar says there is more, and scrolled to either end
    // the rows line up again (the content is a whole number of rows too).
    readonly property real stride: count > 0 ? (contentHeight + spacing) / count : 0
    height: contentHeight <= room || stride <= 0 ? Math.min(contentHeight, room)
      : Math.max(stride - spacing, Math.floor((room + spacing) / stride) * stride - spacing)
    clip: true
    spacing: Style.space(8)
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    model: root.recent
    // A poll publishes a new array; keep the reader's place in it.
    property real rememberedY: 0
    onContentYChanged: if (moving || dragging) rememberedY = contentY
    onModelChanged: contentY = Math.max(0, Math.min(rememberedY, Math.max(0, contentHeight - height)))
    // Shown for as long as there is more to scroll, not only while moving:
    // a cut-off last row alone does not say the list goes on.
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: list.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }

    delegate: Item {
      id: entry
      required property var modelData
      width: ListView.view.width
      implicitHeight: hostLine.implicitHeight + detailLine.implicitHeight + Style.space(2)
      height: implicitHeight

      readonly property string viaText: modelData.via === "direct" ? root.strings.t("recent.direct")
        : (modelData.via === "block" ? root.strings.t("recent.block") : root.strings.t("recent.tunnel"))
      readonly property color viaColor: modelData.via === "tunnel" ? Color.accent
        : (modelData.via === "block" ? Color.urgent : root.dim)

      Text {
        id: hostLine
        anchors.left: parent.left
        anchors.right: countLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.top: parent.top
        textFormat: Text.PlainText
        text: entry.modelData.host
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }

      // The row under the mouse shows its "⋮"; a right click anywhere on the
      // row opens the same actions. Declared before the button, so the
      // button still takes its own clicks.
      HoverHandler { id: rowHover }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function(mouse) {
          root.openRowMenu(entry, mouse.x + rowMenu.width, mouse.y, entry.modelData.ruleHost)
        }
      }

      PanelActionButton {
        id: rowButton
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.top: parent.top
        size: Style.space(20)
        // Only hosts the CLI can take a rule for get actions.
        visible: entry.modelData.ruleHost !== "" && (rowHover.hovered || rowMenu.opened && rowMenu.subject === entry.modelData.ruleHost)
        enabled: root.service.pendingRule === ""
        tooltipText: root.strings.t("rules.actions")
        foreground: root.textColor
        fontFamily: root.panelFontFamily
        onClicked: root.openRowMenu(rowButton, rowButton.width, rowButton.height, entry.modelData.ruleHost)

        ActionIcon {
          anchors.centerIn: parent
          name: "more"
          iconSize: Style.font.caption
          color: root.textColor
        }
      }

      Text {
        id: countLabel
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10) + Style.space(24)
        anchors.baseline: hostLine.baseline
        textFormat: Text.PlainText
        text: root.strings.tn("recent.connections", entry.modelData.count).arg(root.count(entry.modelData.count))
        color: root.dim
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: detailLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10) + Style.space(24)
        anchors.top: hostLine.bottom
        anchors.topMargin: Style.space(2)
        spacing: 0

        Text {
          id: viaLabel
          textFormat: Text.PlainText
          text: entry.viaText
          color: entry.viaColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          width: Math.max(0, detailLine.width - viaLabel.width)
          textFormat: Text.PlainText
          text: {
            var parts = [""]
            // rule is the host's current rule; the connection may predate it.
            if (entry.modelData.rule !== "" && entry.modelData.rule === entry.modelData.via) parts.push(root.strings.t("recent.byRule"))
            if (entry.modelData.via === "tunnel" && entry.modelData.node !== "") parts.push(entry.modelData.node)
            parts.push(entry.modelData.time)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
