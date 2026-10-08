#!/usr/bin/env bash
# Install or remove albumshift for the current user
# Usage  ./install.sh [--uninstall]
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/albumshift.conf"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/albumshift"

if [ "${1:-}" = "--uninstall" ]; then
    systemctl --user disable --now albumshift.timer 2>/dev/null || true
    rm -f "$BIN/albumshift" "$UNITS/albumshift.service" "$UNITS/albumshift.timer"
    systemctl --user daemon-reload
    echo "Removed albumshift. Config left at $CONF, cache at $CACHE"
    exit 0
fi

missing=()
for cmd in python3 shuf plasma-apply-wallpaperimage; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
command -v magick &>/dev/null || command -v convert &>/dev/null || missing+=("ImageMagick")
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing dependencies, ${missing[*]}" >&2
    echo "On Fedora/Nobara  sudo dnf install python3 ImageMagick" >&2
    exit 1
fi

mkdir -p "$BIN" "$UNITS"
install -m 755 "$SRC/albumshift" "$BIN/albumshift"
install -m 644 "$SRC/systemd/albumshift.service" "$UNITS/albumshift.service"
install -m 644 "$SRC/systemd/albumshift.timer" "$UNITS/albumshift.timer"

if [ ! -f "$CONF" ]; then
    install -m 644 "$SRC/albumshift.conf.example" "$CONF"
    echo "Created $CONF, set ALBUM_URL then run  albumshift refresh"
else
    echo "Kept existing config at $CONF"
fi

systemctl --user daemon-reload
systemctl --user enable --now albumshift.timer
echo "Installed. Timer enabled, rotating every 15 minutes"
