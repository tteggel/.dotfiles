#!/usr/bin/env bash
set -euo pipefail

# Manually attach a USB device shared from Windows into this WSL distro.
# Usage: usbip-attach [VID:PID]   (default: Raspberry Pi Debug Probe CMSIS-DAP)
#
# For permanent hands-off attach instead, set wsl.usbip.autoAttach in
# nixos/embedded.nix. One-time on Windows (admin PowerShell):
#   winget install usbipd
#   usbipd list                    # find your probe's BUSID
#   usbipd bind --busid <BUSID>    # share it (persists across reboots)

hwid="${1:-2e8a:000c}"

if ! command -v usbipd.exe >/dev/null 2>&1; then
  echo "usbipd.exe not on the Windows PATH — install it once (admin):" >&2
  echo "    winget install usbipd" >&2
  exit 1
fi

echo "Attaching USB hardware-id ${hwid} into ${WSL_DISTRO_NAME}…"
usbipd.exe attach --wsl --distribution "${WSL_DISTRO_NAME}" --hardware-id "${hwid}"
echo "Done. Verify with: lsusb   and   probe-rs list"
