# BookCreator repos run Copilot in place of Claude and Codex. session-picker
# makes the same choice for the sessions it starts.
layout=~/.config/zellij/layouts/code.kdl
case "$PWD" in
  "$HOME"/src/github.com/bookcreator/*) layout=~/.config/zellij/layouts/code-copilot.kdl ;;
esac

if [ -z "${ZELLIJ:-}" ]; then
  zellij --layout "$layout"
else
  zellij action new-tab --layout "$layout" --cwd "$(pwd)" --name code
  zellij action go-to-previous-tab
  zellij action close-tab
fi

