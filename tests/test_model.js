const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { load, ROOT } = require("./load")

const M = load("Model.js")

// ---- a real `xray-omarchy status --json --nodes` answer, shape for shape -----------
const sample = {
  running: true, service: "active", tun: true, killswitch: "on", dns: "xray",
  mode: "auto", selected: null, current: "🇫🇮 Helsinki 1", current_id: "abcdefabcd",
  exit: { ip: "203.0.113.23", country: "FI", ts: 1794982055 },
  traffic: {
    today: { tunnel_up: 11290457, tunnel_down: 1290954, direct_up: 25508, direct_down: 144660 },
    rate: { tunnel_up: 78979, tunnel_down: 2666, direct_up: 112, direct_down: 1223 }
  },
  subscriptions: [
    { name: "Main", active: true, count: 2, updated: 1794981845, title: "example-network",
      userinfo: { upload: 0, download: 1605615770050, total: 0, expire: 0 }, skipped: [] },
    { name: "Other", active: false, count: 562, updated: 1794981846, title: "Other VPN",
      userinfo: { upload: 0, download: 57254535, total: 536870912000, expire: 1795835049 },
      skipped: [{ code: "insecure_tls", scheme: "vless", count: 1 }, { code: "Bad Code", scheme: "x", count: 1 },
                { code: "hy2_obfs", scheme: "<b>", count: "3" },
                "vless: TLS without certificate check ×1"] }
  ],
  recent: [{ time: "11:09:20", host: "api.anthropic.com", ip: "198.51.100.10", port: 443,
             proto: "tcp", via: "tunnel", node: "🇫🇮 Helsinki 1", count: 330 }],
  protection: { ok: true, codes: [], problems: [] },
  errors: ["2026/11/18 11:06:23.652362 [Warning] core: Xray 26.10.31 started"],
  time: 1794982100,
  nodes: [
    { id: "abcdefabcd", name: "🇫🇮 Helsinki 1", kind: "node", members: 1, delay: 227, alive: true, traffic: 1 },
    { id: "0123456789", name: "🇩🇪 Frankfurt 1", kind: "node", members: 1, delay: 913, alive: true, traffic: 2 },
    { id: "aaaaaaaaaa", name: "Dead", kind: "node", members: 1, delay: null, alive: false, traffic: 0 },
    { id: "bbbbbbbbbb", name: "Fresh", kind: "group", members: 3, delay: null, alive: null, traffic: 0 },
    { id: "../../etc", name: "bad id", kind: "node", members: 1, delay: 1, alive: true, traffic: 0 }
  ]
}

const s = M.parseStatus(JSON.stringify(sample))
assert.ok(s)
assert.strictEqual(s.running, true)
assert.strictEqual(s.currentId, "abcdefabcd")
assert.strictEqual(s.exit.country, "FI")
assert.strictEqual(s.exit.ip, "203.0.113.23")
assert.strictEqual(s.selected, "")
assert.strictEqual(s.subscriptions.length, 2)
assert.strictEqual(s.hasNodes, true)
// A node with an id that is not 10 hex never reaches the list, so it can
// never reach `xray-omarchy select`.
assert.strictEqual(s.nodes.length, 4)
assert.ok(s.nodes.every(n => /^[0-9a-f]{10}$/.test(n.id)))
assert.strictEqual(s.nodes[3].group, true)

// No --nodes: the node table is left as it was.
const noNodes = Object.assign({}, sample); delete noNodes.nodes
assert.strictEqual(M.parseStatus(JSON.stringify(noNodes)).hasNodes, false)

// Garbage in, null out.
assert.strictEqual(M.parseStatus("not json"), null)
assert.strictEqual(M.parseStatus("[1,2]"), null)
assert.strictEqual(M.parseStatus(""), null)

// Bounds: recent ≤ 60, errors ≤ 15 (newest kept), strings clipped.
const flood = Object.assign({}, sample, {
  recent: Array.from({ length: 500 }, (_, i) => ({ time: "1", host: "h" + i, via: "tunnel" })),
  errors: Array.from({ length: 100 }, (_, i) => "e" + i),
  current: "x".repeat(10000),
  exit: { ip: "<img src=x>", country: "<b>" }
})
const f = M.parseStatus(JSON.stringify(flood))
assert.strictEqual(f.recent.length, 60)
assert.strictEqual(f.errors.length, 15)
assert.strictEqual(f.errors[14], "e99")
assert.ok(f.current.length <= 200)
assert.strictEqual(f.exit.ip, "")
assert.strictEqual(f.exit.country, "")
// Markup-shaped text is kept as text (the QML renders it PlainText).
assert.strictEqual(M.clip("<img src=\"https://example.invalid/t\">"), "<img src=\"https://example.invalid/t\">")
assert.strictEqual(M.clip("a\nb\u0007c"), "a b c")

