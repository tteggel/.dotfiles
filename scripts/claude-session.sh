pick=$(printf 'New session\nResume session' | fzf --prompt="Claude> " --height=~50% --reverse) || exit 0
if [ "$pick" = "Resume session" ]; then
  exec claude --resume
else
  exec claude
fi

