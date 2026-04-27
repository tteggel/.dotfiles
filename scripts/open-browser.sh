CHROME="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
if [ -x "$CHROME" ]; then
  "$CHROME" "$@"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$@"
else
  echo "No suitable browser found." >&2
  exit 1
fi

