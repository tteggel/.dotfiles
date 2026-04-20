ppid=$(ps -p $$ -o ppid= | tr -d "[:space:]")
pppid=$(ps -p "$ppid" -o ppid= | tr -d "[:space:]")
pppbin=$(ps -p "$pppid" -o cmd= | tr -d "[:space:]")
if [ "$pppbin" = '/bin/login-f' ]; then
  exit 1
fi

if ! mkdir "$HOME/.init-gh-completed" 2>/dev/null; then
  exit 0
fi

gh auth login --clipboard --git-protocol ssh --hostname github.com --web

mkdir -p "$HOME/src/github.com/tteggel"
gh repo clone tteggel/.dotfiles "$HOME/src/github.com/tteggel/.dotfiles"

