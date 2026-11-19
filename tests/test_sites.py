"""Checked sites in the CLI: the link and name rules, the list in settings.json,
which way a check went (read from the core's access log by the request's local
port, or worked out from the rules), and one notification per change.

The CLI is loaded as a module with every directory pointed at a temporary
copy, so nothing here touches a real tunnel, and nothing goes to the network."""
import atexit
import importlib.machinery
import importlib.util
import json
import os
import shutil
import stat
import sys
import tempfile
import time
import types

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
tmp = tempfile.mkdtemp(prefix="xray-omarchy-test-")
# Gone on every exit, the failing one too.
atexit.register(shutil.rmtree, tmp, True)
for var, sub in (("CONF_DIR", "conf"), ("STATE_DIR", "state"), ("RUN_DIR", "run"), ("ASSET_DIR", "asset"),
                 ("CORE_CACHE", "cache")):
    os.environ["XRAY_OMARCHY_" + var] = os.path.join(tmp, sub)
os.environ["XRAY_OMARCHY_UNIT"] = "xray-omarchy-test-none.service"

loader = importlib.machinery.SourceFileLoader("xray_omarchy_cli", os.path.join(root, "backend", "xray-omarchy"))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


def eq(got, want, what):
    check(got == want, "%s: got %r, want %r" % (what, got, want))


# ---- links ------------------------------------------------------------------
u = cli.site_url("https://www.youtube.com/generate_204")
eq((u["host"], u["port"], u["target"]), ("www.youtube.com", 443, "/generate_204"), "youtube link")
u = cli.site_url("  https://ya.ru  ")
eq((u["url"], u["host"], u["target"]), ("https://ya.ru", "ya.ru", "/"), "bare host, trimmed")
u = cli.site_url("https://Example.COM:8443/a/b?x=1&y=2#frag")
eq((u["host"], u["port"], u["target"]), ("example.com", 8443, "/a/b?x=1&y=2"), "port, query, no fragment")
u = cli.site_url("https://203.0.113.7/")
eq(u["host"], "203.0.113.7", "IPv4 host")
for bad in ["http://ya.ru/", "ftp://ya.ru/", "https://user:pass@ya.ru/", "https://@ya.ru/", "https:///path",
            "https://ya.ru/a b", "https://ya.ru/\x07", "https://localhost/", "https://[::1]/",
            "https://ya.ru:99999/", "https://ya.ru:port/", "https://xn--e1afmkfd.xn--p1ai/é",
            "https://" + "a" * 2000 + ".com/", "", None, 42, "ya.ru", "javascript:alert(1)"]:
    eq(cli.site_url(bad), None, "refused link %r" % (bad if not isinstance(bad, str) else bad[:40]))
check(cli.site_url("https://xn--e1afmkfd.xn--p1ai/") is not None, "punycode host accepted")

# ---- the list in settings.json --------------------------------------------------
raw = {"notify": True, "check_sites": [
    {"name": "Internet", "url": "https://ya.ru/"},
    {"name": "Internet", "url": "https://example.com/"},          # second of a name: dropped
    {"name": "-bad", "url": "https://example.com/"},              # name rule
    {"name": "Plain", "url": "http://example.com/"},              # not https
    "junk", {"name": "NoUrl"},
    {"name": "YouTube", "url": "https://www.youtube.com/generate_204"},
] + [{"name": "S%d" % i, "url": "https://s%d.example.com/" % i} for i in range(20)]}
sites = cli.load_sites(raw)
eq([s["name"] for s in sites[:2]], ["Internet", "YouTube"], "clean list keeps the first of a name")
eq(sites[0]["url"], "https://ya.ru/", "first url kept")
eq(len(sites), cli.SITE_MAX, "capped at SITE_MAX")
eq(cli.load_sites({}), [], "no list: empty, nothing added by itself")
eq(cli.load_sites({"check_sites": "x"}), [], "malformed list: empty")
eq(cli.site_notify_enabled({}), True, "site notifications on by default")
eq(cli.site_notify_enabled({"site_notify": False}), False, "site notifications off")


