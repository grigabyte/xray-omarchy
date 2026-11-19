.pragma library

// Everything the panel decides without a compositor: reading `xray-omarchy status
// --json`, bounding it, sorting and filtering nodes, and formatting numbers.
// Plain JS so tests/test_model.js can run it under node.
//
// Every string here came out of a subscription, a log or the network. It is
// bounded before it reaches the panel, and the panel renders it as plain text.

// The version of this code, as manifest.json says it when it is current
// (tests/check_versions.py keeps them equal). After `omarchy plugin update`
// the shell may keep running the code it loaded before: the manifest on disk
// is newer than this, and the panel asks for a shell restart.
var PANEL_VERSION = "0.7.0"

var NODE_ID_RE = /^[0-9a-f]{10}$/
var COUNTRY_RE = /^[A-Z]{2}$/
var IPV4_RE = /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/
var IPV6_RE = /^[0-9A-Fa-f:]{2,39}$/
// The CLI's machine words: protection problems, skip reasons, on/off results.
// The panel turns them into sentences; anything else is never shown as is.
var CODE_RE = /^[a-z][a-z0-9_]{0,31}$/
var SCHEME_RE = /^[a-z0-9]{1,16}$/
// Words on screen come from the catalogs only; a Cyrillic line from the CLI
// (an older, Russian-speaking build) never reaches the panel.
var CYRILLIC_RE = /[\u0400-\u04ff]/

// Caps. The CLI already trims recent to 60 and errors to 15; the panel does not
// trust that, because a CLI edit should not be able to flood the shell.
var MAX_RECENT = 60
var MAX_ERRORS = 15
var MAX_SUBSCRIPTIONS = 20
var MAX_SKIPPED = 10
var MAX_PROBLEMS = 10
var MAX_NODES = 3000
var MAX_TEXT = 200
var MAX_ERROR_TEXT = 400
var MAX_RULES = 100
var MAX_SITES = 10

