SRC_ROOT="$HOME/src/github.com"
ZW_HOSTS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-web/hosts"

# MRU list of project dirs we've opened. Survives the zellij server dying
# (serialization is off), so the picker can offer recently-used projects even
# when their live session is gone. One absolute path per line, most-recent first.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/session-picker"
RECENT_FILE="$STATE_DIR/recent"

# Push a project dir onto the MRU list (deduped, most-recent first, capped).
# Best-effort: never abort the picker if state can't be written. $HOME is the
# empty-state fallback, not a real project, so it's not recorded.
record_recent() {
  local dir="$1" tmp
  [ -n "$dir" ] || return 0
  [ "$dir" = "$HOME" ] && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  tmp=$(mktemp "$STATE_DIR/.recent.XXXXXX" 2>/dev/null) || return 0
  {
    printf '%s\n' "$dir"
    [ -f "$RECENT_FILE" ] && grep -vxF "$dir" "$RECENT_FILE"
  } 2>/dev/null | awk 'NF && !seen[$0]++' | head -n 50 > "$tmp" || true
  if [ -s "$tmp" ]; then
    mv -f "$tmp" "$RECENT_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  if command -v zoxide >/dev/null 2>&1; then
    zoxide add "$dir" 2>/dev/null || true
  fi
}

# Map a session name back to a project dir: prefer the MRU list (exact basename
# match, most-recent first), fall back to zoxide. Empty output if unknown.
resolve_dir() {
  local want="$1" d
  if [ -f "$RECENT_FILE" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      if [ "$(basename "$d")" = "$want" ]; then
        printf '%s\n' "$d"
        return 0
      fi
    done < "$RECENT_FILE"
  fi
  zoxide query "$want" 2>/dev/null || true
}

start_session() {
  local dir="$1"
  local name
  name=$(basename "$dir")
  record_recent "$dir" || true
  # A dead (EXITED) session of the same name blocks `zellij -s` with "Session
  # with name X already exists, but is dead". Zellij 0.45 keeps EXITED sessions
  # in the list even with serialization off, so reopening a recent project whose
  # session has exited hits this. Serialization is off => the corpse holds no
  # recoverable state, so drop it (dead-only; no --force) and start fresh.
  zellij delete-session "$name" >/dev/null 2>&1 || true
  cd "$dir" && exec zellij -s "$name" -n ~/.config/zellij/layouts/code.kdl
}

new_session() {
  local dir
  dir=$(zoxide query -i 2>/dev/null) || return 1
  start_session "$dir"
}

clone_gh_repo() {
  local repos org_repos all_repos repo owner name target
  repos=$(gh repo list --limit 50 --json nameWithOwner,updatedAt --jq 'sort_by(.updatedAt) | reverse | .[].nameWithOwner' 2>&1) || {
    echo "Failed to fetch repos: $repos" >&2
    echo "Check 'gh auth status'" >&2
    read -r -n 1 </dev/tty || true
    return 1
  }

  org_repos=""
  for org in $(gh org list 2>/dev/null); do
    org_repos="$org_repos
$(gh repo list "$org" --limit 50 --json nameWithOwner,updatedAt --jq 'sort_by(.updatedAt) | reverse | .[].nameWithOwner' 2>/dev/null)"
  done

  all_repos=$(printf '%s\n%s' "$repos" "$org_repos" | sed '/^$/d' | sort -u)

  if [ -z "$all_repos" ]; then
    echo "No repos found." >&2
    read -r -n 1
    return 1
  fi

  repo=$(echo "$all_repos" | fzf --prompt="GitHub repo> " --height=~50% --reverse) || return 1

  owner=$(dirname "$repo")
  name=$(basename "$repo")
  target="$SRC_ROOT/$owner/$name"

  if [ -d "$target" ]; then
    start_session "$target"
  else
    mkdir -p "$SRC_ROOT/$owner"
    gh repo clone "$repo" "$target" || return 1
    start_session "$target"
  fi
}

clone_remote() {
  local url name target
  printf "Remote URL: "
  read -r url </dev/tty || true
  [ -z "$url" ] && return 1

  name=$(basename "$url" .git)
  target="$HOME/src/$name"

  if [ -d "$target" ]; then
    start_session "$target"
  else
    git clone "$url" "$target" || return 1
    start_session "$target"
  fi
}

connect_remote() {
  local hosts host out
  hosts=$(awk '/^Host / {for(i=2; i<=NF; i++) if ($i !~ /[*?]/) print $i}' ~/.ssh/config 2>/dev/null | sort -u)

  if [ -z "$hosts" ]; then
    printf "SSH Host (e.g. user@host): "
    read -r host </dev/tty || true
  else
    out=$(printf "%s\n" "$hosts" | fzf --prompt="SSH Host (or type custom)> " --height=~50% --reverse --print-query --bind "enter:accept-or-print-query") || true
    [ -z "$out" ] && return 1
    host=$(echo "$out" | tail -1 | tr -d '\r' | xargs)
  fi

  [ -z "$host" ] && return 1

  clear
  echo "========================================"
  echo "Connecting to: $host"
  echo "========================================"

  exec ssh "$host"
}

create_from_seed() {
  command -v wsl-spawn >/dev/null 2>&1 || { echo "wsl-spawn unavailable" >&2; return 1; }
  exec wsl-spawn
}

# Each menu row is: id<TAB>label . The id encodes the action; fzf shows
# only the label via --with-nth=2.

# --- Recently-used projects (MRU) merged with live sessions -------------------
# Recent projects recorded by start_session are the source of truth: they
# survive the zellij server dying (serialization is off) and are listed
# most-recently-used first. Live sessions are merged in so running ones stay
# attachable and nothing is hidden.

# Live sessions: name -> status. Use `-n` (not `-s`, which strips the
# annotations) so current/attached/exited can be told apart.
declare -A live_status=()
live_order=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  name=${line%% *}
  [ -n "$name" ] || continue
  case "$line" in
    *"(current)"*) status="current" ;;
    *attached*)    status="attached" ;;
    *EXITED*)      status="exited" ;;
    *)             status="detached" ;;
  esac
  live_status["$name"]="$status"
  live_order+=("$name")
