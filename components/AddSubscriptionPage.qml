import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// A new subscription: the provider's link and, optionally, a name (the
// link's host when empty). Checked here by Model.subscriptionUrl /
// subscriptionName and again by the CLI; the link is never shown anywhere
// else and never logged by the panel. Enter adds, Esc goes back.
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
  readonly property string url: Model.subscriptionUrl(urlField.text)
  readonly property string name: Model.subscriptionName(nameField.text, url)
  readonly property bool urlBad: urlField.text.trim() !== "" && url === ""
  readonly property bool nameBad: nameField.text.trim() !== "" && name === ""
  // A plain-http link: a warning, and Add stays off until "Allow plain HTTP"
  // is pressed for this very link (editing the link takes the consent back).
  readonly property bool insecure: url !== "" && Model.insecureUrl(url)
  property bool allowHttp: false
  readonly property bool canAdd: url !== "" && name !== "" && !service.addingSub && (!insecure || allowHttp)

  function start() {
    Qt.callLater(function() { urlField.forceActiveFocus() })
  }

  function submit() {
    if (root.canAdd) root.service.addSubscription(nameField.text, urlField.text, root.insecure && root.allowHttp)
  }

  Connections {
    target: root.service
    // Added: the fields are emptied for the next one.
    function onSubscriptionAdded(name) {
      urlField.text = ""
      nameField.text = ""
      root.allowHttp = false
    }
  }

  spacing: Style.space(6)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("addSub.body")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { width: 1; height: Style.space(2) }

  PanelSectionHeader {
    text: root.strings.t("addSub.url")
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  TextField {
    id: urlField
    objectName: "subscriptionUrl"
    width: parent.width
    placeholderText: root.strings.t("addSub.urlPlaceholder")
    foreground: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(6)
    maximumLength: 2000
    enabled: !root.service.addingSub
    onTextChanged: root.allowHttp = false
    Keys.onReturnPressed: function(event) { root.submit(); event.accepted = true }
    Keys.onEscapePressed: function(event) { root.cancelRequested(); event.accepted = true }
    Keys.onTabPressed: function(event) { nameField.forceActiveFocus(); event.accepted = true }
  }

  Text {
    visible: root.insecure
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("addSub.httpWarning")
    color: Color.urgent
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Button {
    visible: root.insecure
    enabled: !root.allowHttp && !root.service.addingSub
    opacity: enabled ? 1.0 : 0.6
    text: root.strings.t(root.allowHttp ? "addSub.httpAllowed" : "addSub.allowHttp")
    foreground: root.textColor
    bordered: true
    fontFamily: root.panelFontFamily
    fontSize: Style.font.caption
    verticalPadding: Style.space(3)
    horizontalPadding: Style.space(10)
    onClicked: root.allowHttp = true
  }

  Text {
    visible: root.urlBad
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("addSub.badUrl")
    color: Color.urgent
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item { width: 1; height: Style.space(2) }

  PanelSectionHeader {
    text: root.strings.t("addSub.name")
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  TextField {
    id: nameField
    objectName: "subscriptionName"
    width: parent.width
    placeholderText: root.url !== "" && root.name !== "" && nameField.text.trim() === ""
      ? root.name : root.strings.t("addSub.namePlaceholder")
    foreground: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(6)
    maximumLength: 40
    enabled: !root.service.addingSub
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
      text: root.strings.t(root.service.addingSub ? "addSub.adding" : "addSub.add")
      foreground: root.textColor
      bordered: true
      fontFamily: root.panelFontFamily
      fontSize: Style.font.bodySmall
      verticalPadding: Style.space(4)
      horizontalPadding: Style.space(12)
      onClicked: root.submit()
    }

    Button {
      enabled: !root.service.addingSub
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
