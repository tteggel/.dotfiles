#!/usr/bin/env bash

# Connect to a Zellij session on a GCP instance through IAP, using
# Zellij's web protocol as transport and the local terminal as the
# client.
#
# Topology:
#   local zellij attach <-> http://localhost:LOCAL_PORT
#                       <-SSH(IAP)-> VM:127.0.0.1:8082 (zellij web --daemonize, 127.0.0.1)
#
# Note: zellij web binds to 127.0.0.1 because we use SSH port forwarding over IAP.
#
# Bootstrap-over-SSH discovers (and creates if missing) a long-lived
# auth token, lists remote sessions, and writes a cache file the
# session-picker can read so remote sessions show up alongside local
# ones.

set -euo pipefail

INSTANCE=""
ZONE=""
SESSION=""
PROJECT=""
NEW_SESSION=0
REFRESH_TOKEN=0
LOCAL_PORT="${ZELLIJ_WEB_PORT:-0}"   # 0 = pick a free port
REMOTE_PORT=8082

usage() {
  cat <<'EOF'
Usage: gcloud-iap-zellij-web [OPTIONS]

Connect to a Zellij session on a GCP instance over IAP using the Zellij
web protocol (terminal client, not browser).

OPTIONS
  --instance NAME    Skip the instance picker
  --zone ZONE        Required when --instance is given (cache may supply it)
  --project PROJECT  Override gcloud default project
  --session NAME     Attach to (or create) this remote session by name
  --new              Force prompt for a brand-new session name
  --refresh-token    Revoke any cached login token and create a new one
  --port N           Local port for the IAP tunnel (default: ephemeral)
  -h, --help         Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --instance) INSTANCE="$2"; shift 2;;
    --zone) ZONE="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --session) SESSION="$2"; shift 2;;
    --new) NEW_SESSION=1; shift;;
    --refresh-token) REFRESH_TOKEN=1; shift;;
    --port) LOCAL_PORT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
done

pause_on_error() {
  read -rsn1 -p "Press any key to exit..." </dev/tty || true
}

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  echo "Not authenticated with gcloud. Run gcloud-reauth first." >&2
  pause_on_error
  exit 1
fi

[ -z "$PROJECT" ] && PROJECT=$(gcloud config get-value project 2>/dev/null || true)

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-web"
hosts_dir="$cache_root/hosts"
tokens_dir="$cache_root/tokens"
mkdir -p "$hosts_dir" "$tokens_dir"
chmod 700 "$cache_root" "$hosts_dir" "$tokens_dir"

cache_key() {
  printf '%s__%s' "$1" "$2"
}

if [ -z "$INSTANCE" ]; then
  echo "Fetching running GCP instances for project: $PROJECT..."
  instances=$(gcloud compute instances list \
    --project="$PROJECT" \
    --filter='status=RUNNING' \
    --format='value(name,zone)' || true)

  if [ -z "$instances" ]; then
    echo "No running instances in project $PROJECT." >&2
    pause_on_error
    exit 1
  fi

  formatted=$(echo "$instances" | awk '{printf "%-35s %s\n", $1, $2}')
  selected=$(echo "$formatted" | fzf --prompt="Zellij Web (IAP)> " --height=~50% --reverse) || exit 0
  [ -z "$selected" ] && exit 0
  INSTANCE=$(echo "$selected" | awk '{print $1}')
  ZONE=$(echo "$selected" | awk '{print $2}')
fi

if [ -z "$ZONE" ]; then
  host_file="$hosts_dir/$(cache_key "$PROJECT" "$INSTANCE")"
  if [ -f "$host_file" ]; then
    # shellcheck disable=SC1090
    . "$host_file"
    ZONE="${ZW_ZONE:-}"
  fi
fi

if [ -z "$ZONE" ]; then
  echo "Looking up zone for $INSTANCE in $PROJECT..."
  ZONE=$(gcloud compute instances list \
    --project="$PROJECT" \
    --filter="name=$INSTANCE" \
    --format='value(zone)' | head -1 || true)
fi

if [ -z "$ZONE" ]; then
  echo "Could not resolve zone for $INSTANCE in $PROJECT." >&2
  pause_on_error
  exit 1