// ---- ids and names that reach argv -----------------------------------------
assert.ok(M.validNodeId("abcdefabcd"))
for (const bad of ["ABCDEFABCD", "abcdefabc", "abcdefabcde", "auto", "; rm -rf ~", "", null, 12])
  assert.ok(!M.validNodeId(bad), String(bad))
assert.ok(M.validSubscriptionName("Other", s.subscriptions))
assert.ok(!M.validSubscriptionName("--help", s.subscriptions))
assert.ok(!M.validSubscriptionName("", s.subscriptions))

// ---- connection state --------------------------------------------------------
assert.strictEqual(M.connectionState(null, -1), "unknown")
assert.strictEqual(M.connectionState(s, -1), "on")
assert.strictEqual(M.connectionState(Object.assign({}, s, { tun: false }), -1), "failed")
assert.strictEqual(M.connectionState(Object.assign({}, s, { running: false, service: "failed" }), -1), "failed")
assert.strictEqual(M.connectionState(Object.assign({}, s, { running: false, service: "inactive" }), -1), "off")
assert.strictEqual(M.connectionState(Object.assign({}, s, { running: false, service: "inactive" }), 1), "starting")
assert.strictEqual(M.connectionState(s, 0), "stopping")
// Running but not protected (not routed, killswitch or DNS off): the warning,
// never the plain bolt. Not while `on` is still in flight (DNS switches a
// second after the core starts).
const notRouted = { known: true, ok: false, codes: ["not_routed"] }
const protectedOk = { known: true, ok: true, codes: [] }
assert.strictEqual(M.connectionState(Object.assign({}, s, { protection: notRouted }), -1), "unprotected")
assert.strictEqual(M.connectionState(Object.assign({}, s, { protection: { known: true, ok: false, codes: ["dns_bypass"] } }), 1), "starting")
assert.strictEqual(M.connectionState(Object.assign({}, s, { protection: protectedOk }), 1), "on")
assert.strictEqual(M.connectionState(Object.assign({}, s, { protection: protectedOk }), -1), "on")
// `net up` failed and systemd starts the unit again: not routed, not "starting".
const retrying = Object.assign({}, s, { running: false, tun: false, service: "activating", protection: notRouted })
assert.strictEqual(M.connectionState(retrying, -1), "unprotected")
assert.strictEqual(M.connectionState(Object.assign({}, retrying, { protection: { known: true, ok: false, codes: ["core_stopped"] } }), -1), "starting")
// The switch reads on while systemd retries, so the tunnel can be turned off.
assert.strictEqual(M.engaged(retrying), true)
assert.strictEqual(M.engaged(Object.assign({}, s, { running: false, service: "inactive" })), false)
assert.strictEqual(M.engaged(null), false)
// A newer manifest on disk than the code that runs: restart the shell.
assert.strictEqual(M.restartNeeded(M.PANEL_VERSION), false)
assert.strictEqual(M.restartNeeded(""), false)
assert.strictEqual(M.restartNeeded("99.0.0"), true)
assert.strictEqual(M.restartNeeded("0.0.1"), false)

// ---- sorting and filtering -----------------------------------------------------
const sorted = M.sortNodes(s.nodes).map(n => n.name)
assert.strictEqual(JSON.stringify(sorted), JSON.stringify(["🇫🇮 Helsinki 1", "🇩🇪 Frankfurt 1", "Fresh", "Dead"]))
assert.strictEqual(JSON.stringify(M.filterNodes(s.nodes, "frank").map(n => n.id)), JSON.stringify(["0123456789"]))
assert.strictEqual(JSON.stringify(M.filterNodes(s.nodes, "  ").length), JSON.stringify(4))
assert.strictEqual(M.aliveCount(s.nodes), 2)
assert.strictEqual(M.delayState(s.nodes[0]), "fast")
assert.strictEqual(M.delayState(s.nodes[1]), "slow")
assert.strictEqual(M.delayState(s.nodes[2]), "dead")
assert.strictEqual(M.delayState(s.nodes[3]), "unknown")

// 562 nodes sort and filter without trouble.
const big = Array.from({ length: 562 }, (_, i) => ({
  id: (i + 0x1000000000).toString(16).slice(-10), name: "node " + i, group: false, members: 1,
  delay: i % 7 === 0 ? 100 + i : null, alive: i % 7 === 0 ? true : (i % 3 === 0 ? null : false)
}))
const bs = M.sortNodes(big)
assert.strictEqual(bs.length, 562)
assert.strictEqual(bs[0].delay, 100)
assert.strictEqual(M.filterNodes(big, "node 56").length, 3)  // node 56, 560, 561

