#!/usr/bin/env bash

# Bump every lockfile this flake owns, switch to the result, then commit.
#
# `nix flake update` at the top level does NOT recurse into `path:` inputs: a
# path input's transitive deps are read from *that* flake's own flake.lock, so
# the bespoke/zellij/dim-unfocused subtree (zellij-src, rust-overlay, and the
# nixpkgs zellij is built against) silently froze while the rest of the system
# moved on. Update the child lock first, then the top level, so the top-level
# resolve picks up the new subtree.

set -euo pipefail

DOTFILES="$HOME/src/github.com/tteggel/.dotfiles"
CHILD="bespoke/zellij/dim-unfocused"
LOCKS=("flake.lock" "$CHILD/flake.lock")

# Refuse to run over lock edits that aren't committed yet — this script ends in
# a commit of exactly these files, and would otherwise sweep them up.
for lock in "${LOCKS[@]}"; do
  if ! git -C "$DOTFILES" diff --quiet HEAD -- "$lock"; then
    echo "Error: $lock has uncommitted changes" >&2
    exit 1
  fi
done

echo "==> Updating $CHILD/flake.lock"
nix flake update --flake "$DOTFILES/$CHILD"

echo "==> Updating flake.lock"
nix flake update --flake "$DOTFILES"

echo "==> Switching"
if command -v nixos-rebuild >/dev/null 2>&1; then
  sudo nixos-rebuild switch --flake "$DOTFILES#thixos"
else
  home-manager switch --impure --flake "$DOTFILES#thom@nix"
fi

git -C "$DOTFILES" add -- "${LOCKS[@]}"
if git -C "$DOTFILES" diff --cached --quiet -- "${LOCKS[@]}"; then
  echo "==> Inputs already current, nothing to commit"
  exit 0
fi

git -C "$DOTFILES" commit -m 'Update flake inputs'
git -C "$DOTFILES" push
