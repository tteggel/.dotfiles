#!/usr/bin/env bash
set -euo pipefail

[ -f /var/lib/seed-bootstrap.done ] && exit 0

clear
cat <<'EOF'

   ___  ___  ___  __
  / __|/ _ \/ _ \/ /
  \__ | __/  __/ /
  |___/\___|\___/_/


EOF
echo "Welcome to the .dotfiles seed."
echo
echo "  t) thixos   — interactive dev workstation (sudo, Tailscale, interop)"
echo "  y) yoloixos — sandboxed agent runtime (no sudo, firewalled, no interop)"
echo

choice=""
while [ -z "$choice" ]; do
  printf "Choice [t/y]: "
  if ! read -r ans </dev/tty; then
    echo "No TTY; aborting." >&2
    exit 1
  fi
  case "${ans:-}" in
    t|T) choice=thixos ;;
    y|Y) choice=yoloixos ;;
    *)   echo "Pick t or y." ;;
  esac
done

if [ "$choice" = yoloixos ]; then
  echo
  echo "yoloixos is one-way: the agent user has no sudo, so this image can"
  echo "never be rebuilt back to seed or thixos."
  printf "Type YOLO to confirm: "
  read -r confirm </dev/tty || true
  if [ "${confirm:-}" != "YOLO" ]; then
    echo "Aborted."
    exit 1
  fi
fi

echo
echo "Staging $choice (closures from cache.numtide.com)..."
sudo nixos-rebuild boot --flake "/etc/seed-source#$choice"

sudo install -m 0644 /dev/null /var/lib/seed-bootstrap.done

echo
echo "Staged $choice. Terminating this WSL instance — relaunch to enter $choice."
sync
exec /mnt/c/Windows/System32/wsl.exe --terminate "$WSL_DISTRO_NAME"
