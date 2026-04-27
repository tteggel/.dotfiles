#!/usr/bin/env bash

# Set the host system clipboard from stdin. Prefers clip.exe via WSL
# interop where available (thixos); falls back to OSC 52 to /dev/tty
# for environments without interop (yoloixos, remote SSH sessions).

text=$(cat)
if command -v clip.exe >/dev/null 2>&1; then
  printf '%s' "$text" | clip.exe
else
  b64=$(printf '%s' "$text" | base64 | tr -d '\n')
  printf '\e]52;c;%s\a' "$b64" > /dev/tty
fi