// A host for `xray-omarchy rule`: lowercase, a dotted domain or an IPv4 address, as
// the CLI accepts it. It reaches argv after "--" and only when it came out of
// the CLI's own answer (recent[] or rules); anything else gets no actions.
var HOST_RE = /^(?=.{3,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/
// What `xray-omarchy core status` calls a version: "26.11.9", "v1.8.24".
var VERSION_RE = /^v?[0-9][0-9A-Za-z.+-]{0,31}$/

// Below this a node is "fast" (theme green), above it "slow" (theme yellow).
var DELAY_FAST_MS = 300

function clip(value, limit) {
  if (value === null || value === undefined) return ""
  var text = String(value)
  // Control characters would break a one-line row; replace, never interpret.
  text = text.replace(/[\u0000-\u001f\u007f]+/g, " ")
  var cap = limit || MAX_TEXT
  return text.length > cap ? text.substring(0, cap - 1) + "…" : text
}

function num(value) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? n : 0
}

function validNodeId(id) {
  return typeof id === "string" && NODE_ID_RE.test(id)
}

// A subscription name goes to `xray-omarchy use` as its own argv entry, never through
// a shell. It still has to be a name the CLI itself reported.
function validSubscriptionName(name, subscriptions) {
  if (typeof name !== "string" || name === "" || name.length > MAX_TEXT) return false
  var list = subscriptions || []
  for (var i = 0; i < list.length; i++)
    if (list[i].name === name) return true
  return false
}

// A new subscription from the panel's form: an http(s) link of one line, no
// spaces or control characters, up to 2000 characters. Returns it trimmed, or
// "" when it is not one. It reaches the CLI as its own argv entry after "--".
var SUB_URL_RE = /^https?:\/\/[^\s\/?#@]+(?:[\/?#][^\s]*)?$/i
var CONTROL_RE = /[\u0000-\u001f\u007f]/

function subscriptionUrl(text) {
  var url = String(text || "").trim()
  if (url.length > 2000 || CONTROL_RE.test(url) || !SUB_URL_RE.test(url)) return ""
  return url
}

// A plain-http link: the CLI refuses it (code insecure_url) unless it is added
// with --allow-http, which the form passes only after its own confirmation.
function insecureUrl(url) {
  return /^http:\/\//i.test(String(url || "").trim())
}

// The name for a new subscription: what was typed, or the link's host when the
// field is empty. "" when neither gives a usable one (the CLI's rule: 1-40
// characters, no control characters, not starting with "-").
function subscriptionName(text, url) {
  var name = String(text || "").trim()
  if (name === "") {
    var m = /^https?:\/\/(?:[^\/?#@]*@)?([^\/?#:]+)/i.exec(String(url || "").trim())
    name = m ? m[1].toLowerCase() : ""
  }
  if (name === "" || name.length > 40 || name.charAt(0) === "-" || CONTROL_RE.test(name)) return ""
  return name
}

function countryCode(value) {
  var code = String(value || "").toUpperCase()
  return COUNTRY_RE.test(code) ? code : ""
}

function ipAddress(value) {
  var ip = String(value || "")
  return IPV4_RE.test(ip) || IPV6_RE.test(ip) ? ip : ""
}

function trafficBlock(raw) {
  var src = raw && typeof raw === "object" ? raw : {}
  return {
    tunnel_up: num(src.tunnel_up),
    tunnel_down: num(src.tunnel_down),
    direct_up: num(src.direct_up),
    direct_down: num(src.direct_down)
  }
}

function code(value) {
  return typeof value === "string" && CODE_RE.test(value) ? value : ""
}

function hasCyrillic(text) {
  return CYRILLIC_RE.test(String(text || ""))
}

// Text from the CLI that the panel may show as is (a core log line, an
// exception): bounded, and dropped when it is Cyrillic (see CYRILLIC_RE).
function foreignText(value, limit) {
  var text = clip(value, limit)
  return hasCyrillic(text) ? "" : text
}

// A skipped-links entry: {code, scheme, count}. A cache from an older CLI
// holds a sentence instead; it becomes "legacy" and is never shown.
function normalizeSkip(entry) {
  if (typeof entry === "string") return { code: "legacy", scheme: "", count: 0 }
  if (!entry || typeof entry !== "object") return null
  var c = code(entry.code)
  if (c === "") return null
  var scheme = String(entry.scheme || "")
  return { code: c, scheme: SCHEME_RE.test(scheme) ? scheme : "", count: Math.floor(num(entry.count)) }
}

function normalizeSkipped(list) {
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_SKIPPED; i++) {
    var item = normalizeSkip(list[i])
    if (item) out.push(item)
  }
  return out
}

function normalizeSubscription(raw) {
  var info = raw && raw.userinfo && typeof raw.userinfo === "object" ? raw.userinfo : {}
  return {
    name: clip(raw.name, MAX_TEXT),
    active: raw.active === true,
    count: Math.floor(num(raw.count)),
    updated: num(raw.updated),
    title: clip(raw.title, MAX_TEXT),
    userinfo: {
      upload: num(info.upload),
      download: num(info.download),
      total: num(info.total),
      expire: num(info.expire)
    },
    skipped: normalizeSkipped(raw.skipped)
  }
}

// A host that may go to `xray-omarchy rule`, lowercased, or "" when it is not one.
// Checked on the raw value: a clipped host ends in "…" and fails here.
function ruleHost(value) {
  if (typeof value !== "string") return ""
  var host = value.toLowerCase()
  return HOST_RE.test(host) ? host : ""
}

function ruleSide(value) {
  return value === "direct" || value === "tunnel" ? value : ""
}

// `rules`: {direct: [...], tunnel: [...]}, hosts the CLI stored.
function normalizeRules(raw) {
  var src = raw && typeof raw === "object" ? raw : {}
  var out = { direct: [], tunnel: [] }
  var sides = ["direct", "tunnel"]
  for (var i = 0; i < sides.length; i++) {
    var list = Array.isArray(src[sides[i]]) ? src[sides[i]] : []
    for (var j = 0; j < list.length && out[sides[i]].length < MAX_RULES; j++) {
      var host = ruleHost(list[j])
      if (host !== "" && out[sides[i]].indexOf(host) < 0) out[sides[i]].push(host)
    }
  }
  return out
}

// The rules as rows for the page: [{host, side}], direct first.
function ruleRows(rules) {
  var r = rules || { direct: [], tunnel: [] }
  return r.direct.map(function(h) { return { host: h, side: "direct" } })
    .concat(r.tunnel.map(function(h) { return { host: h, side: "tunnel" } }))
}

// The side a stored rule puts exactly this host on, or "".
function ruleFor(rules, host) {
  if (!rules || host === "") return ""
  if (rules.direct.indexOf(host) >= 0) return "direct"
  if (rules.tunnel.indexOf(host) >= 0) return "tunnel"
  return ""
}

// A host may reach `xray-omarchy rule` only when the CLI itself reported it: a row
// of recent[] or a stored rule.
function knownHost(status, host) {
  if (!status || host === "") return false
  if (ruleFor(status.rules, host) !== "") return true
  for (var i = 0; i < status.recent.length; i++)
    if (status.recent[i].ruleHost === host) return true
  return false
}

// `fallback` from status: the switch, the node it falls back to, and whether
// traffic goes through it now. `active` is true only when the core says so
// (null means it does not know yet).
function normalizeFallback(raw) {
  var src = raw && typeof raw === "object" ? raw : {}
  return {
    enabled: src.enabled === true,
    node: validNodeId(src.node) ? src.node : "",
    nodeName: clip(src.node_name, MAX_TEXT),
    active: src.active === true,
    ready: src.ready === true,
    problem: code(src.problem),
    restartNeeded: src.restart_needed === true
  }
}

// Nodes the fallback may be: plain nodes (not groups) other than the
// selected one that answer, fastest first. The node already chosen stays in
// the list even when it does not answer, so the choice is always visible.
function fallbackCandidates(nodes, selectedId, chosenId) {
  var list = sortNodes(nodes)
  return list.filter(function(n) {
    if (n.group || n.id === selectedId) return false
    return n.alive !== false || n.id === chosenId
  })
}

function normalizeRecent(raw) {
  var via = raw.via === "direct" || raw.via === "block" ? raw.via : "tunnel"
  return {
    ruleHost: ruleHost(raw.host),
    rule: ruleSide(raw.rule),
    time: clip(raw.time, 12),
    host: clip(raw.host, MAX_TEXT),
    ip: clip(raw.ip, 64),
    port: Math.floor(num(raw.port)),
    proto: clip(raw.proto, 8),
    via: via,
    node: clip(raw.node, MAX_TEXT),
    count: Math.max(1, Math.floor(num(raw.count)))
  }
}

// `protection` is the CLI's verdict: ok, or what is wrong as codes the panel
// translates (`problems` is the same list as text for the terminal and is
// never read). No verdict at all is not "protected": the panel says nothing
// rather than lie. A "not ok" without a code it knows still reads as not ok.
function normalizeProtection(raw) {
  if (!raw || typeof raw !== "object" || typeof raw.ok !== "boolean") return { known: false, ok: false, codes: [] }
  var codes = []
  var list = Array.isArray(raw.codes) ? raw.codes.slice(0, MAX_PROBLEMS) : []
  for (var i = 0; i < list.length; i++) {
    var c = code(list[i])
    if (c !== "" && codes.indexOf(c) < 0) codes.push(c)
  }
  if (codes.length === 0 && (raw.ok !== true || (Array.isArray(raw.problems) && raw.problems.length > 0)))
    codes.push("unknown")
  return { known: true, ok: raw.ok === true && codes.length === 0, codes: codes }
}

// What is installed, from `status.setup`. A CLI without the field predates it:
// treated as ready, the panel never blocks on a field it cannot read. version
// is the package's: older than the panel's manifest means "Update components…".
function normalizeSetup(raw) {
  if (!raw || typeof raw !== "object" || typeof raw.ready !== "boolean")
    return { known: false, ready: true, helper: true, core: true, coreCaps: true, geo: true, version: "" }
  return {
    known: true,
    ready: raw.ready === true,
    helper: raw.helper === true,
    core: raw.core === true,
    coreCaps: raw.core_caps === true,
    geo: raw.geo === true,
    version: packageVersion(raw.version)
  }
}

// "0.6.0": three numbers, as manifest.json, PKGBUILD and the CLI write it.
var PACKAGE_VERSION_RE = /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/

function packageVersion(value) {
  return typeof value === "string" && PACKAGE_VERSION_RE.test(value) ? value : ""
}

// True when version a is older than b; false when either is not a version.
function versionOlder(a, b) {
  if (packageVersion(a) === "" || packageVersion(b) === "") return false
  var x = a.split(".").map(Number)
  var y = b.split(".").map(Number)
  for (var i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i]
  return false
}

// The plugin's own version from the text of manifest.json, or "".
function manifestVersion(text) {
  try {
    var raw = JSON.parse(String(text || ""))
    return raw && typeof raw === "object" ? packageVersion(raw.version) : ""
  } catch (e) {
    return ""
  }
}

// The plugin's files were updated under a running shell that still runs the
// code it loaded (PANEL_VERSION): the manifest on disk is a newer version.
function restartNeeded(diskVersion) {
  return versionOlder(PANEL_VERSION, diskVersion)
}

// The installed package is older than the panel: the panel offers
// "Update components…" (install.sh again). Not when the CLI cannot tell.
function componentsOutdated(setup, pluginVersion) {
  return !!setup && setup.known === true && versionOlder(setup.version, pluginVersion)
}

// ---- checked sites -----------------------------------------------------------
//
// `status.sites`: {items: [{name, host, result}], checked, tunnel, notify}.
// The CLI checks them (the watcher once a minute while the tunnel runs, or
// `xray-omarchy site check` from the panel); the panel only shows the last result.

// A link for `xray-omarchy site add`: https only, one line of printable ASCII,
// no user or password, up to 2000 characters. "" when it is not one. The CLI
// checks it again.
var SITE_URL_RE = /^https:\/\/[^\s\/?#@]+(?:[\/?#][\x21-\x7e]*)?$/i

function siteUrl(text) {
  var url = String(text || "").trim()
  if (url.length > 2000 || CONTROL_RE.test(url) || !SITE_URL_RE.test(url)) return ""
  return url
}

// The name for a new site: what was typed, or the link's host. The CLI's rule
// for names, as for subscriptions.
function siteName(text, url) {
  return subscriptionName(text, url)
}

var SITE_VIAS = ["tunnel", "direct", "block"]
var SITE_WHYS = ["rule", "local", "geo", "tunnel_off"]

function normalizeSiteResult(raw) {
  if (!raw || typeof raw !== "object" || typeof raw.ok !== "boolean") return null
  var ms = raw.ms === null || raw.ms === undefined ? null : Number(raw.ms)
  if (ms !== null && (!isFinite(ms) || ms < 0)) ms = null
  var status = Math.floor(num(raw.status))
  return {
    ok: raw.ok,
    status: status >= 100 && status <= 599 ? status : 0,
    ms: ms === null ? null : Math.round(ms),
    error: raw.ok ? "" : (code(raw.error) || "other"),
    via: SITE_VIAS.indexOf(raw.via) >= 0 ? raw.via : "tunnel",
    node: clip(raw.node, MAX_TEXT),
    why: SITE_WHYS.indexOf(raw.why) >= 0 ? raw.why : "",
    fromLog: raw.source === "log"
  }
}

function normalizeSites(raw) {
  var src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null
  if (src === null) return { known: false, items: [], checked: 0, tunnel: null, notify: false }
  var list = Array.isArray(src.items) ? src.items : []
  var items = []
  for (var i = 0; i < list.length && items.length < MAX_SITES; i++) {
    var it = list[i]
    if (!it || typeof it !== "object" || typeof it.name !== "string" || it.name === "") continue
    items.push({ name: clip(it.name, 40), host: clip(it.host, MAX_TEXT), result: normalizeSiteResult(it.result) })
  }
  return {
    known: true,
    items: items,
    checked: num(src.checked),
    tunnel: typeof src.tunnel === "boolean" ? src.tunnel : null,
    notify: src.notify === true
  }
}

// A name the CLI reported, for `xray-omarchy site rm`.
function validSiteName(name, sites) {
  if (typeof name !== "string" || name === "" || !sites) return false
  for (var i = 0; i < sites.items.length; i++) if (sites.items[i].name === name) return true
  return false
}

// The main screen's one line: how many open, which do not, and whether any is
// still unchecked.
function siteSummary(sites) {
  var out = { total: 0, ok: 0, failed: [], unchecked: 0 }
  if (!sites) return out
  out.total = sites.items.length
  for (var i = 0; i < sites.items.length; i++) {
    var r = sites.items[i].result
    if (r === null) out.unchecked++
    else if (r.ok) out.ok++
    else out.failed.push(sites.items[i].name)
  }
  return out
}

// The last check says nothing true any more: never made, older than
// `maxAge` seconds by the CLI's clock, made with the tunnel in the other
// state, or a site added after it. The panel then asks for a fresh one.
function sitesStale(status, maxAge) {
  if (!status || !status.sites || status.sites.items.length === 0) return false
  var s = status.sites
  if (s.checked === 0 || s.tunnel === null || s.tunnel !== status.running) return true
  if (num(status.time) - s.checked > (maxAge || 90)) return true
  for (var i = 0; i < s.items.length; i++) if (s.items[i].result === null) return true
  return false
}

// Direct presets from `status.presets` ({russia: bool}). A CLI without the
// field (older package) has none: the switch is not shown.
var PRESET_NAMES = ["russia"]

function normalizePresets(raw) {
  var out = { known: false }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  for (var i = 0; i < PRESET_NAMES.length; i++) {
    var name = PRESET_NAMES[i]
    if (typeof raw[name] === "boolean") {
      out[name] = raw[name]
      out.known = true
    }
  }
  return out
}

function validPreset(name) {
  return PRESET_NAMES.indexOf(name) >= 0
}

function normalizeNode(raw) {
  if (!raw || !validNodeId(raw.id)) return null
  var delay = raw.delay === null || raw.delay === undefined ? null : Number(raw.delay)
  if (delay !== null && (!isFinite(delay) || delay < 0)) delay = null
  return {
    id: raw.id,
    name: clip(raw.name, MAX_TEXT),
    group: raw.kind === "group",
    members: Math.floor(num(raw.members)),
    delay: delay,
    alive: raw.alive === true ? true : (raw.alive === false ? false : null),
    traffic: num(raw.traffic)
  }
}

function normalizeNodes(list) {
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_NODES; i++) {
    var node = normalizeNode(list[i])
    if (node) out.push(node)
  }
  return out
}

// `xray-omarchy status --json` → the panel's state, or null when the text is not the
// JSON object the CLI prints. Nothing from the input is used unbounded.
function parseStatus(text) {
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var exit = raw.exit && typeof raw.exit === "object" ? raw.exit : {}
  var traffic = raw.traffic && typeof raw.traffic === "object" ? raw.traffic : {}
  var subs = Array.isArray(raw.subscriptions) ? raw.subscriptions.slice(0, MAX_SUBSCRIPTIONS) : []
  var recent = Array.isArray(raw.recent) ? raw.recent.slice(0, MAX_RECENT) : []
  var errors = Array.isArray(raw.errors) ? raw.errors.slice(-MAX_ERRORS) : []
  var state = {
    running: raw.running === true,
    service: clip(raw.service, 24),
    tun: raw.tun === true,
    killswitch: raw.killswitch === "on" || raw.killswitch === "off" ? raw.killswitch : "unknown",
    dns: raw.dns === "xray" ? "xray" : (raw.dns === "router" ? "router" : "unknown"),
    mode: raw.mode === "node" ? "node" : "auto",
    selected: validNodeId(raw.selected) ? raw.selected : "",
    current: clip(raw.current, MAX_TEXT),
    currentId: validNodeId(raw.current_id) ? raw.current_id : "",
    exit: {
      ip: ipAddress(exit.ip),
      country: countryCode(exit.country),
      ts: num(exit.ts)
    },
    today: trafficBlock(traffic.today),
    rate: trafficBlock(traffic.rate),
    subscriptions: subs.filter(function(s) { return s && typeof s === "object" }).map(normalizeSubscription),
    recent: recent.filter(function(r) { return r && typeof r === "object" }).map(normalizeRecent),
    errors: errors.map(function(e) { return foreignText(e, MAX_ERROR_TEXT) }).filter(function(e) { return e !== "" }),
    protection: normalizeProtection(raw.protection),
    fallback: normalizeFallback(raw.fallback),
    notify: raw.notify === true,
    notifyKnown: typeof raw.notify === "boolean",
    sites: normalizeSites(raw.sites),
    rules: normalizeRules(raw.rules),
    presets: normalizePresets(raw.presets),
    setup: normalizeSetup(raw.setup),
    time: num(raw.time),
    hasNodes: Array.isArray(raw.nodes),
    nodes: normalizeNodes(raw.nodes)
  }
  return state
}

// What the bar icon and the hero say. One key, so the two never disagree.
//   off      — the core is not running (switched off, or never started)
//   on       — running, TUN up, and the CLI says protected
//   unprotected — running, but the CLI's verdict is not ok (not routed, the
//              killswitch or DNS off); or `net up` could not set the routes
//              and systemd is starting the unit again (not_routed)
//   failed   — systemd says failed, or running without its TUN device
//   starting / stopping — a switch is in flight (optimistic); `on` is in
//              flight until the CLI says protected, so the DNS switch a
//              second after the core starts never flashes a warning
//   unknown  — no answer from the CLI yet
function connectionState(status, wanted) {
  if (wanted === 1 && !(status && status.running && status.protection && status.protection.ok)) return "starting"
  if (wanted === 0 && status && status.running) return "stopping"
  if (!status) return "unknown"
  if (status.service === "failed") return "failed"
  if (status.running && !status.tun) return "failed"
  var verdict = status.protection || { known: false, ok: false, codes: [] }
  if (status.running && verdict.known && !verdict.ok) return "unprotected"
  if (status.running) return "on"
  if (status.service === "activating" && verdict.known && verdict.codes.indexOf("not_routed") >= 0) return "unprotected"
  if (status.service === "activating") return "starting"
  return "off"
}

// The tunnel's unit wants to run: running, or being started again by systemd
// (after a failed `net up`). The switch shows this, so it can always be
// turned off from the panel.
function engaged(status) {
  return !!status && (status.running === true || status.service === "activating")
}

// Fastest first; never-probed after the living; dead last. Name breaks ties
// so a refresh with equal delays does not shuffle the list under the cursor.
function nodeRank(node) {
  if (node.alive === true) return 0
  if (node.alive === null) return 1
  return 2
}

function sortNodes(nodes) {
  var list = Array.isArray(nodes) ? nodes.slice() : []
  list.sort(function(a, b) {
    var ra = nodeRank(a)
    var rb = nodeRank(b)
    if (ra !== rb) return ra - rb
    if (ra === 0) {
      var da = a.delay === null ? Infinity : a.delay
      var db = b.delay === null ? Infinity : b.delay
      if (da !== db) return da - db
    }
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  })
  return list
}

function filterNodes(nodes, query) {
  var list = Array.isArray(nodes) ? nodes : []
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return list.slice()
  return list.filter(function(node) {
    return node.name.toLowerCase().indexOf(q) !== -1 || node.id.indexOf(q) === 0
  })
}

// ---- the node list's order -------------------------------------------------
//
// The order is taken once — when the panel opens and when the search text
// changes — and then frozen: later polls update delays in place, a node that
// vanished drops out, a new one is appended. Rows never move under the cursor
// or the mouse while the panel is open.
//
// `live` are the nodes that answered (fastest first) and those not probed yet;
// `dead` are folded behind one "Unreachable: N" row.

function nodeOrder(nodes, query) {
  var sorted = sortNodes(filterNodes(nodes, query))
  var live = []
  var dead = []
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].alive === false) dead.push(sorted[i].id)
    else live.push(sorted[i].id)
  }
  return { live: live, dead: dead }
}

