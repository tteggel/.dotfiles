#!/usr/bin/env bash
ppid=$(ps -p $$ -o ppid= | tr -d "[:space:]")
pppid=$(ps -p "$ppid" -o ppid= | tr -d "[:space:]")
pppbin=$(ps -p "$pppid" -o cmd= | tr -d "[:space:]")
if [ "$pppbin" = '/bin/login-f' ]; then
  exit 1
fi

if [ -d "$HOME/.init-yolo-completed" ]; then
  exit 0
fi

clear
echo "=================================================="
echo "    Welcome to YOLO Mode (yoloixos Sandbox)"
echo "=================================================="
echo ""
echo "This environment is strictly isolated. You must"
echo "provide a Fine-Grained Personal Access Token (PAT)"
echo "with Repo-scoped access to clone and push code."
echo ""
printf "GitHub PAT: "
read -rs token < /dev/tty
echo ""

if [ -z "$token" ]; then
  echo "Token is required. Aborting."
  sleep 2
  exit 1
fi

echo "$token" | gh auth login --with-token || {
  echo "Auth failed."
  sleep 2
  exit 1
}

# Persist the token to the environment so the warning in zshrc doesn't trigger, 
# and so gh and git can use it seamlessly in this session.
export GITHUB_TOKEN="$token"

echo ""
printf "Repository to clone (e.g. owner/repo): "
read -r repo < /dev/tty

if [ -z "$repo" ]; then
  echo "Repository is required. Aborting."
  sleep 2
  exit 1
fi

name=$(basename "$repo")
target="$HOME/src/$name"

mkdir -p "$HOME/src"
if gh repo clone "$repo" "$target"; then
  mkdir -p "$HOME/.init-yolo-completed"
  echo ""
  echo "=================================================="
  echo "  Setup Complete! Your agent is ready."
  echo "=================================================="
  sleep 2
else
  echo "Failed to clone repository."
  sleep 2
  exit 1
fi
