#!/usr/bin/env bash

# Ensure gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  echo "Not authenticated with gcloud. Please run gcloud-reauth first." >&2
  read -rsn1 -p "Press any key to exit..." < /dev/tty || true
  exit 1
fi

current_project=$(gcloud config get-value project 2>/dev/null)
echo "Fetching GCP instances for project: $current_project..."

# Fetch instances with name, zone, and status
instances=$(gcloud compute instances list --format="value(name,zone,status)" 2>/dev/null)

if [ -z "$instances" ]; then
  echo "No instances found in project $current_project or failed to fetch." >&2
  read -rsn1 -p "Press any key to exit..." < /dev/tty || true
  exit 1
fi

# Format for fzf: Name, Zone, Status
formatted=$(echo "$instances" | awk '{printf "%-35s %-20s [%s]\n", $1, $2, $3}')

selected=$(echo "$formatted" | fzf --prompt="IAP SSH> " --height=~50% --reverse < /dev/tty) || exit 0

if [ -z "$selected" ]; then
  exit 0
fi

instance_name=$(echo "$selected" | awk '{print $1}')
instance_zone=$(echo "$selected" | awk '{print $2}')

clear
echo "========================================"
echo "Connecting to: $instance_name ($instance_zone)"
echo "Project:       $current_project"
echo "Tunneling via: Google Cloud IAP"
echo "========================================"

exec gcloud compute ssh "$instance_name" --zone="$instance_zone" --tunnel-through-iap
