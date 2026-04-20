if ! gcloud projects list --format="value(projectId)" --limit=1 &>/dev/null; then
  echo "Not authenticated. Logging in..."
  gcloud auth login
  gcloud auth application-default login
fi

project=$(gcloud projects list --format="value(projectId)" --filter="NOT projectId:sys-*" | fzf --prompt="Project> " --height=~100% --reverse) || exit 0
gcloud config set project "$project"

clusters=$(gcloud container clusters list --format="csv[no-heading](name,location)" 2>/dev/null)
count=$(echo "$clusters" | grep -c . || true)

if [ "$count" -eq 0 ]; then
  echo "Switched to project=$project (no clusters)"
  exit 0
elif [ "$count" -eq 1 ]; then
  cluster="$clusters"
else
  cluster=$(echo "$clusters" | fzf --prompt="Cluster> " --height=~100% --reverse) || exit 0
fi

cluster_name="${cluster%%,*}"
cluster_location="${cluster##*,}"
gcloud container clusters get-credentials "$cluster_name" --region "$cluster_location"

echo "Switched to project=$project cluster=$cluster_name"