// Keeps `order` as it is, minus ids no longer in `nodes`, plus new ids (that
// match the query) at the end of the group their state puts them in.
function reconcileOrder(order, nodes, query) {
  var byId = {}
  var list = Array.isArray(nodes) ? nodes : []
  for (var i = 0; i < list.length; i++) byId[list[i].id] = list[i]
  var seen = {}
  function keep(ids) {
    var out = []
    for (var j = 0; j < ids.length; j++) {
      if (byId[ids[j]] && !seen[ids[j]]) {
        seen[ids[j]] = true
        out.push(ids[j])
      }
    }
    return out
  }
  var live = keep(order && order.live ? order.live : [])
  var dead = keep(order && order.dead ? order.dead : [])
  var fresh = filterNodes(list, query)
  for (var k = 0; k < fresh.length; k++) {
    if (seen[fresh[k].id]) continue
    seen[fresh[k].id] = true
    if (fresh[k].alive === false) dead.push(fresh[k].id)
    else live.push(fresh[k].id)
  }
  return { live: live, dead: dead }
}

function sameOrder(a, b) {
  if (!a || !b) return false
  return a.live.join(",") === b.live.join(",") && a.dead.join(",") === b.dead.join(",")
}

// The rows of the scrolled list, as keys: node ids, then "fold" when any node
// is dead, then the dead ids when the fold is open. "Auto" is pinned above the
// list and is not in here.
function listKeys(order, expanded) {
  var keys = order.live.slice()
  if (order.dead.length > 0) {
    keys.push("fold")
    if (expanded) keys = keys.concat(order.dead)
  }
  return keys
}