done < <(zellij list-sessions -n 2>/dev/null || true)

# Label a live, non-exited session for display.
live_label() {
  case "$1" in
    current)  printf '%s (current)' "$2" ;;
    attached) printf '%s (attached)' "$2" ;;
    *)        printf '%s' "$2" ;;
  esac
}

entries=""
declare -A shown=()

# 1) Recent projects, most-recently-used first. Attach if a live session of the
#    same name is running; otherwise reopen the project fresh in its directory.
if [ -f "$RECENT_FILE" ]; then
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    name=$(basename "$dir")
    [ -n "${shown[$name]:-}" ] && continue
    status="${live_status[$name]:-}"
    if [ -n "$status" ] && [ "$status" != "exited" ]; then
      entries+="local:$name"$'\t'"$(live_label "$status" "$name")"$'\n'
      shown["$name"]=1
    elif [ -d "$dir" ]; then
      entries+="recent:$dir"$'\t'"$name"$'\n'
      shown["$name"]=1
    fi
  done < "$RECENT_FILE"
fi

# 2) Live sessions not already listed (started outside the picker, or whose dir
#    predates the MRU file). Reopen exited ones fresh in their dir when zoxide
#    can resolve it, else attach so nothing is hidden.
for name in "${live_order[@]}"; do
  [ -n "${shown[$name]:-}" ] && continue
  shown["$name"]=1
  status="${live_status[$name]}"
  if [ "$status" = "exited" ]; then
    dir=$(resolve_dir "$name")
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      entries+="recent:$dir"$'\t'"$name"$'\n'
    else
      entries+="local:$name"$'\t'"$name (exited)"$'\n'
    fi
  else
    entries+="local:$name"$'\t'"$(live_label "$status" "$name")"$'\n'
  fi
done

