#!/usr/bin/env bash
# Rewrites sha256sums in PKGBUILD from the files as they are now (run after any
# change to a packaged file; `make test` fails while they differ).
#   backend/update-sums.sh [--check]
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r "$here"/. "$tmp"/
cp "$here/../LICENSE" "$tmp/LICENSE"
sums=$(cd "$tmp" && makepkg -g 2>/dev/null)
[[ $sums == sha256sums=\(* ]] || { echo "makepkg -g failed" >&2; exit 1; }
python3 -I - "$here/PKGBUILD" "$sums" "${1:-}" <<'PY'
import re, sys
path, sums, mode = sys.argv[1:]
text = open(path, encoding="utf8").read()
new = re.sub(r"sha256sums=\([^)]*\)", lambda m: sums, text, count=1)
if mode == "--check":
    if new != text:
        sys.exit("PKGBUILD sha256sums are stale: run backend/update-sums.sh")
    print("PKGBUILD sha256sums: current")
else:
    open(path, "w", encoding="utf8").write(new)
    print("PKGBUILD sha256sums updated")
PY
