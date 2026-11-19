#!/usr/bin/env bash
# Installs or updates what the Xray panel needs: the xray-omarchy package (built
# here with makepkg from this folder) and the xray core. Run by the panel's
# "Install required components…" / "Update components…" in a floating
# terminal, or by hand.
#   install.sh [--yes]     --yes: no questions (pacman's included); for tests
#   install.sh --check     only check that pacman can install what is missing
#                          (no sudo, no changes): 0 yes, 3 the package databases
#                          are out of date. The panel runs it before it opens
#                          the terminal.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
yes=0
check=0
[[ ${1:-} == --yes ]] && yes=1
[[ ${1:-} == --check ]] && check=1
noconfirm=()
(( yes )) && noconfirm=(--noconfirm)

say() { printf '\033[1m%s\033[0m\n' "$*"; }
ask() {  # ask "question" -> 0 for yes
  (( yes )) && return 0
  local answer=""
  read -r -p "$1 [y/N] " answer || true
  [[ $answer == [yY]* ]]
}

if (( EUID == 0 )); then
  echo "Run this as your own user, not root: the tunnel belongs to you." >&2
  exit 1
fi

# What pacman has to install: base-devel when makepkg is missing, and the
# package's dependencies that are not installed yet.
tools=()
if ! command -v makepkg >/dev/null || ! command -v fakeroot >/dev/null; then tools=(base-devel); fi
mapfile -t deps < <(bash -c 'source "$1" && pacman -T "${depends[@]}"' _ "$here/PKGBUILD" 2>/dev/null || true)
need=("${tools[@]}" "${deps[@]}")
# A fresh Omarchy knows only the installer's offline package list until its
# first `omarchy update`: v2ray-geoip and v2ray-domain-list-community are not
# in it ("target not found"). The databases are not synced here: `pacman -Sy`
# without the upgrade is a partial upgrade, which Arch does not support. The
# check is `pacman -Sp` (prints the download URLs, reads the local databases
# only: no network, no sudo, no changes), before anything is asked.
if (( ${#need[@]} )) && ! pacman -Sp --print-format %n -- "${need[@]}" >/dev/null 2>&1; then
  echo "pacman cannot find: ${need[*]}" >&2
  echo "Your package databases are out of date. Run \`omarchy update\` first, then use the Xray panel button again." >&2
  exit 3
fi
(( check )) && exit 0

version=$(sed -n 's/^pkgver=//p' "$here/PKGBUILD")
installed=$(pacman -Q xray-omarchy 2>/dev/null | awk '{print $2}' || true)

if [[ -n $installed ]]; then title="update ($installed -> $version)"; else title="install ($version)"; fi
cat <<TEXT
Xray for Omarchy — $title

This will install:
  • the package xray-omarchy, built here from the plugin's backend/ folder:
      /usr/bin/xray-omarchy                          the CLI the panel talks to
      /usr/lib/xray-omarchy/xray-omarchy-helper      the only part that runs as root
      /etc/sudoers.d/xray-omarchy                    lets group wheel run that helper without a password
      /usr/share/xray-omarchy/core-sums.json         SHA-256 of the xray releases the helper may install
      systemd units                                  the tunnel and its timers (per user),
                                                     the killswitch at boot (system)
  • its dependencies from the Arch repositories: python, nftables, networkmanager,
    libcap, libnotify, curl, v2ray-geoip, v2ray-domain-list-community
  • the xray core: the official XTLS release (Xray-linux-64.zip from github.com/XTLS),
    into /var/lib/xray-omarchy/core by the helper.
    Its SHA-256 must equal the one pinned in this package. That check catches a damaged
    or swapped download and a release file changed after it was pinned; it does not
    vouch for the release itself — it only says this is the file the package was made for.

sudo asks for your password once, in this terminal, for pacman.
Nothing changes in your network until you turn the tunnel on.
TEXT
echo
ask "Continue?" || { echo "Nothing was installed."; exit 130; }

if ! id -nG | tr ' ' '\n' | grep -qx wheel; then
  echo "Your user is not in the group wheel: the helper's sudo rule will not apply to you." >&2
  echo "Add it first (sudo usermod -aG wheel $USER, then log in again)." >&2
  exit 1
fi

# A separate step, like any grant of root: what exactly runs without a password.
cat <<'TEXT'

Administrator rights without a password

/etc/sudoers.d/xray-omarchy lets every member of group wheel on this computer run
/usr/lib/xray-omarchy/xray-omarchy-helper as root without a password — and nothing else.
The helper does only this, every argument checked:
  route up|down            ip rules and table 7000 into the tunnel device xray-omarchy0
  killswitch on|off|status the nftables table inet xray-omarchy (and at boot, if it was on)
  dns on|off|list          the DNS of the active NetworkManager connection: saved first,
                           pointed to the core, and put back exactly as saved
  core stage|activate|rollback
                           the xray core in /var/lib/xray-omarchy/core with CAP_NET_ADMIN
                           and CAP_NET_BIND_SERVICE — only a zip whose SHA-256 this package pins;
                           it can be run only by root and group wheel (not by other local users)
  reset                    undo all of the above (run when the package is removed)
The panel needs this to switch the tunnel without asking for a password each time.
TEXT
if (( ! yes )); then
  answer=""
  read -r -p "Type HELPER to allow this (Enter cancels): " answer || true
  if [[ $answer != HELPER ]]; then
    echo "Nothing was installed${installed:+; the installed package $installed is left as it was}."
    exit 130
  fi
fi

# pacman runs here, through one sudo, and makepkg only builds: makepkg's own
# --syncdeps/--install call `sudo -k pacman`, which asks for the password again
# at each step, while the text above promises one prompt.
if (( ${#tools[@]} )); then
  say "==> makepkg needs base-devel"
  sudo pacman -S --needed "${noconfirm[@]}" -- base-devel
fi
if (( ${#deps[@]} )); then
  say "==> Installing the dependencies: ${deps[*]}"
  sudo pacman -S --needed --asdeps "${noconfirm[@]}" -- "${deps[@]}"
fi

# Built in a temporary copy: makepkg writes next to the PKGBUILD, and any write
# inside the plugin folder reloads the shell.
build=$(mktemp -d -t xray-omarchy-build.XXXXXX)
# The plugin folder may be read-only (and copies keep that mode): make the copy
# writable so cleanup works, and drop interpreter caches that tests leave behind.
trap 'chmod -R u+w "$build" 2>/dev/null; rm -rf "$build"' EXIT
cp -r "$here"/. "$build"/
chmod -R u+w "$build"
find "$build" -name __pycache__ -prune -exec rm -rf {} +
cp "$here/../LICENSE" "$build/LICENSE"
say "==> Building the package"
( cd "$build" && makepkg --clean --cleanbuild --force )
# --packagelist follows PKGDEST if the user's makepkg.conf sets one. It also
# names a -debug package that makepkg did not build (no binaries here).
pkgfiles=()
while IFS= read -r f; do
  [[ -f $f && ${f##*/} == xray-omarchy-"$version"-* ]] && pkgfiles+=("$f")
done < <(cd "$build" && makepkg --packagelist)
(( ${#pkgfiles[@]} == 1 )) || { echo "makepkg built no package xray-omarchy-$version" >&2; exit 1; }
say "==> Installing the package"
sudo pacman -U "${noconfirm[@]}" -- "${pkgfiles[@]}"

# 0.5 kept a per-user copy of the core (with capabilities) here: no longer used.
if [[ -e $HOME/.local/lib/xray-omarchy ]]; then
  rm -rf -- "$HOME/.local/lib/xray-omarchy"
  echo "Removed the old per-user core (~/.local/lib/xray-omarchy)."
fi

# The core only when it is missing or lost its capabilities: a newer one replaces
# the running core and restarts the tunnel, so that is left to the panel's Core page.
core_state=$(xray-omarchy status --json | tail -n 1 | python3 -I -c '
import json, sys
s = json.load(sys.stdin).get("setup") or {}
print("missing" if not s.get("core") else ("nocaps" if not s.get("core_caps") else "ok"))')
case $core_state in
  missing)
    say "==> Installing the xray core"
    if ! xray-omarchy core update; then
      xray-omarchy core status || true
      echo "The core was not installed; the panel will offer this again." >&2
      exit 1
    fi ;;
  nocaps)
    say "==> Giving the xray core its network permissions back"
    current=$(xray-omarchy core status --json | tail -n 1 | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("version") or "")')
    xray-omarchy core update --force --to "$current" ;;
  *)
    say "==> The xray core is already installed (newer versions: the panel's Core page)" ;;
esac

say "==> Enabling the timers and the notifications"
if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user enable xray-omarchy-update.timer xray-omarchy-trim.timer xray-omarchy-watch.service
  systemctl --user start xray-omarchy-update.timer xray-omarchy-trim.timer || true
else
  echo "No systemd user session here: run later, in your desktop session:" >&2
  echo "  systemctl --user enable --now xray-omarchy-update.timer xray-omarchy-trim.timer xray-omarchy-watch.service" >&2
fi

if (( ! yes )) && [[ -z $(xray-omarchy sub list) ]]; then
  echo
  echo "Add a subscription now? Paste its URL (https://…), or press Enter to do it later in the panel."
  read -r -p "URL: " url || url=""
  if [[ -n $url ]]; then
    host=$(python3 -I -c 'import sys, urllib.parse as u; print(u.urlsplit(sys.argv[1]).hostname or "")' "$url")
    read -r -p "Name [${host:-subscription}]: " name || name=""
    name=${name:-${host:-subscription}}
    xray-omarchy sub add -- "$name" "$url" && xray-omarchy update --name "$name" || true
  fi
fi

echo
if systemctl --user is-active --quiet xray-omarchy.service 2>/dev/null; then
  say "Done. The tunnel is on."
else
  say "Done. Turn the tunnel on from the Xray panel in the bar (or: xray-omarchy on)."
fi
