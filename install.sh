#!/bin/bash
# Install the RØDECaster App (Windows) under Wine for the RODECaster Video.
#
# Downloads the official app from RØDE, checks it is the tested 2.0.115 build,
# sets up a dedicated Wine prefix, applies the compatibility patch and installs
# a launcher. With sudo it also installs udev rules and a NetworkManager
# connection for the RCV's USB network link.
#
#   ./install.sh [--scale PERCENT] [--zip PATH] [--no-system]
#
#   --scale N    UI scale in percent (default 100; 200 suits 4K screens)
#   --zip PATH   use an already-downloaded RODECaster_App_WIN.zip
#   --no-system  skip the steps that need sudo (udev + NetworkManager)
set -euo pipefail

APP_URL="https://update.rode.com/rc-app/RODECaster_App_WIN.zip"
ZIP_SHA256="c0811d9940189999b3387b552d7b47b2a50adc4d0d41edd0b7675ab8234db12d"
EXE_SHA256="53dae274164e040ac0d2077045f6538591aaf718985be3e15cf8edc86f5f7223"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${RODECASTER_LINUX_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/rodecaster-linux}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rodecaster-linux"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

SCALE=100
ZIP=""
SYSTEM=1
while [ $# -gt 0 ]; do
    case "$1" in
        --scale) SCALE="$2"; shift 2 ;;
        --zip) ZIP="$2"; shift 2 ;;
        --no-system) SYSTEM=0; shift ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

step "Checking requirements"
for cmd in wine wineserver 7z python3 curl sha256sum; do
    command -v "$cmd" >/dev/null || die "'$cmd' is required (packages: wine, p7zip/7zip, python3, curl)"
done
WINE_VER=$(wine --version | sed -E 's/^wine-([0-9]+).*/\1/')
if [ "${WINE_VER:-0}" -lt 11 ] 2>/dev/null; then
    echo "warning: tested with Wine 11; you have $(wine --version)"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

step "Getting RODECaster App from RØDE"
if [ -z "$ZIP" ]; then
    ZIP="$WORK/RODECaster_App_WIN.zip"
    curl -fL --progress-bar -o "$ZIP" "$APP_URL"
fi
echo "$ZIP_SHA256  $ZIP" | sha256sum -c --quiet - 2>/dev/null \
    || die "the download is not RODECaster App 2.0.115 (RØDE may have released an update this installer doesn't support yet)"

step "Extracting"
7z x -y -o"$WORK/zip" "$ZIP" >/dev/null
MSI=$(find "$WORK/zip" -name '*.msi' | head -1)
[ -n "$MSI" ] || die "no installer found in the zip"
7z x -y -o"$WORK/msi" "$MSI" >/dev/null
7z x -y -o"$WORK/cab" "$WORK/msi/disk1.cab" >/dev/null

mkdir -p "$DATA_DIR/app" "$DATA_DIR/lib"
# The cab stores short file-table names; restore the real DLL names.
while read -r short long; do
    cp "$WORK/cab/$short" "$DATA_DIR/app/$long"
done <<'EOF'
RODECasterApp.exe RODECasterApp.exe
avcodec61.dll avcodec-61.dll
avdevice61.dll avdevice-61.dll
avfilter10.dll avfilter-10.dll
avformat61.dll avformat-61.dll
avutil59.dll avutil-59.dll
libmp3lame.dll libmp3lame.dll
libmpg1230.dll libmpg123-0.dll
swresample5.dll swresample-5.dll
swscale8.dll swscale-8.dll
EOF
echo "$EXE_SHA256  $DATA_DIR/app/RODECasterApp.exe" | sha256sum -c --quiet - \
    || die "unexpected RODECasterApp.exe"

install -m 644 "$SRC_DIR/lib/patch_vblank.py" "$DATA_DIR/lib/patch_vblank.py"
python3 -I "$DATA_DIR/lib/patch_vblank.py" "$DATA_DIR/app/RODECasterApp.exe"

step "Creating Wine prefix (this can take a minute)"
export WINEPREFIX="$DATA_DIR/prefix" WINEDEBUG=-all
# Keep Wine from adding file associations and menu entries to the desktop.
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
# The app needs neither Mono nor Gecko; skip their install prompts.
WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree,mshtml=" wineboot -u >/dev/null 2>&1
wineserver -w

step "Installing RØDE fonts"
FONTS_MSI="$WORK/msi/AI_ChainedPackageFile.RODEApplicationFonts.msi"
[ -f "$FONTS_MSI" ] || die "fonts installer not found in the MSI"
cp "$FONTS_MSI" "$WORK/RODEApplicationFonts.msi"
wine msiexec /i "$WORK/RODEApplicationFonts.msi" /qn
wineserver -w

step "Installing launcher"
mkdir -p "$BIN_DIR" "$DESKTOP_DIR" "$CONFIG_DIR"
sed "s|^DATA_DIR=.*|DATA_DIR=\"\${RODECASTER_LINUX_HOME:-$DATA_DIR}\"|" "$SRC_DIR/bin/rodecaster-app" > "$BIN_DIR/rodecaster-app"
chmod 755 "$BIN_DIR/rodecaster-app"
if [ ! -f "$CONFIG_DIR/config" ]; then
    cat > "$CONFIG_DIR/config" <<EOF
# rodecaster-linux settings (read by rodecaster-app at each launch)
SCALE=$SCALE            # UI scale in percent (100, 125, 150, 175, 200 ...)
VIRTUAL_DESKTOP=0    # 1 = run inside one resizable Wine virtual desktop window
DESKTOP_SIZE=1920x1080
EOF
fi
cat > "$DESKTOP_DIR/rodecaster-app.desktop" <<EOF
[Desktop Entry]
Name=RØDECaster App
Comment=Control the RØDECaster Video (Windows app under Wine)
Exec=$BIN_DIR/rodecaster-app
Icon=audio-card
Type=Application
Categories=AudioVideo;Audio;Video;
EOF

if [ "$SYSTEM" = 1 ]; then
    step "System setup (needs sudo): udev rules and network connection"
    sudo install -m 644 "$SRC_DIR/system/70-rode.rules" "$SRC_DIR/system/79-rode-usbncm.rules" /etc/udev/rules.d/
    sudo udevadm control --reload
    sudo udevadm trigger --attr-match=idVendor=19f7 || true
    if command -v nmcli >/dev/null; then
        if ! nmcli -t -f NAME con show | grep -qx "RODECaster Video"; then
            nmcli con add type ethernet con-name "RODECaster Video" ifname usbncm0 \
                ipv4.method link-local ipv6.method link-local connection.autoconnect yes >/dev/null
        fi
    else
        echo "NetworkManager not found: give the RCV's USB network interface (usbncm0) a link-local (169.254.x.x) address yourself."
    fi
else
    echo
    echo "Skipped system setup (--no-system). See README for the udev rules and network connection."
fi

step "Done"
cat <<EOF
Start "RØDECaster App" from your applications menu, or run: $BIN_DIR/rodecaster-app

Connect the RODECaster Video to this computer with its SECONDARY USB-C port
(USB 2). If it was already plugged in, unplug and replug it once.
Settings (UI scale etc.): $CONFIG_DIR/config
EOF
