import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

// Everything the panel knows comes from one command: `xray-omarchy status --json
// --nodes`. Nothing here talks to the core's API, reads its config or touches
// systemd — the CLI owns all of that, and the panel is a view over its answer
// plus the handful of CLI verbs it is allowed to run.
//
// Every command is an argv array. Nothing is ever passed through a shell, and
// the only values that reach argv from data are a node id that matched
// ^[0-9a-f]{10}$, a subscription name the CLI itself reported and a host the
// CLI itself reported (recent[] or rules) that matched Model.ruleHost — the
// last two after "--", so neither can be read as an option.
//
// The panel draws from this cache. It is polled with the panel closed too, so
// opening shows the last answer at once instead of an empty card that fills in
// (and changes height) a moment later.
Item {
  id: root

  property bool panelOpen: false

  // The backend: the xray-omarchy package. Without it (or without its root
  // helper, or the xray core) the panel offers to install it.
  property string cli: "/usr/bin/xray-omarchy"
  property string helperPath: "/usr/lib/xray-omarchy/xray-omarchy-helper"
  // backend/install.sh of this plugin's own folder.
  readonly property string installScript: decodeURIComponent(String(Qt.resolvedUrl("backend/install.sh")).replace(/^file:\/\//, ""))
  // The panel's own version, from its manifest.json. The installed package says
  // its version in status.setup; an older package gets "Update components…".
  property string pluginVersion: ""
  readonly property bool componentsOutdated: backendPresent === 1 && status !== null
    && Model.componentsOutdated(status.setup, pluginVersion)

  FileView {
    path: decodeURIComponent(String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, ""))
    watchChanges: false
    printErrors: false
    onLoaded: root.pluginVersion = Model.manifestVersion(text())
  }

  // The manifest as it is on disk now, read again when it changes and on each
  // open. Newer than the code that runs (Model.PANEL_VERSION): `omarchy plugin
  // update` replaced the files, but the shell keeps what it loaded until it
  // restarts. The panel then offers the restart. Read again on open
  // (openRefresh), in case the watch missed the change.
  property string diskVersion: ""
  readonly property bool restartNeeded: Model.restartNeeded(diskVersion)

  FileView {
    id: diskManifest
    path: decodeURIComponent(String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, ""))
    watchChanges: true
    printErrors: false
    onLoaded: root.diskVersion = Model.manifestVersion(text())
    onFileChanged: reload()
  }

  // Detached: `omarchy restart shell` stops this very shell and starts a new one.
  function restartShell() {
    if (!root.restartNeeded) return
    Quickshell.execDetached(["omarchy", "restart", "shell"])
  }
  // -1 not checked yet, 0 missing, 1 the CLI and the helper are there.
  property int backendPresent: -1
  readonly property bool setupNeeded: backendPresent === 0 || (backendPresent === 1 && status !== null && !status.setup.ready)
  // The plugin's catalogs (Commons.Translations), for the one notice built
  // from parts: the update summary.
  required property var strings

  // Parsed, bounded state (Model.parseStatus) or null until the first answer.
  property var status: null
  // The node table of the active subscription.
  property var nodes: []
  property bool nodesLoaded: false
  // "" while the CLI answers; otherwise why it did not.
  property string pollError: ""

  // Optimism with a deadline (see DESIGN.md). -1 none, 0 off, 1 on.
  property int wantedRunning: -1
  // A node pick in flight: an id, "auto", or "".
  property string pendingSelect: ""
  // A subscription switch in flight: its name, or "".
  property string pendingUse: ""
  property bool updating: false
  // The last `xray-omarchy update --json` answer, one entry per subscription.
  property var updateResults: []
  property bool refreshingExit: false
  // A node switch finished and the answer that shows the new node has not
  // come yet: the header says "checking…" instead of the old node's exit.
  property bool checkingSwitch: false
  // The node being switched to (an id or "auto") until that answer lands:
  // the header names it instead of the node being left.
  property string switchTarget: ""
  // The node the last answer said carries traffic. A change the panel did
  // not ask for (the balancer in Auto) re-checks the exit; the CLI caches it.
  property string _lastNode: ""
  // A poll is in flight that started before the switch finished: its answer
  // may show the old node, so it is dropped and asked again.
  property bool _repoll: false

  // The last action's outcome, for the one notice line: a catalog key, one
  // argument for it, and the core's own words (English) when there are any.
  property bool noticeIsError: false
  property string noticeKey: ""
  property string noticeArg: ""
  property string noticeDetail: ""

  // Fallback: a verb in flight, and one that came back restart_needed and
  // waits for the user to allow the restart (the panel asks).
  property bool fallbackBusy: false
  property var fallbackApply: []
  signal fallbackRestartAsked()

  // Notifications: -1 none in flight, else the state asked for.
  property int wantedNotify: -1

  // A site rule in flight: its host, or "".
  property string pendingRule: ""

  // A direct preset in flight: -1 none, else the state asked for (russia).
  property int wantedPreset: -1

  // The xray core: the last `core status` answer (Model.parseCoreStatus),
  // whether the core page is on screen, and an update the panel started.
  property var core: null
  property bool corePageShown: false
  property bool coreUpdating: false
  property real _coreUpdateStart: 0

  readonly property bool running: status !== null && status.running
  readonly property bool engaged: Model.engaged(status)
  readonly property string connection: Model.connectionState(status, wantedRunning)
  readonly property bool busy: wantedRunning !== -1 || pendingUse !== "" || selectProcess.running

  function say(key, arg, isError, detail) {
    noticeKey = key
    noticeArg = arg || ""
    noticeDetail = detail || ""
    noticeIsError = isError === true
    noticeTimer.restart()
  }

  function clearNotice() {
    noticeKey = ""
    noticeArg = ""
    noticeDetail = ""
    noticeIsError = false
  }

  // ---- polling -------------------------------------------------------------

  // 3 s with the panel open, 15 s closed. `--nodes` costs the CLI nothing
  // extra (0.13 s either way, measured), so every poll carries the node table
  // and the header's delay and the list are never missing on open.
  readonly property int statusInterval: panelOpen ? 3000 : 15000

  function pollStatus() {
    if (backendPresent !== 1) {
      checkBackend()
      return
    }
    if (statusProcess.running || exitProcess.running) return
    root._statusStarted = false
    statusProcess.running = true
    statusWatchdog.restart()
  }

  // A program that cannot start (the package was removed under a running
  // shell) gives no `exited`: only `running` falls back without `started`.
  // Without this the last answer stayed on screen ("Protected") for good.
  property bool _statusStarted: false

  function refresh() {
    pollStatus()
  }

  // A poll whose answer must postdate now: one already in flight is dropped
  // when it lands and asked again.
  function pollFresh() {
    if (statusProcess.running || exitProcess.running) root._repoll = true
    else pollStatus()
  }

  // True when the answer that just landed is stale and was re-asked.
  function takeRepoll() {
    if (!root._repoll) return false
    // The other process is still out: its answer is stale too.
    if (statusProcess.running || exitProcess.running) return true
    root._repoll = false
    root.pollStatus()
    return true
  }

  function applyStatus(text, exitCode) {
    if (exitCode !== 0) {
      root.pollError = "exit"
      // The package may have been removed: look again before the next poll.
      root.backendPresent = -1
      return false
    }
    var next = Model.parseStatus(text)
    if (next === null) {
      root.pollError = "parse"
      return false
    }
    root.pollError = ""
    root.status = next
    // The CLI caches the exit address for ten minutes. When the node carrying
    // traffic changes behind the panel's back (the balancer in Auto), the
    // cached country belongs to the previous node. A switch made here does
    // not count: `xray-omarchy select` re-checks the exit itself, and the first
    // answer after it starts the comparison afresh.
    if (root.checkingSwitch) {
      root.checkingSwitch = false
      root.switchTarget = ""
    } else if (next.running && !selectProcess.running && next.currentId !== "" && root._lastNode !== ""
               && next.currentId !== root._lastNode) {
      root.refreshExit()
    }
    root._lastNode = next.currentId
    // Released once `on`/`off` has returned: until then the DNS switch may
    // still be under way and the verdict is not the final one.
    if (root.wantedRunning !== -1 && !tunnelProcess.running && next.running === (root.wantedRunning === 1))
      root.wantedRunning = -1
    // The switch follows the asked state until an answer after it lands.
    if (!notifyProcess.running) root.wantedNotify = -1
    if (root.pendingUse !== "") {
      for (var i = 0; i < next.subscriptions.length; i++)
        if (next.subscriptions[i].active && next.subscriptions[i].name === root.pendingUse && next.running) {
          root.pendingUse = ""
          break
        }
    }
    if (next.hasNodes) {
      root.nodes = next.nodes
      root.nodesLoaded = true
    }
    return true
  }

  Timer {
    id: statusTimer
    interval: root.statusInterval
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.pollStatus()
  }

  // While a switch is in flight the regular cadence is too slow to release the
  // optimistic state promptly.
  Timer {
    interval: 1000
    repeat: true
    running: root.wantedRunning !== -1 || root.pendingUse !== ""
    onTriggered: root.pollStatus()
  }

  // Opening shows the cache; fresh numbers follow once the card has landed
  // (the open animation is 180 ms), so the answer never lands mid-animation.
  Timer {
    id: openRefresh
    interval: 400
    onTriggered: {
      root.pollStatus()
      diskManifest.reload()
    }
  }

  onPanelOpenChanged: if (panelOpen) openRefresh.restart()

  // The exit-address check inside `status` can take 8 s on its own, so the
  // watchdog sits well above that. It reaps polls only, never an action.
  Timer {
    id: statusWatchdog
    interval: 20000
    onTriggered: if (statusProcess.running) statusProcess.running = false
  }

  Process {
    id: statusProcess
    running: false
    command: [root.cli, "status", "--json", "--nodes"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onStarted: root._statusStarted = true
    onRunningChanged: {
      if (running || root._statusStarted) return
      statusWatchdog.stop()
      root.applyStatus("", -1)
    }
    onExited: function(exitCode) {
      statusWatchdog.stop()
      if (root.takeRepoll()) return
      root.applyStatus(statusOut.text, exitCode)
    }
  }

  // Is the package there? `test` rather than running the CLI: a missing
  // program would not even start.
  function checkBackend() {
    if (presenceProcess.running) return
    presenceProcess.running = true
  }

  Process {
    id: presenceProcess
    running: false
    command: ["test", "-x", root.cli, "-a", "-x", root.helperPath]
    onExited: function(exitCode) {
      var present = exitCode === 0 ? 1 : 0
      root.backendPresent = present
      if (present === 1) {
        root.clearInstallNotice()
        root.pollStatus()
      } else {
        // Removed: back to the first-run state, not the last answer.
        root.status = null
        root.nodes = []
        root.nodesLoaded = false
        root.pollError = ""
        root.wantedRunning = -1
      }
    }
  }

  // Opens Omarchy's floating terminal on backend/install.sh: it says what it
  // installs, asks, and takes the password for pacman there. The launcher
  // runs its argument as a command line, so the path is single-quoted.
  // First `install.sh --check` (no sudo, no changes): exit 3 means pacman's
  // databases are older than what it has to install (a fresh system before
  // its first `omarchy update`). Then the panel says so and opens nothing;
  // any other failure of the check still opens the installer, which explains.
  signal installLaunched()

  function installComponents() {
    if (installCheckProcess.running) return
    root._installCheckStarted = false
    installCheckProcess.running = true
  }

  // A check that cannot start at all gives no `exited` (see _statusStarted):
  // the installer opens anyway.
  property bool _installCheckStarted: false

  // The installer's refusal is about the last press only: gone once the
  // check passes or the package is there.
  function clearInstallNotice() {
    if (root.noticeKey.indexOf("install.") === 0) root.clearNotice()
  }

  function launchInstaller() {
    root.clearInstallNotice()
    var quoted = "'" + root.installScript.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", quoted])
    root.installLaunched()
  }

  Process {
    id: installCheckProcess
    running: false
    command: [root.installScript, "--check"]
    onStarted: root._installCheckStarted = true
    onRunningChanged: if (!running && !root._installCheckStarted) root.launchInstaller()
    onExited: function(exitCode) {
      if (exitCode === 3) {
        root.say("install.stale_db", "", true)
        return
      }
      root.launchInstaller()
    }
  }

  // ---- a new subscription from the panel's form ----------------------------

  // `xray-omarchy sub add --json -- NAME URL`, then `update --json --name=NAME`.
  // Both values were checked by Model.subscriptionUrl / subscriptionName and go
  // after "--" (or glued to --name=), never as options.
  property bool addingSub: false
  signal subscriptionAdded(string name)

  // allowHttp: the form's separate confirmation for a plain-http link; without
  // it such a link is not even sent.
  function addSubscription(nameText, urlText, allowHttp) {
    var url = Model.subscriptionUrl(urlText)
    var name = Model.subscriptionName(nameText, url)
    var insecure = Model.insecureUrl(url)
    if (root.addingSub || url === "" || name === "" || (insecure && allowHttp !== true)) return false
    root.addingSub = true
    addSubProcess.name = name
    addSubProcess.command = [root.cli, "sub", "add", "--json"].concat(insecure ? ["--allow-http"] : []).concat(["--", name, url])
    addSubProcess.running = true
    return true
  }

  Process {
    id: addSubProcess
    property string name: ""
    running: false
    command: []
    stdout: StdioCollector { id: addSubOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(addSubOut.text)
      if (result === null || !result.ok) {
        root.addingSub = false
        root.say(result !== null && result.code !== "" ? "subadd." + result.code : "subadd.other", addSubProcess.name, true)
        return
      }
      fetchSubProcess.name = addSubProcess.name
      fetchSubProcess.command = [root.cli, "update", "--json", "--name=" + addSubProcess.name]
      fetchSubProcess.running = true
    }
  }

  Process {
    id: fetchSubProcess
    property string name: ""
    running: false
    command: []
    stdout: StdioCollector { id: fetchSubOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.addingSub = false
      var results = Model.parseUpdate(fetchSubOut.text) || []
      root.updateResults = results
      var entry = null
      for (var i = 0; i < results.length; i++) if (results[i].name === fetchSubProcess.name) entry = results[i]
      if (entry !== null && entry.ok)
        root.say("notice.subAdded", fetchSubProcess.name, false)
      else
        root.say("notice.subNotFetched", fetchSubProcess.name, true, entry !== null ? entry.error : "")
      root.subscriptionAdded(fetchSubProcess.name)
      root.pollFresh()
    }
  }

  // Re-checks the exit address (up to 8 s) after a node change the panel did
  // not make. Its own process: a poll that is already running must not be
  // mistaken for it.
  Process {
    id: exitProcess
    running: false
    command: [root.cli, "status", "--json", "--nodes", "--refresh"]
    stdout: StdioCollector { id: exitOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshingExit = false
      if (root.takeRepoll()) return
      if (!root.applyStatus(exitOut.text, exitCode)) root.say("notice.exitFailed", "", true)
    }
  }

  function refreshExit() {
    if (exitProcess.running) return
    root.refreshingExit = true
    exitProcess.running = true
  }

  // ---- actions -------------------------------------------------------------

  // The whole tunnel, not just the core: `xray-omarchy off` lifts the killswitch and
  // gives DNS back to the router before stopping the core, `xray-omarchy on` does the
  // reverse. With --json the last line of its output is {ok, code, detail}:
  // a refusal shows as a sentence for its code plus the core's journal line,
  // instead of a knob that silently springs back. The lines before it are
  // the CLI's text for a terminal and are ignored.
  property bool _tunnelOn: false

  function setTunnel(on) {
    if (root.wantedRunning !== -1 || tunnelProcess.running) return
    root.wantedRunning = on ? 1 : 0
    root._tunnelOn = on
    tunnelDeadline.restart()
    tunnelProcess.command = [root.cli, on ? "on" : "off", "--json"]
    tunnelProcess.running = true
  }

  Process {
    id: tunnelProcess
    running: false
    command: []
    stdout: StdioCollector { id: tunnelOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(tunnelOut.text)
      if (exitCode !== 0 || (result !== null && !result.ok)) {
        var prefix = root._tunnelOn ? "on." : "off."
        root.wantedRunning = -1
        tunnelDeadline.stop()
        if (result !== null && result.code !== "")
          root.say(prefix + result.code, result.code, true, result.detail)
        else
          root.say(prefix + "exitCode", String(exitCode), true, result !== null ? result.detail : "")
      }
      root.pollStatus()
    }
  }

  Timer {
    id: tunnelDeadline
    interval: 60000
    onTriggered: {
      if (root.wantedRunning === -1) return
      root.say(root.wantedRunning === 1 ? "notice.tunnelOnTimeout" : "notice.tunnelOffTimeout", "", true)
      root.wantedRunning = -1
    }
  }

  // Switches on the fly through the core's API; no restart. A pick made while
  // one is in flight replaces the queued one (latest wins), never dropped.
  property string _queuedSelect: ""

  function selectNode(id) {
    var target = String(id || "")
    if (target !== "auto" && !Model.validNodeId(target)) return false
    if (!root.running) return false
    if (selectProcess.running) {
      root._queuedSelect = target
      root.pendingSelect = target
      root.switchTarget = target
      return true
    }
    root.pendingSelect = target
    root.switchTarget = target
    selectProcess.command = [root.cli, "select", "--json", target]
    selectProcess.running = true
    selectDeadline.restart()
    return true
  }

  Timer {
    id: selectDeadline
    interval: 20000
    onTriggered: root.pendingSelect = ""
  }

  // The poll after a switch is reaped by the watchdog at 20 s at worst.
  Timer {
    id: checkDeadline
    interval: 25000
    onTriggered: {
      root.checkingSwitch = false
      root.switchTarget = ""
    }
  }

  Process {
    id: selectProcess
    running: false
    command: []
    stdout: StdioCollector { id: selectOut; waitForEnd: true }
    onExited: function(exitCode) {
      var queued = root._queuedSelect
      root._queuedSelect = ""
      // The last line is {ok, code, detail}. "restarted": the live rules were
      // refused and the core restarted; "restart_needed": the fallback starts
      // working after a restart. Neither is a failure.
      var result = Model.parseResult(selectOut.text)
      if (result !== null && !result.ok)
        root.say("select." + (result.code !== "" ? result.code : "other"), "", true)
      else if (exitCode !== 0)
        root.say("notice.selectFailed", String(exitCode), true)
      else if (result !== null && (result.code === "restarted" || result.code === "restart_needed"))
        root.say("select." + result.code, "", false)
      if (queued !== "") {
        root.pendingSelect = ""
        root.selectNode(queued)
        return
      }
      selectDeadline.stop()
      // `xray-omarchy select` re-checks the exit address before it returns, so the
      // next answer already has the new node's country. Until it lands the
      // header says "checking…", never the previous node's numbers.
      root.checkingSwitch = true
      if (exitCode !== 0) root.switchTarget = ""
      root.pendingSelect = ""
      checkDeadline.restart()
      root.pollFresh()
    }
  }

  // Rebuilds the config and restarts the core: the tunnel drops for a second
  // or two. The panel asks for confirmation before calling this. Detached: the
  // restart outlives the panel, and a plugin reload in the middle of it must
  // not kill a half-finished switch.
  function useSubscription(name) {
    if (!root.status || !Model.validSubscriptionName(name, root.status.subscriptions)) return false
    if (root.pendingUse !== "") return false
    root.pendingUse = name
    useDeadline.restart()
    root.nodes = []
    root.nodesLoaded = false
    // Detached, so its {ok, code} line is not read: the name is one the CLI
    // reported and the button is off for a subscription without nodes, the
    // two refusals `use` has. The deadline below catches anything else.
    Quickshell.execDetached([root.cli, "use", "--json", "--", name])
    return true
  }

  Timer {
    id: useDeadline
    interval: 45000
    onTriggered: {
      if (root.pendingUse === "") return
      root.say("notice.useTimeout", root.pendingUse, true)
      root.pendingUse = ""
      root.refresh()
    }
  }

  // Fetches every subscription. Without --apply: a changed active
  // subscription is picked up on the next switch, never by restarting the
  // core behind the user's back. The answer is one entry per subscription;
  // the CLI exits non-zero when any of them failed, and so does the notice.
  function updateSubscriptions() {
    if (updateProcess.running) return
    root.updating = true
    updateProcess.running = true
  }

  Process {
    id: updateProcess
    running: false
    command: [root.cli, "update", "--json"]
    stdout: StdioCollector { id: updateOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.updating = false
      var results = Model.parseUpdate(updateOut.text)
      if (results === null) {
        // Not the JSON array: the CLI printed a sentence (no
        // subscriptions at all, say). Only the exit code is shown.
        root.updateResults = []
        root.say("notice.updateFailed", String(exitCode), true)
      } else {
        root.updateResults = results
        var failed = Model.updateFailures(results)
        if (failed.length > 0) {
          var reasons = failed.map(function(r) { return r.error !== "" ? r.name + " — " + r.error : r.name })
          root.say("notice.updatePartial", Model.clip(reasons.join("; "), 300), true)
        } else if (exitCode !== 0) {
          root.say("notice.updateFailed", String(exitCode), true)
        } else {
          root.say("notice.updateDone", results.map(function(r) {
            return root.strings.t("notice.updateEntry").arg(r.name)
              .arg(root.strings.tn("subs.nodes", r.count).arg(Commons.I18n.formatNumber(r.count)))
          }).join(", "), false)
        }
      }
      root.pollStatus()
    }
  }

  // ---- fallback node ---------------------------------------------------------

  // `xray-omarchy fallback set ID | on | off [--apply] --json`. Setting the node with
  // the fallback off only saves it. Any of them may answer restart_needed:
  // the node probing changes only on a core restart, so the panel asks and
  // runs the same verb again with --apply.
  function runFallback(args, apply) {
    if (root.fallbackBusy || !root.status) return false
    var verb = args[0]
    if (verb === "set") {
      if (args.length !== 2 || !Model.validNodeId(args[1])) return false
    } else if (!(args.length === 1 && (verb === "on" || verb === "off"))) {
      return false
    }
    var command = [root.cli, "fallback"].concat(args)
    if (apply === true) command.push("--apply")
    command.push("--json")
    root.fallbackBusy = true
    root.fallbackApply = []
    fallbackProcess.args = args
    fallbackProcess.command = command
    fallbackProcess.running = true
    return true
  }

  function confirmFallbackApply() {
    var args = root.fallbackApply
    root.fallbackApply = []
    if (args.length > 0) root.runFallback(args, true)
  }

  function cancelFallbackApply() {
    if (root.fallbackApply.length === 0) return
    root.fallbackApply = []
    root.say("fallback.restartLater", "", false)
  }

  Process {
    id: fallbackProcess
    property var args: []
    running: false
    command: []
    stdout: StdioCollector { id: fallbackOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.fallbackBusy = false
      var result = Model.parseResult(fallbackOut.text)
      if (result === null) {
        root.say("notice.fallbackFailed", String(exitCode), true)
      } else if (!result.ok) {
        root.say("fallback." + (result.code !== "" ? result.code : "other"), "", true)
      } else if (result.code === "restart_needed") {
        root.fallbackApply = fallbackProcess.args
        root.fallbackRestartAsked()
      } else if (result.code === "restarted") {
        root.say("fallback.restarted", "", false)
      }
      root.pollFresh()
    }
  }

  // ---- notifications ---------------------------------------------------------

  // `xray-omarchy notify on|off --json`: the watcher (xray-omarchy-watch) reads the setting.
  function setNotify(on) {
    if (notifyProcess.running) return
    root.wantedNotify = on ? 1 : 0
    notifyProcess.command = [root.cli, "notify", on ? "on" : "off", "--json"]
    notifyProcess.running = true
  }

  Process {
    id: notifyProcess
    running: false
    command: []
    stdout: StdioCollector { id: notifyOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(notifyOut.text)
      if (result === null || !result.ok) {
        root.wantedNotify = -1
        root.say("notice.notifyFailed", String(exitCode), true)
      }
      root.pollFresh()
    }
  }

  // ---- site rules --------------------------------------------------------------

  // `xray-omarchy rule add direct|tunnel --json -- HOST`, `xray-omarchy rule rm --json -- HOST`.
  // The host must be one the CLI reported and a host by Model.ruleHost.
  function addRule(side, host) {
    if (Model.ruleSide(side) === "") return false
    return runRule(["add", side], host)
  }

  function removeRule(host) {
    if (Model.ruleFor(root.status ? root.status.rules : null, host) === "") return false
    return runRule(["rm"], host)
  }

  function runRule(verb, host) {
    if (ruleProcess.running || Model.ruleHost(host) !== host || !Model.knownHost(root.status, host)) return false
    root.pendingRule = host
    ruleProcess.verb = verb
    ruleProcess.command = [root.cli, "rule"].concat(verb).concat(["--json", "--", host])
    ruleProcess.running = true
    return true
  }

  Process {
    id: ruleProcess
    property var verb: []
    running: false
    command: []
    stdout: StdioCollector { id: ruleOut; waitForEnd: true }
    onExited: function(exitCode) {
      var host = root.pendingRule
      root.pendingRule = ""
      var result = Model.parseResult(ruleOut.text)
      if (result === null) root.say("notice.ruleFailed", String(exitCode), true)
      else if (!result.ok) root.say("rule." + (result.code !== "" ? result.code : "other"), host, true)
      else if (ruleProcess.verb[0] === "rm") root.say("rule.removed", host, false)
      else root.say("rule.added." + ruleProcess.verb[1], host, false)
      root.pollFresh()
    }
  }

  // ---- direct presets -------------------------------------------------------------

  // `xray-omarchy preset russia on|off [--apply] --json`. The core resolves and
  // routes by these lists, so a running core picks the change up on restart:
  // the panel asks first and passes --apply (PanelContent's confirmation).
  function setPreset(name, on, apply) {
    if (presetProcess.running || !Model.validPreset(name)) return false
    root.wantedPreset = on ? 1 : 0
    var command = [root.cli, "preset", name, on ? "on" : "off"]
    if (apply === true) command.push("--apply")
    command.push("--json")
    presetProcess.command = command
    presetProcess.running = true
    return true
  }

  Process {
    id: presetProcess
    running: false
    command: []
    stdout: StdioCollector { id: presetOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(presetOut.text)
      root.wantedPreset = -1
      if (result === null || !result.ok) root.say("notice.presetFailed", String(exitCode), true)
      else if (result.code === "restart_needed") root.say("preset.restartNeeded", "", false)
      else if (result.code === "restarted") root.say("preset.restarted", "", false)
      else root.say("preset.saved", "", false)
      root.pollFresh()
    }
  }

  // ---- the xray core -------------------------------------------------------------

  // `xray-omarchy core status --json` only while the core page is shown or an update
  // runs — never in the regular poll. The release check is the CLI's, cached
  // for a day.
  function pollCore() {
    if (coreProcess.running) return
    coreProcess.running = true
  }

  onCorePageShownChanged: if (corePageShown) pollCore()

  Timer {
    interval: 2000
    repeat: true
    running: root.coreUpdating || (root.corePageShown && root.core !== null && root.core.inProgress)
    onTriggered: root.pollCore()
  }

  Process {
    id: coreProcess
    running: false
    command: [root.cli, "core", "status", "--json"]
    stdout: StdioCollector { id: coreOut; waitForEnd: true }
    onExited: function(exitCode) {
      // While the new core restarts the CLI may not answer: keep the last.
      var next = Model.parseCoreStatus(coreOut.text)
      if (next === null) return
      root.core = next
      if (!root.coreUpdating) return
      var u = next.update
      if (!u || u.state === "running" || u.started + 5 < root._coreUpdateStart) return
      root.coreUpdating = false
      coreDeadline.stop()
      if (u.state === "lost") root.say("core.lost", "", true)
      else if (u.ok && u.code === "ok") root.say("core.ok", u.to, false)
      else root.say("core." + (u.code !== "" ? u.code : "other"), u.from, true, u.detail)
      root.pollStatus()
    }
  }

  // Downloads, checks the checksum and the config, then hands the swap to a
  // detached unit (it restarts the core: the connection drops for a few
  // seconds, and a failing new core is rolled back). Only from the button on
  // the core page, after a confirmation.
  function updateCore() {
    if (root.coreUpdating || coreUpdateProcess.running) return false
    if (root.core === null || root.core.updateAvailable !== true || root.core.inProgress) return false
    root.coreUpdating = true
    root._coreUpdateStart = Date.now() / 1000
    coreDeadline.restart()
    coreUpdateProcess.running = true
    return true
  }

  Process {
    id: coreUpdateProcess
    running: false
    command: [root.cli, "core", "update", "--json"]
    stdout: StdioCollector { id: coreUpdateOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(coreUpdateOut.text)
      // started: the swap runs in its own unit; the result comes through
      // `core status`. in_progress: one is already running — follow it.
      if (result !== null && result.ok && result.code === "started") return
      if (result !== null && result.code === "in_progress") {
        root._coreUpdateStart = 0
        return
      }
      root.coreUpdating = false
      coreDeadline.stop()
      if (result === null) root.say("notice.coreFailed", String(exitCode), true)
      else if (result.ok && result.code === "up_to_date") root.say("core.up_to_date", result.detail, false)
      else root.say("core." + (result.code !== "" ? result.code : "other"), "", true, result.detail)
      root.pollCore()
    }
  }

  // The swap's own health check gives up after about a minute and a half;
  // a download may take a while before that.
  Timer {
    id: coreDeadline
    interval: 600000
    onTriggered: {
      if (!root.coreUpdating) return
      root.coreUpdating = false
      root.say("core.timeout", "", true)
    }
  }

  // Good news goes by itself; a failure stays until it is dismissed.
  Timer {
    id: noticeTimer
    interval: 12000
    onTriggered: if (!root.noticeIsError) root.clearNotice()
  }
}
