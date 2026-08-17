# If we are on pure Linux, just use native zed if available
if ! command -v wslpath >/dev/null 2>&1; then
  if command -v zed >/dev/null 2>&1; then
    exec zed --wait "$@"
  else
    echo "Zed is not installed or not in PATH." >&2
    exit 1
  fi
fi

# Find zed.exe via WSL interop PATH, or fall back to scanning Windows user dirs
ZED_EXE="$(command -v zed.exe 2>/dev/null || true)"
if [ -z "$ZED_EXE" ]; then
  for candidate in /mnt/c/Users/*/AppData/Local/Programs/Zed/zed.exe; do
    [ -x "$candidate" ] && ZED_EXE="$candidate" && break
  done
fi

args=()
for arg in "$@"; do
  if [[ "$arg" == -* ]]; then
    args+=("$arg")
    continue
  fi

  # Zed also accepts `file:line` and `file:line:col` (lazygit's editAtLine uses
  # it). Peel a trailing numeric suffix off so the path still resolves, then
  # reattach it to the translated Windows path.
  path="$arg"
  suffix=""
  while [[ ! -e "$path" && "$path" == *:* && "${path##*:}" =~ ^[0-9]+$ ]]; do
    suffix=":${path##*:}$suffix"
    path="${path%:*}"
  done

  if [[ -e "$path" ]]; then
    args+=("$(wslpath -w "$path")$suffix")
  else
    args+=("$arg")
  fi
done

"$ZED_EXE" --wait "${args[@]}"

