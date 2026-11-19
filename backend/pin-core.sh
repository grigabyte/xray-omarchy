#!/usr/bin/env bash
# Maintainer tool: pins xray core releases for the package. For every VERSION it
# downloads the official Xray-linux-64.zip and its .dgst from the XTLS release,
# checks the zip against the .dgst, and writes the zip's SHA-256 into
# core-sums.json (installed as /usr/share/xray-omarchy/core-sums.json; the root
# helper installs only a zip with one of these sums). Then bump pkgver and run
# update-sums.sh.
#   backend/pin-core.sh [--keep DIR] VERSION...      e.g. 26.11.9 26.10.31
# --keep DIR leaves the zips in DIR/VERSION/ (a test stand uses them offline).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
keep=""
if [[ ${1:-} == --keep ]]; then keep=$2; shift 2; fi
(( $# )) || { echo "usage: pin-core.sh [--keep DIR] VERSION..." >&2; exit 2; }
base=https://github.com/XTLS/Xray-core/releases/download
asset=Xray-linux-64.zip
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pairs=()
for ver in "$@"; do
  [[ $ver =~ ^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$ ]] || { echo "bad version: $ver" >&2; exit 2; }
  dir="$tmp/$ver"; mkdir -p "$dir"
  curl -fsSL --max-filesize $((64 << 20)) -o "$dir/$asset" "$base/v$ver/$asset"
  curl -fsSL --max-filesize 65536 -o "$dir/$asset.dgst" "$base/v$ver/$asset.dgst"
  sum=$(sha256sum "$dir/$asset" | cut -d' ' -f1)
  want=$(grep -oiE 'SHA2-256 *= *[0-9a-f]{64}' "$dir/$asset.dgst" | grep -oiE '[0-9a-f]{64}' | tr A-F a-f)
  [[ $sum == "$want" ]] || { echo "$ver: zip $sum does not match the release's .dgst ($want)" >&2; exit 1; }
  echo "$ver  $sum  (matches the release's .dgst)"
  pairs+=("$ver=$sum")
  if [[ -n $keep ]]; then mkdir -p "$keep/$ver"; cp "$dir/$asset" "$dir/$asset.dgst" "$keep/$ver/"; fi
done
python3 -I - "$here/core-sums.json" "${pairs[@]}" <<'PY'
import json, sys
path, pairs = sys.argv[1], sys.argv[2:]
try:
    data = json.load(open(path, encoding="utf8"))
except (OSError, ValueError):
    data = {}
versions = data.get("versions") or {}
for pair in pairs:
    ver, sha = pair.split("=")
    versions.setdefault(ver, {})["x86_64"] = sha
key = lambda v: tuple(int(x) for x in v.split("."))
data = {
    "schemaVersion": 1,
    "comment": "SHA-256 of the official Xray-linux-64.zip per xray version, checked against the "
               "release's .dgst when pinned (backend/pin-core.sh). The root helper installs only these.",
    "source": "https://github.com/XTLS/Xray-core/releases/download/",
    "assets": {"x86_64": "Xray-linux-64.zip"},
    "versions": {v: versions[v] for v in sorted(versions, key=key, reverse=True)},
}
with open(path, "w", encoding="utf8") as fh:
    json.dump(data, fh, indent=1)
    fh.write("\n")
print("core-sums.json: %s" % ", ".join(data["versions"]))
PY
