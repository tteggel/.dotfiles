#!/usr/bin/env bash
set -euo pipefail

# Manually attach a USB device shared from Windows into this WSL distro.
# Usage: usbip-attach [VID:PID|BUSID]
# Default: Raspberry Pi Debug Probe CMSIS-DAP (2e8a:000c)
#
# For permanent hands-off attach instead, set wsl.usbip.autoAttach in
# nixos/embedded.nix. One-time on Windows (admin PowerShell):
#   winget install usbipd
#   usbipd list                    # find your probe's BUSID
#   usbipd bind --busid <BUSID>    # share it (persists across reboots)

target="${1:-2e8a:000c}"
distro="${WSL_DISTRO_NAME:-}"

if ! command -v usbipd.exe >/dev/null 2>&1; then
  echo "usbipd.exe not on the Windows PATH — install it once (admin):" >&2
  echo "    winget install usbipd" >&2
  exit 1
fi

if [[ -z "${distro}" ]]; then
  echo "WSL_DISTRO_NAME is not set — run this from inside WSL." >&2
  exit 1
fi

if [[ "${target}" == *:* ]]; then
  target_kind="hardware-id"
  attach_args=(--hardware-id "${target}")
elif [[ "${target}" == *-* ]]; then
  target_kind="busid"
  attach_args=(--busid "${target}")
else
  echo "Expected a VID:PID hardware ID or BUSID, got: ${target}" >&2
  echo "Examples: usbip-attach 2e8a:000c   or   usbip-attach 1-1" >&2
  exit 1
fi

echo "Attaching USB ${target_kind} ${target} into ${distro}…"
if ! output="$(usbipd.exe attach --wsl "${distro}" "${attach_args[@]}" 2>&1)"; then
  if [[ "${output}" == *"already attached to a client"* ]] &&
    [[ "${target_kind}" == "hardware-id" ]] &&
    command -v lsusb >/dev/null 2>&1 &&
    lsusb | grep -qi "ID ${target}"; then
    echo "Already attached to this WSL distro."
  else
    printf '%s\n' "${output}" >&2
    exit 1
  fi
else
  printf '%s\n' "${output}"
fi

echo "Done. Verify with: lsusb   and   probe-rs list"