# The verbs, through argparse-shaped namespaces, against the temporary settings.json.
def run(action, name=None, url=None):
    args = types.SimpleNamespace(action=action, name=name, url=url, json=True)
    out = []
    # The module's own print, caught for the duration: its last line is the JSON.
    cli.print = lambda *a, **k: out.append(" ".join(str(x) for x in a))
    try:
        code = cli.cmd_site(args)
    finally:
        del cli.print
    return code, json.loads(out[-1]) if out else None


os.makedirs(os.environ["XRAY_OMARCHY_CONF_DIR"], exist_ok=True)
with open(cli.SETTINGS_FILE, "w", encoding="utf8") as fh:
    json.dump({"notify": True, "lan_domains": ["lan"]}, fh)
eq(run("add", "Internet", "https://ya.ru/")[1], {"ok": True, "code": "", "detail": "Internet"}, "add")
eq(run("add", "YouTube", "https://www.youtube.com/generate_204")[1]["ok"], True, "add second")
eq(run("add", "Internet", "https://ya.ru/?x=1")[1]["code"], "replaced", "add again: replaced")
eq(run("add", "Plain", "http://ya.ru/")[1]["code"], "insecure_url", "http refused")
eq(run("add", "Bad", "https://u:p@ya.ru/")[1]["code"], "invalid_url", "userinfo refused")
eq(run("add", "-x", "https://ya.ru/")[1]["code"], "invalid_name", "dash name refused")
eq(run("add", None, None)[1]["code"], "usage", "add without arguments")
saved = json.load(open(cli.SETTINGS_FILE, encoding="utf8"))
eq(saved["lan_domains"], ["lan"], "other settings kept")
eq([s["name"] for s in saved["check_sites"]], ["Internet", "YouTube"], "replace keeps the place")
eq(saved["check_sites"][0]["url"], "https://ya.ru/?x=1", "replaced url")
for i in range(8):
    run("add", "S%d" % i, "https://s%d.example.com/" % i)
eq(run("add", "One more", "https://more.example.com/")[1]["code"], "too_many", "eleventh refused")
eq(run("rm", "Nope")[1]["code"], "not_found", "rm unknown")
eq(run("rm", "S0")[1]["ok"], True, "rm")
eq(run("notify", "off")[1]["detail"], "off", "notify off")
eq(json.load(open(cli.SETTINGS_FILE, encoding="utf8"))["site_notify"], False, "notify saved")
eq(run("notify", "maybe")[1]["code"], "usage", "notify garbage")

# ---- which way a check went: the core's access log ----------------------------
# Lines as xray writes them (the source is the TUN side of this machine's socket).
LOG = """\
2026/11/19 16:07:24.605763 from tcp:172.19.0.1:43558 accepted tcp:203.0.113.10:443 [tun -> x-0123456789]
2026/11/19 16:07:39.440624 from tcp:172.19.0.1:36862 accepted tcp:198.51.100.20:443 [tun -> direct]
2026/11/19 16:07:39.440632 from tcp:172.19.0.1:3686 accepted tcp:198.51.100.21:443 [tun >> x-abcdefabcd]
2026/11/19 16:07:40.000001 from 127.0.0.1:50000 accepted udp:1.1.1.1:53 [dns-in -> dns-out]
2026/11/19 16:07:41.000001 from tcp:172.19.0.1:50111 accepted tcp:203.0.113.66:443 [tun -> block]
2026/11/19 16:07:42.000001 from tcp:172.19.0.1:43558 accepted tcp:203.0.113.10:443 [tun >> x-aaaaaaaaaa]
not a log line at all
""".splitlines()
eq(cli.route_from_log(LOG, 36862), "direct", "direct by port")
eq(cli.route_from_log(LOG, 3686), "x-abcdefabcd", "balancer line, port that is a suffix of another")
eq(cli.route_from_log(LOG, 43558), "x-aaaaaaaaaa", "the newest line of a reused port wins")
eq(cli.route_from_log(LOG, 43558, "203.0.113.11"), None, "port reused for another address")
eq(cli.route_from_log(LOG, 36862, "198.51.100.20", 8443), None, "another destination port")
eq(cli.route_from_log(LOG, 50111, "203.0.113.66", 443), "block", "blocked")
eq(cli.route_from_log(LOG, 50000), None, "not from the TUN")
eq(cli.route_from_log(LOG, 6862), None, "no partial port match")
eq(cli.route_from_log([], 1), None, "empty log")