// ---- protection and folded hosts ----------------------------------------------
assert.deepStrictEqual(JSON.parse(JSON.stringify(s.protection)), { known: true, ok: true, codes: [] })
assert.strictEqual(s.recent[0].count, 330)
// Codes are kept, the `problems` text never; a code that is not a machine
// word is dropped, duplicates collapse. The problems below are Cyrillic on
// purpose: Model.js drops any Cyrillic text that comes from the CLI (only the
// catalogs may put Russian on screen), and the last assert checks exactly that.
const bad = M.parseStatus(JSON.stringify(Object.assign({}, sample, {
  protection: { ok: false, codes: ["killswitch_off", "<img src=x>", "dns_bypass", "killswitch_off", 7, "x".repeat(40)],
                problems: ["предохранитель снят", "DNS идёт мимо ядра"] }
})))
assert.strictEqual(bad.protection.ok, false)
assert.deepStrictEqual(Array.from(bad.protection.codes), ["killswitch_off", "dns_bypass"])
assert.ok(!JSON.stringify(bad.protection).match(/[\u0400-\u04ff]/))
// "not ok" with no code the panel can read is still not ok ("unknown").
assert.deepStrictEqual(Array.from(M.parseStatus(JSON.stringify(Object.assign({}, sample, { protection: { ok: false, problems: ["no"] } }))).protection.codes), ["unknown"])
// "ok: true" with problems listed is not protected; no verdict is "unknown", never "protected".
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, sample, { protection: { ok: true, problems: ["dns"] } }))).protection.ok, false)
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, sample, { protection: { ok: true, codes: ["dns_bypass"] } }))).protection.ok, false)
// Skipped links: codes and schemes checked, an older cache's sentence becomes "legacy".
assert.deepStrictEqual(JSON.parse(JSON.stringify(s.subscriptions[1].skipped)), [
  { code: "insecure_tls", scheme: "vless", count: 1 },
  { code: "hy2_obfs", scheme: "", count: 3 },
  { code: "legacy", scheme: "", count: 0 }])
// Core errors are English from xray; a Cyrillic line is not shown (Cyrillic
// on purpose: this is the filter under test).
assert.deepStrictEqual(Array.from(M.parseStatus(JSON.stringify(Object.assign({}, sample, { errors: ["a", "ядро", "b"] }))).errors), ["a", "b"])
const none = Object.assign({}, sample); delete none.protection
assert.strictEqual(M.parseStatus(JSON.stringify(none)).protection.known, false)
assert.strictEqual(M.parseStatus(JSON.stringify(none)).protection.ok, false)
// A recent entry without count is one connection.
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, sample, { recent: [{ host: "a", via: "direct" }] }))).recent[0].count, 1)

// ---- the frozen order --------------------------------------------------------
const o1 = M.nodeOrder(s.nodes, "")
assert.deepStrictEqual(Array.from(o1.live), ["abcdefabcd", "0123456789", "bbbbbbbbbb"])  // fastest first, unprobed after
assert.deepStrictEqual(Array.from(o1.dead), ["aaaaaaaaaa"])
assert.deepStrictEqual(Array.from(M.listKeys(o1, false)), ["abcdefabcd", "0123456789", "bbbbbbbbbb", "fold"])
assert.deepStrictEqual(Array.from(M.listKeys(o1, true)), ["abcdefabcd", "0123456789", "bbbbbbbbbb", "fold", "aaaaaaaaaa"])
assert.deepStrictEqual(Array.from(M.listKeys({ live: ["a"], dead: [] }, true)), ["a"])  // no fold row without dead nodes
// A poll where Frankfurt became faster than Helsinki: the order does not move.
const faster = s.nodes.map(n => Object.assign({}, n, n.id === "0123456789" ? { delay: 5 } : {}))
const o2 = M.reconcileOrder(o1, faster, "")
assert.ok(M.sameOrder(o1, o2))
// ...but a fresh open sorts again.
assert.strictEqual(M.nodeOrder(faster, "").live[0], "0123456789")
// A vanished node drops out, a new one is appended to its group.
const changed = faster.filter(n => n.id !== "bbbbbbbbbb").concat([
  { id: "cccccccccc", name: "New", group: false, members: 1, delay: 1, alive: true, traffic: 0 },
  { id: "dddddddddd", name: "Gone", group: false, members: 1, delay: null, alive: false, traffic: 0 }])
