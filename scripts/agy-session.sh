pick=$(printf 'New session\nContinue session' | fzf --prompt="Agy> " --height=~50% --reverse) || exit 0
if [ "$pick" = "Continue session" ]; then
  exec agy --continue
else
  exec agy
fi
