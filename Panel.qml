import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "components"

// The bar widget and panel for the xray-omarchy tunnel (one xray core). A view over
// `xray-omarchy status --json --nodes` plus the CLI verbs it may run — see Service.qml.
//
// Built like the shell's Tailscale panel: the bar button, the service and the
// IPC live here and run with the panel closed; the card's content
// (components/PanelContent.qml) is built the first time the panel opens and
// kept after that.
Panel {
  id: root
  moduleName: "grigabyte.xray-omarchy"
  ipcTarget: "grigabyte.xray-omarchy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Null until the panel first opens.
  readonly property Item content: panel.loadedContent

  SystemTheme { id: systemTheme }

  // The plugin's own catalogs, following Setup > Language live like the
  // shell's plugins: English unless another language is picked there.
  Commons.Translations {
    id: tr
    directory: Qt.resolvedUrl("i18n")
  }

  Service {
    id: vpn
    panelOpen: root.opened
    strings: tr
  }

  readonly property string connection: vpn.connection
  readonly property bool connected: connection === "on"
  // Not protected (not routed, killswitch or DNS off) shows the warning too:
  // the bolt alone would read as protected.
  readonly property bool failed: connection === "failed" || connection === "unprotected" || vpn.pollError !== ""

  readonly property string barTooltip: {
    var parts = [tr.t("title"), vpn.pollError !== "" ? tr.t("state.noAnswer") : tr.t("state." + connection)]
    if (connected && vpn.status.exit.country !== "") parts.push(vpn.status.exit.country)
    if (connected && vpn.status.current !== "") parts.push(vpn.status.current)
    // Traffic goes through the fallback node: the primary does not answer.
    if (connected && vpn.status.fallback.active) parts.push(tr.t("bar.onFallback"))
    return parts.join(" · ")
  }

  // No IPC verb for on, off or switching the subscription: those cut the
  // tunnel, and a stray script call must not be able to.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(); return "ok" }
    // main, subs, sites, settings or core; "menu" opens the menu. Builds the
    // content if the panel never opened. Only shows things: nothing here
    // changes the fallback, the notifications, a rule or the core.
    function showPage(value: string): string {
      var content = panel.ensureContent()
      if (!content) return "not built"
      return content.showPage(String(value || "")) ? "ok" : "expected main, subs, sites, settings, core, addsub or menu"
    }
    // Types into the node search (shown past ten nodes).
    function filter(value: string): string {
      var content = panel.ensureContent()
      if (!content) return "not built"
      return content.setFilter(String(value || "")) ? "ok" : "no search: ten nodes or fewer"
    }
    // Same path as a click on a node row.
    function select(value: string): string {
      var id = String(value || "")
      if (id !== "auto" && !Model.validNodeId(id)) return "expected auto or a 10-hex node id"
      return vpn.selectNode(id) ? "ok" : "not running"
    }
    function status(): string {
      var s = vpn.status
      var c = root.content
      return JSON.stringify({
        state: root.connection,
        mode: s ? s.mode : "",
        selected: s ? s.selected : "",
        current: s ? s.current : "",
        country: s ? s.exit.country : "",
        nodes: vpn.nodes.length,
        // The code that runs and the manifest on disk (a restart is offered when they differ).
        version: Model.PANEL_VERSION,
        diskVersion: vpn.diskVersion,
        restartNeeded: vpn.restartNeeded,
        pollError: vpn.pollError,
        page: c ? c.page : "",
        // The list as it is on screen, for checking that it stays put.
        order: c ? c.listKeys().slice(0, 20) : [],
        height: c ? Math.round(c.implicitHeight) : 0
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.barTooltip
    // No text label: the kit sizes an icon button to one slot, and a country
    // code beside the bolt spilled into the neighbouring widget.
    readonly property color glyphColor: root.connected || root.failed
      ? root.barForeground
      : Qt.darker(root.barForeground, 1.55)

    iconComponent: Component {
      Item {
        XrayIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: button.glyphColor
          badgeColor: Color.urgent
          crossed: !root.connected && !root.failed
          warning: root.failed
          ringed: false
        }
      }
    }
    // One mouse action: open the panel. State changes live inside it.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelContent {
      anchors.fill: parent
      service: vpn
      strings: tr
      panelOpen: root.opened
      foreground: root.foreground
      urgent: root.urgent
      fontFamily: root.fontFamily
      fastColor: systemTheme.green
      slowColor: systemTheme.yellow
      onDismissRequested: root.close()
      onSwitchPanelRequested: function(direction) { root.switchPanel(direction) }
    }
  }
}
