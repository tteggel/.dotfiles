CHROME="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
if [ -x "$CHROME" ]; then
  exec "$CHROME" "$@"
fi

# Not WSL: hand off to a real xdg-open. Skip our own shim (scripts/xdg-open.sh),
# which execs straight back into this script and would otherwise loop forever.
while read -r candidate; do
  [ -n "$candidate" ] || continue
  if grep -q 'open-browser-shim' "$candidate" 2>/dev/null; then
    continue
  fi
  exec "$candidate" "$@"
done < <(type -aP xdg-open 2>/dev/null || true)

echo "No suitable browser found." >&2
exit 1