const o3 = M.reconcileOrder(o1, changed, "")
assert.deepStrictEqual(Array.from(o3.live), ["abcdefabcd", "0123456789", "cccccccccc"])
assert.deepStrictEqual(Array.from(o3.dead), ["aaaaaaaaaa", "dddddddddd"])
// The search narrows new arrivals too.
assert.deepStrictEqual(Array.from(M.reconcileOrder(M.nodeOrder(s.nodes, "hel"), changed, "hel").live), ["abcdefabcd"])
// The cursor is a key: it moves by position in the current rows and clamps.
const keys = M.listKeys(o1, false)
assert.strictEqual(M.moveKey(keys, "", 1), "auto")
assert.strictEqual(M.moveKey(keys, "auto", 1), "abcdefabcd")
assert.strictEqual(M.moveKey(keys, "0123456789", -1), "abcdefabcd")
assert.strictEqual(M.moveKey(keys, "fold", 1), "fold")
assert.strictEqual(M.moveKey(keys, "auto", -1), "auto")
// After a reorder elsewhere the cursor stays on its node, wherever it went.
const reordered = { live: ["0123456789", "abcdefabcd", "bbbbbbbbbb"], dead: ["aaaaaaaaaa"] }
assert.strictEqual(M.moveKey(M.listKeys(reordered, false), "abcdefabcd", 1), "bbbbbbbbbb")

// 562 nodes: order, search and reconcile stay cheap and correct.
const bigOrder = M.nodeOrder(big, "")
assert.strictEqual(bigOrder.live.length + bigOrder.dead.length, 562)
const t0 = Date.now()
for (let i = 0; i < 50; i++) M.reconcileOrder(bigOrder, big, "")
assert.ok(Date.now() - t0 < 1000, "reconcile on 562 nodes is slow")
assert.ok(M.sameOrder(bigOrder, M.reconcileOrder(bigOrder, big, "")))
assert.strictEqual(M.nodeOrder(big, "node 56").live.length + M.nodeOrder(big, "node 56").dead.length, 3)

// ---- the header line ----------------------------------------------------------
const nodeMode = M.parseStatus(JSON.stringify(Object.assign({}, sample, { mode: "node", selected: "0123456789", current: "🇩🇪 Frankfurt 1", current_id: "0123456789" })))
const hp = M.heroParts(nodeMode, s.nodes)
assert.deepStrictEqual([hp.country, hp.ip, hp.delay], ["FI", "203.0.113.23", 913])
assert.strictEqual(M.heroParts(nodeMode, []).delay, null)
assert.strictEqual(M.heroParts(null, []).country, "")
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.totals(s.today))), { down: 1290954 + 144660, up: 11290457 + 25508 })

// ---- command output ------------------------------------------------------------
// on/off --json: the terminal lines before the JSON are ignored.
const r1 = M.parseResult('stopped the old tunnel\ncore did not start: Job failed\n{"ok": false, "code": "start_failed", "detail": "Main process exited, code=exited, status=23/n/a"}\n')
assert.deepStrictEqual(JSON.parse(JSON.stringify(r1)), { ok: false, code: "start_failed", detail: "Main process exited, code=exited, status=23/n/a" })
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.parseResult('tunnel up\n{"ok": true, "code": "", "detail": ""}'))), { ok: true, code: "", detail: "" })
// A Cyrillic detail is dropped (Cyrillic on purpose: the filter under test);
// a bad code too.
assert.strictEqual(M.parseResult('{"ok": false, "code": "no_tun", "detail": "конфиг не пересобран"}').detail, "")
assert.strictEqual(M.parseResult('{"ok": false, "code": "<b>", "detail": ""}').code, "")
// No JSON as the last line: null, never the terminal sentence.
assert.strictEqual(M.parseResult("core did not start: Job failed"), null)
assert.strictEqual(M.parseResult(""), null)
assert.strictEqual(M.parseResult('{"code": "x"}'), null)
// The "Ru" entry's Cyrillic error is on purpose: it must come back as "".
const upd = M.parseUpdate('[{"name": "Main", "ok": true, "count": 2, "skipped": [{"code": "insecure_tls", "scheme": "vless", "count": 1}]}, {"name": "Spare", "ok": false, "error": "HTTP Error 403: <b>Forbidden</b>"}, {"ok": true}, 5, {"name": "Ru", "ok": false, "error": "ошибка"}]')
assert.strictEqual(upd.length, 3)
assert.strictEqual(upd[0].count, 2)
assert.strictEqual(upd[0].skipped[0].code, "insecure_tls")
assert.strictEqual(upd[2].error, "")
assert.strictEqual(upd[1].ok, false)
assert.strictEqual(upd[1].error, "HTTP Error 403: <b>Forbidden</b>")
assert.deepStrictEqual(Array.from(M.updateFailures(upd).map(r => r.name)), ["Spare", "Ru"])
assert.strictEqual(M.parseUpdate("no subscriptions: xray-omarchy sub add NAME URL"), null)
assert.strictEqual(M.parseUpdate('{"name": "x"}'), null)

