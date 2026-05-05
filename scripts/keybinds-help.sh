B=$'\e[1m'; D=$'\e[2m'; C=$'\e[36m'; Y=$'\e[33m'; G=$'\e[32m'; R=$'\e[0m'

clear

cat <<HELP
${B}${C}═══ Zellij ═══${R}

  ${Y}Mode${R}
    ${G}Ctrl+Shift+G${R}      Lock / unlock (passes keys through)
    ${G}Ctrl+Shift+Q${R}      Detach session
    ${G}Ctrl+Shift+S${R}      Scroll mode  (j/k, d/u, /search, Esc exit)

  ${Y}Panes${R}
    ${G}Ctrl+Shift+N${R}      New pane
    ${G}Ctrl+Shift+W${R}      Close pane
    ${G}Ctrl+Shift+H/J/K/L${R}  Move focus
    ${G}Ctrl+Shift+= / -${R}  Grow / shrink pane
    ${G}Ctrl+Shift+Z${R}      Toggle fullscreen

  ${Y}Tabs${R}
    ${G}Ctrl+Shift+T${R}      New tab
    ${G}Ctrl+Shift+1..5${R}   Switch to tab N
    ${G}Ctrl+Shift+[ / ]${R}  Previous / next tab

  ${Y}Overlays${R}
    ${G}Ctrl+Shift+O${R}      Session picker
    ${G}Ctrl+Shift+P${R}      Command palette
    ${G}Ctrl+Shift+/${R}      This help
    ${G}Ctrl+Shift+Space${R}  Next swap layout

${B}${C}═══ Environment ═══${R}

  EDITOR                    micro
  BROWSER                   open-browser
  CLAUDE_CODE_EFFORT_LEVEL  max
  GEMINI_EXP                ~/.gemini/experiments.json (3.1 flag)
  STARSHIP_CONFIG           ~/.config/starship.toml
  MANPAGER                  bat

${B}${C}═══ Helpers on PATH ═══${R}

  ${Y}Sessions${R}
    session-picker          launch / attach a zellij session
    command-palette         fuzzy launcher (Ctrl+Shift+P)
    claude-session          pick / resume a Claude Code session
    gemini-session          pick / resume a Gemini session
    code-session            open code layout in zellij

  ${Y}GCP${R}
    gcloud-switch           fzf project / cluster / kube-context
    gcloud-reauth           refresh gcloud + firebase auth
    gcloud-iap-ssh          IAP-tunneled SSH picker
    gcloud-iap-zellij-web   IAP-tunneled zellij web

  ${Y}Misc${R}
    init-yolo / init-gh     repo + GitHub bootstrap
    gh-sandbox-token        generate pre-filled GH PAT URL
    hygiene-inspection      dotfiles cleanliness check
    open-browser            open a URL via Chrome / xdg-open
    zed                     open Zed from inside WSL
    yy                      yazi wrapper that syncs cwd

${D}Press any key to close.${R}
HELP

read -rsn1 _ || true
