"""One version in four places (manifest.json, PKGBUILD, the CLI, Model.js): the panel
compares the package's version with its own, and its running code with the manifest on disk. And core-sums.json pins something."""
import json
import os
import re
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
manifest = json.load(open(os.path.join(root, "manifest.json"), encoding="utf8"))["version"]
pkgbuild = re.search(r"^pkgver=(\S+)$", open(os.path.join(root, "backend/PKGBUILD"), encoding="utf8").read(), re.M)
cli = re.search(r'^VERSION = "([^"]+)"$', open(os.path.join(root, "backend/xray-omarchy"), encoding="utf8").read(), re.M)
panel = re.search(r'^var PANEL_VERSION = "([^"]+)"$', open(os.path.join(root, "Model.js"), encoding="utf8").read(), re.M)
found = (manifest, pkgbuild and pkgbuild.group(1), cli and cli.group(1), panel and panel.group(1))
if len(set(found)) != 1:
    sys.exit("versions differ: manifest %s, PKGBUILD %s, CLI %s, Model.js %s" % found)
print("version %s: manifest, PKGBUILD, CLI and Model.js agree" % manifest)

sums = json.load(open(os.path.join(root, "backend/core-sums.json"), encoding="utf8"))
versions = sums.get("versions") or {}
bad = [v for v, e in versions.items()
       if not re.fullmatch(r"[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}", v)
       or not re.fullmatch(r"[0-9a-f]{64}", (e or {}).get("x86_64", ""))]
if not versions or bad:
    sys.exit("core-sums.json: no pinned versions, or bad entries: %s" % bad)
print("core-sums.json: %d pinned versions (%s)" % (len(versions), ", ".join(versions)))
