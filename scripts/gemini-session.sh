pick=$(printf 'New session\nResume session' | fzf --prompt="Gemini> " --height=~50% --reverse) || exit 0
if [ "$pick" = "Resume session" ]; then
  exec gemini --resume latest
else
  exec gemini
fi

