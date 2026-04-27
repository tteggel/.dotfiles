#!/usr/bin/env bash

# Dump the current screen from Zellij
tmp=$(mktemp)
zellij action dump-screen "$tmp"

# Extract URLs, meticulously stitching lines together to handle terminal wrapping
# 1. sed: removes trailing spaces from all lines (terminal padding)
# 2. tr: removes all newlines, flattening the screen into one long string
# 3. grep: strictly extracts the URL regex
urls=$(sed -e 's/ *$//' "$tmp" | tr -d '\n' | grep -oE '(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]')

if [ -z "$urls" ]; then
  echo "No URLs found on screen."
  read -rsn1 -p "Press any key to close..." </dev/tty || true
  rm -f "$tmp"
  exit 0
fi

# De-duplicate
unique_urls=$(echo "$urls" | awk '!seen[$0]++')

# Single URL -> auto select. Multiple URLs -> fzf prompt.
url_count=$(echo "$unique_urls" | wc -l)

if [ "$url_count" -eq 1 ]; then
  url="$unique_urls"
else
  url=$(echo "$unique_urls" | fzf --prompt="Open URL> " --height=~50% --reverse </dev/tty) || true
fi

rm -f "$tmp"

if [ -n "$url" ]; then
  if command -v open-browser >/dev/null 2>&1; then
    exec open-browser "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "$url"
  else
    echo "No browser tool found in PATH."
    read -rsn1 -p "Press any key to close..." </dev/tty || true
  fi
fi
