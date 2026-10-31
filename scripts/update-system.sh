#!/usr/bin/env bash

# Bump every lockfile this flake owns, switch to the result, then commit.
#
# `nix flake update` at the top level does NOT recurse into `path:` inputs: a
# path input's transitive deps are read from *that* flake's own flake.lock, so
# the bespoke/zellij/dim-unfocused subtree (zellij-src, rust-overlay, and the
# nixpkgs zellij is built against) silently froze while the rest of the system
# moved on. Update the child lock first, then the top level, so the top-level
# resolve picks up the new subtree.
#
# The Entire plugins are pinned in their own lockfile, home/entire-plugins.json
# (see home/entire-plugins.nix for why), which is bumped here too.

set -euo pipefail

DOTFILES="$HOME/src/github.com/tteggel/.dotfiles"
CHILD="bespoke/zellij/dim-unfocused"
PLUGINS="home/entire-plugins.json"
LOCKS=("flake.lock" "$CHILD/flake.lock" "$PLUGINS")

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

# Pin each plugin to its latest release (drafts and prereleases excluded),
# taking the hash from the release's checksums.txt, which is what
# `entire plugin install` verifies against.
echo "==> Updating $PLUGINS"
mapfile -t plugins < <(jq -r 'keys[]' "$DOTFILES/$PLUGINS")
pins='{}'
for name in "${plugins[@]}"; do
  repo="entireio/entire-$name"
  tag=$(gh api "repos/$repo/releases/latest" --jq .tag_name)
  version=${tag#v}
  asset="entire-${name}_${version}_linux_amd64.tar.gz"
  sum=$(gh release download "$tag" -R "$repo" -p checksums.txt -O - |
    awk -v asset="$asset" '$2 == asset { print $1 }')
  if [[ -z $sum ]]; then
    echo "Error: $repo $tag has no checksum for $asset" >&2
    exit 1
  fi
  hash=$(nix hash convert --hash-algo sha256 --to sri "$sum")
  pins=$(jq --arg name "$name" --arg version "$version" --arg hash "$hash" \
    '.[$name] = {version: $version, hash: $hash}' <<<"$pins")
done
printf '%s\n' "$pins" >"$DOTFILES/$PLUGINS"

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
