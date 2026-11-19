import QtQuick
import qs.Commons
import qs.Ui
import qs.Commons as Commons
import "../Model.js" as Model

// The subscriptions the CLI knows, in its order. The active one is marked by
// a filled dot, the selected fill and the word ACTIVE. Each row says how many
// nodes the CLI could use, when it was fetched, what the provider reports
// about traffic and expiry, why links were skipped, and why the last update of
// that subscription failed, if it did.
//
// Facts are whole phrases packed into lines (Model.packLines): a narrow card
// wraps between phrases, never inside one, and a separator only ever stands
// between two phrases on the same line. "until 28.11.2026 · 9 days left" is
// one phrase, so the date and the days left never part.
//
// Making another one active restarts the core; the button only asks, the
// panel confirms. The URLs are never shown: the CLI does not even print them.
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily

  property int cursorIndex: -1

  signal useRequested(string name)
  signal addRequested()
  signal rowHovered(int index)

  readonly property var status: service.status
  readonly property var subscriptions: status ? status.subscriptions : []
  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  readonly property string separator: " · "
  // Ticks so "updated N minutes ago" ages while the page stays open.
  property real now: Date.now() / 1000

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.now = Date.now() / 1000
  }

  // Measures phrases in the facts' font for packing them into lines.
  FontMetrics {
    id: factMetrics
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
  }

  function bytes(n) { return Model.formatBytes(n, Commons.I18n.formatNumber) }

  // Dates in Omarchy's format locale, which follows Setup > Language live.
  function date(epoch) {
    return new Date(epoch * 1000).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
  }

  function count(n) { return Commons.I18n.formatNumber(n) }

  function ageText(ts) {
    if (!ts) return root.strings.t("subs.never")
    var a = Model.age(root.now - ts)
    if (a.unit === "now") return root.strings.t("subs.justNow")
    return root.strings.tn("subs.ago." + a.unit, a.count).arg(root.count(a.count))
  }

  function facts(sub) {
    var q = Model.quota(sub.userinfo, root.now)
    var out = [
      { text: root.strings.tn("subs.nodes", sub.count).arg(root.count(sub.count)), urgent: false },
      { text: root.strings.t("subs.updated").arg(root.ageText(sub.updated)), urgent: false }
    ]
    if (q.unlimited) {
      out.push({ text: root.strings.t("subs.unlimited"), urgent: false })
      out.push({ text: root.strings.t("subs.used").arg(root.bytes(q.used)), urgent: false })
    } else {
      out.push({ text: root.strings.t("subs.remaining").arg(root.bytes(q.remaining)).arg(root.bytes(q.total)), urgent: q.exhausted })
    }
    if (q.endless) out.push({ text: root.strings.t("subs.endless"), urgent: false })
    else if (q.expired) out.push({ text: root.strings.t("subs.expired").arg(root.date(q.expire)), urgent: true })
    else out.push({
      text: root.strings.tn("subs.untilLeft", q.daysLeft).arg(root.date(q.expire)).arg(root.count(q.daysLeft)),
      urgent: false
    })
    return out
  }

  // The facts as lines of phrases for a body `width` wide.
  function factLines(sub, width) {
    var list = root.facts(sub)
    var widths = list.map(function(f) { return factMetrics.advanceWidth(f.text) })
    var lines = Model.packLines(widths, factMetrics.advanceWidth(root.separator), width)
    return lines.map(function(indices) { return indices.map(function(i) { return list[i] }) })
  }

  // One skipped-links entry in words. A code this catalog does not know reads
  // as "some links were skipped", never as the code; an entry from an older
  // CLI's cache as "some links skipped".
  function skipText(item) {
    if (item.code === "legacy") return root.strings.t("subs.skippedLegacy")
    var reason = root.strings.t("subs.skip." + item.code, "")
    if (reason === "") return root.strings.t("subs.skippedOther").arg(root.count(item.count))
    if (item.scheme !== "") return root.strings.t("subs.skippedScheme").arg(item.scheme).arg(reason).arg(root.count(item.count))
    return root.strings.t("subs.skipped").arg(reason).arg(root.count(item.count))
  }

  function updateError(name) {
    var results = root.service.updateResults
    for (var i = 0; i < results.length; i++)
      if (results[i].name === name && !results[i].ok) return results[i].error !== "" ? results[i].error : "?"
    return ""
  }

  spacing: Style.space(6)

  Text {
    visible: root.subscriptions.length === 0
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("subs.none")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.subscriptions

    delegate: CursorSurface {
      id: subRow
      required property var modelData
      required property int index

      readonly property bool pending: root.service.pendingUse === modelData.name
      readonly property string failure: root.updateError(modelData.name)
      readonly property string fullName: modelData.title !== "" && modelData.title !== modelData.name
        ? modelData.name + " · " + modelData.title
        : modelData.name

      width: root.width
      hasCursor: root.cursorIndex === index
      current: modelData.active
      foreground: root.textColor
      implicitHeight: body.implicitHeight + Style.space(16)

      HoverHandler {
        onHoveredChanged: if (hovered) root.rowHovered(subRow.index)
      }

      Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: Style.space(8) + (nameLine.implicitHeight - height) / 2
        width: Style.space(8)
        height: width
        radius: width / 2
        color: subRow.modelData.active ? Color.accent : "transparent"
        border.width: 1
        border.color: subRow.modelData.active ? Color.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.3)
      }

      Column {
        id: body
        anchors.left: dot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        spacing: Style.space(3)

        Item {
          id: nameLine
          width: parent.width
          implicitHeight: Math.max(nameText.implicitHeight, useButton.visible ? useButton.implicitHeight : 0, activeLabel.implicitHeight)

          // Name and the provider's title: someone else's strings. Whatever
          // does not fit beside the button is elided, and the whole of it is
          // in the tooltip.
          Text {
            id: nameText
            anchors.left: parent.left
            anchors.right: useButton.visible ? useButton.left : (activeLabel.visible ? activeLabel.left : parent.right)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: subRow.fullName
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight

            HoverHandler { id: nameHover }

            // No wider than the card and kept inside its window.
            PanelToolTip {
              visible: nameHover.hovered && nameText.truncated
              text: subRow.fullName
              fontFamily: root.panelFontFamily
              width: Math.min(implicitWidth, root.width)
              margins: 0
            }
          }

          Text {
            id: activeLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: subRow.modelData.active || subRow.pending
            textFormat: Text.PlainText
            text: subRow.pending ? root.strings.t("subs.switching") : root.strings.t("subs.active")
            color: subRow.modelData.active ? Color.accent : root.dim
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Button {
            id: useButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !subRow.modelData.active && !subRow.pending
            enabled: root.service.pendingUse === "" && subRow.modelData.count > 0
            // `…`: it opens a confirmation instead of switching there and then.
            text: root.strings.t("subs.use")
            foreground: root.textColor
            bordered: true
            fontFamily: root.panelFontFamily
            fontSize: Style.font.caption
            verticalPadding: Style.space(3)
            horizontalPadding: Style.space(8)
            onClicked: root.useRequested(subRow.modelData.name)
          }
        }

        // The facts, packed into lines of whole phrases.
        Repeater {
          model: root.factLines(subRow.modelData, body.width - Style.space(2))

          delegate: Row {
            id: factLine
            required property var modelData
            width: body.width

            Repeater {
              model: factLine.modelData

              delegate: Text {
                required property var modelData
                required property int index
                textFormat: Text.PlainText
                text: (index > 0 ? root.separator : "") + modelData.text
                width: Math.min(implicitWidth, body.width)
                color: modelData.urgent ? Color.urgent : root.dim
                font.family: root.panelFontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        Repeater {
          model: subRow.modelData.skipped

          delegate: Text {
            required property var modelData
            width: body.width
            textFormat: Text.PlainText
            text: root.skipText(modelData)
            color: root.dim
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }

        Text {
          visible: subRow.failure !== ""
          width: body.width
          textFormat: Text.PlainText
          text: root.strings.t("subs.updateFailed").arg(subRow.failure)
          color: Color.urgent
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
      }
    }
  }

  Item { width: 1; height: Style.space(4) }

  // `…`: it opens the form.
  Button {
    text: root.strings.t("subs.add")
    foreground: root.textColor
    bordered: true
    fontFamily: root.panelFontFamily
    fontSize: Style.font.caption
    verticalPadding: Style.space(3)
    horizontalPadding: Style.space(8)
    onClicked: root.addRequested()
  }
}