// ---- formatting --------------------------------------------------------------
// Units stay Latin in every language; the number goes through the formatter.
const comma = (v, d) => Number(v).toFixed(d === undefined ? 0 : d).replace(".", ",")
assert.strictEqual(M.formatBytes(0, comma), "0 B")
assert.strictEqual(M.formatBytes(2666, comma), "2,6 KB")
assert.strictEqual(M.formatBytes(11290457, comma), "11 MB")
assert.strictEqual(M.formatBytes(1536), "1.5 KB")

// Facts into lines: whole phrases, never a separator at a line end.
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.packLines([50, 60, 70], 10, 130))), [[0, 1], [2]])
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.packLines([50, 60, 70], 10, 300))), [[0, 1, 2]])
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.packLines([500, 20], 10, 100))), [[0], [1]])
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.packLines([], 10, 100))), [])

// total=0 is no cap, expire=0 is no end date.
const q1 = M.quota(sample.subscriptions[0].userinfo, 1794982100)
assert.ok(q1.unlimited && q1.endless)
const q2 = M.quota(sample.subscriptions[1].userinfo, 1794982100)
assert.ok(!q2.unlimited && !q2.endless && !q2.expired)
assert.strictEqual(q2.remaining, 536870912000 - 57254535)
assert.strictEqual(q2.daysLeft, 9)
assert.ok(M.quota({ total: 10, download: 20, expire: 5 }, 100).exhausted)
assert.ok(M.quota({ total: 10, download: 20, expire: 5 }, 100).expired)

assert.strictEqual(JSON.stringify(M.age(30)), JSON.stringify({ unit: "now", count: 0 }))
assert.strictEqual(JSON.stringify(M.age(125)), JSON.stringify({ unit: "minutes", count: 2 }))
assert.strictEqual(JSON.stringify(M.age(7200)), JSON.stringify({ unit: "hours", count: 2 }))
assert.strictEqual(JSON.stringify(M.age(86400 * 3)), JSON.stringify({ unit: "days", count: 3 }))


const e = M.shortError(sample.errors[0])
assert.strictEqual(JSON.stringify([e.time, e.level, e.message]), JSON.stringify(["11:06:23", "Warning", "core: Xray 26.10.31 started"]))

// ---- catalogs ----------------------------------------------------------------
const ru = JSON.parse(fs.readFileSync(path.join(ROOT, "i18n/ru.json"), "utf8"))
const en = JSON.parse(fs.readFileSync(path.join(ROOT, "i18n/en.json"), "utf8"))
assert.deepStrictEqual(Object.keys(ru).sort(), Object.keys(en).sort())
for (const [k, v] of Object.entries(ru)) {
  if (typeof v === "object") for (const form of ["one", "few", "many"]) assert.ok(v[form], k + " needs " + form)
}
for (const [k, v] of Object.entries(en)) {
  if (typeof v === "object") for (const form of ["one", "other"]) assert.ok(v[form], k + " needs " + form)
}


