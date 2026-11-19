import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model

// What the card shows. Built lazily by the panel the first time it opens and
// kept after that (KeyboardPanel's `content`), the way the shell's own panels
// do it. Everything it draws comes from the service's cache, which is polled
// with the panel closed as well: opening never shows an empty state that
// fills in a moment later.
//
// One main screen, Tailscale's shape: a header with the node, the exit and
// the switch; one line of speed and today's traffic; one line of protection;
// the node list. Subscriptions, sites, settings (notifications and the
// fallback node) and the core are second pages behind the menu, with a back
// arrow, built only while they are shown. The main screen gains one line
// only while traffic goes through the fallback node, and one line of checked
// sites once there are any (its rows unfold in place).
PanelKeyCatcher {
  id: root

  required property var service
  required property var strings
  required property bool panelOpen
  required property color foreground
  required property color urgent
  required property string fontFamily
  required property color fastColor
  required property color slowColor

  // PanelKeyCatcher's own closeRequested means "Esc"; on a second page Esc
  // goes back, so the panel listens to these instead.
  signal dismissRequested()
  signal switchPanelRequested(int direction)

  // "main", "subs", "sites", "settings", "core", "addsub" or "addsite".
  property string page: "main"
  // The checked sites' rows under their line on the main screen.
  property bool sitesExpanded: false
  // The node-list cursor holds a key (see NodeList), "" with no cursor.
  property string cursorKey: ""
  property int subCursor: -1
  // What waits for confirmation: "" none, "use" (confirmArg is the
  // subscription), "fallback" (a core restart for the fallback setting) or
  // "core" (the core update) or "preset" (confirmArg on/off: a core restart
  // for the Russia preset).
  property string confirmKind: ""
  property string confirmArg: ""
  readonly property string confirmUse: confirmKind === "use" ? confirmArg : ""

  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property var status: service.status
  readonly property string connection: service.connection
  readonly property bool connected: connection === "on"
  readonly property bool failed: connection === "failed" || connection === "unprotected" || service.pollError !== ""
  // First run: the package or the core is missing — the main screen is one
  // card that opens the installer. Then, with no subscription yet, one card
  // that leads to the form. Neither shows a switch, nodes or protection.
  readonly property bool setupMode: service.setupNeeded
  readonly property bool emptyMode: !setupMode && service.backendPresent === 1 && status !== null
    && status.subscriptions.length === 0
  readonly property bool tunnelScreen: !setupMode && !emptyMode

  // A confirmation is drawn inside the card, and the card is the panel's
  // window: on a short page (the core page is about 140 px) the dialog
  // would be cut off. While one is open the card is at least as tall as the
  // dialog needs, measured with the dialog's own font and width.
  implicitHeight: Math.max(column.implicitHeight, confirmKind !== "" ? confirmNeed : 0)

  readonly property real confirmNeed: confirmMeasure.implicitHeight + Style.space(20) + Style.space(34)
    + Style.space(18) * 2 + Style.normalBorderWidth * 2 + Style.space(24)

  Text {
    id: confirmMeasure
    visible: false
    width: Math.min(root.width - Style.space(32), Style.space(370)) - Style.space(18) * 2 - Style.normalBorderWidth * 2
    textFormat: Text.PlainText
    text: useConfirm.message
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    wrapMode: Text.WordWrap
  }
  blocked: nodeList.filterFocused || confirmKind !== "" || moreMenu.menuOpen || addSubForm.typing || addSiteForm.typing

  function bytes(n) { return Model.formatBytes(n, Commons.I18n.formatNumber) }

  // While a node switch runs, and until the answer after it lands, the
  // header shows no exit at all: the cached one would be the previous node's.
  readonly property bool exitStale: service.pendingSelect !== "" || service.checkingSwitch || service.refreshingExit

  // During a switch the header names the node being switched to.
  readonly property string heroTitle: {
    if (!connected) return strings.t("title")
    var target = service.switchTarget
    if (target === "auto") return strings.t("nodes.auto")
    if (target !== "") {
      var node = Model.nodeById(service.nodes, target)
      if (node) return node.name
    }
    return status.current !== "" ? status.current : strings.t("title")
  }

  // The caps part of the header's second line; the delay goes in heroTail.
  readonly property string heroMeta: {
    if (setupMode) return strings.t("state.notInstalled")
    if (emptyMode) return strings.t("state.noSubscriptions")
    if (service.pollError !== "") return strings.t("state.noAnswer")
    if (!connected) return strings.t("state." + connection)
    if (service.pendingSelect !== "") return strings.t("mode.switching")
    if (exitStale) return strings.t("mode.checking")
    var p = Model.heroParts(status, service.nodes)
    var parts = []
    if (p.country !== "") parts.push(p.country)
    if (p.ip !== "") parts.push(p.ip)
    return parts.length > 0 || p.delay !== null ? parts.join(" · ") : strings.t("state.on")
  }

  readonly property string heroTail: {
    if (service.pollError !== "" || !connected || exitStale) return ""
    var p = Model.heroParts(status, service.nodes)
    return p.delay !== null ? strings.t("hero.delay").arg(Commons.I18n.formatNumber(p.delay)) : ""
  }

  // A notice key is a catalog key. A CLI result is "<verb>.<code>" (on, off,
  // select, fallback, rule, core); a code this catalog does not know reads as
  // that verb's ".other" sentence, never as the code itself. The core's own
  // words, when the CLI gave any, follow.
  readonly property var codeFamilies: ["on.", "off.", "select.", "fallback.", "rule.", "core.", "subadd.", "install.",
    "siteadd.", "siterm."]

  function noticeSentence() {
    var key = service.noticeKey
    var prefix = ""
    for (var i = 0; i < codeFamilies.length; i++) if (key.indexOf(codeFamilies[i]) === 0) prefix = codeFamilies[i]
    var text = prefix !== "" ? strings.t(key, strings.t(prefix + "other")) : strings.t(key)
    // Only sentences with a slot take the argument (QString::arg warns otherwise).
    if (text.indexOf("%1") >= 0) text = text.arg(service.noticeArg)
    return service.noticeDetail !== "" ? strings.t("notice.withDetail").arg(text).arg(service.noticeDetail) : text
  }

  readonly property string noticeText: {
    if (service.noticeKey !== "") return noticeSentence()
    if (setupMode) return ""
    if (service.pollError === "exit") return strings.t("notice.pollExit")
    if (service.pollError === "parse") return strings.t("notice.pollParse")
    if (connection === "failed") return strings.t("notice.failed")
    return ""
  }
  readonly property bool noticeUrgent: service.noticeKey !== "" ? service.noticeIsError : noticeText !== ""

  // ---- navigation ----------------------------------------------------------

  // Every open starts on the main screen with a fresh order, the search
  // cleared and no cursor. Runs before the first frame of the open, so the
  // card is drawn once at its final height.
  function resetForOpen() {
    moreMenu.closeMenu()
    page = "main"
    cursorKey = ""
    subCursor = -1
    sitesExpanded = false
    if (confirmKind === "fallback") service.cancelFallbackApply()
    confirmKind = ""
    confirmArg = ""
    nodeList.clearFilter()
    nodeList.resetOrder(true)
    panelFlick.contentY = 0
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  onPanelOpenChanged: if (panelOpen) resetForOpen()
  Component.onCompleted: resetForOpen()

  readonly property var pages: ["main", "subs", "sites", "settings", "core", "addsub", "addsite"]

  function showPage(name) {
    if (name === "menu") {
      showPage("main")
      moreMenu.openMenu()
      return true
    }
    if (pages.indexOf(name) < 0) return false
    moreMenu.closeMenu()
    page = name
    subCursor = -1
    panelFlick.contentY = 0
    if (name === "addsub") addSubForm.start()
    else if (name === "addsite") addSiteForm.start()
    else Qt.callLater(function() { root.forceActiveFocus() })
    return true
  }

  // The rows as they stand, Auto first: the IPC status reports these so a
  // check can confirm the order holds across polls.
  function listKeys() { return ["auto"].concat(nodeList.keys) }

  function setFilter(text) {
    if (!nodeList.searchable) return false
    showPage("main")
    nodeList.setFilter(text)
    return true
  }

  onMoveRequested: function(dx, dy) {
    if (page !== "main") {
      if (dx < 0) { showPage("main"); return }
      if (page === "subs") {
        var count = status ? status.subscriptions.length : 0
        if (count > 0) subCursor = Math.max(0, Math.min(count - 1, subCursor + dy))
      } else if (page === "sites" && sitesLoader.item) {
        sitesLoader.item.scrollBy(dy)
      }
      return
    }
    if (dy === 0) return
    cursorKey = Model.moveKey(nodeList.keys, cursorKey, dy)
    nodeList.ensureVisible(cursorKey)
  }

  // Enter picks the node under the cursor or opens the fold. Nothing on the
  // keyboard turns the tunnel off or switches the subscription.
  onActivateRequested: if (page === "main" && cursorKey !== "") nodeList.activate(cursorKey)
  onCloseRequested: page !== "main" ? showPage("main") : root.dismissRequested()
  // The installer's terminal opened: the panel steps out of its way. When
  // its check refused (install.stale_db), the panel stays with the notice.
  Connections {
    target: root.service
    function onInstallLaunched() { root.dismissRequested() }
  }
  onTabRequested: function(direction) { root.switchPanelRequested(direction) }
  onTextKey: function(text) {
    var key = String(text || "").toLowerCase()
    if (key === "r") service.refresh()
    // Before the backend is installed there is nothing for the other keys to run.
    else if (setupMode) return
    else if (key === "/" || key === "f") { showPage("main"); nodeList.focusFilter() }
    else if (key === "s") showPage("subs")
    else if (key === "c") showPage("sites")
    else if (key === "u") service.updateSubscriptions()
    else if (key === "m" && page === "main") moreMenu.openMenu()
  }

  function askUse(name) {
    if (!status || !Model.validSubscriptionName(name, status.subscriptions)) return
    askConfirm("use", name)
  }

  // Every confirmation opens on Cancel, so a double Enter does nothing.
  function askConfirm(kind, arg) {
    moreMenu.closeMenu()
    confirmKind = kind
    confirmArg = arg || ""
    useConfirm.selectedIndex = 0
    Qt.callLater(function() { confirmKeys.forceActiveFocus() })
  }

  function closeConfirm() {
    confirmKind = ""
    confirmArg = ""
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  // A fallback verb came back restart_needed: ask before the restart.
  Connections {
    target: root.service
    function onFallbackRestartAsked() { root.askConfirm("fallback") }
    // Back to the main screen: the nodes of the new subscription, or the card
    // with the notice of why it did not download.
    function onSubscriptionAdded(name) { if (root.page === "addsub") root.showPage("main") }
    // A site added: back to the sites page, where its first check shows up.
    function onSiteAdded(name) { if (root.page === "addsite") root.showPage("sites") }
  }

  // `core status` runs only while the core page is on screen.
  Binding {
    target: root.service
    property: "corePageShown"
    value: root.page === "core" && root.panelOpen
  }

  Flickable {
    id: panelFlick
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: column
      width: panelFlick.width
      spacing: Style.space(12)

      // ---- header: Tailscale's hero ---------------------------------------
      Item {
        id: header
        visible: root.page === "main"
        width: parent.width
        implicitHeight: Math.max(hero.implicitHeight, controls.implicitHeight)

        XrayHero {
          id: hero
          anchors.left: parent.left
          anchors.right: controls.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          title: root.heroTitle
          meta: root.heroMeta
          metaTail: root.heroTail
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.connected || root.failed ? 1.0 : 0.5
          iconComponent: Component {
            XrayIcon {
              iconSize: Style.font.display
              color: root.foreground
              badgeColor: Color.urgent
              crossed: !root.connected && !root.failed
              warning: root.failed
              ringed: false
            }
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          // The whole tunnel: `xray-omarchy on` / `xray-omarchy off` move the core, the
          // killswitch and the system DNS together. The knob follows the
          // requested position until the CLI confirms it.
          ToggleSwitch {
            id: powerSwitch
            anchors.verticalCenter: parent.verticalCenter
            visible: root.status !== null && root.tunnelScreen
            checked: root.service.wantedRunning === -1 ? root.service.engaged : root.service.wantedRunning === 1
            busy: root.service.wantedRunning !== -1 || root.service.pendingUse !== ""
            cursorRing: false
            foreground: root.foreground
            onToggled: root.service.setTunnel(!root.service.engaged)

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.service.wantedRunning !== -1
                ? root.strings.t(root.service.wantedRunning === 1 ? "switch.starting" : "switch.stopping")
                : root.strings.t(root.service.engaged ? "switch.turnOff" : "switch.turnOn")
              fontFamily: root.fontFamily
            }
          }

          MoreMenu {
            id: moreMenu
            visible: !root.setupMode
            anchors.verticalCenter: parent.verticalCenter
            textColor: root.foreground
            panelFontFamily: root.fontFamily
            strings: root.strings
            updating: root.service.updating
            onSubscriptionsRequested: root.showPage("subs")
            onSitesRequested: root.showPage("sites")
            onSettingsRequested: root.showPage("settings")
            onCoreRequested: root.showPage("core")
            onUpdateRequested: root.service.updateSubscriptions()
          }
        }
      }

      // ---- second pages: a back arrow and the page's name ---------------
      Item {
        visible: root.page !== "main"
        width: parent.width
        implicitHeight: Math.max(backButton.height, pageTitle.implicitHeight)

        PanelActionButton {
          id: backButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(26)
          tooltipText: root.strings.t("back")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showPage("main")

          ActionIcon {
            anchors.centerIn: parent
            name: "back"
            iconSize: Style.font.icon
            color: root.foreground
          }
        }

        PanelSectionHeader {
          id: pageTitle
          anchors.left: backButton.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.strings.t(root.page === "subs" ? "subs.header"
            : (root.page === "settings" ? "settings.header" : (root.page === "core" ? "corePage.header"
            : (root.page === "addsub" ? "addSub.header" : (root.page === "addsite" ? "addSite.header" : "recent.header")))))
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          anchors.left: pageTitle.right
          anchors.leftMargin: Style.space(12)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          visible: root.page === "sites" && root.status !== null && root.status.recent.length > 0
          text: root.status ? root.strings.tn("recent.count", root.status.recent.length).arg(Commons.I18n.formatNumber(root.status.recent.length)) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // ---- one notice line: the last action, or why the CLI did not answer
      Item {
        visible: root.noticeText !== ""
        width: parent.width
        implicitHeight: Math.max(noticeLine.implicitHeight, noticeClose.visible ? noticeClose.height : 0)

        Text {
          id: noticeLine
          anchors.left: parent.left
          anchors.right: noticeClose.visible ? noticeClose.left : parent.right
          anchors.rightMargin: noticeClose.visible ? Style.space(6) : 0
          anchors.top: parent.top
          textFormat: Text.PlainText
          text: root.noticeText
          color: root.noticeUrgent ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        PanelActionButton {
          id: noticeClose
          visible: root.service.noticeKey !== ""
          anchors.right: parent.right
          anchors.top: parent.top
          size: Style.space(20)
          tooltipText: root.strings.t("notice.dismiss")
          foreground: root.noticeUrgent ? root.urgent : root.foreground
          hoverColor: foreground
          fontFamily: root.fontFamily
          onClicked: root.service.clearNotice()

          ActionIcon {
            anchors.centerIn: parent
            name: "close"
            iconSize: Style.font.caption
            color: noticeClose.foreground
          }
        }
      }

      // ---- one line: speed now, traffic today ---------------------------
      // ---- first run: install, or add the first subscription --------------
      FirstRunCard {
        visible: root.page === "main" && (root.setupMode || root.emptyMode)
        width: parent.width
        service: root.service
        strings: root.strings
        textColor: root.foreground
        panelFontFamily: root.fontFamily
        setupMode: root.setupMode
        onInstallRequested: {
          root.service.installComponents()
        }
        onAddRequested: root.showPage("addsub")
      }

      // ---- the plugin was updated under the running shell: restart it -------
      Item {
        id: restartRow
        visible: root.page === "main" && root.service.restartNeeded
        width: parent.width
        implicitHeight: Math.max(restartText.implicitHeight, restartButton.implicitHeight)

        Text {
          id: restartText
          anchors.left: parent.left
          anchors.right: restartButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.strings.t("shell.restartNeeded").arg(root.service.diskVersion)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          id: restartButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.strings.t("shell.restart")
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          verticalPadding: Style.space(3)
          horizontalPadding: Style.space(8)
          onClicked: root.service.restartShell()
        }
      }

      // ---- the package is older than the panel: one line and the installer --
      Item {
        id: outdatedRow
        visible: root.page === "main" && !root.setupMode && root.service.componentsOutdated && !root.service.restartNeeded
        width: parent.width
        implicitHeight: Math.max(outdatedText.implicitHeight, outdatedButton.implicitHeight)

        Text {
          id: outdatedText
          anchors.left: parent.left
          anchors.right: outdatedButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.strings.t("setup.outdated").arg(root.status !== null ? root.status.setup.version : "")
            .arg(root.service.pluginVersion)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          id: outdatedButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          // `…`: the installer says what it changes and asks first.
          text: root.strings.t("setup.update")
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          verticalPadding: Style.space(3)
          horizontalPadding: Style.space(8)
          onClicked: {
            root.service.installComponents()
          }
        }
      }

      Item {
        id: speedRow
        visible: root.page === "main" && root.tunnelScreen
        width: parent.width
        implicitHeight: Math.max(speedLeft.implicitHeight, speedRight.implicitHeight)

        readonly property var rate: Model.totals(root.status ? root.status.rate : null)
        readonly property var today: Model.totals(root.status ? root.status.today : null)

        Row {
          id: speedLeft
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "download"
            iconSize: Style.font.bodySmall
            color: Color.accent
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.strings.t("speed.rate").arg(root.bytes(speedRow.rate.down))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Item { width: Style.space(6); height: 1 }
          // Both directions in the accent: red is for trouble only.
          ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "upload"
            iconSize: Style.font.bodySmall
            color: Color.accent
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.strings.t("speed.rate").arg(root.bytes(speedRow.rate.up))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          id: speedRight
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.strings.t("speed.today")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "download"
            iconSize: Style.font.caption
            color: root.dim
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.bytes(speedRow.today.down)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "upload"
            iconSize: Style.font.caption
            color: root.dim
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.bytes(speedRow.today.up)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- one line of protection; problems and core errors only if any --
      Column {
        id: guard
        visible: root.page === "main" && root.tunnelScreen
        width: parent.width
        spacing: Style.space(4)

        readonly property var protection: root.status ? root.status.protection : null
        readonly property bool known: protection !== null && protection.known
        readonly property bool ok: known && protection.ok
        readonly property var errors: root.status ? root.status.errors.slice(-3) : []

        Row {
          spacing: Style.space(6)

          ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "shield"
            iconSize: Style.font.bodySmall
            color: guard.ok || !guard.known ? root.dim : root.urgent
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: !guard.known ? root.strings.t("guard.unknown")
              : (guard.ok ? root.strings.t("guard.ok") : root.strings.t("guard.bad"))
            color: guard.ok || !guard.known ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: guard.known && !guard.ok
          }
        }

        // What is wrong, one line per CLI code, in the language on screen.
        Repeater {
          model: guard.known && !guard.ok ? guard.protection.codes : []

          delegate: Text {
            required property var modelData
            x: Style.font.bodySmall + Style.space(6)
            width: guard.width - x
            textFormat: Text.PlainText
            text: root.strings.t("guard.code." + modelData, root.strings.t("guard.code.other"))
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // The core's last warnings and errors (the CLI already dropped the
        // start-up lines), one line each; the whole line on hover. Absent
        // when there are none.
        Repeater {
          model: guard.errors

          delegate: Text {
            id: errorLine
            required property var modelData
            readonly property var line: Model.shortError(modelData)
            x: Style.font.bodySmall + Style.space(6)
            width: guard.width - x
            textFormat: Text.PlainText
            text: line.time !== "" ? line.time + "  " + line.message : line.message
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight

            HoverHandler { id: errorHover }

            // No wider than the card and kept inside its window: the
            // panel's window is the card, and what spills out is cut off.
            PanelToolTip {
              visible: errorHover.hovered && errorLine.truncated
              text: errorLine.modelData
              fontFamily: root.fontFamily
              width: Math.min(implicitWidth, root.width)
              margins: 0
            }
          }
        }

        // Traffic goes through the fallback node: the primary does not
        // answer. In the theme's yellow, a notice and not an alarm — the
        // tunnel still works, and it comes back by itself. Absent otherwise.
        Row {
          id: fallbackLine
          visible: root.connected && root.status.fallback.active
          spacing: Style.space(6)

          ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "fallback"
            iconSize: Style.font.bodySmall
            color: root.slowColor
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, guard.width - Style.font.bodySmall - Style.space(6))
            textFormat: Text.PlainText
            text: root.strings.t("fallback.onFallback").arg(root.status !== null && root.status.fallback.nodeName !== ""
              ? root.status.fallback.nodeName : root.status !== null ? root.status.current : "")
            color: root.slowColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        // Checked sites: one line under protection — "Sites: 2 of 2 open",
        // or which ones do not open, in the theme's yellow (a notice: the
        // tunnel itself is fine). A click unfolds one row per site in place:
        // its name and which way it went. The chevron sits in the icon column
        // on the left, as on the node list's "Unreachable: N" fold. Absent
        // with no sites, so a new user's main screen is as it was; every open
        // starts folded.
        Item {
          id: sitesLine
          visible: sitesLine.sites !== null && sitesLine.sites.items.length > 0
          width: guard.width
          implicitHeight: sitesText.implicitHeight

          readonly property var sites: root.status ? root.status.sites : null
          readonly property var summary: Model.siteSummary(sites)
          readonly property bool trouble: summary.failed.length > 0
          readonly property color tone: trouble ? root.slowColor : root.dim

          // The same column and size as the shield above.
          Item {
            id: sitesChevron
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.bodySmall
            height: Style.font.bodySmall

            ActionIcon {
              anchors.centerIn: parent
              name: root.sitesExpanded ? "chevron-up" : "chevron-down"
              iconSize: Style.font.caption
              color: sitesLine.tone
            }
          }
          Text {
            id: sitesText
            anchors.left: sitesChevron.right
            anchors.leftMargin: Style.space(6)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: sitesLine.trouble ? root.strings.t("sites.notOpening").arg(sitesLine.summary.failed.join(", "))
              : (sitesLine.summary.unchecked === sitesLine.summary.total ? root.strings.t("sites.checking")
              : root.strings.t("sites.summary").arg(Commons.I18n.formatNumber(sitesLine.summary.ok))
                  .arg(Commons.I18n.formatNumber(sitesLine.summary.total)))
            color: sitesLine.tone
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sitesExpanded = !root.sitesExpanded
          }
        }

        Repeater {
          model: root.sitesExpanded && sitesLine.visible ? sitesLine.sites.items : []

          delegate: Item {
            id: siteRow
            required property var modelData
            readonly property bool opens: modelData.result !== null && modelData.result.ok
            x: Style.font.bodySmall + Style.space(6)
            width: guard.width - x
            implicitHeight: Math.max(siteName.implicitHeight, siteWay.implicitHeight)

            Text {
              id: siteName
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.4)
              textFormat: Text.PlainText
              text: siteRow.modelData.name
              color: siteRow.opens ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              id: siteWay
              anchors.left: siteName.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: root.service.siteDetail(siteRow.modelData.result)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      PanelSeparator {
        visible: root.page === "main" && root.tunnelScreen
        foreground: root.foreground
      }

      NodeList {
        id: nodeList
        visible: root.page === "main" && root.tunnelScreen
        width: parent.width
        service: root.service
        strings: root.strings
        textColor: root.foreground
        panelFontFamily: root.fontFamily
        fastColor: root.fastColor
        slowColor: root.slowColor
        cursorKey: root.cursorKey
        onRowHovered: function(key) { root.cursorKey = key }
        onLeaveFilter: {
          root.forceActiveFocus()
          if (root.cursorKey === "") root.cursorKey = nodeList.keys.length > 0 ? nodeList.keys[0] : "auto"
        }
      }

      Loader {
        id: subsLoader
        active: root.page === "subs"
        visible: active
        width: parent.width
        sourceComponent: SubsPage {
          width: column.width
          service: root.service
          strings: root.strings
          textColor: root.foreground
          panelFontFamily: root.fontFamily
          cursorIndex: root.subCursor
          onRowHovered: function(index) { root.subCursor = index }
          onUseRequested: function(name) { root.askUse(name) }
          onAddRequested: root.showPage("addsub")
        }
      }

      Loader {
        id: sitesLoader
        active: root.page === "sites"
        visible: active
        width: parent.width
        sourceComponent: SitesPage {
          width: column.width
          service: root.service
          strings: root.strings
          textColor: root.foreground
          panelFontFamily: root.fontFamily
          menuHost: root
          onAddSiteRequested: root.showPage("addsite")
        }
      }

      Loader {
        id: settingsLoader
        active: root.page === "settings"
        visible: active
        width: parent.width
        sourceComponent: SettingsPage {
          width: column.width
          service: root.service
          strings: root.strings
          textColor: root.foreground
          panelFontFamily: root.fontFamily
          fastColor: root.fastColor
          slowColor: root.slowColor
          onRestartRequested: {
            var fb = root.status ? root.status.fallback : null
            if (!fb) return
            // Same verb as the setting stands, now with the restart allowed.
            root.service.fallbackApply = [fb.enabled ? "on" : "off"]
            root.askConfirm("fallback")
          }
          // A running core takes a preset only on restart: asked first.
          onPresetRequested: function(name, on) {
            if (root.status !== null && root.status.running) root.askConfirm("preset", on ? "on" : "off")
            else root.service.setPreset(name, on, false)
          }
        }
      }

      // Kept built (not a Loader): its fields hold what was typed while the
      // page is left for a notice and come back to.
      AddSubscriptionPage {
        id: addSubForm
        visible: root.page === "addsub"
        width: parent.width
        service: root.service
        strings: root.strings
        textColor: root.foreground
        panelFontFamily: root.fontFamily
        onCancelRequested: root.showPage(root.status !== null && root.status.subscriptions.length > 0 ? "subs" : "main")
      }

      // A new site to check; kept built for the same reason.
      AddSitePage {
        id: addSiteForm
        visible: root.page === "addsite"
        width: parent.width
        service: root.service
        strings: root.strings
        textColor: root.foreground
        panelFontFamily: root.fontFamily
        onCancelRequested: root.showPage("sites")
      }

      Loader {
        id: coreLoader
        active: root.page === "core"
        visible: active
        width: parent.width
        sourceComponent: CorePage {
          width: column.width
          service: root.service
          strings: root.strings
          textColor: root.foreground
          panelFontFamily: root.fontFamily
          onUpdateRequested: if (root.service.core !== null) root.askConfirm("core", root.service.core.latest)
        }
      }
    }
  }

  // Switching the subscription, restarting the core for the fallback and
  // updating the core each cut the connection for a moment. Asked, never
  // assumed; the dialog opens on Cancel so a double Enter does nothing.
  Item {
    id: confirmKeys
    anchors.fill: parent
    visible: root.confirmKind !== ""
    z: 10
    Keys.onPressed: function(event) {
      if (useConfirm.handleKey(event)) event.accepted = true
    }

    ConfirmDialog {
      id: useConfirm
      anchors.fill: parent
      opened: root.confirmKind !== ""
      message: root.confirmKind === "use" ? root.strings.t("subs.confirm").arg(root.confirmArg)
        : (root.confirmKind === "core" ? root.strings.t("corePage.confirm").arg(root.confirmArg)
        : (root.confirmKind === "preset" ? root.strings.t("settings.confirmPreset")
        : root.strings.t("settings.confirmRestart")))
      confirmText: root.strings.t(root.confirmKind === "use" ? "subs.confirmButton"
        : (root.confirmKind === "core" ? "corePage.confirmButton" : "settings.confirmButton"))
      cancelText: root.strings.t("subs.cancel")
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: {
        if (root.confirmKind === "fallback") root.service.cancelFallbackApply()
        root.closeConfirm()
      }
      onConfirmed: {
        var kind = root.confirmKind
        var arg = root.confirmArg
        root.closeConfirm()
        if (kind === "use") root.service.useSubscription(arg)
        else if (kind === "fallback") root.service.confirmFallbackApply()
        else if (kind === "core") root.service.updateCore()
        else if (kind === "preset") root.service.setPreset("russia", arg === "on", true)
      }
    }
  }
}
