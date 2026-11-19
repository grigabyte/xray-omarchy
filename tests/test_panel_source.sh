#!/usr/bin/env bash
set -euo pipefail

# Adapted from an earlier panel's test of the same name. Quickshell's Process, Panel
# and the qs.Ui kit exist only inside a running shell, so the decisions that
# matter are pinned here at the source level.

cd "$(dirname "$0")/.."

# `set -e` ignores a command inverted with `!`, so every negative check goes
# through this.
refute() {
  if grep "$@" >/dev/null 2>&1; then
    printf 'unexpected match: grep %s\n' "$*" >&2
    exit 1
  fi
}

QML=(Panel.qml Service.qml components/*.qml)

# ---- one backend: the xray-omarchy CLI ---------------------------------------------
# Nothing from the previous core's stack: not its API, not its CLI, not its
# core. The pattern is assembled so this file does not match itself.
old_stack="mih""oro|mih""omo|cla""sh"
# The catalogs name a CLI skip code about a subscription format, not the stack;
# the README compares the plugin with other clients by name.
refute -rniE "$old_stack" --exclude=test_panel_source.sh --exclude=README.md --exclude-dir=i18n --exclude-dir=backend --exclude-dir=.git .
# No HTTP from the panel: everything comes from the CLI's JSON.
refute -nE 'https?://|XMLHttpRequest|curl' "${QML[@]}"
# No systemd from the panel: the CLI owns the unit.
refute -nE 'systemctl' "${QML[@]}" Model.js

# ---- commands are argv arrays ----------------------------------------------
refute -nE '"(ba)?sh"|"-c"|bash -c|sh -c' "${QML[@]}"
grep -Fq 'command: [root.cli, "status", "--json", "--nodes"]' Service.qml
grep -Fq 'command: [root.cli, "status", "--json", "--nodes", "--refresh"]' Service.qml
grep -Fq 'command: [root.cli, "update", "--json"]' Service.qml
grep -Fq 'selectProcess.command = [root.cli, "select", "--json", target]' Service.qml
grep -Fq 'var result = Model.parseResult(selectOut.text)' Service.qml
# On/off run as a Process with --json: the reason is the code in its last
# line, never a line of the CLI's terminal output.
grep -Fq 'tunnelProcess.command = [root.cli, on ? "on" : "off", "--json"]' Service.qml
grep -Fq 'var result = Model.parseResult(tunnelOut.text)' Service.qml
grep -Fq 'root.say(prefix + result.code, result.code, true, result.detail)' Service.qml
refute -n 'lastLine' Service.qml Panel.qml components/*.qml Model.js
# The one detached launch is the subscription switch (it restarts the core).
# The name goes after "--": a name that starts with "-" is not an option.
grep -Fq 'Quickshell.execDetached([root.cli, "use", "--json", "--", name])' Service.qml
# The other: the installer, in Omarchy's floating terminal, its path quoted
# for the launcher's command line. The panel never asks for a password itself.
grep -Fq 'Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", quoted])' Service.qml
# And the shell restart, offered only when the plugin's files on disk are a
# newer version than the code that runs (after `omarchy plugin update`).
grep -Fq 'Quickshell.execDetached(["omarchy", "restart", "shell"])' Service.qml
grep -Fq 'if (!root.restartNeeded) return' Service.qml
[[ "$(grep -c 'execDetached' Service.qml)" -eq 3 ]]
# The installer's pre-check: the script itself with --check, argv only; exit 3
# is the refusal the panel words itself.
grep -Fq 'command: [root.installScript, "--check"]' Service.qml
grep -Fq 'root.say("install.stale_db", "", true)' Service.qml
refute -rnE 'echoMode|password: *true|"sudo"' --include='*.qml' --include='*.js' .
# The package is looked for with test(1), never by running what may not exist.
grep -Fq 'command: ["test", "-x", root.cli, "-a", "-x", root.helperPath]' Service.qml
# A new subscription: checked values, after "--" or glued to --name=.
grep -Fq 'addSubProcess.command = [root.cli, "sub", "add", "--json"].concat(insecure ? ["--allow-http"] : []).concat(["--", name, url])' Service.qml
# A plain-http link goes out only after the form's own confirmation.
grep -Fq '(insecure && allowHttp !== true)) return false' Service.qml
grep -Fq 'fetchSubProcess.command = [root.cli, "update", "--json", "--name=" + addSubProcess.name]' Service.qml
grep -Fq 'var url = Model.subscriptionUrl(urlText)' Service.qml
refute -n 'execDetached' Panel.qml components/*.qml
# The direct preset: a known name, argv only, --apply only after the panel asked.
grep -Fq 'var command = [root.cli, "preset", name, on ? "on" : "off"]' Service.qml
grep -Fq 'if (presetProcess.running || !Model.validPreset(name)) return false' Service.qml
grep -Fq 'else if (kind === "preset") root.service.setPreset("russia", arg === "on", true)' components/PanelContent.qml
# The panel's version comes from its own manifest.json, read as a file, never run.
grep -Fq 'onLoaded: root.pluginVersion = Model.manifestVersion(text())' Service.qml
grep -Fq 'Qt.resolvedUrl("manifest.json")' Service.qml
# "Update components…" opens the same installer.
[[ "$(grep -c 'root.service.installComponents()' components/PanelContent.qml)" -eq 2 ]]

# The new verbs, each with --json and its {ok, code, detail} line read.
grep -Fq 'var command = [root.cli, "fallback"].concat(args)' Service.qml
grep -Fq 'if (apply === true) command.push("--apply")' Service.qml
grep -Fq 'notifyProcess.command = [root.cli, "notify", on ? "on" : "off", "--json"]' Service.qml
grep -Fq 'ruleProcess.command = [root.cli, "rule"].concat(verb).concat(["--json", "--", host])' Service.qml
grep -Fq 'command: [root.cli, "core", "status", "--json"]' Service.qml
grep -Fq 'command: [root.cli, "core", "update", "--json"]' Service.qml
# Never the forms that skip a step: no --dry-run games, no --force, no
# fallback --apply without the confirmation that sets fallbackApply.
refute -nE '"--force"|"--dry-run"' Service.qml Panel.qml components/*.qml
[[ "$(grep -c 'root.runFallback(args, true)' Service.qml)" -eq 1 ]]
grep -Fq 'root.fallbackApply = fallbackProcess.args' Service.qml
# The fallback verbs take a checked node id or nothing.
grep -Fq 'if (args.length !== 2 || !Model.validNodeId(args[1])) return false' Service.qml
# A rule host is one the CLI reported and a host by the CLI's own rules.
grep -Fq 'if (ruleProcess.running || Model.ruleHost(host) !== host || !Model.knownHost(root.status, host)) return false' Service.qml
grep -Fq 'var HOST_RE = /^(?=.{3,253}$)' Model.js
# `core status` only while the core page is shown or an update runs.
grep -Fq 'value: root.page === "core" && root.panelOpen' components/PanelContent.qml
refute -n 'pollCore' Panel.qml components/*.qml

# Only checked values reach argv: a 10-hex node id, a subscription name the CLI
# reported.
grep -Fq 'var NODE_ID_RE = /^[0-9a-f]{10}$/' Model.js
grep -Fq 'if (target !== "auto" && !Model.validNodeId(target)) return false' Service.qml
grep -Fq 'Model.validSubscriptionName(name, root.status.subscriptions)' Service.qml

# ---- polling -----------------------------------------------------------------
# One poll, with the node table, open (3 s) and closed (15 s): the panel opens
# on cached data instead of an empty card that fills in.
grep -Fq 'readonly property int statusInterval: panelOpen ? 3000 : 15000' Service.qml
refute -n 'nodesProcess\|pollNodes' Service.qml Panel.qml components/*.qml
# Opening does not fire a poll at once: fresh numbers come after the card lands.
grep -Fq 'onPanelOpenChanged: if (panelOpen) openRefresh.restart()' Service.qml
grep -Fq 'interval: 400' <<<"$(sed -n '/id: openRefresh/,/^  }/p' Service.qml)"
# A node change the panel did not make re-checks the exit address (the CLI
# caches it); a switch made here does not: `xray-omarchy select` re-checks it itself,
# and the panel polls once, at once, after it.
grep -Fq '&& next.currentId !== root._lastNode) {' Service.qml
select_exit="$(sed -n '/id: selectProcess/,/^  }/p' Service.qml)"
grep -Fq 'root.pollFresh()' <<<"$select_exit"
grep -Fq 'root.checkingSwitch = true' <<<"$select_exit"
refute -F 'refreshExit' <<<"$select_exit"
# While a switch runs or its answer is pending the header shows no exit.
grep -Fq 'readonly property bool exitStale: service.pendingSelect !== "" || service.checkingSwitch || service.refreshingExit' components/PanelContent.qml
# A poll never starts over one still running, and the watchdog outlasts the
# CLI's 8 s exit check.
grep -Fq 'if (statusProcess.running || exitProcess.running) return' Service.qml
grep -Fq 'interval: 20000' <<<"$(sed -n '/id: statusWatchdog/,/^  }/p' Service.qml)"
# Lists are bounded in the panel as well as in the CLI.
grep -Fq 'var MAX_RECENT = 60' Model.js
grep -Fq 'var MAX_ERRORS = 15' Model.js

# ---- shape -------------------------------------------------------------------
# Lazy content like the shell's own panels; second pages only while shown.
grep -Fq 'content: PanelContent {' Panel.qml
grep -Fq 'active: root.page === "subs"' components/PanelContent.qml
grep -Fq 'active: root.page === "sites"' components/PanelContent.qml
grep -Fq 'active: root.page === "settings"' components/PanelContent.qml
grep -Fq 'active: root.page === "core"' components/PanelContent.qml
# The fallback is quiet: on the main screen only while traffic goes through it.
grep -Fq 'visible: root.connected && root.status.fallback.active' components/PanelContent.qml
# The fallback picker is a bounded ListView too (a subscription holds 562 nodes).
grep -Fq 'ListView {' components/SettingsPage.qml
refute -n 'Repeater' components/SettingsPage.qml
# The row menu is one per page, never inside a delegate.
[[ "$(grep -c 'RowMenu {' components/SitesPage.qml)" -eq 1 ]]
grep -Fq 'parent: root.menuHost' components/SitesPage.qml
refute -nE 'tab\.|TabBar|Repeater \{[^}]*tab' Panel.qml components/PanelContent.qml
# Nodes: a virtualised list with a bounded viewport, never a Repeater; search
# past ten nodes; the order frozen and the cursor a key.
grep -Fq 'readonly property bool searchable: service.nodes.length > 10' components/NodeList.qml
grep -Fq 'readonly property int maxRows: 7' components/NodeList.qml
grep -Fq 'reuseItems: true' components/NodeList.qml
refute -n 'Repeater' components/NodeList.qml
grep -Fq 'Model.reconcileOrder(root.order' components/NodeList.qml
grep -Fq 'cursorKey = Model.moveKey(nodeList.keys, cursorKey, dy)' components/PanelContent.qml
# Sites: a ListView too.
grep -Fq 'ListView {' components/SitesPage.qml
# No test fixture or fake CLI ever ships.
refute -rniE 'fixture|fake-xray-omarchy|harness' --include='*.qml' --include='*.js' .

# ---- the tunnel is never cut by accident -----------------------------------
# On/off only from the header switch; subscription switch only through the
# confirmation, which opens on Cancel.
[[ "$(grep -c 'service.setTunnel(' components/PanelContent.qml)" -eq 1 ]]
# engaged: running, or being started again by systemd after a failed `net up`:
# the switch then reads on, and can turn the tunnel off.
grep -Fq 'onToggled: root.service.setTunnel(!root.service.engaged)' components/PanelContent.qml
refute -n 'setTunnel' Panel.qml components/NodeList.qml components/SubsPage.qml components/SitesPage.qml components/MoreMenu.qml
[[ "$(grep -c 'service.useSubscription(' components/PanelContent.qml)" -eq 1 ]]
refute -n 'useSubscription' Panel.qml components/SubsPage.qml components/MoreMenu.qml
grep -Fq 'useConfirm.selectedIndex = 0' components/PanelContent.qml
# The core update and the restart for the fallback: only from the
# confirmation, which opens on Cancel too.
[[ "$(grep -c 'service.updateCore()' components/PanelContent.qml)" -eq 1 ]]
[[ "$(grep -c 'service.confirmFallbackApply()' components/PanelContent.qml)" -eq 1 ]]
refute -n 'updateCore\|confirmFallbackApply' Panel.qml components/CorePage.qml components/SettingsPage.qml components/MoreMenu.qml components/SitesPage.qml
ipc="$(sed -n '/IpcHandler {/,/^  }/p' Panel.qml)"
grep -Fq 'function select(value: string)' <<<"$ipc"
refute -E 'setTunnel|useSubscription|updateSubscriptions|runFallback|setNotify|addRule|removeRule|updateCore|confirmFallbackApply' <<<"$ipc"
# No single-letter key reaches on/off or use.
keys="$(sed -n '/onTextKey:/,/^  }/p' components/PanelContent.qml)"
grep -Fq 'service.refresh()' <<<"$keys"
refute -E 'setTunnel|useSubscription|askUse|askConfirm|runFallback|setNotify|addRule|removeRule|updateCore' <<<"$keys"
# The bar icon has one mouse action: open the panel.
grep -Fq 'if (buttonCode === Qt.LeftButton) root.toggle()' Panel.qml

# ---- untrusted text --------------------------------------------------------
# Every Text this plugin declares is PlainText: node names, hosts and log lines
# are someone else's strings.
python3 - "${QML[@]}" <<'PY'
import re, sys
bad = []
for path in sys.argv[1:]:
    src = open(path, encoding="utf8").read()
    for m in re.finditer(r'\bText\s*\{', src):
        # The block up to its matching brace.
        depth, i = 0, m.end() - 1
        for j in range(i, len(src)):
            if src[j] == "{": depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0: break
        if "textFormat: Text.PlainText" not in src[i:j]:
            bad.append("%s:%d" % (path, src.count("\n", 0, m.start()) + 1))
if bad:
    sys.exit("Text without PlainText: " + ", ".join(bad))
PY
refute -nE 'Text\.(AutoText|RichText|StyledText|MarkdownText)' "${QML[@]}"

# ---- colour ----------------------------------------------------------------
# Theme colours only. ThemeColors.js reads hex out of the theme file and is the
# one place a hex pattern may appear.
refute -nE '#[0-9a-fA-F]{3,8}\b' "${QML[@]}" Model.js
refute -nE '"(red|green|blue|white|black|gray|grey|yellow|orange|purple|cyan|magenta)"' "${QML[@]}"
refute -nE 'Qt\.rgba\([0-9.]+, *[0-9.]+, *[0-9.]+' "${QML[@]}"
grep -Fq 'fastColor: systemTheme.green' Panel.qml
# Upload and download in the accent; urgent is for trouble only.
speed="$(sed -n '/id: speedRow/,/id: guard/p' components/PanelContent.qml)"
refute -F 'Color.urgent' <<<"$speed"
refute -F 'root.urgent' <<<"$speed"
# The delay's unit is not shouted: the header keeps it out of the caps.
grep -Fq 'var head = root.meta.toUpperCase()' components/XrayHero.qml
grep -Fq 'metaTail: root.heroTail' components/PanelContent.qml
refute -n 'PanelHero {' components/PanelContent.qml
# Lists that scroll say so while they can: the bar stays on, not only in motion.
grep -Fq 'policy: list.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff' components/NodeList.qml
grep -Fq 'policy: list.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff' components/SitesPage.qml
grep -Fq 'slowColor: systemTheme.yellow' Panel.qml

# ---- translations ------------------------------------------------------------
# The shell's own Commons.Translations, nothing in between: English unless a
# language is picked under Setup > Language.
grep -Fq 'Commons.Translations {' Panel.qml
[[ ! -e components/Strings.qml ]]
refute -rn 'Strings {\|languageChosen\|russianPlural' --include='*.qml' --include='*.js' .
# No Russian in the plugin's code or its English catalog: every word on screen
# comes from a catalog, and i18n/ru.json is the one place Cyrillic may live.
# (The manifest's author and the search alias are names, not interface.)
python3 - <<'PY'
import glob, re
bad = []
files = glob.glob("*.qml") + glob.glob("*.js") + glob.glob("components/*") + ["i18n/en.json", "manifest.json"]
for path in files:
    for n, line in enumerate(open(path, encoding="utf8"), 1):
        if path == "manifest.json" and re.match(r'\s*("author": .*|"\w+",?)$', line):
            continue
        if re.search(r"[\u0400-\u04ff]", line):
            bad.append("%s:%d" % (path, n))
if bad:
    raise SystemExit("Cyrillic outside i18n/ru.json: " + ", ".join(bad))
PY
# One ellipsis character on screen, never three dots.
refute -n '\.\.\.' i18n/en.json i18n/ru.json
# Numbers through the shell's formatter, dates in its format locale; units Latin.
refute -n 'unit\.bytes\|strings\.decimal' Panel.qml components/*.qml
grep -Fq 'Model.formatBytes(n, Commons.I18n.formatNumber)' components/PanelContent.qml
grep -Fq 'Qt.locale(Commons.I18n.formatLocale)' components/SubsPage.qml
python3 - <<'PY'
import json, re, glob
ru = json.load(open("i18n/ru.json", encoding="utf8"))
en = json.load(open("i18n/en.json", encoding="utf8"))
assert set(ru) == set(en), sorted(set(ru) ^ set(en))
used = set()
for path in ["Panel.qml", "Service.qml"] + glob.glob("components/*.qml"):
    text = open(path, encoding="utf8").read()
    used |= set(re.findall(r'\btn?\("([A-Za-z_.]+)"', text))
    used |= set(re.findall(r'\bsay\("([A-Za-z_.]+)"', text))
    used |= set(re.findall(r'"(notice\.\w+)"', text))
# Keys built at run time: state.<connection>, subs.ago.<unit>, and the CLI's
# codes: on./off.<result>, guard.code.<protection>, subs.skip.<reason>.
for k in ["on", "off", "failed", "unprotected", "starting", "stopping", "unknown"]: used.add("state." + k)
for k in ["minutes", "hours", "days"]: used.add("subs.ago." + k)
for k in ["direct", "tunnel"]: used.add("rule.added." + k)
cli = {
    "on.": ["start_failed", "core_crashed", "no_tun", "foreign_tun", "not_routed", "dns_failed", "foreign_dns", "other", "exitCode"],
    # install.sh --check: exit 3 is stale_db; install.other is the family's fallback sentence.
    "install.": ["stale_db", "other"],
    "off.": ["killswitch_failed", "stop_failed", "dns_failed", "other", "exitCode"],
    "select.": ["not_found", "restarted", "restart_needed", "other"],
    # fallback.onFallback, .restarted, .restartLater are the panel's own lines.
    "fallback.": ["not_node_mode", "primary_not_node", "no_fallback_node", "fallback_not_found", "same_node",
                  "apply_failed", "restarted", "restartLater", "onFallback", "other"],
    "rule.": ["invalid_host", "not_found", "apply_failed", "removed", "added.direct", "added.tunnel", "other"],
    "core.": ["ok", "up_to_date", "download_failed", "checksum_mismatch", "config_rejected", "check_failed",
              "rolled_back", "stage_failed", "stage_busy", "no_space", "not_pinned", "lost", "timeout", "other"],
    "subadd.": ["invalid_url", "insecure_url", "invalid_name", "usage", "other"],
    "corePage.last.": ["ok", "rolled_back", "stage_failed", "stage_busy", "no_space", "lost", "other"],
    "guard.code.": ["core_stopped", "no_tun", "not_routed", "killswitch_off", "killswitch_unknown", "killswitch_tampered", "dns_bypass", "unknown", "other"],
    "subs.skip.": ["insecure_tls", "hy2_obfs", "parse_error", "unsupported_scheme", "loopback_profile", "no_group", "no_node", "clash_format"],
}
for prefix, codes in cli.items():
    for c in codes:
        used.add(prefix + c)
    extra = sorted(k for k in en if k.startswith(prefix) and k[len(prefix):] not in codes)
    assert not extra, "catalog codes the CLI does not send: %s" % extra
# Every catalog key is used somewhere: a stale catalog hides missing words.
dynamic = ("state.", "subs.ago.") + tuple(cli)
src = "".join(open(p, encoding="utf8").read() for p in ["Panel.qml", "Service.qml"] + glob.glob("components/*.qml"))
unused = sorted(k for k in ru if not k.startswith(dynamic) and '"%s"' % k not in src)
assert not unused, "unused keys: %s" % unused
used = {k for k in used if not k.endswith(".")}
missing = sorted(used - set(ru))
assert not missing, "missing keys: %s" % missing
PY

echo "test_panel_source.sh passed"