// ---- fallback, notifications, rules (CLI round 2) ---------------------------
const fbRaw = Object.assign({}, sample, {
  mode: "node", selected: "0123456789",
  fallback: { enabled: true, node: "abcdefabcd", node_name: "🇫🇮 Helsinki 1", active: true, ready: true,
              problem: null, restart_needed: false },
  notify: false,
  rules: { direct: ["example.com", "Bad Host", "example.org", "example.com", "a_b.com"], tunnel: ["1.1.1.1", "x.com/p"] },
  recent: [{ time: "1", host: "example.com", via: "direct", rule: "direct", count: 2 },
           { time: "2", host: "www.example.com", via: "direct", rule: "direct", count: 1 },
           { time: "3", host: "-rf", via: "tunnel", rule: "weird", count: 1 }]
})
const fb = M.parseStatus(JSON.stringify(fbRaw))
assert.strictEqual(fb.fallback.enabled, true)
assert.strictEqual(fb.fallback.active, true)
assert.strictEqual(fb.fallback.node, "abcdefabcd")
assert.strictEqual(fb.notify, false)
assert.strictEqual(fb.notifyKnown, true)
assert.deepStrictEqual(Array.from(fb.rules.direct), ["example.com", "example.org"])
assert.deepStrictEqual(Array.from(fb.rules.tunnel), ["1.1.1.1"])
assert.strictEqual(fb.recent[0].rule, "direct")
assert.strictEqual(fb.recent[2].rule, "")
assert.strictEqual(fb.recent[2].ruleHost, "")
// active is true only when the core says so; null is "not known yet".
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, fbRaw, { fallback: { active: null } }))).fallback.active, false)
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, fbRaw, { fallback: { node: "../x", problem: "Not A Code" } }))).fallback.node, "")
assert.strictEqual(M.parseStatus(JSON.stringify(sample)).notifyKnown, false)
assert.strictEqual(M.parseStatus(JSON.stringify(sample)).fallback.enabled, false)
// Hosts: only what the CLI would take, and only what the CLI reported.
for (const good of ["example.com", "1.1.1.1", "api.anthropic.com", "xn--p1ai.xn--p1ai"]) assert.strictEqual(M.ruleHost(good), good)
for (const bad of ["-rf", "--help", "localhost", "a_b.com", "x.com/p", "http://x.com", "1.2.3.0/24", "exa…mple.com", "", null, 5, "a b.com"])
  assert.strictEqual(M.ruleHost(bad), "", String(bad))
assert.strictEqual(M.knownHost(fb, "example.com"), true)
assert.strictEqual(M.knownHost(fb, "www.example.com"), true)
assert.strictEqual(M.knownHost(fb, "example.org"), true)
assert.strictEqual(M.knownHost(fb, "evil.com"), false)
assert.strictEqual(M.ruleFor(fb.rules, "www.example.com"), "")
assert.strictEqual(M.ruleFor(fb.rules, "1.1.1.1"), "tunnel")
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.ruleRows(fb.rules))), [
  { host: "example.com", side: "direct" }, { host: "example.org", side: "direct" }, { host: "1.1.1.1", side: "tunnel" }])
// Fallback candidates: plain nodes that answer, not the selected one, fastest
// first; the chosen one stays even when dead.
assert.deepStrictEqual(Array.from(M.fallbackCandidates(s.nodes, "0123456789", "").map(n => n.id)), ["abcdefabcd"])
assert.deepStrictEqual(Array.from(M.fallbackCandidates(s.nodes, "0123456789", "aaaaaaaaaa").map(n => n.id)), ["abcdefabcd", "aaaaaaaaaa"])
assert.deepStrictEqual(Array.from(M.fallbackCandidates(s.nodes, "", "").map(n => n.id)), ["abcdefabcd", "0123456789"])

// ---- core status ------------------------------------------------------------
const core = M.parseCoreStatus('{"version": "26.10.31", "path": "/x", "latest": "26.11.9", "latest_published": "2026-11-09T05:31:16Z", "latest_checked": 1794992543, "update_available": true, "check_error": null, "prev": false, "prev_version": null, "in_progress": false, "update": null}')
assert.strictEqual(core.version, "26.10.31")
assert.strictEqual(core.latest, "26.11.9")
assert.strictEqual(core.published, "2026-11-09")
assert.strictEqual(core.updateAvailable, true)
assert.strictEqual(core.inProgress, false)
assert.strictEqual(core.update, null)
const coreDone = M.parseCoreStatus('text first\n{"version": "26.11.9", "latest": "26.11.9", "update_available": false, "check_error": "HTTP <b>", "prev_version": "26.10.31", "in_progress": false, "update": {"state": "done", "ok": false, "code": "rolled_back", "detail": "new core: probe answered 000; rollback: healthy", "from": "26.10.31", "to": "26.11.9", "started": 10, "finished": 20}}')
assert.strictEqual(coreDone.update.code, "rolled_back")
assert.strictEqual(coreDone.update.ok, false)
assert.strictEqual(coreDone.prevVersion, "26.10.31")
assert.strictEqual(coreDone.checkError, "HTTP <b>")
assert.strictEqual(M.parseCoreStatus('{"update": {"state": "running"}}').inProgress, true)
assert.strictEqual(M.parseCoreStatus('{"version": "1.0; rm -rf", "update": {"state": "weird"}}').version, "")
assert.strictEqual(M.parseCoreStatus('{"update": {"state": "weird"}}').update, null)
assert.strictEqual(M.parseCoreStatus("not json"), null)
assert.strictEqual(M.parseCoreStatus("[1]"), null)
// Results of the new verbs share the {ok, code, detail} line.
assert.deepStrictEqual(JSON.parse(JSON.stringify(M.parseResult('fallback on: Helsinki\n{"ok": true, "code": "restart_needed", "detail": "node probing interval changes on core restart"}'))).code, "restart_needed")
assert.strictEqual(M.parseResult('{"ok": true, "code": "started", "detail": "see xray-omarchy core status", "version": "26.10.31"}').code, "started")

