import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// A new site to check: an https link and, optionally, a name (the link's host
// when empty). Checked here by Model.siteUrl / siteName and again by the CLI.
// Enter adds, Esc goes back to the sites page. Once added, the CLI checks it
// at once and the sites page shows the result.
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily

  signal cancelRequested()

  // The panel's own keys stay off while a field has the keyboard.
  readonly property bool typing: urlField.activeFocus || nameField.activeFocus
  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  readonly property string url: Model.siteUrl(urlField.text)
  readonly property string name: Model.siteName(nameField.text, url)
  readonly property bool urlBad: urlField.text.trim() !== "" && url === ""
  readonly property bool nameBad: nameField.text.trim() !== "" && name === ""
  readonly property bool canAdd: url !== "" && name !== "" && !service.addingSite

  function start() {
    Qt.callLater(function() { urlField.forceActiveFocus() })
  }

  function submit() {
    if (root.canAdd) root.service.addSite(nameField.text, urlField.text)
  }

  Connections {
    target: root.service
    // Added: the fields are emptied for the next one.
    function onSiteAdded(name) {
      urlField.text = ""
      nameField.text = ""
    }
  }

  spacing: Style.space(6)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("addSite.body")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { width: 1; height: Style.space(2) }

  PanelSectionHeader {
    text: root.strings.t("addSite.url")
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  TextField {
    id: urlField
    objectName: "siteUrl"
    width: parent.width
    placeholderText: root.strings.t("addSite.urlPlaceholder")
    foreground: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(6)
    maximumLength: 2000
    enabled: !root.service.addingSite
    Keys.onReturnPressed: function(event) { root.submit(); event.accepted = true }
    Keys.onEscapePressed: function(event) { root.cancelRequested(); event.accepted = true }
    Keys.onTabPressed: function(event) { nameField.forceActiveFocus(); event.accepted = true }
  }

  Text {
    visible: root.urlBad
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("addSite.badUrl")
    color: Color.urgent
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { width: 1; height: Style.space(2) }

  PanelSectionHeader {
    text: root.strings.t("addSite.name")
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  TextField {
    id: nameField
    objectName: "siteName"
    width: parent.width
    placeholderText: root.url !== "" && root.name !== "" && nameField.text.trim() === ""
      ? root.name : root.strings.t("addSite.namePlaceholder")
    foreground: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(6)
    maximumLength: 40
    enabled: !root.service.addingSite
    Keys.onReturnPressed: function(event) { root.submit(); event.accepted = true }
    Keys.onEscapePressed: function(event) { root.cancelRequested(); event.accepted = true }
    Keys.onBacktabPressed: function(event) { urlField.forceActiveFocus(); event.accepted = true }
  }

  Text {
    visible: root.nameBad
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("addSub.badName")
    color: Color.urgent
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { width: 1; height: Style.space(4) }

  Row {
    spacing: Style.space(8)

    Button {
      enabled: root.canAdd
      opacity: enabled ? 1.0 : 0.45
      text: root.strings.t(root.service.addingSite ? "addSub.adding" : "addSub.add")
      foreground: root.textColor
      bordered: true
      fontFamily: root.panelFontFamily
      fontSize: Style.font.bodySmall
      verticalPadding: Style.space(4)
      horizontalPadding: Style.space(12)
      onClicked: root.submit()
    }

    Button {
      enabled: !root.service.addingSite
      opacity: enabled ? 1.0 : 0.45
      text: root.strings.t("subs.cancel")
      foreground: root.textColor
      fontFamily: root.panelFontFamily
      fontSize: Style.font.bodySmall
      verticalPadding: Style.space(4)
      horizontalPadding: Style.space(12)
      onClicked: root.cancelRequested()
    }
  }
}