// The keyboard cursor holds a key, never a row number: "auto", "fold" or an
// id. Moving finds the key in the current rows and steps from there.
function moveKey(keys, current, dy) {
  var all = ["auto"].concat(keys)
  var at = all.indexOf(current)
  if (at < 0) return dy > 0 ? all[0] : all[all.length - 1]
  return all[Math.max(0, Math.min(all.length - 1, at + dy))]
}

function nodeById(nodes, id) {
  var list = Array.isArray(nodes) ? nodes : []
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

// What the header's second line says while the tunnel runs: country, exit
// address and the delay of the node carrying traffic, whichever are known.
function heroParts(status, nodes) {
  if (!status) return { country: "", ip: "", delay: null }
  var node = status.currentId !== "" ? nodeById(nodes, status.currentId) : null
  return {
    country: status.exit.country,
    ip: status.exit.ip,
    delay: node && node.alive === true && node.delay !== null ? node.delay : null
  }
}

function totals(block) {
  var b = block || {}
  return { down: num(b.tunnel_down) + num(b.direct_down), up: num(b.tunnel_up) + num(b.direct_up) }
}

// `xray-omarchy on --json` / `xray-omarchy off --json`: the last line is {ok, code, detail};
// every line before it is the CLI talking to a terminal and is ignored. null
// when there is no such line (a crash, an older CLI). `detail` is a line of
// the core's journal; dropped when it is Cyrillic (see CYRILLIC_RE).
function parseResult(text) {
  var lines = String(text || "").split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = lines[i].trim()
    if (line === "") continue
    var raw
    try {
      raw = JSON.parse(line)
    } catch (e) {
      return null
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw) || typeof raw.ok !== "boolean") return null
    return { ok: raw.ok, code: code(raw.code), detail: foreignText(raw.detail, MAX_TEXT) }
  }
  return null
}

