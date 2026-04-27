#!/usr/bin/env bash

# Read from stdin and emit OSC 52 to /dev/tty so the host terminal
# (e.g. WezTerm) updates the system clipboard. Works across SSH/IAP
# tunnels and isolated WSL environments where wayland/X11/clip.exe
# are unavailable.

text=$(cat)
b64=$(printf "%s" "$text" | base64 | tr -d '\n')
printf "\033]52;c;%s\a" "$b64" > /dev/tty
