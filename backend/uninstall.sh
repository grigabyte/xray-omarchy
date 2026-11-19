#!/usr/bin/env bash
# Removes the xray-omarchy package. The package's removal script takes the
# tunnel down for every logged-in user, puts routes, the killswitch table and
# the system DNS (as saved) back, and deletes the xray core with its
# capabilities (/var/lib/xray-omarchy). Your data stays unless you agree to delete it.
#   uninstall.sh [--yes] [--purge]
set -euo pipefail
yes=0; purge=0
for arg in "$@"; do
  case $arg in --yes) yes=1 ;; --purge) purge=1 ;; *) echo "usage: uninstall.sh [--yes] [--purge]" >&2; exit 2 ;; esac
done
noconfirm=()
(( yes )) && noconfirm=(--noconfirm)
ask() { (( yes )) && return 0; local a; read -r -p "$1 [y/N] " a; [[ $a == [yY]* ]]; }

# Asked before anything changes: a "no" leaves the tunnel as it was.
installed=0
if pacman -Q xray-omarchy >/dev/null 2>&1; then
  installed=1
  ask "Remove the package xray-omarchy?" || exit 130
fi
if command -v xray-omarchy >/dev/null; then
  xray-omarchy off || true
  systemctl --user disable --now xray-omarchy.service xray-omarchy-watch.service \
    xray-omarchy-update.timer xray-omarchy-trim.timer 2>/dev/null || true
fi
if (( installed )); then
  sudo pacman -R "${noconfirm[@]}" xray-omarchy
fi
# ~/.local/lib/xray-omarchy: the per-user core of version 0.5, if it is still there.
rm -rf -- ~/.local/lib/xray-omarchy
data=(~/.config/xray-omarchy ~/.local/state/xray-omarchy ~/.local/share/xray-omarchy ~/.cache/xray-omarchy)
if (( purge )) || { (( ! yes )) && ask "Also delete your subscriptions and settings (${data[*]})?"; }; then
  rm -rf -- "${data[@]}"
  echo "Data removed."
fi
echo "xray-omarchy is removed. Remove the panel with: omarchy plugin remove grigabyte.xray-omarchy"