st = cli.load_settings()
st["direct_geo"] = {"geosite": ["category-ru"], "geoip": ["ru"], "domains": ["ru", "su"]}
rules = {"direct": ["example.org"], "tunnel": ["mail.example.org"]}
names = {"x-0123456789": "Helsinki 1", "x-abcdefabcd": "Frankfurt 1"}
P = cli.site_path
eq(P("www.youtube.com", "203.0.113.10", "x-0123456789", True, rules, st, names),
   {"via": "tunnel", "node": "Helsinki 1", "why": "", "source": "log"}, "via a node, from the log")
# A public address (the documentation ranges count as private, like geoip:private).
eq(P("ya.ru", "87.250.250.242", "direct", True, rules, st, names),
   {"via": "direct", "node": "", "why": "geo", "source": "log"}, "direct by the preset, from the log")
eq(P("example.org", "93.184.215.14", "direct", True, rules, st, names),
   {"via": "direct", "node": "", "why": "rule", "source": "log"}, "direct by a site rule")
eq(P("mail.example.org", "198.51.100.20", "x-abcdefabcd", True, rules, st, names),
   {"via": "tunnel", "node": "Frankfurt 1", "why": "rule", "source": "log"}, "tunnel by a longer rule")
eq(P("www.example.org", "198.51.100.20", None, True, rules, st, names)["via"], "direct",
   "subdomain of a direct rule, predicted")
eq(P("x.ru", "", None, True, rules, st, names, lambda: "Helsinki 1"),
   {"via": "direct", "node": "", "why": "geo", "source": "rules"}, "predicted: a direct zone")
eq(P("www.youtube.com", "", None, True, rules, st, names, lambda: "Helsinki 1"),
   {"via": "tunnel", "node": "Helsinki 1", "why": "", "source": "rules"}, "predicted: the tunnel, current node")
eq(P("printer.lan", "", None, True, {"direct": [], "tunnel": []}, st, names)["why"], "local", "LAN name")
eq(P("www.youtube.com", "203.0.113.10", None, False, rules, st, names),
   {"via": "direct", "node": "", "why": "tunnel_off", "source": "rules"}, "tunnel off")
eq(cli.site_way({"via": "direct", "why": "tunnel_off"}), "direct, tunnel off", "way: tunnel off")
eq(cli.site_way({"via": "tunnel", "node": "Helsinki 1"}), "via Helsinki 1", "way: node")
eq(cli.site_error_text({"error": "http_status", "status": 503}), "answered 503", "error text with a status")
eq(cli.site_error_text({"error": "weird"}), "failed", "unknown error code")

# ---- `status` reads the list and the last check, no network --------------------
os.makedirs(os.environ["XRAY_OMARCHY_STATE_DIR"], exist_ok=True)
cli.write_json(cli.SITES_FILE, {"time": 1795000000, "tunnel": True, "results": [
    {"name": "Internet", "url": "https://ya.ru/?x=1", "host": "ya.ru", "ok": True, "status": 302, "ms": 136,
     "error": "", "via": "direct", "node": "", "why": "geo", "source": "log"},
    {"name": "YouTube", "url": "https://old.example.com/", "ok": True}]})
ss = cli.sites_status()
eq(ss["items"][0]["result"]["ms"], 136, "status: the last result of a site")
eq(ss["items"][1]["result"], None, "status: a result for another link is not this site's")
eq(ss["checked"], 1795000000, "status: when")
eq(ss["notify"], False, "status: the switch")

# ---- notifications: one per change, three failures in a row first ---------------
eq(cli.SITE_CONFIRM, 3, "three failed checks before unreachable")
eq(cli.SITE_TIMEOUT, 10, "ten seconds for a check")


def snap(ok, way="log", error="timeout", name="YouTube", node="Helsinki 1"):
    r = {"name": name, "ok": ok, "ms": 164 if ok else None, "status": 204 if ok else None,
         "error": "" if ok else error, "via": "tunnel", "node": node, "why": "", "source": way}
    return {"time": 1795000000, "protection": {"ok": True, "codes": []}, "sites": [r]}


