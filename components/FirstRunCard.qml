import QtQuick
import qs.Commons
import qs.Ui

// The main screen before the tunnel can work. Two states, one card:
//   setupMode — the xray-omarchy package (the CLI and its root helper) or the
//               xray core is missing: says what, and opens the installer in
//               Omarchy's floating terminal (the password is asked there, by
//               sudo, never here);
//   otherwise — installed, but no subscription yet: leads to the form.
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily
  required property bool setupMode

  signal installRequested()
  signal addRequested()

  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  readonly property var setup: service.status !== null ? service.status.setup : null

  // What is missing, in words, when the CLI could tell; nothing when the
  // package itself is not there (the CLI is what would tell).
  readonly property string missing: {
    if (!setupMode) return ""
    if (service.backendPresent !== 1) return strings.t("setup.missing.package")
    if (setup === null || !setup.known) return ""
    var parts = []
    if (!setup.helper) parts.push(strings.t("setup.missing.helper"))
    if (!setup.core) parts.push(strings.t("setup.missing.core"))
    else if (!setup.coreCaps) parts.push(strings.t("setup.missing.caps"))
    if (!setup.geo) parts.push(strings.t("setup.missing.geo"))
    return parts.join(", ")
  }

  spacing: Style.space(8)

  PanelSeparator {
    foreground: root.textColor
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t(root.setupMode ? "setup.title" : "empty.title")
    color: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    wrapMode: Text.WordWrap
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t(root.setupMode ? "setup.body" : "empty.body")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.missing !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("setup.missing").arg(root.missing)
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { width: 1; height: Style.space(2) }

  Button {
    id: action
    // `…`: the installer explains and asks before it does anything; the
    // form asks for the link.
    text: root.strings.t(root.setupMode ? (root.service.componentsOutdated ? "setup.update" : "setup.install") : "empty.add")
    foreground: root.textColor
    bordered: true
    fontFamily: root.panelFontFamily
    fontSize: Style.font.bodySmall
    verticalPadding: Style.space(5)
    horizontalPadding: Style.space(12)
    onClicked: root.setupMode ? root.installRequested() : root.addRequested()
  }

  Text {
    visible: root.setupMode
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("setup.hint")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
