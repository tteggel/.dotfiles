#!/usr/bin/env bash

# Exit on error
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <repository-name>"
  echo "Example: $0 .dotfiles"
  exit 1
fi

REPO_NAME="$1"
EXPIRATION_DAYS=30
TOKEN_NAME="Sandbox-${REPO_NAME}"
DESCRIPTION="Generated+for+sandbox"

# URL encode the variables
encode_url() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c" ;;
     esac
     encoded+="${o}"
  done
  echo "${encoded}"
}

ENCODED_TOKEN_NAME=$(encode_url "$TOKEN_NAME")
ENCODED_REPO_NAME=$(encode_url "$REPO_NAME")

# Construct the URL with required permissions
# We include full read/write for standard dev operations:
# contents, metadata, issues, pull_requests, workflows
URL="https://github.com/settings/personal-access-tokens/new?name=${ENCODED_TOKEN_NAME}&description=${DESCRIPTION}&expires_in=${EXPIRATION_DAYS}&repository_selection=selected&repositories=${ENCODED_REPO_NAME}&contents=write&metadata=read&issues=write&pull_requests=write&workflows=write"

echo "Generated URL for fine-grained PAT creation:"
echo ""
echo "$URL"
echo ""

# Try to open the URL automatically
if command -v xdg-open &> /dev/null; then
  echo "Opening browser..."
  xdg-open "$URL"
elif command -v open &> /dev/null; then
  echo "Opening browser..."
  open "$URL"
else
  echo "Could not find a command to open the browser automatically. Please copy and paste the URL above."
fi
