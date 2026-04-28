SRC_ROOT="$HOME/src/github.com"
ZW_HOSTS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-web/hosts"

start_session() {
  local dir="$1"
  local name
  name=$(basename "$dir")
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

# Each menu row is: id<TAB>label . The id encodes the action; fzf shows
# only the label via --with-nth=2.

# Local sessions, with attached/exited annotations.
sessions=$(zellij list-sessions -n -s 2>/dev/null || true)
no_client=""
has_client=""
if [ -n "$sessions" ]; then
  while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    [ -z "$name" ] && continue
    if echo "$line" | grep -q "EXITED"; then
      entry="local:$name"$'\t'"$name (EXITED)"
      no_client="${no_client}${entry}"$'\n'
    elif echo "$line" | grep -q "(current session)"; then
      entry="local:$name"$'\t'"$name (current)"
      has_client="${has_client}${entry}"$'\n'
    elif echo "$line" | grep -q "attached"; then
      entry="local:$name"$'\t'"$name (attached)"
      has_client="${has_client}${entry}"$'\n'
    else
      entry="local:$name"$'\t'"$name"
      no_client="${no_client}${entry}"$'\n'
    fi
  done <<< "$sessions"
fi

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

NEW_LABEL="[+] New session         (Ctrl+N)"
NEWREMOTE_LABEL="[+] New remote session  (Ctrl+W)"
GH_LABEL="[+] Clone GitHub repo   (Ctrl+G)"
CLONE_LABEL="[+] Clone remote        (Ctrl+U)"
SSH_LABEL="[+] Connect to remote   (Ctrl+S)"
IAP_LABEL="[+] GCP IAP shell       (Ctrl+I)"

cmd_lines=""
cmd_lines+="cmd:new"$'\t'"$NEW_LABEL"$'\n'
cmd_lines+="cmd:newremote"$'\t'"$NEWREMOTE_LABEL"$'\n'
cmd_lines+="cmd:clonegh"$'\t'"$GH_LABEL"$'\n'
cmd_lines+="cmd:cloneremote"$'\t'"$CLONE_LABEL"$'\n'
cmd_lines+="cmd:ssh"$'\t'"$SSH_LABEL"$'\n'
cmd_lines+="cmd:iap"$'\t'"$IAP_LABEL"$'\n'

display="${no_client}${has_client}${remote_lines}${cmd_lines}"

# Empty state: no local sessions and no remote sessions cached → jump
# straight to creating one (matches old behaviour).
if [ -z "$no_client$has_client$remote_lines" ]; then
  new_session
  exit $?
fi

pick=$(printf '%s' "$display" | fzf --prompt="Zellij session> " --height=~50% --reverse \
  --delimiter=$'\t' --with-nth=2 \
  --bind "ctrl-n:become(echo cmd:new)" \
  --bind "ctrl-w:become(echo cmd:newremote)" \
  --bind "ctrl-g:become(echo cmd:clonegh)" \
  --bind "ctrl-u:become(echo cmd:cloneremote)" \
  --bind "ctrl-s:become(echo cmd:ssh)" \
  --bind "ctrl-i:become(echo cmd:iap)") || exit 1

id="${pick%%$'\t'*}"
[ -z "$id" ] && exit 0

case "$id" in
  cmd:new)         new_session ;;
  cmd:newremote)   exec gcloud-iap-zellij-web ;;
  cmd:clonegh)     clone_gh_repo ;;
  cmd:cloneremote) clone_remote ;;
  cmd:ssh)         connect_remote ;;
  cmd:iap)         exec gcloud-iap-ssh ;;
  local:*)
    name="${id#local:}"
    exec zellij attach "$name"
    ;;
  remote:*)
    spec="${id#remote:}"
    IFS='|' read -r p i z s <<<"$spec"
    exec gcloud-iap-zellij-web --project "$p" --instance "$i" --zone "$z" --session "$s"
    ;;
  *) exit 0 ;;
esac
