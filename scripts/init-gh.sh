ppid=$(ps -p $$ -o ppid= | tr -d "[:space:]")
pppid=$(ps -p "$ppid" -o ppid= | tr -d "[:space:]")
pppbin=$(ps -p "$pppid" -o cmd= | tr -d "[:space:]")
if [ "$pppbin" = '/bin/login-f' ]; then
  exit 1
fi

# Marker is a flag, not a lock: only created after every step below
# succeeds, so a half-finished init (network blip, key not yet propagated,
# user cancelling the gh login flow) is retried on next login.
[ -d "$HOME/.init-gh-completed" ] && exit 0

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  gh auth login --clipboard --git-protocol ssh --hostname github.com --web
fi

# Seed ~/.ssh/known_hosts so the user's future SSH-based git ops don't
# hang on the host-key prompt. (gh auth login doesn't seed this.)
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! grep -q "^github.com " "$HOME/.ssh/known_hosts" 2>/dev/null; then
  ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>/dev/null >> "$HOME/.ssh/known_hosts"
fi

# Bootstrap clone uses anonymous HTTPS so it doesn't depend on the SSH
# key actually having been uploaded by `gh auth login` (which has been
# observed to silently no-op — key exists locally, never reaches GitHub,
# the SSH clone then fails to authenticate). Flip the remote back to SSH
# afterwards so subsequent git ops match the configured git protocol.
target="$HOME/src/github.com/tteggel/.dotfiles"
mkdir -p "$(dirname "$target")"
if [ ! -d "$target" ]; then
  git clone https://github.com/tteggel/.dotfiles.git "$target"
  git -C "$target" remote set-url origin git@github.com:tteggel/.dotfiles.git
fi

mkdir -p "$HOME/.init-gh-completed"
