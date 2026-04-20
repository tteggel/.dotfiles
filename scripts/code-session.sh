if [ -z "${ZELLIJ:-}" ]; then
  zellij --layout /etc/zellij/layouts/code.kdl
else
  zellij action new-tab --layout /etc/zellij/layouts/code.kdl --cwd "$(pwd)" --name code
  zellij action go-to-previous-tab
  zellij action close-tab
fi

