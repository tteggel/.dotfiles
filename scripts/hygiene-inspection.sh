RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
BOLD=$'\033[1m'
NC=$'\033[0m'

issues=0
warnings=0

issue() { printf '%s  ISSUE:%s %s\n' "$RED" "$NC" "$1"; issues=$((issues + 1)); }
warn()  { printf '%s  WARN:%s  %s\n' "$YELLOW" "$NC" "$1"; warnings=$((warnings + 1)); }
section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$NC"; }

ALLOWLIST="$HOME/.config/hygiene-expected-dotfiles"

# --- Unmanaged dotfiles ---
section "Home directory"
while IFS= read -r entry; do
  name="${entry#"$HOME"/}"
  matched=false
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # shellcheck disable=SC2254
    case "$name" in
      $pattern) matched=true; break ;;
    esac
  done < "$ALLOWLIST"
  if [ "$matched" = false ]; then
    issue "Unmanaged: ~/$name"
  fi
done < <(find "$HOME" -maxdepth 1 -mindepth 1 | sort)

# --- Dirty git repos ---
section "Git repositories"
while IFS= read -r gitdir; do
  repo="${gitdir%/.git}"
  name="${repo#"$HOME"/}"
  pushd "$repo" > /dev/null || continue

  if [ -n "$(timeout 5 git status --porcelain 2>/dev/null)" ]; then
    issue "Dirty repo: $name (uncommitted changes)"
  fi

  stash_count=$(timeout 5 git stash list 2>/dev/null | wc -l)
  if [ "$stash_count" -gt 0 ]; then
    issue "Stashes in: $name ($stash_count stash(es))"
  fi

  # Check for unpushed commits on current branch
  upstream=$(timeout 5 git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
  if [ -n "$upstream" ]; then
    unpushed=$(timeout 5 git rev-list "$upstream"..HEAD 2>/dev/null | wc -l)
    if [ "$unpushed" -gt 0 ]; then
      issue "Unpushed commits: $name ($unpushed commit(s))"
    fi
  fi

  popd > /dev/null || true
done < <(timeout 10 fd --type d --hidden --no-ignore --glob '.git' "$HOME/src" 2>/dev/null)

# --- Imperative nix packages ---
section "Nix"
nix_env_out=$(nix-env -q 2>/dev/null | grep -v '^home-manager-path$' || true)
if [ -n "$nix_env_out" ]; then
  issue "Imperative nix packages found (use flake instead): $nix_env_out"
fi

# --- User crontabs ---
section "Cron"
if crontab -l 2>/dev/null | grep -qv '^#\|^$'; then
  issue "User crontab entries found"
fi

# --- Unmanaged systemd user units ---
section "Systemd user units"
if [ -d "$HOME/.config/systemd/user" ]; then
  unit_count=$(find "$HOME/.config/systemd/user" -type f 2>/dev/null | wc -l)
  if [ "$unit_count" -gt 0 ]; then
    issue "Unmanaged systemd user units ($unit_count file(s) in ~/.config/systemd/user)"
  fi
fi

# --- Warnings: credentials & state ---
section "Credentials & state"
if [ -d "$HOME/.ssh" ]; then
  key_count=$(find "$HOME/.ssh" -name '*.pub' 2>/dev/null | wc -l)
  if [ "$key_count" -gt 0 ]; then
    warn "SSH keys present ($key_count key(s))"
  fi
fi

if [ -d "$HOME/.gnupg" ]; then
  warn "GPG directory present"
fi

if gh auth status &>/dev/null; then
  warn "gh authenticated"
fi

if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  warn "gcloud authenticated"
fi

if kubectl config current-context &>/dev/null; then
  warn "kubectl context configured"
fi

if [ -d "$HOME/.docker" ]; then
  warn "Docker state present (~/.docker)"
fi

# Large /tmp files (>100MB)
large_tmp=$(find /tmp -maxdepth 2 -user "$(whoami)" -size +100M 2>/dev/null | wc -l)
if [ "$large_tmp" -gt 0 ]; then
  warn "Large files in /tmp ($large_tmp file(s) >100MB)"
fi

# --- Summary ---
printf '\n%s---%s\n' "$BOLD" "$NC"
if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
  printf '%sClean: safe to move.%s\n' "$GREEN" "$NC"
else
  [ "$issues" -gt 0 ] && printf '%s%d issue(s)%s ' "$RED" "$issues" "$NC"
  [ "$warnings" -gt 0 ] && printf '%s%d warning(s)%s ' "$YELLOW" "$warnings" "$NC"
  printf '\n'
fi