// `xray-omarchy update --json`: [{name, ok, count | error, skipped}]. null when the
// answer is not that array (the CLI printed a plain sentence instead).
function parseUpdate(text) {
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!Array.isArray(raw)) return null
  var out = []
  for (var i = 0; i < raw.length && out.length < MAX_SUBSCRIPTIONS; i++) {
    var r = raw[i]
    if (!r || typeof r !== "object" || typeof r.name !== "string" || r.name === "") continue
    out.push({
      name: clip(r.name, MAX_TEXT),
      ok: r.ok === true,
      count: Math.floor(num(r.count)),
      error: r.ok === true ? "" : foreignText(r.error, MAX_TEXT),
      skipped: normalizeSkipped(r.skipped)
    })
  }
  return out
}

function version(value) {
  return typeof value === "string" && VERSION_RE.test(value) ? value : ""
}

// The last line of `xray-omarchy core status --json`: the installed core, the latest
// release, and the last update's outcome. null when it is not that object.
function parseCoreStatus(text) {
  var lines = String(text || "").trim().split("\n")
  var raw
  try {
    raw = JSON.parse(lines[lines.length - 1])
  } catch (e) {
    return null
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var u = raw.update && typeof raw.update === "object" ? raw.update : null
  var update = null
  if (u) {
    var state = u.state === "running" || u.state === "done" || u.state === "lost" ? u.state : ""
    if (state !== "") update = {
      state: state,
      ok: u.ok === true,
      code: code(u.code),
      detail: foreignText(u.detail, MAX_TEXT),
      from: version(u.from),
      to: version(u.to),
      started: num(u.started),
      finished: num(u.finished)
    }
  }
  return {
    version: version(raw.version),
    latest: version(raw.latest),
    published: /^\d{4}-\d\d-\d\dT/.test(String(raw.latest_published || "")) ? String(raw.latest_published).substring(0, 10) : "",
    checked: num(raw.latest_checked),
    updateAvailable: raw.update_available === true ? true : (raw.update_available === false ? false : null),
    checkError: foreignText(raw.check_error, MAX_TEXT),
    prevVersion: version(raw.prev_version),
    // The newest XTLS release when this package does not pin it yet: it comes
    // with a package update ("Update components…"), not from this page.
    unpinnedRelease: raw.release_pinned === false ? version(raw.release) : "",
    inProgress: raw.in_progress === true || (update !== null && update.state === "running"),
    update: update
  }
}

function updateFailures(results) {
  return (results || []).filter(function(r) { return !r.ok })
}

function aliveCount(nodes) {
  var n = 0
  for (var i = 0; i < (nodes || []).length; i++) if (nodes[i].alive === true) n++
  return n
}

function delayState(node) {
  if (!node || node.alive === null) return "unknown"
  if (node.alive === false) return "dead"
  if (node.delay === null) return "unknown"
  return node.delay <= DELAY_FAST_MS ? "fast" : "slow"
}

var BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"]

// Units stay as they are in every language. `format(value, decimals)` writes
// the number: the panel passes Commons.I18n.formatNumber, so the decimal
// separator and digits follow the language; without one it is plain toFixed.
function formatBytes(bytes, format) {
  var value = num(bytes)
  var unit = 0
  while (value >= 1024 && unit < BYTE_UNITS.length - 1) {
    value /= 1024
    unit++
  }
  var digits = unit === 0 ? 0 : (value < 10 ? 1 : 0)
  var text = typeof format === "function" ? format(value, digits) : Number(value).toFixed(digits)
  return text + " " + BYTE_UNITS[unit]
}

// Remaining traffic and expiry from `subscription-userinfo`. total=0 means no
// cap and expire=0 means no end date: the provider sends zeros, not nulls.
function quota(userinfo, now) {
  var info = userinfo || {}
  var used = num(info.upload) + num(info.download)
  var total = num(info.total)
  var expire = num(info.expire)
  var nowSec = num(now)
  return {
    used: used,
    unlimited: total === 0,
    total: total,
    remaining: total > 0 ? Math.max(0, total - used) : 0,
    exhausted: total > 0 && used >= total,
    endless: expire === 0,
    expire: expire,
    expired: expire > 0 && nowSec > 0 && expire <= nowSec,
    daysLeft: expire > 0 && nowSec > 0 ? Math.max(0, Math.floor((expire - nowSec) / 86400)) : 0
  }
}

// An age as a count and a unit key, for a plural catalog entry.
function age(seconds) {
  var s = Math.max(0, Math.floor(num(seconds)))
  if (s < 60) return { unit: "now", count: 0 }
  var m = Math.floor(s / 60)
  if (m < 60) return { unit: "minutes", count: m }
  var h = Math.floor(m / 60)
  if (h < 48) return { unit: "hours", count: h }
  return { unit: "days", count: Math.floor(h / 24) }
}

// "2026/11/18 11:06:23.652362 [Warning] core: Xray started" → time, level and
// message. The date is today's for anything the tail of a tmpfs log holds.
function shortError(line) {
  var text = clip(line, MAX_ERROR_TEXT)
  var m = text.match(/^\d{4}\/\d\d\/\d\d (\d\d:\d\d:\d\d)(?:\.\d+)? \[(\w+)\] (.*)$/)
  if (!m) return { time: "", level: "", message: text }
  return { time: m[1], level: m[2], message: m[3] }
}

// Phrases into lines for a narrow card: greedy, never breaking a phrase and
// never leaving a separator at the end of a line (it goes before a phrase and
// only between two phrases on the same line). `widths` are the phrases'
// widths, `sep` the separator's. Returns the phrase indices of each line.
function packLines(widths, sep, maxWidth) {
  var lines = []
  var line = []
  var used = 0
  for (var i = 0; i < widths.length; i++) {
    var w = num(widths[i])
    if (line.length > 0 && used + sep + w > maxWidth) {
      lines.push(line)
      line = []
      used = 0
    }
    used += (line.length > 0 ? sep : 0) + w
    line.push(i)
  }
  if (line.length > 0) lines.push(line)
  return lines
}
