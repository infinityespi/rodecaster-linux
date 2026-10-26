# rodecaster-linux

Run RØDE's **RØDECaster App** on Linux to control a **RØDECaster Video**: Scene Builder, Audio Mixer, device configuration, firmware info, all of it. It uses Wine plus a few fixes found by reverse-engineering why the Windows app didn't work under Wine.

This repo contains **no RØDE software**. The installer downloads the official app from RØDE's own update server (the same URL the app uses to update itself), checks it is the tested version, and applies the fixes on your machine.

> Unofficial and not affiliated with RØDE. Use at your own risk, and read RØDE's licence terms for the app.

## Tested with

| | |
|---|---|
| Device | RØDECaster Video, firmware 1.4.03.1549 |
| App | RØDECaster App **2.0.115** (Windows build) |
| Wine | 11.0 (staging) |
| System | Fedora 44, GNOME on Wayland, NetworkManager |

Other RØDE devices (RØDECaster Pro II, Duo, Streamer X) talk to the app differently (USB HID) and are untested.

## Install

You need `wine` (11 recommended), `7z` (p7zip / 7zip), `python3` and `curl`.

```sh
git clone https://github.com/infinityespi/rodecaster-linux
cd rodecaster-linux
./install.sh            # or: ./install.sh --scale 200   for 4K screens
```

The installer asks for `sudo` once to add two udev rules and a NetworkManager connection (see [What the installer changes](#what-the-installer-changes)). Use `--no-system` to skip that part and set it up yourself.

Then:

1. Connect the RØDECaster Video's **secondary USB-C port (USB 2)** to your computer. If it was already plugged in, unplug and replug it once.
2. Start **RØDECaster App** from your applications menu (or run `rodecaster-app`).
3. Click **RCV-…** in the left sidebar.

**USB 1 vs USB 2:** the app controls the RCV over a USB network link that only exists on the secondary port. USB 1 provides webcam video and audio, which is what OBS uses, but no control link. You can connect both ports at once to use the app and OBS together.

## Settings

`~/.config/rodecaster-linux/config`, read each time the app starts:

```sh
SCALE=100            # UI scale in percent (100, 125, 150, 175, 200 ...)
VIRTUAL_DESKTOP=0    # 1 = run inside one resizable Wine virtual desktop window
DESKTOP_SIZE=1920x1080
```

The app's own windows have fixed layouts, so `SCALE` is the way to make it bigger.

## Uninstall

```sh
./uninstall.sh            # app, Wine prefix, settings, launcher
./uninstall.sh --system   # also the udev rules and the network connection
```

## How it works (what was broken)

Under plain Wine the app starts, but you get "Please connect a device", and later a black screen. Three things were wrong:

1. **The RCV is reached over a USB network link.** On its secondary USB port the RCV presents a CDC-NCM Ethernet adapter. Linux sees it, but NetworkManager waits forever for DHCP. The RCV uses link-local addressing (169.254.x.x), so the installer adds a link-local connection for it. The app discovers the RCV with a UDP broadcast on port 9999, then talks to it over TCP 9998 (discovery), TCP 10024 (OSC control) and SFTP (show media).

2. **The app only accepts an RCV it can also see over USB.** It looks in Windows' device list for a USB interface whose description contains `UsbNcm` (Windows' NCM driver) and reads the RCV's serial number from the parent device's instance ID (`USB\VID_19F7&PID_006D\<serial>`). Then it matches that serial against the network announcement. Wine provides neither value, so the launcher writes both into the Wine prefix's device registry before each start. (Quirk: the RCV's USB serial has a trailing space that has to be trimmed.)

3. **Nothing redrew after the first paint.** The app uses JUCE 7.0.9, which on Windows flushes all repaints only when the display signals a vertical blank, via `IDXGIOutput::WaitForVBlank`. In Wine that function is a stub that always fails, so every window kept its very first frame: black pages, a frozen 0% bar, clicks with no visible effect. `lib/patch_vblank.py` changes 30 bytes in the app so that on failure it waits 16 ms and carries on as if a VBlank arrived (~60 Hz repaints, ~0% CPU). It checks the original bytes first and refuses to touch any other version.

Point 3 affects every JUCE 7 app under Wine; a proper fix in Wine (implementing `WaitForVBlank`) would make the patch unnecessary.

## What the installer changes

In your home folder:
- `~/.local/share/rodecaster-linux/`: the app (downloaded from RØDE and patched) and its own Wine prefix
- `~/.local/bin/rodecaster-app`: the launcher
- `~/.local/share/applications/rodecaster-app.desktop`: the menu entry
- `~/.config/rodecaster-linux/config`: settings

System-wide (with sudo, skippable with `--no-system`):
- `/etc/udev/rules.d/70-rode.rules`: lets your user open RØDE USB devices
- `/etc/udev/rules.d/79-rode-usbncm.rules`: names the RCV's USB network interface `usbncm0`
- a NetworkManager connection "RODECaster Video": link-local IPv4/IPv6 on `usbncm0`

Without NetworkManager, give `usbncm0` a 169.254.x.x address some other way (for example `systemd-networkd` with `LinkLocalAddressing=yes`).

## When RØDE releases a new version

The installer only accepts the exact 2.0.115 download and stops with a message if RØDE's file has changed. Supporting a new version means finding the same JUCE VBlank loop in the new binary and updating the address and bytes in `lib/patch_vblank.py`, plus the hashes in `install.sh`.

## Troubleshooting

- **"Please connect a device"**: check the cable is in the secondary port (`lsusb` should show `19f7:006d`), and that `ip addr show usbncm0` has a 169.254.x.x address. Replug the RCV after installing.
- **Black window or no redraws**: the VBlank patch didn't apply. Run `python3 ~/.local/share/rodecaster-linux/lib/patch_vblank.py ~/.local/share/rodecaster-linux/app/RODECasterApp.exe`.
- **Clicks land in the wrong place**: try `VIRTUAL_DESKTOP=1` in the config.

## Licence

The scripts in this repo are MIT licensed (see `LICENSE`). The RØDECaster App itself is RØDE's software and is not included.
