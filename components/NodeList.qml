import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model

// The nodes of the active subscription, the way Tailscale lists exit nodes:
// "Auto" pinned on top, then the nodes that answer, fastest first; the dead
// ones folded into one "Unreachable: N" row that opens in place.
//
// The order is frozen while the panel is open. It is taken when the panel
// opens and when the search text changes; polls after that only change the
// delays printed in the rows (see Model.reconcileOrder). The keyboard cursor
// holds a node id, not a row number, so nothing slides under it.
//
// A subscription can hold 562 nodes, so the list is a ListView that builds
// only the rows in view, and its viewport stops at `maxRows`: the panel does
// not grow with the subscription. A search field appears past ten nodes.
Column {
  id: root

  required property var service
  required property var strings
  required property color textColor
  required property string panelFontFamily
  required property color fastColor
  required property color slowColor

  // "auto", "fold", a node id, or "" with no cursor on screen.
  property string cursorKey: ""
  readonly property bool filterFocused: filterField.activeFocus
  readonly property int maxRows: 7

  signal rowHovered(string key)
  signal leaveFilter()

  readonly property var status: service.status
  readonly property bool live: status !== null && status.running
  readonly property color dim: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  // Read straight from the field: inside its own textChanged handler a
  // binding on the text may not have caught up yet.
  function currentQuery() { return filterField.visible ? filterField.text : "" }
  readonly property bool searchable: service.nodes.length > 10

  readonly property var byId: {
    var map = ({})
    var list = service.nodes
    for (var i = 0; i < list.length; i++) map[list[i].id] = list[i]
    return map
  }

  property var order: ({ live: [], dead: [] })
  property bool expanded: false
  readonly property var keys: Model.listKeys(order, expanded)

  readonly property string activeSubscription: {
    var subs = status ? status.subscriptions : []
    for (var i = 0; i < subs.length; i++) if (subs[i].active) return subs[i].name
    return ""
  }

  // ---- the frozen order --------------------------------------------------

  // On open: sort afresh, fold closed, and the picked node in view — a
  // 562-node list must not hide it below the seventh row. A picked node that
  // is dead sits in the fold, which then opens. A new search starts at the top.
  function resetOrder(keepSelectedInView) {
    var order = Model.nodeOrder(root.service.nodes, root.currentQuery())
    root.expanded = keepSelectedInView === true && root.selectedId !== "" && order.dead.indexOf(root.selectedId) >= 0
    root.order = order
    syncModel()
    var at = keepSelectedInView === true && root.selectedId !== "" ? root.keys.indexOf(root.selectedId) : -1
    if (at >= 0) {
      list.forceLayout()
      list.positionViewAtIndex(at, ListView.Center)
    } else {
      list.positionViewAtBeginning()
    }
  }

  // A poll: delays change in the rows by themselves (they read `byId`); the
  // order only drops vanished nodes and appends new ones.
  Connections {
    target: root.service
    function onNodesChanged() {
      var next = Model.reconcileOrder(root.order, root.service.nodes, root.currentQuery())
      if (!Model.sameOrder(next, root.order)) root.order = next
    }
  }

  onKeysChanged: syncModel()

  // The ListView's model holds keys only. Opening the fold appends rows and
  // closing it removes them, so the scroll position survives both; anything
  // else rebuilds the model.
  function syncModel() {
    var next = root.keys
    var count = keyModel.count
    var prefix = 0
    while (prefix < count && prefix < next.length && keyModel.get(prefix).rowKey === next[prefix]) prefix++
    if (prefix === count && prefix === next.length) return
    if (prefix === count) {
      for (var i = prefix; i < next.length; i++) keyModel.append({ rowKey: next[i] })
      return
    }
    if (prefix === next.length) {
      keyModel.remove(prefix, count - prefix)
      return
    }
    keyModel.clear()
    for (var j = 0; j < next.length; j++) keyModel.append({ rowKey: next[j] })
  }

  function focusFilter() { if (filterField.visible) filterField.forceActiveFocus() }
  function setFilter(text) { filterField.text = String(text || "").substring(0, 64) }
  function clearFilter() { filterField.text = "" }

  function activate(key) {
    if (key === "fold") root.expanded = !root.expanded
    else if (key === "auto") root.service.selectNode("auto")
    else if (Model.validNodeId(key)) root.service.selectNode(key)
  }

  function ensureVisible(key) {
    var at = root.keys.indexOf(key)
    if (at >= 0) list.positionViewAtIndex(at, ListView.Contain)
  }

  // ---- what a row says ---------------------------------------------------

  readonly property bool autoMode: status !== null && (service.pendingSelect === "auto"
    || (service.pendingSelect === "" && status.mode === "auto"))
  readonly property string selectedId: service.pendingSelect !== "" && service.pendingSelect !== "auto"
    ? service.pendingSelect
    : (status !== null && status.mode === "node" ? status.selected : "")

  function delayText(node) {
    var state = Model.delayState(node)
    var text = state === "unknown" ? root.strings.t("node.unprobed")
      : (state === "dead" ? root.strings.t("node.dead") : root.strings.t("node.delay").arg(Commons.I18n.formatNumber(node.delay)))
    if (node.group) text = root.strings.tn("nodes.group", node.members).arg(Commons.I18n.formatNumber(node.members)) + " · " + text
    return text
  }

  function delayColor(node) {
    var state = Model.delayState(node)
    if (state === "fast") return root.fastColor
    if (state === "slow") return root.slowColor
    return root.dim
  }

  spacing: Style.space(10)

  Item {
    width: parent.width
    implicitHeight: Math.max(nodesHeader.implicitHeight, countLabel.implicitHeight)

    PanelSectionHeader {
      id: nodesHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.strings.t("nodes.header")
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    // The active subscription is someone else's string: plain text, elided.
    Text {
      id: countLabel
      anchors.left: nodesHeader.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: root.service.pendingSelect !== ""
        ? root.strings.t("mode.switching")
        : root.strings.t("nodes.meta").arg(root.activeSubscription)
          .arg(Commons.I18n.formatNumber(Model.aliveCount(root.service.nodes)))
          .arg(Commons.I18n.formatNumber(root.service.nodes.length))
      visible: root.service.nodesLoaded
      color: root.dim
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideLeft
    }
  }

  TextField {
    id: filterField
    visible: root.searchable
    width: parent.width
    placeholderText: root.strings.t("nodes.filter")
    foreground: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(6)
    maximumLength: 64
    // A new search is the one other moment the order is taken.
    onTextChanged: root.resetOrder(false)
    onVisibleChanged: if (!visible && text !== "") text = ""
    Keys.onEscapePressed: function(event) {
      if (filterField.text !== "") filterField.text = ""
      else root.leaveFilter()
      event.accepted = true
    }
    Keys.onDownPressed: function(event) { root.leaveFilter(); event.accepted = true }
    Keys.onUpPressed: function(event) { root.leaveFilter(); event.accepted = true }
    Keys.onReturnPressed: function(event) { root.leaveFilter(); event.accepted = true }
  }

  // Pinned outside the scrolled list: never filtered away, never scrolled
  // out of reach.
  NodeRow {
    id: autoRow
    width: parent.width
    key: "auto"
    title: root.strings.t("nodes.auto")
    trailing: root.autoMode && root.status && root.status.current !== ""
      ? root.strings.t("nodes.autoNow").arg(root.status.current)
      : root.strings.t("nodes.autoHint")
    selected: root.autoMode
  }

  Text {
    visible: !root.live || !root.service.nodesLoaded || root.keys.length === 0
    width: parent.width
    textFormat: Text.PlainText
    text: !root.live ? root.strings.t("nodes.notRunning")
      : (!root.service.nodesLoaded ? root.strings.t("nodes.loading") : root.strings.t("nodes.nothingFound"))
    color: root.dim
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }

  ListView {
    id: list
    width: parent.width
    visible: root.keys.length > 0
    // Every row is one line, as tall as the pinned Auto row.
    height: Math.min(contentHeight, root.maxRows * (autoRow.implicitHeight + spacing) - spacing)
    clip: true
    spacing: Style.space(6)
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    model: ListModel { id: keyModel }
    // Shown for as long as there is more to scroll, not only while moving:
    // a cut-off last row alone does not say the list goes on.
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: list.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }

    delegate: NodeRow {
      required property string rowKey
      key: rowKey
      readonly property var node: key === "fold" ? null : (root.byId[key] || null)
      width: ListView.view.width
      title: key === "fold" ? root.strings.t("nodes.unreachable").arg(root.order.dead.length)
        : (node ? node.name : key)
      trailing: node ? root.delayText(node) : ""
      trailingColor: node ? root.delayColor(node) : root.dim
      selected: node !== null && root.selectedId === key
      carrying: node !== null && root.autoMode && root.live && root.status.currentId === key
      muted: key === "fold" || (node !== null && node.alive === false)
    }
  }

  // One row: a 22-px marker column like Tailscale's glyphs, the name, and the
  // delay on the right. The picked node is marked three ways: a check, the
  // selected fill and border (`current`), and bold — never by colour alone.
  component NodeRow: CursorSurface {
    id: nodeRow
    property string key: ""
    property string title: ""
    property string trailing: ""
    property color trailingColor: root.dim
    property bool selected: false
    property bool carrying: false
    property bool muted: false
    readonly property bool isFold: key === "fold"

    hasCursor: root.cursorKey !== "" && root.cursorKey === key
    current: selected
    foreground: root.textColor
    implicitHeight: Math.max(nameText.implicitHeight, rightText.implicitHeight) + Style.spacing.xl
    opacity: root.live || isFold ? 1.0 : 0.45

    Item {
      id: marker
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: Style.font.body

      ActionIcon {
        anchors.centerIn: parent
        visible: nodeRow.selected || nodeRow.isFold
        name: nodeRow.isFold ? (root.expanded ? "chevron-up" : "chevron-down") : "check"
        iconSize: Style.font.body
        color: nodeRow.isFold ? root.dim : Color.accent
      }

      // In Auto: the node the balancer is using right now.
      ActionIcon {
        anchors.centerIn: parent
        visible: nodeRow.carrying && !nodeRow.selected
        name: "dot"
        iconSize: Style.font.body
        color: Color.accent
      }
    }

    Text {
      id: nameText
      anchors.left: marker.right
      anchors.leftMargin: Style.space(8)
      anchors.right: rightText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: nodeRow.title
      color: nodeRow.muted ? root.dim : root.textColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.body
      font.bold: nodeRow.selected
      elide: Text.ElideRight
    }

    Text {
      id: rightText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, nodeRow.width * 0.5)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: nodeRow.trailing
      color: nodeRow.trailingColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.live || nodeRow.isFold ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.rowHovered(nodeRow.key)
      onClicked: if (root.live || nodeRow.isFold) root.activate(nodeRow.key)
    }
  }
}
