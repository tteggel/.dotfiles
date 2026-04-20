# Find zed.exe via WSL interop PATH
ZED_EXE="$(command -v zed.exe 2>/dev/null || echo "/mnt/c/Users/thom/AppData/Local/Programs/Zed/zed.exe")"

args=()
for arg in "$@"; do
  if [[ "$arg" == -* ]]; then
    args+=("$arg")
  elif [[ -e "$arg" || -d "$arg" ]]; then
    args+=("$(wslpath -w "$arg")")
  else
    args+=("$arg")
  fi
done

"$ZED_EXE" --wait "${args[@]}"

