#!/usr/bin/env bash
set -euo pipefail

if ! command -v wsl.exe >/dev/null 2>&1; then
  echo "wsl.exe not on PATH (Windows interop required)." >&2
  exit 1
fi

default_name="seed-$(date +%Y%m%d-%H%M%S)"
printf "New WSL distro name [%s]: " "$default_name"
read -r name </dev/tty || true
name=${name:-$default_name}

if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid name (use A-Za-z0-9._-)." >&2
  exit 1
fi

if WSL_UTF8=1 wsl.exe -l -q 2>/dev/null | tr -d '\000\r' | grep -Fxq "$name"; then
  echo "WSL distro '$name' already exists." >&2
  exit 1
fi

win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n ')
if [ -z "$win_user" ]; then
  echo "Could not resolve Windows %USERNAME%." >&2
  exit 1
fi
install_root_win="C:\\Users\\${win_user}\\WSL\\${name}"

tarball=$(mktemp --suffix=.wsl)
trap 'rm -f "$tarball"' EXIT

echo "Downloading latest seed.wsl from GitHub..."
curl --fail --location --output "$tarball" \
  "https://github.com/tteggel/.dotfiles/releases/latest/download/seed.wsl"

tarball_win=$(wslpath -w "$tarball")
echo "Importing as WSL distro: $name (install dir: $install_root_win)"
wsl.exe --import "$name" "$install_root_win" "$tarball_win"

echo "Launching $name — you'll be prompted to pick thixos or yoloixos."
exec wsl.exe -d "$name"
