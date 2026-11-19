import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model

// Three quiet options, off the main screen.
//
// Notifications: the watcher (xray-omarchy-watch) tells the desktop when protection
// drops, a node goes down or the fallback takes over. One switch.
//
// Russia preset: off by default, everything goes through the tunnel. On, the
// Russian sites (geosite category-ru, geoip ru, the zones ru, su, xn--p1ai) go direct
// and are resolved by the network's DNS. A running core takes it on restart;
// the panel asks first.
//
// The fallback node: off by default. With a node picked by hand, the core
// probes it and, when it stops answering, sends traffic through a second
// node and back once it recovers. The switch needs a node picked from the
// list below it: plain nodes of the active subscription that answer, other
// than the selected one, fastest first — a ListView with a bounded
// viewport, since a subscription can hold 562 nodes. Changing it may need a
// core restart; the panel asks first (PanelContent's confirmation).
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily
  required property color fastColor
  required property color slowColor

  readonly property int maxRows: 5

  // The fallback needs a core restart to take full effect; the button asks.
  signal restartRequested()
  // A preset switch: PanelContent asks before a restart, or runs it at once.
  signal presetRequested(string name, bool on)

  readonly property var status: service.status
  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  readonly property var fallback: status ? status.fallback : null
  readonly property bool nodeMode: status !== null && status.mode === "node"
  readonly property string selectedId: nodeMode ? status.selected : ""
  readonly property var candidates: fallback ? Model.fallbackCandidates(service.nodes, selectedId, fallback.node) : []
  readonly property bool notifyOn: service.wantedNotify !== -1 ? service.wantedNotify === 1 : (status !== null && status.notify)
  readonly property bool russiaOn: service.wantedPreset !== -1 ? service.wantedPreset === 1
    : (status !== null && status.presets.russia === true)

  // Why the switch cannot be turned on, or what is wrong with the setting.
  readonly property string fallbackNote: {
    if (!fallback) return ""
    if (fallback.problem !== "") return root.strings.t("fallback." + fallback.problem, root.strings.t("fallback.other"))
    if (!nodeMode) return root.strings.t("settings.fallbackNeedsNode")
    if (fallback.node === "") return root.strings.t("settings.fallbackPick")
    return ""
  }
  readonly property bool canTurnOn: fallback !== null && nodeMode && fallback.node !== "" && fallback.node !== selectedId

  function delayText(node) {
    var state = Model.delayState(node)
    return state === "unknown" ? root.strings.t("node.unprobed")
      : (state === "dead" ? root.strings.t("node.dead") : root.strings.t("node.delay").arg(Commons.I18n.formatNumber(node.delay)))
  }

  function delayColor(node) {
    var state = Model.delayState(node)
    if (state === "fast") return root.fastColor
    if (state === "slow") return root.slowColor
    return root.dim
  }

  spacing: Style.space(12)

  // ---- notifications -------------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: Math.max(notifyLabels.implicitHeight, notifySwitch.implicitHeight)

    Column {
      id: notifyLabels
      anchors.left: parent.left
      anchors.right: notifySwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.notify")
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.notifyHint")
        color: root.dim
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    ToggleSwitch {
      id: notifySwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.status !== null && root.status.notifyKnown
      checked: root.notifyOn
      busy: root.service.wantedNotify !== -1
      cursorRing: false
      foreground: root.textColor
      onToggled: root.service.setNotify(!root.notifyOn)
    }
  }

  PanelSeparator {
    width: parent.width
    foreground: root.textColor
  }

  // ---- Russia preset -----------------------------------------------------------
  Item {
    visible: root.status !== null && root.status.presets.known
    width: parent.width
    implicitHeight: Math.max(russiaLabels.implicitHeight, russiaSwitch.implicitHeight)

    Column {
      id: russiaLabels
      anchors.left: parent.left
      anchors.right: russiaSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.russia")
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.russiaHint")
        color: root.dim
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    ToggleSwitch {
      id: russiaSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: root.russiaOn
      busy: root.service.wantedPreset !== -1
      interactive: root.service.wantedPreset === -1
      cursorRing: false
      foreground: root.textColor
      onToggled: root.presetRequested("russia", !root.russiaOn)
    }
  }

  PanelSeparator {
    visible: root.status !== null && root.status.presets.known
    width: parent.width
    foreground: root.textColor
  }

  // ---- fallback node ----------------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: Math.max(fallbackLabels.implicitHeight, fallbackSwitch.implicitHeight)

    Column {
      id: fallbackLabels
      anchors.left: parent.left
      anchors.right: fallbackSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.fallback")
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.strings.t("settings.fallbackHint")
        color: root.dim
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    ToggleSwitch {
      id: fallbackSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.fallback !== null
      checked: root.fallback !== null && root.fallback.enabled
      busy: root.service.fallbackBusy
      // Turning it off is always allowed; on, only with a node to fall back to.
      interactive: !root.service.fallbackBusy && (checked || root.canTurnOn)
      opacity: interactive || checked ? 1.0 : 0.45
      cursorRing: false
      foreground: root.textColor
      onToggled: root.service.runFallback([checked ? "off" : "on"])
    }
  }

  // What stands in the way, or what is wrong: one or two lines.
  Text {
    visible: root.fallbackNote !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.fallbackNote
    color: root.fallback !== null && root.fallback.problem !== "" && root.fallback.enabled ? Color.urgent : root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }

  // The setting is saved and applied, but the core probes the nodes the old
  // way until it restarts.
  Item {
    visible: root.fallback !== null && root.fallback.restartNeeded
    width: parent.width
    implicitHeight: Math.max(restartText.implicitHeight, restartButton.implicitHeight)

    Text {
      id: restartText
      anchors.left: parent.left
      anchors.right: restartButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.strings.t("settings.restartNeeded")
      color: root.slowColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Button {
      id: restartButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      enabled: !root.service.fallbackBusy
      opacity: enabled ? 1.0 : 0.45
      text: root.strings.t("settings.restart")
      foreground: root.textColor
      bordered: true
      fontFamily: root.panelFontFamily
      fontSize: Style.font.caption
      verticalPadding: Style.space(3)
      horizontalPadding: Style.space(8)
      onClicked: root.restartRequested()
    }
  }

  // ---- the node to fall back to -------------------------------------------------
  Item {
    visible: root.status !== null && root.status.running
    width: parent.width
    implicitHeight: Math.max(pickHeader.implicitHeight, pickCount.implicitHeight)

    PanelSectionHeader {
      id: pickHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.strings.t("settings.fallbackNode")
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    Text {
      id: pickCount
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.fallback !== null && root.fallback.node !== "" && root.fallback.nodeName !== ""
        ? root.fallback.nodeName : ""
      color: root.dim
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      width: Math.min(implicitWidth, parent.width - pickHeader.implicitWidth - Style.space(12))
    }
  }

  Text {
    visible: root.status !== null && !root.status.running
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("nodes.notRunning")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.status !== null && root.status.running && root.candidates.length === 0
    width: parent.width
    textFormat: Text.PlainText
    text: root.strings.t("settings.noCandidates")
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  ListView {
    id: list
    width: parent.width
    visible: root.status !== null && root.status.running && root.candidates.length > 0
    height: Math.min(contentHeight, root.maxRows * (Style.font.body + Style.spacing.xl + spacing) - spacing)
    clip: true
    spacing: Style.space(6)
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    model: root.candidates
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: list.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }

    delegate: CursorSurface {
      id: pickRow
      required property var modelData
      readonly property bool chosen: root.fallback !== null && root.fallback.node === modelData.id
      width: ListView.view.width
      current: chosen
      hasCursor: pickMouse.containsMouse
      foreground: root.textColor
      implicitHeight: Math.max(pickName.implicitHeight, pickDelay.implicitHeight) + Style.spacing.xl
      opacity: root.service.fallbackBusy ? 0.6 : 1.0

      ActionIcon {
        id: pickMark
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6) + (Style.space(22) - Style.font.body) / 2
        anchors.verticalCenter: parent.verticalCenter
        visible: pickRow.chosen
        name: "check"
        iconSize: Style.font.body
        color: Color.accent
      }

      Text {
        id: pickName
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6) + Style.space(22) + Style.space(8)
        anchors.right: pickDelay.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: pickRow.modelData.name
        color: pickRow.modelData.alive === false ? root.dim : root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.body
        font.bold: pickRow.chosen
        elide: Text.ElideRight
      }

      Text {
        id: pickDelay
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8) + (list.interactive ? Style.space(6) : 0)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.delayText(pickRow.modelData)
        color: root.delayColor(pickRow.modelData)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: pickMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pickRow.chosen ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!pickRow.chosen) root.service.runFallback(["set", pickRow.modelData.id])
      }
    }
  }
}