fi

token_file="$tokens_dir/$(cache_key "$PROJECT" "$INSTANCE")"
token_name_file="$tokens_dir/$(cache_key "$PROJECT" "$INSTANCE").name"
host_file="$hosts_dir/$(cache_key "$PROJECT" "$INSTANCE")"

old_token_name=""
[ -s "$token_name_file" ] && old_token_name=$(cat "$token_name_file")

if [ "$REFRESH_TOKEN" -eq 1 ]; then
  rm -f "$token_file" "$token_name_file"
fi

# One SSH round-trip: ensure web server, mint token if needed, list sessions.
need_token=1
[ -s "$token_file" ] && need_token=0

echo "Bootstrapping zellij web on $INSTANCE ($ZONE)..."
remote_script=$(cat <<REMOTE
set -e
if ! command -v zellij >/dev/null 2>&1; then
  echo "ERROR: zellij is not installed on \$(hostname)." >&2
  echo "Install Zellij >=0.43 with web_server_capability before retrying." >&2
  exit 64
fi
probe_port() {
  (echo > /dev/tcp/127.0.0.1/${REMOTE_PORT}) 2>/dev/null
}
daemonize_out=""
if ! probe_port; then
  daemonize_rc=0
  daemonize_out=\$(zellij web --daemonize --ip 127.0.0.1 --port ${REMOTE_PORT} 2>&1) || daemonize_rc=\$?
  if [ "\$daemonize_rc" -ne 0 ] && ! printf '%s\n' "\$daemonize_out" | grep -qi 'address already in use'; then
    echo "ERROR: zellij web --daemonize failed on \$(hostname) (port ${REMOTE_PORT})." >&2
    printf '%s\n' "\$daemonize_out" >&2
    exit 65
  fi
fi
listening=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if probe_port; then
    listening=1
    break
  fi
  sleep 1
done
if [ "\$listening" -eq 0 ]; then
  echo "ERROR: nothing listening on port ${REMOTE_PORT} on \$(hostname) after bootstrap." >&2
  echo "  zellij version: \$(zellij --version 2>&1 || true)" >&2
  if [ -n "\$daemonize_out" ]; then
    echo "  zellij web --daemonize output:" >&2
    printf '    %s\n' "\$daemonize_out" >&2
  fi
  status_out=\$(zellij web --status --port ${REMOTE_PORT} 2>&1 || true)
  echo "  zellij web --status output:" >&2
  printf '    %s\n' "\$status_out" >&2
  echo "  listeners on this host:" >&2
  (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null || true) | sed 's/^/    /' >&2
  exit 66
fi
echo "---SESSIONS-BEGIN---"
zellij list-sessions -n -s 2>/dev/null || true
echo "---SESSIONS-END---"
if [ "$need_token" = "1" ]; then
  if [ -n "${old_token_name}" ]; then
    zellij web --revoke-token "${old_token_name}" >/dev/null 2>&1 || true
  fi
  zellij web --create-token
fi
REMOTE
)

if ! bootstrap_out=$(gcloud compute ssh "$INSTANCE" \
      --project="$PROJECT" \
      --zone="$ZONE" \
      --tunnel-through-iap \
      --command="$remote_script" 2>&1); then
  echo "$bootstrap_out" >&2
  pause_on_error
  exit 1
fi

remote_sessions=$(printf '%s\n' "$bootstrap_out" \
  | awk '/---SESSIONS-BEGIN---/{flag=1; next} /---SESSIONS-END---/{flag=0} flag' \
  | awk '{print $1}' \
  | grep -v '^$' || true)

if [ "$need_token" -eq 1 ]; then
  name_value=$(printf '%s\n' "$bootstrap_out" \
    | awk '/---SESSIONS-END---/{seen=1; next} seen' \
    | grep -E '^[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]+[A-Fa-f0-9-]+' \
    | tail -1)
  if [ -z "$name_value" ]; then
    echo "Could not parse token from remote output:" >&2
    printf '%s\n' "$bootstrap_out" >&2
    pause_on_error
    exit 1
  fi
  new_token_name=$(printf '%s\n' "$name_value" | awk -F': *' '{print $1}')
  token=$(printf '%s\n' "$name_value" | awk -F': *' '{print $2}')
  (umask 077 && printf '%s' "$token" > "$token_file")
  (umask 077 && printf '%s' "$new_token_name" > "$token_name_file")