memory, daily = {}, {}
E = lambda s: [(e[0], e[2]) for e in cli.watch_events(s, memory, daily, 2)]
eq(E(snap(True)), [], "first good check: nothing")
eq(E(snap(False)), [], "one failure: nothing yet")
eq(E(snap(False)), [], "two failures: nothing yet")
eq(E(snap(False)), [("site_down", "Site unreachable: YouTube (via Helsinki 1)")], "third failure: unreachable")
eq(E(snap(False)), [], "fourth failure: no repeat")
eq(E({"time": 1, "protection": {"ok": True}}), [], "a poll without a check changes nothing")
eq(E(snap(True)), [("site_up", "Site is back: YouTube (via Helsinki 1)")], "good again: back")
eq(E(snap(True)), [], "good again: no repeat")
eq(E(snap(False)), [], "one blip: nothing")
eq(E(snap(False)), [], "two blips: nothing")
eq(E(snap(True)), [], "blips over: nothing, the streak is reset")
eq(E(snap(False)), [], "failure 1")
eq(E(snap(False)), [], "failure 2")
# The way named is the failing check's own, not the last good one's.
eq(E(snap(False, node="Frankfurt 1")), [("site_down", "Site unreachable: YouTube (via Frankfurt 1)")],
   "unreachable names this check's node")
eq(memory["sites"]["YouTube"]["state"], "down", "memory: down")
E({"time": 1, "protection": {"ok": True}, "sites": []})
eq(memory["sites"], {}, "a site taken off the list leaves memory")
# The name did not resolve: no log line, and nothing but the default sends it
# anywhere; it took no way, and the notification does not invent one.
memory = {"sites": {"YouTube": {"state": "ok", "streak": 2, "way": "via Helsinki 1"}}}
eq(E(snap(False, way="rules", error="dns_failed")), [("site_down", "Site unreachable: YouTube (way unknown)")],
   "no log line, no rule: way unknown")
eq("way" in memory["sites"]["YouTube"], False, "the old remembered way is dropped")
# Worked out from the rules but certain: a direct zone, a rule, the tunnel off.
r = snap(False, way="rules", error="dns_failed")
r["sites"][0].update(via="direct", node="", why="geo")
eq(cli.watch_events(r, {"sites": {"YouTube": {"state": "ok", "streak": 2}}}, {}, 2)[0][2],
   "Site unreachable: YouTube (direct)", "a direct zone from the rules: named")
r["sites"][0].update(why="tunnel_off")
eq(cli.watch_events(r, {"sites": {"YouTube": {"state": "ok", "streak": 2}}}, {}, 2)[0][2],
   "Site unreachable: YouTube (direct, tunnel off)", "tunnel off: named")
memory = {}
eq(E(snap(False, name="New")), [], "a new site failing: not at once")
eq(E(snap(False, name="New")), [], "a new site failing twice: not yet")
eq([e[0] for e in E(snap(False, name="New"))], ["site_down"], "a site down from the start is reported")
s503 = snap(False, error="http_status", name="X")
s503["sites"][0]["status"] = 503
body = cli.watch_events(s503, {"sites": {"X": {"state": "ok", "streak": 2}}}, {}, 2)[0][3]
eq(body, "Answered 503, 3 checks in a row.", "body for an http status")

# ---- the request looks like a browser's, not this program's ---------------------
check("xray" not in (cli.SITE_UA + cli.SITE_HEADERS).lower() and "omarchy" not in cli.SITE_UA.lower(),
      "no program name in the request")
check(cli.SITE_UA.startswith("Mozilla/5.0 (X11; Linux x86_64; rv:") and "Firefox/" in cli.SITE_UA,
      "an ordinary Firefox for Linux User-Agent")

# ---- the checks' own connections stay out of `recent` ---------------------------
os.makedirs(cli.RUN_DIR, exist_ok=True)
T = time.strftime("%Y/%m/%d %H:%M:%S", time.localtime(1795000000))
T_LATER = time.strftime("%Y/%m/%d %H:%M:%S", time.localtime(1795000000 + 600))
with open(cli.ACCESS_LOG, "w", encoding="utf8") as fh:
    fh.write("""%(t)s.000001 from tcp:172.19.0.1:40001 accepted tcp:203.0.113.10:443 [tun -> x-0123456789]
%(t)s.000002 from tcp:172.19.0.1:40002 accepted tcp:198.51.100.20:443 [tun -> direct]
%(t)s.000003 from tcp:172.19.0.1:40003 accepted tcp:203.0.113.10:443 [tun -> x-0123456789]
%(later)s.000004 from tcp:172.19.0.1:40001 accepted tcp:203.0.113.10:443 [tun -> x-0123456789]
""" % {"t": T, "later": T_LATER})
cli.remember_probes(1795000000, [{"src_port": 40001, "ip": "203.0.113.10", "port": 443},
                                 {"src_port": 40002, "ip": "198.51.100.20", "port": 443},
                                 {"src_port": 0, "ip": "", "port": 443}])