console.log("test_model.js passed")

// ---- first run: setup and the new-subscription form ------------------------
assert.strictEqual(s.setup.known, false)
assert.strictEqual(s.setup.ready, true)
const fresh = M.parseStatus(JSON.stringify(Object.assign({}, sample, { subscriptions: [],
  setup: { version: "0.5.0", helper: true, core: false, core_caps: false, geo: true, ready: false } })))
assert.strictEqual(fresh.setup.known, true)
assert.strictEqual(fresh.setup.ready, false)
assert.strictEqual(fresh.setup.core, false)
assert.strictEqual(fresh.subscriptions.length, 0)
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, sample, { setup: { ready: "yes" } }))).setup.known, false)

assert.strictEqual(M.subscriptionUrl("  https://sub.example.com/api/sub/abc?x=1  "), "https://sub.example.com/api/sub/abc?x=1")
assert.strictEqual(M.subscriptionUrl("http://203.0.113.5:2096/sub"), "http://203.0.113.5:2096/sub")
for (const bad of ["", "ftp://x.com/a", "https://", "https:// x.com", "https://x.com/a b", "vless://id@x.com:443",
                   "https://x.com/\na", "javascript:alert(1)", "https://" + "a".repeat(2000)])
  assert.strictEqual(M.subscriptionUrl(bad), "", bad)
assert.strictEqual(M.subscriptionName("", "https://Sub.Example.com/api/x"), "sub.example.com")
assert.strictEqual(M.subscriptionName("", "https://user@sub.example.com:8443/x"), "sub.example.com")
assert.strictEqual(M.subscriptionName("  Work  ", "https://sub.example.com/x"), "Work")
assert.strictEqual(M.subscriptionName("-rm", "https://sub.example.com/x"), "")
assert.strictEqual(M.subscriptionName("x".repeat(41), ""), "")
assert.strictEqual(M.subscriptionName("", "nonsense"), "")

// ---- package version against the panel's, presets, unpinned core releases ----
assert.strictEqual(fresh.setup.version, "0.5.0")
assert.strictEqual(M.versionOlder("0.5.0", "0.6.0"), true)
assert.strictEqual(M.versionOlder("0.6.0", "0.6.0"), false)
assert.strictEqual(M.versionOlder("0.10.0", "0.9.9"), false)
assert.strictEqual(M.versionOlder("0.9.9", "0.10.0"), true)
assert.strictEqual(M.versionOlder("", "0.6.0"), false)
assert.strictEqual(M.versionOlder("0.5.0", "x"), false)
assert.strictEqual(M.manifestVersion(fs.readFileSync(path.join(ROOT, "manifest.json"), "utf8")),
                   JSON.parse(fs.readFileSync(path.join(ROOT, "manifest.json"), "utf8")).version)
assert.strictEqual(M.manifestVersion("{"), "")
assert.strictEqual(M.manifestVersion('{"version": "1.0.0\\nx"}'), "")
assert.strictEqual(M.componentsOutdated(fresh.setup, "0.6.0"), true)
assert.strictEqual(M.componentsOutdated(fresh.setup, "0.5.0"), false)
assert.strictEqual(M.componentsOutdated(s.setup, "9.9.9"), false)  // the CLI did not say
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, sample, {
  setup: { version: "0.5.0<b>", helper: true, core: true, core_caps: true, geo: true, ready: true } }))).setup.version, "")
assert.strictEqual(s.presets.known, false)
const withPresets = M.parseStatus(JSON.stringify(Object.assign({}, sample, { presets: { russia: true, other: true } })))
assert.strictEqual(withPresets.presets.known, true)
assert.strictEqual(withPresets.presets.russia, true)
assert.strictEqual(withPresets.presets.other, undefined)
assert.strictEqual(M.parseStatus(JSON.stringify(Object.assign({}, sample, { presets: { russia: "yes" } }))).presets.known, false)
assert.strictEqual(M.validPreset("russia"), true)
assert.strictEqual(M.validPreset("--apply"), false)
const unpinned = M.parseCoreStatus('{"version": "26.11.9", "latest": "26.11.9", "release": "26.12.1", "release_pinned": false, "update_available": false}')
assert.strictEqual(unpinned.unpinnedRelease, "26.12.1")
assert.strictEqual(M.parseCoreStatus('{"version": "26.11.9", "latest": "26.11.9", "release": "26.11.9", "release_pinned": true}').unpinnedRelease, "")

