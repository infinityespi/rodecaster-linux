#!/bin/bash
# Remove rodecaster-linux. Pass --system to also remove the udev rules and the
# "RODECaster Video" NetworkManager connection (needs sudo for the rules).
set -euo pipefail

DATA_DIR="${RODECASTER_LINUX_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/rodecaster-linux}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rodecaster-linux"

WINEPREFIX="$DATA_DIR/prefix" wineserver -k 2>/dev/null || true
rm -rf "$DATA_DIR" "$CONFIG_DIR"
rm -f "$HOME/.local/bin/rodecaster-app" "${XDG_DATA_HOME:-$HOME/.local/share}/applications/rodecaster-app.desktop"
echo "Removed the app, its Wine prefix, settings and launcher."

if [ "${1:-}" = "--system" ]; then
    sudo rm -f /etc/udev/rules.d/70-rode.rules /etc/udev/rules.d/79-rode-usbncm.rules
    sudo udevadm control --reload
    nmcli con delete "RODECaster Video" 2>/dev/null || true
    echo "Removed udev rules and the network connection."
fi