# Cached remote (zellij-web/IAP) sessions: one file per host with shell-sourceable
# ZW_PROJECT/ZW_INSTANCE/ZW_ZONE/ZW_SESSIONS, written by gcloud-iap-zellij-web.
remote_lines=""
if [ -d "$ZW_HOSTS_DIR" ]; then
  for f in "$ZW_HOSTS_DIR"/*; do
    [ -f "$f" ] || continue
    ZW_PROJECT=""; ZW_INSTANCE=""; ZW_ZONE=""; ZW_SESSIONS=""
    # shellcheck disable=SC1090
    . "$f" || continue
    [ -z "$ZW_INSTANCE" ] && continue
    [ -z "$ZW_PROJECT" ] && continue
    [ -z "$ZW_ZONE" ] && continue
    for s in $ZW_SESSIONS; do
      id="remote:$ZW_PROJECT|$ZW_INSTANCE|$ZW_ZONE|$s"
      label="gcp/$ZW_INSTANCE/$s"
      remote_lines+="$id"$'\t'"$label"$'\n'
    done
  done
fi

# Other local WSL distros (skip current). Visible only when Windows interop
# is registered — i.e. on thixos, not yoloixos.
wsl_lines=""
if command -v wsl.exe >/dev/null 2>&1; then
  while IFS= read -r d; do
    d=$(printf '%s' "$d" | tr -d '\000\r')
    [ -z "$d" ] && continue
    [ "$d" = "${WSL_DISTRO_NAME:-}" ] && continue
    wsl_lines+="wsl:$d"$'\t'"wsl/$d"$'\n'
  done < <(WSL_UTF8=1 wsl.exe -l -q 2>/dev/null)
fi

NEW_LABEL="[+] New session         (Ctrl+N)"
NEWREMOTE_LABEL="[+] New remote session  (Ctrl+W)"
GH_LABEL="[+] Clone GitHub repo   (Ctrl+G)"
CLONE_LABEL="[+] Clone remote        (Ctrl+U)"
SSH_LABEL="[+] Connect to remote   (Ctrl+S)"
IAP_LABEL="[+] GCP IAP shell"
SEED_LABEL="[+] Create from seed    (Ctrl+Y)"

cmd_lines=""
cmd_lines+="cmd:new"$'\t'"$NEW_LABEL"$'\n'
cmd_lines+="cmd:newremote"$'\t'"$NEWREMOTE_LABEL"$'\n'
cmd_lines+="cmd:clonegh"$'\t'"$GH_LABEL"$'\n'
cmd_lines+="cmd:cloneremote"$'\t'"$CLONE_LABEL"$'\n'
cmd_lines+="cmd:ssh"$'\t'"$SSH_LABEL"$'\n'
cmd_lines+="cmd:iap"$'\t'"$IAP_LABEL"$'\n'
if command -v wsl-spawn >/dev/null 2>&1; then
  cmd_lines+="cmd:seed"$'\t'"$SEED_LABEL"$'\n'
fi

display="${entries}${remote_lines}${wsl_lines}${cmd_lines}"

# Empty state: no local sessions, no remote sessions cached, no other WSL
# distros → start one in $HOME. Don't call new_session here: it requires a
# non-empty zoxide DB and would exit 1 on first boot, which would bubble
# up through `session-picker; exit` in zsh init and kill the whole shell.
if [ -z "$entries$remote_lines$wsl_lines" ]; then
  start_session "$HOME"
fi

pick=$(printf '%s' "$display" | fzf --prompt="Zellij session> " --height=~50% --reverse \
  --delimiter=$'\t' --with-nth=2 \
  --bind "ctrl-n:become(echo cmd:new)" \
  --bind "ctrl-w:become(echo cmd:newremote)" \
  --bind "ctrl-g:become(echo cmd:clonegh)" \
  --bind "ctrl-u:become(echo cmd:cloneremote)" \
  --bind "ctrl-s:become(echo cmd:ssh)" \
  --bind "ctrl-y:become(echo cmd:seed)") || exit 1

id="${pick%%$'\t'*}"
[ -z "$id" ] && exit 0

case "$id" in
  cmd:new)         new_session ;;
  cmd:newremote)   exec gcloud-iap-zellij-web ;;
  cmd:clonegh)     clone_gh_repo ;;
  cmd:cloneremote) clone_remote ;;
  cmd:ssh)         connect_remote ;;
  cmd:iap)         exec gcloud-iap-ssh ;;
  cmd:seed)        create_from_seed ;;
  local:*)
    name="${id#local:}"
    dir=$(resolve_dir "$name")
    if [ -n "$dir" ]; then record_recent "$dir" || true; fi
    exec zellij attach "$name"
    ;;
  recent:*)
    dir="${id#recent:}"
    start_session "$dir"
    ;;
  remote:*)
    spec="${id#remote:}"
    IFS='|' read -r p i z s <<<"$spec"
    exec gcloud-iap-zellij-web --project "$p" --instance "$i" --zone "$z" --session "$s"
    ;;
  wsl:*)
    name="${id#wsl:}"
    exec wsl.exe -d "$name"
    ;;
  *) exit 0 ;;
esac
