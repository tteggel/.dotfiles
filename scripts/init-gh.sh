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

# `gh auth login --git-protocol ssh` uploads a key to GitHub but does not
# seed ~/.ssh/known_hosts. Without this, the first SSH clone below blocks
# on the host-key prompt and init-gh aborts.
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! grep -q "^github.com " "$HOME/.ssh/known_hosts" 2>/dev/null; then
  ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>/dev/null >> "$HOME/.ssh/known_hosts"
fi

target="$HOME/src/github.com/tteggel/.dotfiles"
mkdir -p "$(dirname "$target")"
if [ ! -d "$target" ]; then
  gh repo clone tteggel/.dotfiles "$target"
fi

mkdir -p "$HOME/.init-gh-completed"