fi
token=$(cat "$token_file")

# Refresh host-cache so session-picker can surface entries.
{
  echo "ZW_PROJECT=$PROJECT"
  echo "ZW_INSTANCE=$INSTANCE"
  echo "ZW_ZONE=$ZONE"
  echo "ZW_UPDATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ZW_SESSIONS=\"$(printf '%s\n' "$remote_sessions" | tr '\n' ' ' | sed 's/ *$//')\""
} > "$host_file"
chmod 600 "$host_file"

if [ "$NEW_SESSION" -eq 1 ]; then
  SESSION=""
fi

if [ -z "$SESSION" ]; then
  NEW_ENTRY="[+] New remote session"
  if [ -n "$remote_sessions" ]; then
    menu="$remote_sessions"$'\n'"$NEW_ENTRY"
  else
    menu="$NEW_ENTRY"
  fi
  pick=$(printf '%s\n' "$menu" \
    | fzf --prompt="$INSTANCE> " --height=~50% --reverse \
          --bind "ctrl-n:become(echo '$NEW_ENTRY')") || exit 0
  if [ "$pick" = "$NEW_ENTRY" ] || [ -z "$pick" ]; then
    printf "New session name: "
    read -r SESSION </dev/tty || true
    SESSION=$(echo "$SESSION" | tr -cd 'A-Za-z0-9_.-' | head -c 64)
    [ -z "$SESSION" ] && SESSION="$(whoami)-$(date +%s)"
  else
    SESSION="$pick"
  fi
fi

# Pick a free local port if not specified, so multiple connections coexist.
if [ "$LOCAL_PORT" -eq 0 ]; then
  for _ in $(seq 1 100); do
    candidate=$((18000 + RANDOM % 1000))
    if ! (echo > "/dev/tcp/127.0.0.1/$candidate") 2>/dev/null; then
      LOCAL_PORT=$candidate
      break
    fi
  done
  if [ "$LOCAL_PORT" -eq 0 ]; then
    echo "Could not find a free local port for the IAP tunnel." >&2
    pause_on_error
    exit 1
  fi
fi

echo "Starting SSH port forwarding localhost:$LOCAL_PORT -> $INSTANCE:127.0.0.1:$REMOTE_PORT via IAP..."
tunnel_log=$(mktemp -t zellij-iap.XXXXXX)
gcloud compute ssh "$INSTANCE" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --tunnel-through-iap \
  -- -N -L "$LOCAL_PORT:127.0.0.1:$REMOTE_PORT" >"$tunnel_log" 2>&1 &
tunnel_pid=$!
trap 'kill "$tunnel_pid" 2>/dev/null || true; wait 2>/dev/null || true; rm -f "$tunnel_log"' EXIT INT TERM

ready=0
for _ in $(seq 1 120); do
  if (echo > "/dev/tcp/127.0.0.1/$LOCAL_PORT") 2>/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    break
  fi
  sleep 0.5
done
if [ "$ready" -ne 1 ]; then
  echo "SSH tunnel failed to come up on port $LOCAL_PORT." >&2
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    echo "(gcloud compute ssh exited before the tunnel was ready)" >&2
  fi
  if [ -s "$tunnel_log" ]; then
    echo "--- gcloud output ---" >&2
    cat "$tunnel_log" >&2
    echo "---------------------" >&2
  else
    echo "(gcloud produced no output)" >&2
  fi
  pause_on_error
  exit 1
fi

clear
echo "========================================"
echo "Zellij Web (IAP)"
echo "  Project:   $PROJECT"
echo "  Instance:  $INSTANCE ($ZONE)"
echo "  Session:   $SESSION"
echo "========================================"

attach_rc=0
zellij attach "http://localhost:$LOCAL_PORT/$SESSION" \
  --token "$token" \
  --remember || attach_rc=$?

kill "$tunnel_pid" 2>/dev/null || true
wait 2>/dev/null || true
exit "$attach_rc"