console.log("test_model.js first-run checks passed")

// ---- checked sites ------------------------------------------------------------
assert.strictEqual(M.siteUrl("https://www.youtube.com/generate_204"), "https://www.youtube.com/generate_204")
assert.strictEqual(M.siteUrl("  https://ya.ru/  "), "https://ya.ru/")
for (const bad of ["http://ya.ru/", "https://u:p@ya.ru/", "https://ya.ru/a b", "ya.ru", "https://",
                   "https://ya.ru/\u00e9", "https://ya.ru/\u0007", "https://" + "a".repeat(2000) + ".ru/", "", null])
  assert.strictEqual(M.siteUrl(bad), "", "refused: " + String(bad).substring(0, 30))
assert.strictEqual(M.siteName("", "https://www.youtube.com/generate_204"), "www.youtube.com")
assert.strictEqual(M.siteName("YouTube", "https://www.youtube.com/"), "YouTube")
assert.strictEqual(M.siteName("-x", "https://ya.ru/"), "")

// No `sites` from an older CLI: nothing on screen, and no switch.
assert.strictEqual(s.sites.known, false)
assert.strictEqual(s.sites.items.length, 0)
assert.strictEqual(M.sitesStale(s, 90), false)
const siteSample = Object.assign({}, sample, { sites: {
  checked: 1794982080, tunnel: true, notify: true,
  items: [
    { name: "Internet", host: "ya.ru", result: { ok: true, status: 302, ms: 136.4, error: "", via: "direct", node: "", why: "geo", source: "log" } },
    { name: "YouTube", host: "www.youtube.com", result: { ok: false, status: null, ms: null, error: "timeout", via: "tunnel", node: "🇩🇪 Frankfurt 1", why: "", source: "log" } },
    { name: "New", host: "example.org", result: null },
    { name: "", host: "x" }, "junk",
    { name: "Weird", host: "x.org", result: { ok: false, error: "Bad Code", via: "sideways", why: "magic", status: 99999, ms: -5 } }
  ] } })
const ws = M.parseStatus(JSON.stringify(siteSample))
assert.strictEqual(ws.sites.known, true)
assert.strictEqual(ws.sites.notify, true)
assert.strictEqual(ws.sites.items.map(i => i.name).join(), "Internet,YouTube,New,Weird")
assert.strictEqual(ws.sites.items[0].result.ms, 136)
assert.strictEqual(ws.sites.items[0].result.fromLog, true)
assert.strictEqual(ws.sites.items[1].result.node, "🇩🇪 Frankfurt 1")
assert.strictEqual(ws.sites.items[2].result, null)
// Anything the panel does not know is bounded: an unknown error is "other",
// an odd path is the tunnel with no reason, a status out of range is none.
const weird = ws.sites.items[3].result
assert.strictEqual(weird.error, "other")
assert.strictEqual(weird.via, "tunnel")
assert.strictEqual(weird.why, "")
assert.strictEqual(weird.status, 0)
assert.strictEqual(weird.ms, null)
const sum = M.siteSummary(ws.sites)
assert.strictEqual([sum.total, sum.ok, sum.failed.join(), sum.unchecked].join("|"), "4|1|YouTube,Weird|1")
assert.strictEqual(M.validSiteName("YouTube", ws.sites), true)
assert.strictEqual(M.validSiteName("--json", ws.sites), false)
// Stale: a site never checked here.
assert.strictEqual(M.sitesStale(ws, 90), true)
const fresh2 = M.parseStatus(JSON.stringify(Object.assign({}, siteSample, { sites: Object.assign({}, siteSample.sites,
  { items: siteSample.sites.items.slice(0, 2) }) })))
assert.strictEqual(M.sitesStale(fresh2, 90), false)
// Older than 90 s by the CLI's clock, or made with the tunnel in the other state.
assert.strictEqual(M.sitesStale(Object.assign({}, fresh2, { time: fresh2.sites.checked + 91 }), 90), true)
assert.strictEqual(M.sitesStale(Object.assign({}, fresh2, { running: false }), 90), true)
// Capped at ten, names clipped to 40.
const many = M.parseStatus(JSON.stringify(Object.assign({}, sample, { sites: { items:
  Array.from({ length: 50 }, (_, i) => ({ name: "n".repeat(100) + i, host: "h", result: null })) } })))
assert.strictEqual(many.sites.items.length, 10)
assert.ok(many.sites.items[0].name.length <= 40)
console.log("test_model.js site checks passed")