probes = cli.load_probes()
eq(sorted(probes), [(40001, "203.0.113.10", 443), (40002, "198.51.100.20", 443)], "probes kept: port, address, port")
rec = cli.recent_connections({"x-0123456789": "Helsinki 1"}, rules={"direct": [], "tunnel": []})
eq(sorted((r["host"], r["count"]) for r in rec), [("203.0.113.10", 2)],
   "recent: the checks' own lines left out, the user's own (another port, the same port later) kept")
check(not cli.is_probe(probes, T, "tcp:172.19.0.1:40001", "203.0.113.11", "443"), "another address: not a probe")
check(not cli.is_probe(probes, T, "tcp:172.19.0.1:40001", "203.0.113.10", "8443"), "another port: not a probe")
check(cli.is_probe(probes, T, "tcp:172.19.0.1:40001", "203.0.113.10", "443"), "same port, address, time: probe")
# Entries older than the log's first line can match nothing and are dropped.
with open(cli.ACCESS_LOG, "w", encoding="utf8") as fh:
    fh.write("%s.000001 from tcp:172.19.0.1:40009 accepted tcp:203.0.113.10:443 [tun -> direct]\n" % T_LATER)
cli.remember_probes(1795000000 + 600, [{"src_port": 40009, "ip": "203.0.113.10", "port": 443}])
eq(sorted(cli.load_probes()), [(40009, "203.0.113.10", 443)], "probes older than the log are pruned")

# The connection is noted before it is made: `recent` knows it while the
# check still runs. A closed port on this machine; nothing leaves it.
import socket
probe_sock = socket.socket()
probe_sock.bind(("127.0.0.1", 0))
closed_port = probe_sock.getsockname()[1]
probe_sock.close()
noted = []
box = {"ok": False, "status": 0, "ms": None, "error": "", "ip": "", "src_port": 0, "done": False}
cli.check_site({"host": "127.0.0.1", "port": closed_port, "target": "/"}, time.monotonic() + 5, box, noted.append)
eq(box["error"], "refused", "closed port: refused")
eq([(n["src_port"], n["ip"], n["port"]) for n in noted], [(box["src_port"], "127.0.0.1", closed_port)],
   "the connection noted before connecting, with its local port")
check(box["src_port"] > 0, "a local port even for a connection that never completes")

# ---- reading the log from where it ended before the check ------------------------
size = cli.log_size(cli.ACCESS_LOG)
with open(cli.ACCESS_LOG, "a", encoding="utf8") as fh:
    fh.write("after the start\n")
eq(cli.read_from(cli.ACCESS_LOG, size), ["after the start"], "only what came after the start")
eq(cli.read_from(cli.ACCESS_LOG, 10 ** 9)[-1], "after the start", "a trimmed log is read whole")
eq(cli.read_from(os.path.join(tmp, "none.log"), 0), [], "no log")

# ---- private files: a temporary of its own, nothing left behind -----------------
target = os.path.join(tmp, "private", "x.json")
cli.write_json(target, {"a": 1})
cli.write_json(target, {"a": 2})
eq(json.load(open(target, encoding="utf8")), {"a": 2}, "written")
eq(os.listdir(os.path.dirname(target)), ["x.json"], "no temporary file left")
eq(stat.S_IMODE(os.stat(target).st_mode), 0o600, "mode 0600")

# The panel words every error code the CLI sends, and no other.
en = json.load(open(os.path.join(root, "i18n", "en.json"), encoding="utf8"))
eq({k[len("sites.err."):] for k in en if k.startswith("sites.err.")}, set(cli.SITE_ERROR_TEXT),
   "catalog error codes are the CLI's")

if failures:
    sys.exit("test_sites.py: %d failed" % failures)
print("test_sites.py passed")
