import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The xray core: the version installed, the latest release and whether it is
// newer, and how the last update went. "Update core…" only asks; the panel
// confirms (the connection drops for a few seconds, and a new core that fails
// is rolled back by itself). While an update runs the page says so and the
// service follows it through `xray-omarchy core status` until it is done.
//
// `core status` runs only while this page is shown or an update runs; the
// release check behind it is the CLI's, cached for a day.
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily

  signal updateRequested()

  readonly property var core: service.core
  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  readonly property bool updating: service.coreUpdating || (core !== null && core.inProgress)

  function date(iso) {
    if (iso === "") return ""
    var d = new Date(iso + "T00:00:00")
    return isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
  }

  readonly property string latestText: {
    if (core === null || core.latest === "") return root.strings.t("corePage.unknown")
    var when = root.date(core.published)
    return when !== "" ? root.strings.t("corePage.latestOn").arg(core.latest).arg(when) : core.latest
  }

  // One line on where things stand.
  readonly property string stateText: {
    if (core === null) return root.strings.t("corePage.loading")
    if (root.updating) return root.strings.t("corePage.updating")
    if (core.updateAvailable === true) return root.strings.t("corePage.available")
    if (core.updateAvailable === false) return root.strings.t("corePage.current")
    return core.checkError !== "" ? root.strings.t("corePage.checkFailed") : root.strings.t("corePage.unknown")
  }

  // How the last update ended, when there was one.
  readonly property string lastText: {
    if (core === null || core.update === null || core.update.state === "running") return ""
    var u = core.update
    var outcome = u.state === "lost" ? root.strings.t("corePage.last.lost")
      : root.strings.t("corePage.last." + u.code, root.strings.t("corePage.last.other"))
    return root.strings.t("corePage.last").arg(u.from).arg(u.to).arg(outcome)
  }

  spacing: Style.space(8)

  component Fact: Item {
    property string label: ""
    property string value: ""
    property color valueColor: root.textColor
    width: root.width
    implicitHeight: Math.max(factLabel.implicitHeight, factValue.implicitHeight)

    Text {
      id: factLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      color: root.dim
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: factValue
      anchors.left: factLabel.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: parent.value
      color: parent.valueColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  Fact {
    label: root.strings.t("corePage.installed")
    value: root.core !== null && root.core.version !== "" ? root.core.version : root.strings.t("corePage.unknown")
  }

  Fact {
    label: root.strings.t("corePage.latest")
    value: root.latestText
  }

  Fact {
    visible: root.core !== null && root.core.prevVersion !== ""
    label: root.strings.t("corePage.previous")
    value: root.core !== null ? root.core.prevVersion : ""
    valueColor: root.dim
  }

  Item { width: 1; height: Style.space(2) }

  // Where things stand and the button.
  Item {
    width: parent.width
    implicitHeight: Math.max(stateLine.implicitHeight, updateButton.implicitHeight)

    Text {
      id: stateLine
      anchors.left: parent.left
      anchors.right: updateButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.stateText
      color: root.updating || (root.core !== null && root.core.updateAvailable === true) ? Color.accent : root.dim
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.updating || (root.core !== null && root.core.updateAvailable === true)
      wrapMode: Text.WordWrap
    }

    Button {
      id: updateButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      enabled: root.core !== null && root.core.updateAvailable === true && !root.updating
      opacity: enabled ? 1.0 : 0.45
      // `…`: it opens a confirmation.
      text: root.strings.t("corePage.update")
      foreground: root.textColor
      bordered: true
      fontFamily: root.panelFontFamily
      fontSize: Style.font.caption
      verticalPadding: Style.space(3)
      horizontalPadding: Style.space(8)
      onClicked: root.updateRequested()
    }
  }

  // A newer XTLS release than this package pins: it comes with "Update components…".
  Text {
    visible: root.core !== null && root.core.unpinnedRelease !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.core !== null ? root.strings.t("corePage.unpinned").arg(root.core.unpinnedRelease) : ""
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }

  Text {
    visible: root.core !== null && root.core.checkError !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.core !== null ? root.strings.t("corePage.checkError").arg(root.core.checkError) : ""
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }

  Text {
    visible: root.lastText !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.lastText
    color: root.core !== null && root.core.update !== null && !root.core.update.ok ? Color.urgent : root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }

  Text {
    visible: root.core !== null && root.core.update !== null && !root.core.update.ok
      && root.core.update.state === "done" && root.core.update.detail !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.core !== null && root.core.update !== null ? root.core.update.detail : ""
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }
}
